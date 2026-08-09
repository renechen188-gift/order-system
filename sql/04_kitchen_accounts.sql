-- ============================================
-- 1. inventory.users 加 assigned_cats 欄位
-- ============================================
ALTER TABLE inventory.users ADD COLUMN IF NOT EXISTS assigned_cats TEXT[];

-- ============================================
-- 2. 建立 3 組央廚帳號
-- ============================================
DO $$
DECLARE
  v_id UUID;
  v_store_id UUID;
  accounts TEXT[][] := ARRAY[
    ['mmjkt01@order.com', 'mmjkt01888', '信義央廚', 'kitchen_fulfill'],
    ['mmjkt02@order.com', 'mmjkt02888', '信義央廚', 'kitchen_fulfill'],
    ['mmjkt03@order.com', 'mmjkt03888', '信義央廚', 'kitchen_fulfill']
  ];
  acct TEXT[];
BEGIN
  FOREACH acct SLICE 1 IN ARRAY accounts LOOP
    v_id := gen_random_uuid();
    SELECT id INTO v_store_id FROM inventory.stores WHERE name = acct[3];

    INSERT INTO auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at,
      created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      is_super_admin, confirmation_token, recovery_token, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_id, 'authenticated', 'authenticated', acct[1],
      crypt(acct[2], gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      '{}',
      false, '', '', ''
    );

    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at
    ) VALUES (
      v_id, v_id, acct[1],
      jsonb_build_object('sub', v_id::text, 'email', acct[1]),
      'email', now(), now(), now()
    );

    INSERT INTO inventory.users (auth_id, name, store_id, role)
    VALUES (v_id, acct[3], v_store_id, acct[4]);

    RAISE NOTICE 'Created: % -> %', acct[1], acct[3];
  END LOOP;
END;
$$;

-- ============================================
-- 3. 設定各帳號負責的分類
-- ============================================
UPDATE inventory.users
SET assigned_cats = ARRAY['主食', '包材', '調料', '飲品']
WHERE auth_id = (SELECT id FROM auth.users WHERE email = 'mmjkt01@order.com');

UPDATE inventory.users
SET assigned_cats = ARRAY['醬包類', '大陸調料']
WHERE auth_id = (SELECT id FROM auth.users WHERE email = 'mmjkt02@order.com');

UPDATE inventory.users
SET assigned_cats = ARRAY['小菜', '蛋品', '肉品', '蔬菜']
WHERE auth_id = (SELECT id FROM auth.users WHERE email = 'mmjkt03@order.com');

-- 驗證
SELECT u.name, u.role, u.assigned_cats, au.email
FROM inventory.users u
LEFT JOIN auth.users au ON u.auth_id = au.id
WHERE au.email LIKE 'mmjkt%'
ORDER BY au.email;
