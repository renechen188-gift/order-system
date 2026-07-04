# 麻媽家·涼三伯 叫貨系統

進銷存管理系統，部署於 Cloudflare Pages + Supabase。

## 部署資訊
- **前端**: Cloudflare Pages (`order-system-9po.pages.dev`)
- **後端**: Supabase (`sjvnnpqhrlahgnbibvuv.supabase.co`)
- **Schema**: `inventory`（獨立於 `scheduling` schema）

## 檔案結構
```
index.html          # 主程式（單頁應用）
sql/
  01_schema.sql     # 資料庫 schema（17 表 + 5 觸發器）
  02_seed_data.sql  # 門店/廠商/品項初始資料
  03_store_accounts.sql  # 門店帳號建立
```

## 已完成功能
- [x] 門店叫貨（外部廠商 / 信義央廚）
- [x] 收貨確認 + 價格核對
- [x] 廠商彙總採購單（LINE 複製格式）
- [x] 價格異動審核
- [x] 品項管理 + CSV 匯入
- [x] 中央廚房出貨彙總
- [x] 叫貨紀錄 + 明細查看
- [x] 角色權限（admin / store_manager / kitchen）

## 待開發
- [ ] 盤點功能（月中/月底）
- [ ] 門店調撥
- [ ] 廠商對帳（應付帳款）
- [ ] 管理者門店切換
- [ ] 成本報表

## 帳號規則
- 門店：輸入代號（如 `xinyi`），密碼自動為 `代號888`
- 管理者：輸入完整 email，手動輸入密碼
