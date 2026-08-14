-- ═══════════════════════════════════════════════════════════════════════
-- بذور التطوير المحلي
--
-- ⚠️ يعمل هذا الملف مع `supabase db reset` محلياً فقط. لا يُشغَّل ضمن
-- `supabase db push`، فلا يصل إلى الإنتاج.
--
-- لإنشاء المالك في الإنتاج، راجع القسم في نهاية الملف.
-- ═══════════════════════════════════════════════════════════════════════

-- ── مستخدم تطوير بصلاحية المالك ────────────────────────────────────────
--   البريد:      owner@seco.local
--   كلمة المرور: SecoSeco2026!

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'owner@seco.local',
  crypt('SecoSeco2026!', gen_salt('bf')),
  now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"full_name": "مالك النظام"}'::jsonb,
  now(),
  now()
)
on conflict (id) do nothing;

-- gotrue يتطلب سجل هوية مطابقاً حتى يقبل تسجيل الدخول بالبريد
insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  created_at,
  updated_at
)
values (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'sub', '00000000-0000-4000-8000-000000000001',
    'email', 'owner@seco.local',
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(),
  now()
)
on conflict (provider_id, provider) do nothing;

-- تريجر handle_new_user أنشأ الملف بدور auditor؛ نرقّيه إلى المالك.
update public.profiles
set role = 'owner', full_name = 'مالك النظام'
where id = '00000000-0000-4000-8000-000000000001';


-- ═══════════════════════════════════════════════════════════════════════
-- إنشاء المالك في الإنتاج
--
-- 1) Supabase Dashboard → Authentication → Users → Add user
--    فعّل "Auto Confirm User" وأدخل بريداً وكلمة مرور قوية.
--
-- 2) في SQL Editor، رقّه إلى مالك:
--
--      update public.profiles
--      set role = 'owner', full_name = 'الاسم'
--      where id = (select id from auth.users where email = 'البريد');
--
-- هذه هي الحركة اليدوية الوحيدة المسموح بها على قاعدة الإنتاج: لا يمكن
-- أن يمنح النظام نفسه أول مالك، وبعدها يدير المالك بقية المستخدمين
-- من داخل النظام.
-- ═══════════════════════════════════════════════════════════════════════
