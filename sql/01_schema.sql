-- ============================================
-- 麻媽家·涼三伯 進銷存系統 Supabase Schema
-- 版本: v2 (含盤點設定/調撥/價格審核)
-- 使用方式: 複製到 Supabase SQL Editor 執行
-- ============================================

-- 建立獨立 schema（不影響現有資料表）
CREATE SCHEMA IF NOT EXISTS inventory;

-- ============================================
-- 1. 門店 stores
-- ============================================
CREATE TABLE inventory.stores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  brand TEXT NOT NULL,                   -- 麻媽家 / 涼三伯 / 眾旺
  type TEXT NOT NULL DEFAULT 'store'
    CHECK (type IN ('store', 'warehouse')),  -- store=門店, warehouse=中央廚房
  address TEXT,
  phone TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.stores IS '門店與中央廚房主檔';

-- ============================================
-- 2. 使用者 users
-- ============================================
CREATE TABLE inventory.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id UUID UNIQUE REFERENCES auth.users(id),
  name TEXT NOT NULL,
  store_id UUID REFERENCES inventory.stores(id),
  role TEXT NOT NULL DEFAULT 'store_manager'
    CHECK (role IN ('admin', 'store_manager', 'kitchen')),
  phone TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.users IS '系統使用者';

-- ============================================
-- 3. 廠商 suppliers
-- ============================================
CREATE TABLE inventory.suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'external'
    CHECK (type IN ('external', 'central_kitchen')),
  contact_name TEXT,
  phone TEXT,
  line_id TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.suppliers IS '供應商主檔（含中央廚房）';

-- ============================================
-- 4. 品項主檔 items
-- ============================================
CREATE TABLE inventory.items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE,                      -- 原始編號 (M001, P001)
  name TEXT NOT NULL,
  category TEXT NOT NULL,                -- 肉類/蔬菜/包材/涼皮類...
  type TEXT NOT NULL
    CHECK (type IN ('material', 'packaging', 'semi', 'product')),
  unit TEXT NOT NULL,                    -- g/kg/包/個/瓶
  spec TEXT,                             -- 規格說明
  brand_scope TEXT NOT NULL DEFAULT 'ALL'
    CHECK (brand_scope IN ('麻媽家', '涼三伯', 'ALL')),
  purchase_price NUMERIC(10,2),          -- 進貨價
  unit_cost NUMERIC(12,6),               -- 換算單位成本
  min_stock NUMERIC(10,2),               -- 安全庫存量（選填）
  needs_count BOOLEAN NOT NULL DEFAULT true,  -- 是否列入盤點
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.items IS '品項主檔';
COMMENT ON COLUMN inventory.items.needs_count IS 'true=列入盤點，false=忽略（如鹽巴牙籤等）';

CREATE INDEX idx_items_type ON inventory.items(type);
CREATE INDEX idx_items_category ON inventory.items(category);
CREATE INDEX idx_items_brand ON inventory.items(brand_scope);

-- ============================================
-- 5. 品項 × 廠商對應
-- ============================================
CREATE TABLE inventory.item_suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES inventory.items(id) ON DELETE CASCADE,
  supplier_id UUID NOT NULL REFERENCES inventory.suppliers(id) ON DELETE CASCADE,
  is_default BOOLEAN NOT NULL DEFAULT false,
  supplier_item_code TEXT,
  note TEXT,
  UNIQUE(item_id, supplier_id)
);

COMMENT ON TABLE inventory.item_suppliers IS '品項與供應商多對多對應';

-- ============================================
-- 6. 叫貨單 orders
-- ============================================
CREATE TABLE inventory.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES inventory.stores(id),
  created_by UUID NOT NULL REFERENCES inventory.users(id),
  order_type TEXT NOT NULL
    CHECK (order_type IN ('internal', 'external')),
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('draft', 'submitted', 'confirmed', 'received', 'cancelled')),
  order_date DATE NOT NULL DEFAULT CURRENT_DATE,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.orders IS '門店/廚房叫貨單';

CREATE INDEX idx_orders_store ON inventory.orders(store_id);
CREATE INDEX idx_orders_date ON inventory.orders(order_date);
CREATE INDEX idx_orders_status ON inventory.orders(status);

-- ============================================
-- 7. 叫貨明細 order_items
-- ============================================
CREATE TABLE inventory.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES inventory.orders(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  supplier_id UUID REFERENCES inventory.suppliers(id),
  ordered_qty NUMERIC(10,2) NOT NULL,
  received_qty NUMERIC(10,2),
  received_by UUID REFERENCES inventory.users(id),
  received_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'received', 'short', 'cancelled')),
  note TEXT
);

CREATE INDEX idx_order_items_order ON inventory.order_items(order_id);

-- ============================================
-- 8. 廠商彙總採購單
-- ============================================
CREATE TABLE inventory.purchase_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID NOT NULL REFERENCES inventory.suppliers(id),
  order_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'generated'
    CHECK (status IN ('generated', 'sent', 'completed')),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  UNIQUE(supplier_id, order_date)
);

CREATE TABLE inventory.purchase_summary_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  summary_id UUID NOT NULL REFERENCES inventory.purchase_summaries(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  total_qty NUMERIC(10,2) NOT NULL,
  detail JSONB                           -- [{"store":"松山店","qty":5}, ...]
);

-- ============================================
-- 9. 庫存異動流水帳
-- ============================================
CREATE TABLE inventory.stock_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES inventory.stores(id),
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  type TEXT NOT NULL
    CHECK (type IN ('receive', 'adjust', 'transfer_in', 'transfer_out')),
  qty NUMERIC(10,2) NOT NULL,            -- 正=入庫, 負=出庫
  ref_type TEXT,                         -- 'order_item' / 'inventory_count' / 'transfer'
  ref_id UUID,
  note TEXT,
  created_by UUID REFERENCES inventory.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE inventory.stock_ledger IS '庫存異動流水帳（不含 consume，用盤點反推使用量）';

CREATE INDEX idx_stock_store_item ON inventory.stock_ledger(store_id, item_id);
CREATE INDEX idx_stock_created ON inventory.stock_ledger(created_at);

-- ============================================
-- 10. 即時庫存 View
-- ============================================
CREATE OR REPLACE VIEW inventory.current_stock AS
SELECT
  store_id,
  item_id,
  SUM(qty) AS qty_on_hand
FROM inventory.stock_ledger
GROUP BY store_id, item_id;

-- ============================================
-- 11. 盤點紀錄
-- ============================================
CREATE TABLE inventory.inventory_counts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES inventory.stores(id),
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  count_period TEXT,                     -- '2026-07-上' / '2026-07-下'
  system_qty NUMERIC(10,2) NOT NULL,
  actual_qty NUMERIC(10,2) NOT NULL,
  diff NUMERIC(10,2) GENERATED ALWAYS AS (actual_qty - system_qty) STORED,
  counted_by UUID NOT NULL REFERENCES inventory.users(id),
  counted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_counts_store ON inventory.inventory_counts(store_id);
CREATE INDEX idx_counts_period ON inventory.inventory_counts(count_period);

-- ============================================
-- 12. 盤點單（管理後台生成）
-- ============================================
CREATE TABLE inventory.count_sheets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES inventory.stores(id),
  period TEXT NOT NULL,                  -- '2026-07-上'
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_progress', 'completed')),
  created_by UUID REFERENCES inventory.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  UNIQUE(store_id, period)
);

COMMENT ON TABLE inventory.count_sheets IS '管理後台生成的盤點單，推送到各門店';

-- ============================================
-- 13. 門店調撥
-- ============================================
CREATE TABLE inventory.transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_store_id UUID NOT NULL REFERENCES inventory.stores(id),
  to_store_id UUID NOT NULL REFERENCES inventory.stores(id),
  status TEXT NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested', 'approved', 'shipped', 'received', 'cancelled')),
  requested_by UUID NOT NULL REFERENCES inventory.users(id),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  shipped_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ,
  note TEXT,
  CHECK (from_store_id <> to_store_id)
);

COMMENT ON TABLE inventory.transfers IS '門店間調撥單';

CREATE TABLE inventory.transfer_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id UUID NOT NULL REFERENCES inventory.transfers(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  requested_qty NUMERIC(10,2) NOT NULL,
  actual_qty NUMERIC(10,2)               -- 實際出貨量
);

-- ============================================
-- 14. 價格異動紀錄（自動記錄）
-- ============================================
CREATE TABLE inventory.price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  old_price NUMERIC(10,2),
  new_price NUMERIC(10,2),
  old_unit_cost NUMERIC(12,6),
  new_unit_cost NUMERIC(12,6),
  changed_by UUID REFERENCES inventory.users(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- 15. 價格異動審核（門店回報）
-- ============================================
CREATE TABLE inventory.price_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES inventory.items(id),
  supplier_id UUID REFERENCES inventory.suppliers(id),
  store_id UUID NOT NULL REFERENCES inventory.stores(id),
  reported_by UUID NOT NULL REFERENCES inventory.users(id),
  old_price NUMERIC(10,2) NOT NULL,      -- 系統現有價格
  new_price NUMERIC(10,2) NOT NULL,      -- 門店回報的新價格
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES inventory.users(id),
  reviewed_at TIMESTAMPTZ,
  reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  note TEXT
);

COMMENT ON TABLE inventory.price_reviews IS '門店收貨時回報的價格異動，待管理者審核';

CREATE INDEX idx_price_reviews_status ON inventory.price_reviews(status);

-- ============================================
-- 輔助函式
-- ============================================
CREATE OR REPLACE FUNCTION inventory.get_user_role()
RETURNS TEXT AS $$
  SELECT role FROM inventory.users WHERE auth_id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION inventory.get_user_store_id()
RETURNS UUID AS $$
  SELECT store_id FROM inventory.users WHERE auth_id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================
-- RLS 啟用
-- ============================================
ALTER TABLE inventory.stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.item_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.purchase_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.purchase_summary_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.inventory_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.count_sheets ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.price_reviews ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS Policies
-- ============================================

-- stores: 全員可讀
CREATE POLICY "stores_select" ON inventory.stores FOR SELECT USING (true);
CREATE POLICY "stores_admin" ON inventory.stores FOR ALL USING (inventory.get_user_role() = 'admin');

-- users: 管理者全看，員工看自己
CREATE POLICY "users_admin" ON inventory.users FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "users_self" ON inventory.users FOR SELECT USING (auth_id = auth.uid());

-- suppliers: 全員可讀，管理者可寫
CREATE POLICY "suppliers_select" ON inventory.suppliers FOR SELECT USING (true);
CREATE POLICY "suppliers_admin" ON inventory.suppliers FOR ALL USING (inventory.get_user_role() = 'admin');

-- items: 全員可讀（含價格，直營店開放），管理者可寫
CREATE POLICY "items_select" ON inventory.items FOR SELECT USING (true);
CREATE POLICY "items_admin" ON inventory.items FOR ALL USING (inventory.get_user_role() = 'admin');

-- item_suppliers: 全員可讀，管理者可寫
CREATE POLICY "item_suppliers_select" ON inventory.item_suppliers FOR SELECT USING (true);
CREATE POLICY "item_suppliers_admin" ON inventory.item_suppliers FOR ALL USING (inventory.get_user_role() = 'admin');

-- orders: 自己店+管理者
CREATE POLICY "orders_admin" ON inventory.orders FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "orders_store_select" ON inventory.orders FOR SELECT USING (store_id = inventory.get_user_store_id());
CREATE POLICY "orders_store_insert" ON inventory.orders FOR INSERT WITH CHECK (store_id = inventory.get_user_store_id());
CREATE POLICY "orders_store_update" ON inventory.orders FOR UPDATE USING (store_id = inventory.get_user_store_id());

-- order_items: 跟隨 orders
CREATE POLICY "oi_admin" ON inventory.order_items FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "oi_store_select" ON inventory.order_items FOR SELECT USING (
  order_id IN (SELECT id FROM inventory.orders WHERE store_id = inventory.get_user_store_id()));
CREATE POLICY "oi_store_insert" ON inventory.order_items FOR INSERT WITH CHECK (
  order_id IN (SELECT id FROM inventory.orders WHERE store_id = inventory.get_user_store_id()));
CREATE POLICY "oi_store_update" ON inventory.order_items FOR UPDATE USING (
  order_id IN (SELECT id FROM inventory.orders WHERE store_id = inventory.get_user_store_id()));

-- purchase_summaries: 僅管理者
CREATE POLICY "ps_admin" ON inventory.purchase_summaries FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "psi_admin" ON inventory.purchase_summary_items FOR ALL USING (inventory.get_user_role() = 'admin');

-- stock_ledger: 自己店+管理者
CREATE POLICY "sl_admin" ON inventory.stock_ledger FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "sl_store" ON inventory.stock_ledger FOR SELECT USING (store_id = inventory.get_user_store_id());

-- inventory_counts: 自己店可寫+管理者全看
CREATE POLICY "ic_admin" ON inventory.inventory_counts FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "ic_store_select" ON inventory.inventory_counts FOR SELECT USING (store_id = inventory.get_user_store_id());
CREATE POLICY "ic_store_insert" ON inventory.inventory_counts FOR INSERT WITH CHECK (store_id = inventory.get_user_store_id());

-- count_sheets: 自己店可讀+管理者可寫
CREATE POLICY "cs_admin" ON inventory.count_sheets FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "cs_store" ON inventory.count_sheets FOR SELECT USING (store_id = inventory.get_user_store_id());
CREATE POLICY "cs_store_update" ON inventory.count_sheets FOR UPDATE USING (store_id = inventory.get_user_store_id());

-- transfers: 調出/調入方+管理者
CREATE POLICY "tf_admin" ON inventory.transfers FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "tf_from" ON inventory.transfers FOR SELECT USING (from_store_id = inventory.get_user_store_id());
CREATE POLICY "tf_to" ON inventory.transfers FOR SELECT USING (to_store_id = inventory.get_user_store_id());
CREATE POLICY "tf_insert" ON inventory.transfers FOR INSERT WITH CHECK (
  from_store_id = inventory.get_user_store_id() OR to_store_id = inventory.get_user_store_id());
CREATE POLICY "tf_update" ON inventory.transfers FOR UPDATE USING (
  from_store_id = inventory.get_user_store_id() OR to_store_id = inventory.get_user_store_id());

CREATE POLICY "tfi_admin" ON inventory.transfer_items FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "tfi_select" ON inventory.transfer_items FOR SELECT USING (
  transfer_id IN (SELECT id FROM inventory.transfers
    WHERE from_store_id = inventory.get_user_store_id() OR to_store_id = inventory.get_user_store_id()));
CREATE POLICY "tfi_insert" ON inventory.transfer_items FOR INSERT WITH CHECK (
  transfer_id IN (SELECT id FROM inventory.transfers
    WHERE from_store_id = inventory.get_user_store_id() OR to_store_id = inventory.get_user_store_id()));

-- price_history: 僅管理者
CREATE POLICY "ph_admin" ON inventory.price_history FOR ALL USING (inventory.get_user_role() = 'admin');

-- price_reviews: 自己店可新增+管理者可審核
CREATE POLICY "pr_admin" ON inventory.price_reviews FOR ALL USING (inventory.get_user_role() = 'admin');
CREATE POLICY "pr_store_select" ON inventory.price_reviews FOR SELECT USING (store_id = inventory.get_user_store_id());
CREATE POLICY "pr_store_insert" ON inventory.price_reviews FOR INSERT WITH CHECK (store_id = inventory.get_user_store_id());

-- ============================================
-- 觸發器: 價格異動自動記錄
-- ============================================
CREATE OR REPLACE FUNCTION inventory.log_price_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.purchase_price IS DISTINCT FROM NEW.purchase_price
     OR OLD.unit_cost IS DISTINCT FROM NEW.unit_cost THEN
    INSERT INTO inventory.price_history (item_id, old_price, new_price, old_unit_cost, new_unit_cost)
    VALUES (NEW.id, OLD.purchase_price, NEW.purchase_price, OLD.unit_cost, NEW.unit_cost);
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_price_change
  BEFORE UPDATE ON inventory.items
  FOR EACH ROW EXECUTE FUNCTION inventory.log_price_change();

-- ============================================
-- 觸發器: 收貨確認自動寫入 stock_ledger
-- ============================================
CREATE OR REPLACE FUNCTION inventory.on_receive()
RETURNS TRIGGER AS $$
DECLARE
  v_store_id UUID;
BEGIN
  IF NEW.status = 'received' AND (OLD.status IS NULL OR OLD.status = 'pending') THEN
    SELECT store_id INTO v_store_id
    FROM inventory.orders WHERE id = NEW.order_id;

    INSERT INTO inventory.stock_ledger (store_id, item_id, type, qty, ref_type, ref_id, created_by)
    VALUES (v_store_id, NEW.item_id, 'receive',
            COALESCE(NEW.received_qty, NEW.ordered_qty),
            'order_item', NEW.id, NEW.received_by);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_on_receive
  AFTER UPDATE ON inventory.order_items
  FOR EACH ROW EXECUTE FUNCTION inventory.on_receive();

-- ============================================
-- 觸發器: 盤點差異自動寫入 stock_ledger
-- ============================================
CREATE OR REPLACE FUNCTION inventory.on_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (NEW.actual_qty - NEW.system_qty) <> 0 THEN
    INSERT INTO inventory.stock_ledger (store_id, item_id, type, qty, ref_type, ref_id, created_by)
    VALUES (NEW.store_id, NEW.item_id, 'adjust',
            NEW.actual_qty - NEW.system_qty,
            'inventory_count', NEW.id, NEW.counted_by);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_on_count
  AFTER INSERT ON inventory.inventory_counts
  FOR EACH ROW EXECUTE FUNCTION inventory.on_count();

-- ============================================
-- 觸發器: 調撥收貨自動寫入 stock_ledger
-- ============================================
CREATE OR REPLACE FUNCTION inventory.on_transfer_complete()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'received' AND OLD.status = 'shipped' THEN
    -- 調出方扣庫存
    INSERT INTO inventory.stock_ledger (store_id, item_id, type, qty, ref_type, ref_id)
    SELECT NEW.from_store_id, ti.item_id, 'transfer_out',
           -COALESCE(ti.actual_qty, ti.requested_qty), 'transfer', NEW.id
    FROM inventory.transfer_items ti WHERE ti.transfer_id = NEW.id;

    -- 調入方加庫存
    INSERT INTO inventory.stock_ledger (store_id, item_id, type, qty, ref_type, ref_id)
    SELECT NEW.to_store_id, ti.item_id, 'transfer_in',
           COALESCE(ti.actual_qty, ti.requested_qty), 'transfer', NEW.id
    FROM inventory.transfer_items ti WHERE ti.transfer_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_on_transfer
  AFTER UPDATE ON inventory.transfers
  FOR EACH ROW EXECUTE FUNCTION inventory.on_transfer_complete();

-- ============================================
-- 觸發器: 價格審核核准後自動更新 items 價格
-- ============================================
CREATE OR REPLACE FUNCTION inventory.on_price_approved()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status = 'pending' THEN
    UPDATE inventory.items
    SET purchase_price = NEW.new_price
    WHERE id = NEW.item_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_on_price_approved
  AFTER UPDATE ON inventory.price_reviews
  FOR EACH ROW EXECUTE FUNCTION inventory.on_price_approved();

-- ============================================
-- 初始資料: 門店
-- ============================================
-- ⚠️ 請依實際門店名稱修改
INSERT INTO inventory.stores (name, brand, type) VALUES
  ('松山店', '麻媽家', 'store'),
  ('東湖店', '麻媽家', 'store'),
  ('南港店', '麻媽家', 'store'),
  ('信義店', '涼三伯', 'store'),
  ('大安店', '涼三伯', 'store'),
  ('中央廚房', '眾旺', 'warehouse');

-- 初始資料: 中央廚房作為供應商
INSERT INTO inventory.suppliers (name, type, note) VALUES
  ('中央廚房', 'central_kitchen', '眾旺自有中央廚房');

-- ============================================
-- 將 inventory schema 加入 API 存取
-- ============================================
-- Supabase 預設只暴露 public schema
-- 需要到 Dashboard > Settings > API > Schema 加入 inventory
-- 或執行以下 SQL：
NOTIFY pgrst, 'reload config';
ALTER ROLE authenticator SET pgrst.db_schemas TO 'public, inventory';
NOTIFY pgrst, 'reload config';

-- ============================================
-- 完成！共 16 張表 + 1 View + 5 觸發器
-- ============================================