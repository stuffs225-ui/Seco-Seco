-- ═══════════════════════════════════════════════════════════════════════
-- محاكاة بيئة Supabase على PostgreSQL عادي — للتطوير والاختبار المحلي فقط
--
-- ⚠️ هذا الملف ليس ترحيلاً ولا يُطبَّق على أي بيئة حقيقية.
-- Supabase توفّر schema auth والأدوار جاهزة؛ هذا يعيد إنشاء الحد الأدنى
-- منها ليعمل `scripts/local-db/setup.sh` حين يتعذّر تشغيل Supabase محلياً.
--
-- المرجع الرسمي هو `supabase start`. عند توفره استخدمه بدل هذا الملف.
-- ═══════════════════════════════════════════════════════════════════════

-- ── أدوار Supabase ─────────────────────────────────────────────────────

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin noinherit;
  end if;
end
$$;

grant anon, authenticated, service_role to current_user;

-- ── schema auth ────────────────────────────────────────────────────────

create schema if not exists auth authorization current_user;
grant usage on schema auth to anon, authenticated, service_role;

-- مجموعة فرعية من أعمدة auth.users الحقيقية: ما تعتمد عليه ترحيلاتنا،
-- بالإضافة إلى ما يحتاجه seed.sql لإنشاء مستخدم تطوير قابل للدخول.
create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  instance_id        uuid,
  aud                text,
  role               text,
  email              text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data  jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  is_super_admin     boolean,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  confirmation_token text default '',
  recovery_token     text default '',
  email_change       text default '',
  email_change_token_new text default ''
);

create table if not exists auth.identities (
  id              uuid primary key default gen_random_uuid(),
  provider_id     text not null,
  user_id         uuid not null references auth.users (id) on delete cascade,
  identity_data   jsonb not null,
  provider        text not null,
  last_sign_in_at timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (provider_id, provider)
);

-- ── auth.uid() ─────────────────────────────────────────────────────────
-- في Supabase تُقرأ هوية المستخدم من مطالبات الـ JWT التي يحقنها PostgREST
-- كإعداد جلسة. نفس الآلية هنا، فتنتحل الاختبارات هوية مستخدم بـ:
--   set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    'anon'
  );
$$;

create or replace function auth.email()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  );
$$;

grant execute on function auth.uid(), auth.role(), auth.email()
  to anon, authenticated, service_role;

-- ── الامتدادات التي تفعّلها Supabase افتراضياً ─────────────────────────

create extension if not exists pgcrypto with schema public;
create extension if not exists btree_gist with schema public;
