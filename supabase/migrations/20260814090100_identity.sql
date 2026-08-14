-- ═══════════════════════════════════════════════════════════════════════
-- 0002 — الهوية والأدوار والصلاحيات
--
-- الأدوار الخمسة من §12 ومصفوفة الصلاحيات الحساسة من §28.
--
-- ملاحظة على النطاق: المرحلة الحالية تُفعِّل دور المالك وحده، لكن البنية
-- كاملة من الآن. السبب أن فصل التقارير الداخلية عن تقارير الموزعين (V5.8)
-- مبني على الصلاحيات؛ إضافتها لاحقاً تعني إعادة كتابة كل سياسات RLS.
-- تفعيل بقية الأدوار يصبح مجرد إنشاء مستخدم بالدور المناسب.
-- ═══════════════════════════════════════════════════════════════════════

-- ── الأدوار ────────────────────────────────────────────────────────────

create type public.user_role as enum (
  'owner',        -- المالك/المدير: إدارة النظام والشركاء والنسب والاعتمادات والإقفال
  'operations',   -- مسؤول العمليات: المشتريات والمخزون والعهد والمرتجعات
  'collections',  -- مسؤول التحصيل: التحصيلات وأرصدة الموزعين
  'finance',      -- مسؤول مالي: السحوبات والتوزيعات والتقارير المالية
  'auditor'       -- مدقق/مشاهد: قراءة التقارير وسجل التدقيق فقط
);

comment on type public.user_role is 'أدوار النظام الخمسة (§12).';

-- ── ملفات المستخدمين ───────────────────────────────────────────────────

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text        not null default '',
  role        public.user_role not null default 'auditor',
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'ملف المستخدم ودوره. الدور الافتراضي auditor (الأقل صلاحية) — الترقية '
  'قرار صريح، فلا يحصل مستخدم جديد على صلاحيات بالخطأ.';

create index profiles_role_idx on public.profiles (role) where is_active;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;

-- ── إنشاء ملف تلقائياً عند إنشاء مستخدم ────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── دوال الصلاحيات ─────────────────────────────────────────────────────

create or replace function public.current_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active;
$$;

comment on function public.current_role is
  'دور المستخدم الحالي، أو null إن لم يكن مسجلاً أو كان معطلاً.';

/*
  مصفوفة الصلاحيات (§28).

  تُعرَّف في مكان واحد لأن تكرارها عبر سياسات RLS يجعل تغيير قاعدة واحدة
  تعديلاً في عشرات المواضع — وهو بالضبط ما ينتج ثغرة.

  المالك يملك كل شيء ضمناً، فلا يُذكر في القائمة.
*/
create or replace function public.role_has_permission(
  p_role       public.user_role,
  p_permission text
)
returns boolean
language sql
immutable
as $$
  select case
    when p_role is null then false
    when p_role = 'owner' then true

    when p_role = 'operations' then p_permission in (
      'items.manage',
      'suppliers.manage',
      'purchases.manage',
      'distributors.manage',
      'deals.draft',
      'deals.deliver',
      'deals.record_sale',
      'deals.return',
      'reports.internal'
    )

    when p_role = 'collections' then p_permission in (
      'payments.record',
      'payments.allocate',
      'distributors.view',
      'reports.distributor'
    )

    when p_role = 'finance' then p_permission in (
      'payments.record',
      'payments.allocate',
      'payments.reverse',
      'credits.resolve',
      'partners.withdrawals',
      'reports.internal',
      'reports.distributor'
    )

    -- المدقق: قراءة فقط، ولا يملك أي صلاحية تغيير
    when p_role = 'auditor' then p_permission in (
      'reports.internal'
    )

    else false
  end;
$$;

comment on function public.role_has_permission is
  'مصفوفة الصلاحيات الحساسة (§28) — مصدر واحد لكل قرارات التفويض.';

create or replace function public.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select public.role_has_permission(public.current_role(), p_permission);
$$;

comment on function public.has_permission is
  'هل يملك المستخدم الحالي هذه الصلاحية؟ تُستخدم في سياسات RLS.';

/*
  الحارس الذي تبدأ به كل دالة RPC حساسة.

  يرفع استثناء بدل إرجاع false، حتى لا تتمكن دالة من إكمال عملها بصمت
  إذا نُسي فحص القيمة المُرجَعة.
*/
create or replace function public.assert_permission(p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
begin
  if not public.has_permission(p_permission) then
    raise exception 'لا تملك صلاحية تنفيذ هذه العملية (%).', p_permission
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function public.assert_permission is
  'حارس الصلاحية — يُستدعى في أول كل RPC حساسة (§28، §30).';

-- ── سياسات الوصول ──────────────────────────────────────────────────────

-- كل مستخدم نشط يرى ملفه
create policy profiles_select_self
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

-- المالك يرى ويدير كل الملفات
create policy profiles_select_owner
  on public.profiles for select
  to authenticated
  using (public.current_role() = 'owner');

create policy profiles_insert_owner
  on public.profiles for insert
  to authenticated
  with check (public.current_role() = 'owner');

create policy profiles_update_owner
  on public.profiles for update
  to authenticated
  using (public.current_role() = 'owner')
  with check (public.current_role() = 'owner');

-- لا سياسة حذف: تعطيل المستخدم يكون بـ is_active = false، لأن حذف الملف
-- يقطع ارتباط حركاته التاريخية في سجل التدقيق (§11).

-- سجل التدقيق: من يملك صلاحية التقارير الداخلية يقرؤه. لا أحد يكتب فيه
-- مباشرة — الكتابة عبر write_audit وحدها.
create policy audit_log_select
  on public.audit_log for select
  to authenticated
  using (public.has_permission('reports.internal'));
