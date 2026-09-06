-- 調撥推送損益：刪除舊資料 + 插入新資料，SECURITY DEFINER 繞過 RLS
CREATE OR REPLACE FUNCTION inventory.push_transfer_cost(
  p_month text,
  p_entries jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.cashflow_entries
  WHERE attribution_month = p_month
    AND description = '央廚調撥（自動推送）';

  INSERT INTO public.cashflow_entries (entry_date, store, subject, vendor, description, amount, fee, attribution_month, updated_at)
  SELECT
    (e->>'entry_date')::date,
    e->>'store',
    e->>'subject',
    e->>'vendor',
    e->>'description',
    (e->>'amount')::numeric,
    (e->>'fee')::numeric,
    e->>'attribution_month',
    now()
  FROM jsonb_array_elements(p_entries) AS e;
END;
$$;

GRANT EXECUTE ON FUNCTION inventory.push_transfer_cost TO authenticated;

-- 盤點推送期末盤存到 cashflow_records，SECURITY DEFINER 繞過 RLS
CREATE OR REPLACE FUNCTION inventory.push_inventory_value(
  p_store text,
  p_month text,
  p_amount numeric,
  p_desc text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.cashflow_records
  WHERE store = p_store
    AND attribution_month = p_month
    AND pnl_group = '盤存'
    AND pnl_item = '期末盤存';

  INSERT INTO public.cashflow_records (store, attribution_month, pnl_section, pnl_group, pnl_item, amount, description)
  VALUES (p_store, p_month, '成本', '盤存', '期末盤存', p_amount, p_desc);
END;
$$;

GRANT EXECUTE ON FUNCTION inventory.push_inventory_value TO authenticated;
