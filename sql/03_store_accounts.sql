-- ============================================
-- 批次建立門店帳號 + 綁定 inventory.users
-- ============================================

-- 1. 建立 Auth 帳號
DO $$
DECLARE
  v_id UUID;
  v_store_id UUID;
  accounts TEXT[][] := ARRAY[
    ['xinyi@order.com',   'xinyi888',   '麻媽家信義店', 'store_manager'],
    ['neihu@order.com',   'neihu888',   '麻媽家內湖店', 'store_manager'],
    ['anju@order.com',    'anju888',    '麻媽家安居店', 'store_manager'],
    ['donghu@order.com',  'donghu888',  '麻媽家東湖店', 'store_manager'],
    ['dongke@order.com',  'dongke888',  '涼三伯東科店', 'store_manager'],
    ['liang@order.com',   'liang888',   '涼三伯東湖店', 'store_manager'],
    ['kitchen@order.com', 'kitchen888', '信義央廚',     'kitchen']
  ];
  acct TEXT[];
BEGIN
  FOREACH acct SLICE 1 IN ARRAY accounts LOOP
    -- Generate UUID
    v_id := gen_random_uuid();

    -- Find store_id
    SELECT id INTO v_store_id FROM inventory.stores WHERE name = acct[3];

    -- Insert into auth.users
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

    -- Insert into auth.identities
    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at
    ) VALUES (
      v_id, v_id, acct[1],
      jsonb_build_object('sub', v_id::text, 'email', acct[1]),
      'email', now(), now(), now()
    );

    -- Insert into inventory.users
    INSERT INTO inventory.users (auth_id, name, store_id, role)
    VALUES (v_id, acct[3], v_store_id, acct[4]);

    RAISE NOTICE 'Created: % -> %', acct[1], acct[3];
  END LOOP;
END;
$$;

-- 驗證
SELECT u.name, u.role, s.name AS store, au.email
FROM inventory.users u
LEFT JOIN inventory.stores s ON u.store_id = s.id
LEFT JOIN auth.users au ON u.auth_id = au.id
ORDER BY u.created_at;