-- ═══════════════════════════════════════════════════════════════════════
-- سيكو سيكو — تهيئة قاعدة البيانات بلصق واحد
--
-- ⚠️ ملف مولَّد آلياً من supabase/migrations — لا تحرره.
--    لإعادة توليده: npm run bootstrap:build
--
-- الاستخدام:
--   1. عدّل السطور المعلَّمة ✏️ أدناه
--   2. الصق الملف كاملاً في Supabase → SQL Editor
--   3. اضغط Run
--
-- الملف كله معاملة واحدة: إن فشل أي سطر لا يُطبَّق شيء إطلاقاً، فتصحّح
-- وتعيد التشغيل بأمان. وهو مخصص لمشروع جديد فارغ — بعد أول نجاح تُطبَّق
-- الترحيلات اللاحقة عبر workflow أو `npm run db:push`.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  ✏️  عدّل هذه السطور قبل التشغيل                                    │
-- └─────────────────────────────────────────────────────────────────────┘

create schema seco_bootstrap;

create table seco_bootstrap.config (
  owner_email text not null,
  owner_code  text not null,
  owner_name  text not null
);

insert into seco_bootstrap.config (owner_email, owner_code, owner_name) values (
  'owner@example.com',   -- ✏️ بريدك الذي ستنشئ به الحساب
  'Aa123123',            -- ✏️ رمز الدخول (8 خانات على الأقل)
  'المالك'               -- ✏️ اسمك كما يظهر في النظام
);

/*
  التحقق يقع هنا قبل أي إنشاء.

  لو تُرك في نهاية الملف لكانت الترحيلات قد طُبِّقت بالفعل عند اكتشاف
  الخطأ، فتفشل إعادة التشغيل على «الجدول موجود». الفحص المبكر مع
  المعاملة الواحدة يجعل الملف قابلاً لإعادة التشغيل فعلاً لا ادعاءً.
*/
do $seco_check$
declare
  v_cfg record;
begin
  select * into v_cfg from seco_bootstrap.config limit 1;

  if v_cfg.owner_email = 'owner@example.com' then
    raise exception
      'لم تُعدّل البريد في أعلى الملف. غيّر owner@example.com إلى بريدك ثم أعد التشغيل. لم يُطبَّق أي تغيير.';
  end if;

  if position('@' in v_cfg.owner_email) = 0 then
    raise exception 'البريد % ليس بصيغة صحيحة.', v_cfg.owner_email;
  end if;

  if length(v_cfg.owner_code) < 8 then
    raise exception 'رمز الدخول يجب أن يكون 8 خانات على الأقل.';
  end if;
end
$seco_check$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) بنية قاعدة البيانات — الترحيلات بترتيبها
-- ═══════════════════════════════════════════════════════════════════════


-- ─── 20260814090000_foundation.sql ───────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0001 — الأساس
--
-- الأنواع المشتركة، سجل التدقيق، ودوال الحراسة التي تعتمد عليها
-- كل الترحيلات التالية.
--
-- المرجع: الخطة الرئيسية §11 (الحوكمة والضوابط)، §30 (تعليمات نهائية)
-- ═══════════════════════════════════════════════════════════════════════

-- ── نطاقات الدقة الرقمية ───────────────────────────────────────────────
-- لا floats في أي مكان من النظام. المال والوزن يُخزَّنان كـ numeric بدقة
-- محددة، وسعر الجرام بدقة أعلى لأن كسوره تتراكم عبر آلاف الحركات.

create domain money_amount as numeric(18, 4);
comment on domain money_amount is 'مبلغ مالي — 4 خانات عشرية';

create domain weight_grams as numeric(14, 3);
comment on domain weight_grams is 'وزن بالجرام — 3 خانات عشرية';

create domain rate_per_gram as numeric(18, 6);
comment on domain rate_per_gram is
  'تكلفة أو سعر الجرام — 6 خانات عشرية. لا تُضرب في الوزن لاشتقاق '
  'رصيد متبق؛ الرصيد يُشتق من مجموع حركات الـ Ledger (§26).';

-- ── تحديث updated_at آلياً ─────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at is
  'تريجر مشترك: يحدّث updated_at عند كل تعديل.';

-- ── منع التعديل والحذف على جداول الـ Ledger ────────────────────────────
-- المبدأ الثاني في الخطة: الـ Ledger مصدر الحقيقة ولا يُعدَّل. التصحيح
-- يكون بحركة عكسية تُضاف، لا بتغيير حركة سابقة (§11، §24.2، §26).

create or replace function public.forbid_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'الجدول % سجل حركات غير قابل للتعديل أو الحذف. التصحيح يكون بحركة عكسية.',
    tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

comment on function public.forbid_mutation is
  'تريجر حراسة: يُثبَّت BEFORE UPDATE OR DELETE على كل جدول ledger.';

-- ── سجل التدقيق ────────────────────────────────────────────────────────
-- كل عملية حساسة تكتب هنا: من، ماذا، متى، وعلى أي كيان (§11، §28).

create table public.audit_log (
  id            bigint generated always as identity primary key,
  occurred_at   timestamptz  not null default now(),
  actor_id      uuid         references auth.users (id) on delete set null,
  action        text         not null,
  entity_type   text         not null,
  entity_id     text,
  -- لقطة مما تغيّر — تكفي لإعادة بناء ما حدث دون قراءة الجداول الأصلية
  details       jsonb        not null default '{}'::jsonb,
  constraint audit_log_action_not_blank check (btrim(action) <> ''),
  constraint audit_log_entity_type_not_blank check (btrim(entity_type) <> '')
);

comment on table public.audit_log is
  'سجل التدقيق — كل حركة حساسة تُقيَّد هنا ولا تُحذف أبداً (§11).';

create index audit_log_entity_idx
  on public.audit_log (entity_type, entity_id, occurred_at desc);
create index audit_log_actor_idx
  on public.audit_log (actor_id, occurred_at desc);
create index audit_log_occurred_at_idx
  on public.audit_log (occurred_at desc);

-- سجل التدقيق لا يُعدَّل ولا يُحذف منه شيء
create trigger audit_log_immutable
  before update or delete on public.audit_log
  for each row execute function public.forbid_mutation();

alter table public.audit_log enable row level security;

-- ── كتابة سجل التدقيق ──────────────────────────────────────────────────

create or replace function public.write_audit(
  p_action      text,
  p_entity_type text,
  p_entity_id   text default null,
  p_details     jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_id bigint;
begin
  insert into public.audit_log (actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, coalesce(p_details, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.write_audit is
  'تُستدعى من داخل كل RPC حساسة. security definer لأن الجدول مقفل بـ RLS.';

-- الكتابة تتم عبر write_audit وحدها، لا مباشرة من العميل
revoke all on function public.write_audit(text, text, text, jsonb) from public, anon, authenticated;


-- ─── 20260814090100_identity.sql ─────────────────────────────

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


-- ─── 20260814090200_settings.sql ─────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0003 — إعدادات النظام
--
-- القرارات القابلة للتغيير من §16 وإضافة V5.7، مخزَّنة كإعدادات لا كثوابت
-- في الشيفرة — لأن تغيير أي منها قرار عمل، لا نشرة برمجية.
-- ═══════════════════════════════════════════════════════════════════════

create table public.app_settings (
  key         text        primary key,
  value       jsonb       not null,
  description text        not null default '',
  updated_by  uuid        references auth.users (id) on delete set null,
  updated_at  timestamptz not null default now(),
  constraint app_settings_key_not_blank check (btrim(key) <> '')
);

comment on table public.app_settings is
  'إعدادات النظام — القرارات المحاسبية والتشغيلية القابلة للتغيير (§16).';

alter table public.app_settings enable row level security;

-- ── قراءة إعداد ────────────────────────────────────────────────────────

create or replace function public.get_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select s.value from public.app_settings s where s.key = p_key;
$$;

comment on function public.get_setting is
  'قراءة إعداد. security definer لأن قواعد الأعمال تحتاجه بغض النظر عن دور المنفّذ.';

/*
  قراءة إعداد نصي مع رفض المفتاح المجهول.

  الصمت هنا خطر: إعداد ناقص يعني أن قاعدة عمل ستتصرف بقيمة افتراضية
  لم يقررها أحد. الاستثناء أفضل من حساب مالي بقيمة مفترضة.
*/
create or replace function public.get_setting_text(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_value jsonb;
begin
  v_value := public.get_setting(p_key);

  if v_value is null then
    raise exception 'الإعداد % غير معرَّف في النظام.', p_key
      using errcode = 'no_data_found';
  end if;

  return v_value #>> '{}';
end;
$$;

-- ── تدقيق تغييرات الإعدادات ────────────────────────────────────────────
-- تغيير إعداد يغيّر سلوك حسابات مالية، فيجب أن يبقى أثره واضحاً (§11).

create or replace function public.audit_setting_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();

  if new.value is distinct from old.value then
    perform public.write_audit(
      'setting.changed',
      'app_settings',
      new.key,
      jsonb_build_object('from', old.value, 'to', new.value)
    );
  end if;

  return new;
end;
$$;

create trigger app_settings_audit
  before update on public.app_settings
  for each row execute function public.audit_setting_change();

-- ── سياسات الوصول ──────────────────────────────────────────────────────

-- كل مستخدم مسجَّل يقرأ الإعدادات — الشاشات تحتاجها لتعرف كيف تتصرف
create policy app_settings_select
  on public.app_settings for select
  to authenticated
  using (auth.uid() is not null);

-- المالك وحده يغيّرها
create policy app_settings_update_owner
  on public.app_settings for update
  to authenticated
  using (public.current_role() = 'owner')
  with check (public.current_role() = 'owner');

-- لا insert ولا delete من العميل: مجموعة المفاتيح تُعرَّف في الترحيلات،
-- فلا يستطيع أحد إنشاء مفتاح لا تعرفه قواعد الأعمال أو حذف مفتاح تعتمد عليه.

-- ── القيم المعتمدة ─────────────────────────────────────────────────────

insert into public.app_settings (key, value, description) values

  -- §16.1 + §24.9 — القرار المعتمد: الربح يتحقق عند التصريف الفعلي.
  -- النقد المحصل يبقى مؤشراً مستقلاً تماماً ولا يخلط بالربح.
  ('profit_recognition', '"on_sale"'::jsonb,
   'متى يصبح الربح محققاً: on_sale عند تسجيل التصريف، on_collection عند التحصيل'),

  -- §16.7 — القرار المعتمد: كل مصروف يحمل مفتاحه الخاص، فالمصاريف
  -- المفعّلة ترفع تكلفة الجرام والباقي مصروف تشغيلي.
  ('expense_capitalization', '"per_expense_flag"'::jsonb,
   'رسملة مصاريف الشراء: per_expense_flag بمفتاح لكل مصروف، always دائماً، never أبداً'),

  -- إضافة V5.7 — القرار المعتمد: الاسترداد يُقيَّم تجارياً بسعر الجرام
  -- في الصفقة نفسها (مثال الخطة: 100ج × 24 = 2,400).
  ('return_commercial_valuation', '"deal_price_per_gram"'::jsonb,
   'تقييم الكمية المستردة تجاه الموزع: deal_price_per_gram أو manual_value'),

  -- §24.1 — القرار المعتمد: صفقة واحدة من دفعة واحدة. جدول deal_lines
  -- مبني للتوسع، والقيد يُرفع بتغيير هذا الإعداد وحده.
  ('deal_multi_lot', 'false'::jsonb,
   'هل يُسمح للصفقة بأسطر من أكثر من دفعة؟'),

  -- §V5.1 — التأكيد عند كل تصدير يقلل احتمال إرسال تقرير داخلي بالخطأ
  ('report_type_confirmation_required', 'true'::jsonb,
   'هل يؤكد المستخدم نوع التقرير عند كل تصدير حتى مع وجود افتراضي؟'),

  ('currency_label', '"ريال"'::jsonb,
   'رمز العملة المعروض في الشاشات والتقارير');


-- ─── 20260814090300_inventory.sql ────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0004 — الأصناف والمشتريات والدفعات والمخزون
--
-- المبدأ المحاسبي الأول (§2): كل عملية شراء تنشئ دفعة مستقلة حتى لو كان
-- الصنف نفسه، لأن تكلفة الجرام تختلف من دفعة إلى أخرى.
--
-- المرجع: §2، §4، §14، §16.7
-- ═══════════════════════════════════════════════════════════════════════

-- ── الأصناف ────────────────────────────────────────────────────────────

create table public.items (
  id          uuid        primary key default gen_random_uuid(),
  code        text        not null unique,
  name        text        not null,
  description text        not null default '',
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint items_code_not_blank check (btrim(code) <> ''),
  constraint items_name_not_blank check (btrim(name) <> '')
);

comment on table public.items is 'الأصناف — التعريف فقط. الكمية والتكلفة تخص الدفعة لا الصنف.';

create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

alter table public.items enable row level security;

-- ── الموردون ───────────────────────────────────────────────────────────

create table public.suppliers (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  phone      text        not null default '',
  notes      text        not null default '',
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_name_not_blank check (btrim(name) <> '')
);

create trigger suppliers_set_updated_at
  before update on public.suppliers
  for each row execute function public.set_updated_at();

alter table public.suppliers enable row level security;

-- ── المشتريات ──────────────────────────────────────────────────────────

create table public.purchases (
  id            uuid        primary key default gen_random_uuid(),
  supplier_id   uuid        references public.suppliers (id) on delete restrict,
  purchase_date date        not null,
  invoice_ref   text        not null default '',
  notes         text        not null default '',
  created_by    uuid        references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.purchases is
  'رأس عملية الشراء. الوزن والقيمة يخصان الدفعة (lot) المرتبطة بها.';

create index purchases_date_idx on public.purchases (purchase_date desc);
create index purchases_supplier_idx on public.purchases (supplier_id);

create trigger purchases_set_updated_at
  before update on public.purchases
  for each row execute function public.set_updated_at();

alter table public.purchases enable row level security;

-- ── مصاريف الشراء (§16.7) ──────────────────────────────────────────────
-- القرار المعتمد: مفتاح رسملة لكل مصروف. المصاريف المفعّلة تدخل في تكلفة
-- الدفعة وترفع تكلفة الجرام؛ الباقي مصروف تشغيلي يخصم من الربح لاحقاً.

create table public.purchase_expenses (
  id              uuid         primary key default gen_random_uuid(),
  purchase_id     uuid         not null references public.purchases (id) on delete cascade,
  expense_type    text         not null,
  amount          money_amount not null,
  include_in_cost boolean      not null default true,
  notes           text         not null default '',
  created_at      timestamptz  not null default now(),
  constraint purchase_expenses_amount_positive check (amount > 0),
  constraint purchase_expenses_type_not_blank check (btrim(expense_type) <> '')
);

comment on column public.purchase_expenses.include_in_cost is
  'هل يُرسمل هذا المصروف في تكلفة الدفعة؟ (§16.7 — القرار المعتمد: '
  'مفتاح لكل مصروف).';

create index purchase_expenses_purchase_idx
  on public.purchase_expenses (purchase_id);

alter table public.purchase_expenses enable row level security;

-- ── الدفعات (Lots) ─────────────────────────────────────────────────────

create table public.lots (
  id                   uuid         primary key default gen_random_uuid(),
  lot_no               text         not null unique,
  item_id              uuid         not null references public.items (id) on delete restrict,
  purchase_id          uuid         not null references public.purchases (id) on delete restrict,
  received_date        date         not null,

  purchased_weight_g   weight_grams not null,
  purchase_value       money_amount not null,
  -- مجموع المصاريف المرسملة لحظة الإنشاء. تُثبَّت هنا ولا تُشتق لاحقاً
  -- حتى لا تتغير تكلفة دفعة بيعت منها كميات بأثر رجعي.
  capitalized_expenses money_amount not null default 0,

  total_cost           money_amount generated always as
                         (purchase_value + capitalized_expenses) stored,
  cost_per_g           rate_per_gram generated always as
                         ((purchase_value + capitalized_expenses) / purchased_weight_g) stored,

  notes                text         not null default '',
  created_by           uuid         references auth.users (id) on delete set null,
  created_at           timestamptz  not null default now(),

  constraint lots_weight_positive check (purchased_weight_g > 0),
  constraint lots_value_not_negative check (purchase_value >= 0),
  constraint lots_expenses_not_negative check (capitalized_expenses >= 0)
);

comment on table public.lots is
  'الدفعة — وحدة التكلفة في النظام. كل شراء ينشئ دفعة مستقلة حتى لو '
  'تكرر الصنف، لأن تكلفة الجرام تختلف بينها (§2).';

comment on column public.lots.cost_per_g is
  'تكلفة الجرام محسوبة آلياً. مثال §14: 21,000 ÷ 1,200ج = 17.50. '
  'لا تُضرب في الوزن لاشتقاق تكلفة متبقية — الرصيد من الـ ledger (§26).';

create index lots_item_idx on public.lots (item_id);
create index lots_purchase_idx on public.lots (purchase_id);
create index lots_received_date_idx on public.lots (received_date desc);

alter table public.lots enable row level security;

-- ── دفتر حركات المخزون ─────────────────────────────────────────────────
-- مصدر الحقيقة للوزن المتاح في كل دفعة. الرصيد يُشتق بالجمع، ولا يُخزَّن
-- كحقل قابل للتعديل (§26).

create type public.inventory_entry_type as enum (
  'LOT_RECEIVED',   -- استلام دفعة جديدة — يزيد المتاح
  'DELIVERED',      -- تسليم كمية لموزع — يخفض المتاح وينقلها لعهدته
  'RETURNED',       -- استرداد كمية من موزع — تعود بنفس تكلفتها الأصلية
  'ADJUSTMENT'      -- تسوية معتمدة بسبب موثق
);

create table public.inventory_ledger (
  id             bigint       generated always as identity primary key,
  lot_id         uuid         not null references public.lots (id) on delete restrict,
  entry_type     public.inventory_entry_type not null,
  -- موجب يزيد المتاح في المخزن، سالب يخفضه
  weight_delta_g weight_grams not null,
  cost_delta     money_amount not null default 0,
  ref_type       text         not null default '',
  ref_id         text,
  notes          text         not null default '',
  occurred_at    timestamptz  not null default now(),
  created_by     uuid         references auth.users (id) on delete set null,
  constraint inventory_ledger_delta_not_zero check (weight_delta_g <> 0)
);

comment on table public.inventory_ledger is
  'دفتر حركات المخزون — مصدر الحقيقة للوزن المتاح. append-only.';

create index inventory_ledger_lot_idx
  on public.inventory_ledger (lot_id, occurred_at);
create index inventory_ledger_ref_idx
  on public.inventory_ledger (ref_type, ref_id);

create trigger inventory_ledger_immutable
  before update or delete on public.inventory_ledger
  for each row execute function public.forbid_mutation();

alter table public.inventory_ledger enable row level security;

-- ── رصيد المخزون المشتق ────────────────────────────────────────────────

create view public.v_lot_stock
with (security_invoker = true)
as
select
  l.id                            as lot_id,
  l.lot_no,
  l.item_id,
  i.code                          as item_code,
  i.name                          as item_name,
  l.received_date,
  l.purchased_weight_g,
  l.purchase_value,
  l.capitalized_expenses,
  l.total_cost,
  l.cost_per_g,
  -- الوزن المتاح في المخزن = مجموع حركات الدفعة
  coalesce(sum(le.weight_delta_g), 0)::weight_grams  as on_hand_weight_g,
  -- الوزن الخارج للموزعين حالياً = المشترى ناقص المتاح
  (l.purchased_weight_g - coalesce(sum(le.weight_delta_g), 0))::weight_grams
                                                     as out_weight_g,
  /*
    تكلفة المخزون المتاح — من مجموع حركات التكلفة، لا بالضرب.

    الضرب (وزن × تكلفة الجرام) يبدو أبسط لكنه ينحرف: دفعة 21,500 على
    1,200ج تكلفة جرامها 17.916667 (كسر غير منتهٍ)، وضربها في 1,200 يعطي
    21,500.0004 لا 21,500. الفرق يتراكم مع كل حركة.

    لذلك كل حركة تحمل cost_delta الخاصة بها، والتكلفة المتبقية = مجموعها.
    هذه هي القاعدة الحاكمة في §26، وتطبيقها هنا يجعل رقم المخزون مطابقاً
    تماماً لتكلفة الدفعة عندما لا يخرج منها شيء.
  */
  coalesce(sum(le.cost_delta), 0)::money_amount      as on_hand_cost
from public.lots l
join public.items i on i.id = l.item_id
left join public.inventory_ledger le on le.lot_id = l.id
group by l.id, i.code, i.name;

comment on view public.v_lot_stock is
  'رصيد كل دفعة مشتقاً من دفتر الحركات — لا يوجد حقل رصيد مخزَّن (§26).';

-- ── سياسات الوصول ──────────────────────────────────────────────────────

-- القراءة متاحة لكل مستخدم مسجَّل: هذه بيانات تشغيلية داخلية، والفصل
-- الحساس (التكلفة والربح) يقع عند حدود تقارير الموزعين لا هنا.
create policy items_select on public.items
  for select to authenticated using (auth.uid() is not null);
create policy suppliers_select on public.suppliers
  for select to authenticated using (auth.uid() is not null);
create policy purchases_select on public.purchases
  for select to authenticated using (auth.uid() is not null);
create policy purchase_expenses_select on public.purchase_expenses
  for select to authenticated using (auth.uid() is not null);
create policy lots_select on public.lots
  for select to authenticated using (auth.uid() is not null);
create policy inventory_ledger_select on public.inventory_ledger
  for select to authenticated using (auth.uid() is not null);

-- الأصناف والموردون: إدارة مباشرة لمن يملك الصلاحية (بيانات مرجعية،
-- لا أثر محاسبي لها بذاتها).
create policy items_write on public.items
  for all to authenticated
  using (public.has_permission('items.manage'))
  with check (public.has_permission('items.manage'));

create policy suppliers_write on public.suppliers
  for all to authenticated
  using (public.has_permission('suppliers.manage'))
  with check (public.has_permission('suppliers.manage'));

/*
  المشتريات والدفعات والمخزون: لا سياسات كتابة إطلاقاً.

  إنشاء دفعة يجب أن يكتب في lots و purchase_expenses و inventory_ledger
  معاً وإلا اختلّ الرصيد. لذلك المسار الوحيد هو دالة create_purchase_lot
  داخل معاملة واحدة (§30). غياب السياسة هنا ليس سهواً — هو القفل.
*/


-- ─── 20260814090400_inventory_rpc.sql ────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0005 — دوال المخزون
--
-- المسار الوحيد لإنشاء دفعة. يكتب في purchases و purchase_expenses و lots
-- و inventory_ledger داخل معاملة واحدة، لأن نجاح بعضها دون بعض يترك
-- المخزون مختلاً (§30).
-- ═══════════════════════════════════════════════════════════════════════

-- ── ترقيم الدفعات ──────────────────────────────────────────────────────

create sequence public.lot_no_seq;

create or replace function public.next_lot_no(p_date date)
returns text
language sql
volatile
as $$
  select 'LOT-' || to_char(p_date, 'YYYY') || '-'
       || lpad(nextval('public.lot_no_seq')::text, 4, '0');
$$;

comment on function public.next_lot_no is
  'رقم دفعة فريد. المتسلسلة ذرية فلا تتصادم عمليتان متزامنتان.';

-- ── إنشاء دفعة شراء ────────────────────────────────────────────────────

create or replace function public.create_purchase_lot(
  p_item_id         uuid,
  p_purchase_date   date,
  p_weight_g        weight_grams,
  p_purchase_value  money_amount,
  p_supplier_id     uuid    default null,
  p_invoice_ref     text    default '',
  p_notes           text    default '',
  -- مصفوفة مصاريف: [{"expense_type":"نقل","amount":500,"include_in_cost":true}]
  p_expenses        jsonb   default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_purchase_id   uuid;
  v_lot_id        uuid;
  v_lot_no        text;
  v_capitalized   money_amount := 0;
  v_policy        text;
  v_expense       jsonb;
  v_include       boolean;
  v_amount        money_amount;
begin
  perform public.assert_permission('purchases.manage');

  -- ── التحقق من المدخلات ───────────────────────────────────────────────
  -- القيود موجودة على الجداول أيضاً؛ الفحص هنا يعطي رسالة عربية مفهومة
  -- بدل نص قيد قاعدة بيانات.

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن الدفعة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_purchase_value is null or p_purchase_value < 0 then
    raise exception 'قيمة الشراء لا يمكن أن تكون سالبة.'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.items where id = p_item_id) then
    raise exception 'الصنف غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  -- ── رأس عملية الشراء ─────────────────────────────────────────────────

  insert into public.purchases
    (supplier_id, purchase_date, invoice_ref, notes, created_by)
  values
    (p_supplier_id, p_purchase_date, coalesce(p_invoice_ref, ''),
     coalesce(p_notes, ''), auth.uid())
  returning id into v_purchase_id;

  -- ── المصاريف ورسملتها (§16.7) ────────────────────────────────────────

  v_policy := public.get_setting_text('expense_capitalization');

  for v_expense in select * from jsonb_array_elements(coalesce(p_expenses, '[]'::jsonb))
  loop
    v_amount := (v_expense ->> 'amount')::money_amount;

    if v_amount is null or v_amount <= 0 then
      raise exception 'قيمة المصروف يجب أن تكون أكبر من صفر.'
        using errcode = 'check_violation';
    end if;

    -- السياسة العامة تحكم أولاً؛ المفتاح الفردي يُقرأ فقط في وضع
    -- per_expense_flag، وهو القرار المعتمد لهذا النظام.
    v_include := case v_policy
      when 'always' then true
      when 'never'  then false
      else coalesce((v_expense ->> 'include_in_cost')::boolean, true)
    end;

    insert into public.purchase_expenses
      (purchase_id, expense_type, amount, include_in_cost, notes)
    values
      (v_purchase_id,
       coalesce(v_expense ->> 'expense_type', 'غير محدد'),
       v_amount,
       v_include,
       coalesce(v_expense ->> 'notes', ''));

    if v_include then
      v_capitalized := v_capitalized + v_amount;
    end if;
  end loop;

  -- ── الدفعة ───────────────────────────────────────────────────────────
  -- cost_per_g عمود مولَّد: (قيمة الشراء + المصاريف المرسملة) ÷ الوزن

  v_lot_no := public.next_lot_no(p_purchase_date);

  insert into public.lots (
    lot_no, item_id, purchase_id, received_date,
    purchased_weight_g, purchase_value, capitalized_expenses,
    notes, created_by
  )
  values (
    v_lot_no, p_item_id, v_purchase_id, p_purchase_date,
    p_weight_g, p_purchase_value, v_capitalized,
    coalesce(p_notes, ''), auth.uid()
  )
  returning id into v_lot_id;

  -- ── إدخال الكمية للمخزون ─────────────────────────────────────────────

  insert into public.inventory_ledger (
    lot_id, entry_type, weight_delta_g, cost_delta,
    ref_type, ref_id, notes, created_by
  )
  values (
    v_lot_id, 'LOT_RECEIVED', p_weight_g,
    p_purchase_value + v_capitalized,
    'purchase', v_purchase_id::text,
    'استلام دفعة ' || v_lot_no, auth.uid()
  );

  perform public.write_audit(
    'lot.created',
    'lots',
    v_lot_id::text,
    jsonb_build_object(
      'lot_no',      v_lot_no,
      'item_id',     p_item_id,
      'weight_g',    p_weight_g,
      'value',       p_purchase_value,
      'capitalized', v_capitalized,
      'cost_per_g',  (select cost_per_g from public.lots where id = v_lot_id)
    )
  );

  return v_lot_id;
end;
$$;

comment on function public.create_purchase_lot is
  'المسار الوحيد لإنشاء دفعة شراء — معاملة ذرية واحدة (§4، §30).';

revoke all on function public.create_purchase_lot(
  uuid, date, weight_grams, money_amount, uuid, text, text, jsonb
) from public, anon;

grant execute on function public.create_purchase_lot(
  uuid, date, weight_grams, money_amount, uuid, text, text, jsonb
) to authenticated;


-- ─── 20260814090500_distributors.sql ─────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0006 — الموزعون
--
-- المرجع: §4، §8، §24.11 (حدود العهدة والائتمان)
-- ═══════════════════════════════════════════════════════════════════════

create table public.distributors (
  id                 uuid         primary key default gen_random_uuid(),
  code               text         not null unique,
  name               text         not null,
  phone              text         not null default '',
  -- حدود العهدة: صفر يعني بلا حد. تُستخدم للتنبيه لا للمنع الصارم،
  -- لأن تجاوز الحد قرار عمل قد يوافق عليه المدير (§24.11)
  credit_limit_value money_amount not null default 0,
  credit_limit_weight weight_grams not null default 0,
  notes              text         not null default '',
  is_active          boolean      not null default true,
  created_at         timestamptz  not null default now(),
  updated_at         timestamptz  not null default now(),
  constraint distributors_code_not_blank check (btrim(code) <> ''),
  constraint distributors_name_not_blank check (btrim(name) <> ''),
  constraint distributors_limits_not_negative
    check (credit_limit_value >= 0 and credit_limit_weight >= 0)
);

comment on table public.distributors is
  'الموزعون. الأرصدة لا تُخزَّن هنا — تُشتق من الصفقات والدفعات (§26).';

create index distributors_active_idx on public.distributors (name) where is_active;

create trigger distributors_set_updated_at
  before update on public.distributors
  for each row execute function public.set_updated_at();

alter table public.distributors enable row level security;

create policy distributors_select on public.distributors
  for select to authenticated using (auth.uid() is not null);

create policy distributors_write on public.distributors
  for all to authenticated
  using (public.has_permission('distributors.manage'))
  with check (public.has_permission('distributors.manage'));


-- ─── 20260814090600_deals.sql ────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0007 — الصفقات ودفتر حركاتها
--
-- الصفقة هي الكيان المحوري لكل تعامل مع الموزع (§24.1)، والـ Ledger هو
-- مصدر الحقيقة لكل رصيد فيها (§24.2، §26). لا يوجد حقل رصيد مخزَّن.
--
-- المرجع: §18، §19، §24.1–24.3، §25، §26
-- ═══════════════════════════════════════════════════════════════════════

-- ── دورة حياة الصفقة (§24.3) ───────────────────────────────────────────
-- هذه الحالة مخزَّنة لأنها قرار إداري صريح، بخلاف حالتَي الوزن والمال
-- اللتين تُشتقان من الأرصدة.

create type public.deal_status as enum (
  'draft',          -- مجهّزة ولم تُسلَّم بعد
  'active',         -- تم التسليم والصفقة جارية
  'in_settlement',  -- قيد المصالحة النهائية
  'ready_to_close', -- المصالحة بلا فروقات — تنتظر اعتماد الإغلاق
  'closed',         -- مغلقة بلقطة نهائية
  'reopened',       -- أُعيد فتحها بصلاحية خاصة
  'cancelled'       -- ألغيت بحركة عكسية
);

-- ── حالتا الوزن والمال (§24.3) ─────────────────────────────────────────
-- منفصلتان عمداً: صفقة مدفوعة بالكامل مع وزن مفتوح ليست مغلقة، والعكس.

create type public.quantity_status as enum (
  'open',              -- لا توجد تسوية كمية بعد
  'partially_settled', -- جزء من الوزن سُوّي
  'fully_settled',     -- كل الوزن سُوّي
  'exception'          -- الوزن المسوّى يتجاوز المسلَّم — يحتاج تدخلاً
);

create type public.payment_status as enum (
  'unpaid',
  'partially_paid',
  'fully_paid',
  'credit_balance',    -- المدفوع يتجاوز القيمة المعدلة (§24.5)
  'exception'
);

-- ── الصفقات ────────────────────────────────────────────────────────────

create table public.deals (
  id             uuid        primary key default gen_random_uuid(),
  deal_no        text        not null unique,
  distributor_id uuid        not null references public.distributors (id) on delete restrict,
  status         public.deal_status not null default 'draft',
  delivery_date  date,
  due_date       date,
  notes          text        not null default '',
  opened_by      uuid        references auth.users (id) on delete set null,
  closed_at      timestamptz,
  closed_by      uuid        references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint deals_closed_consistency
    check ((status = 'closed') = (closed_at is not null))
);

comment on table public.deals is
  'رأس الصفقة ودورة حياتها. الأوزان والقيم والأرصدة كلها في deal_ledger '
  'وتُشتق عبر v_deal_* — لا حقل رصيد هنا (§26).';

create index deals_distributor_idx on public.deals (distributor_id, created_at desc);
create index deals_status_idx on public.deals (status);
create index deals_due_date_idx on public.deals (due_date) where status = 'active';

create trigger deals_set_updated_at
  before update on public.deals
  for each row execute function public.set_updated_at();

alter table public.deals enable row level security;

-- ── أسطر الصفقة ────────────────────────────────────────────────────────
-- اقتصاديات الجرام تُثبَّت هنا لحظة التسليم ولا تتغير بعدها، لأن كل
-- حساب لاحق (استرداد، بيع، مصالحة) يرجع إليها (§18.1).

create table public.deal_lines (
  id                    uuid          primary key default gen_random_uuid(),
  deal_id               uuid          not null references public.deals (id) on delete cascade,
  lot_id                uuid          not null references public.lots (id) on delete restrict,

  weight_g              weight_grams  not null,
  -- لقطة من تكلفة الدفعة وقت التسليم؛ لا تُقرأ من lots لاحقاً حتى لا
  -- يتغير تاريخ الصفقة إن عُدّلت الدفعة
  cost_per_g            rate_per_gram not null,
  deal_value_per_g      rate_per_gram not null,
  expected_profit_per_g rate_per_gram not null,

  created_at            timestamptz   not null default now(),

  constraint deal_lines_weight_positive check (weight_g > 0),
  constraint deal_lines_rates_not_negative
    check (cost_per_g >= 0 and deal_value_per_g >= 0),
  -- الربح المتوقع للجرام مشتق لا مستقل: قيمة الصفقة ناقص التكلفة (§18.1)
  constraint deal_lines_profit_is_derived
    check (expected_profit_per_g = deal_value_per_g - cost_per_g)
);

create index deal_lines_deal_idx on public.deal_lines (deal_id);
create index deal_lines_lot_idx on public.deal_lines (lot_id);

alter table public.deal_lines enable row level security;

/*
  قيد الدفعة الواحدة لكل صفقة (§24.1 — القرار المعتمد).

  مطبَّق كتريجر لا كقيد جدول لأنه يقرأ إعداداً قابلاً للتغيير: رفع القيد
  مستقبلاً يكون بتغيير app_settings لا بترحيل جديد.
*/
create or replace function public.enforce_deal_line_policy()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_multi_lot boolean;
  v_existing  int;
begin
  v_multi_lot := coalesce((public.get_setting('deal_multi_lot'))::boolean, false);

  if v_multi_lot then
    return new;
  end if;

  select count(*) into v_existing
  from public.deal_lines
  where deal_id = new.deal_id;

  if v_existing > 0 then
    raise exception
      'الصفقة تقبل دفعة واحدة فقط. أنشئ صفقة جديدة للكمية من دفعة أخرى.'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger deal_lines_enforce_policy
  before insert on public.deal_lines
  for each row execute function public.enforce_deal_line_policy();

-- ── دفتر حركات الصفقة (§24.2) ──────────────────────────────────────────

create type public.deal_entry_type as enum (
  'DEAL_OPEN',             -- إنشاء الصفقة وتثبيت الوزن والقيمة الأصلية
  'QTY_DELIVERED',         -- إضافة كمية للموزع من دفعة محددة
  'QTY_SOLD',              -- تصريف فعلي — هنا يتحول الربح إلى محقق
  'PAYMENT_RECEIVED',      -- تخفيض الرصيد المالي فقط
  'QTY_RETURNED',          -- إعادة كمية للمخزون وإلغاء قيمتها وربحها المتوقع
  'COMMERCIAL_ADJUSTMENT', -- خصم أو إضافة تجارية معتمدة
  'WEIGHT_ADJUSTMENT',     -- تسوية وزن بسبب موثق واعتماد
  'PAYMENT_REVERSAL',      -- عكس دفعة دون حذف الحركة الأصلية
  'CREDIT_TRANSFER',       -- نقل رصيد دائن من/إلى صفقة أخرى
  'DEAL_CLOSE'             -- إغلاق بعد المصالحة النهائية
);

create table public.deal_ledger (
  id                    bigint       generated always as identity primary key,
  deal_id               uuid         not null references public.deals (id) on delete restrict,
  deal_line_id          uuid         references public.deal_lines (id) on delete restrict,
  entry_type            public.deal_entry_type not null,

  /*
    الوزن في دلوين فقط:
      delivered — الداخل إلى عهدة الموزع
      settled   — الخارج منها ببيع أو استرداد أو تسوية

    الوزن المفتوح = مجموع الأول ناقص مجموع الثاني. نوع الحركة يفصّل
    أي نوع تسوية كانت، فلا حاجة لعمود لكل حالة.
  */
  delivered_weight_g    weight_grams not null default 0,
  settled_weight_g      weight_grams not null default 0,

  -- القيمة التجارية للصفقة: ما يلتزم الموزع بسداده
  commercial_value_delta money_amount not null default 0,
  -- رأس المال المرتبط بالوزن المفتوح: يدخل بالتسليم ويخرج بالبيع أو الاسترداد
  cost_delta            money_amount not null default 0,
  -- الربح المتوقع المرتبط بالوزن المفتوح
  expected_profit_delta money_amount not null default 0,
  -- الربح المحقق: يتراكم عند التصريف الفعلي وحده (القرار المعتمد §16.1)
  realized_profit_delta money_amount not null default 0,
  -- النقد المخصص لهذه الصفقة
  paid_delta            money_amount not null default 0,

  ref_type              text         not null default '',
  ref_id                text,
  reason                text         not null default '',
  notes                 text         not null default '',
  occurred_at           timestamptz  not null default now(),
  created_by            uuid         references auth.users (id) on delete set null,

  constraint deal_ledger_weights_not_negative
    check (delivered_weight_g >= 0 and settled_weight_g >= 0),

  /*
    معادلة §18.1: قيمة الصفقة = رأس المال + الربح المتوقع.

    تُفرض على حركات التسليم والاسترداد، وهي جوهر منطق §18.3: استرداد
    100ج بتكلفة 2,000 وربح متوقع 400 يخفض قيمة الصفقة 2,400 بالضبط.
    الحركات الأخرى (بيع، دفع، تسوية) لا تخضع لها.
  */
  constraint deal_ledger_value_equals_cost_plus_profit
    check (
      entry_type not in ('QTY_DELIVERED', 'QTY_RETURNED')
      or commercial_value_delta = cost_delta + expected_profit_delta
    )
);

comment on table public.deal_ledger is
  'دفتر حركات الصفقة — مصدر الحقيقة لكل رصيد. append-only: التصحيح '
  'بحركة عكسية لا بتعديل حركة سابقة (§24.2، §26، §30).';

create index deal_ledger_deal_idx on public.deal_ledger (deal_id, occurred_at, id);
create index deal_ledger_type_idx on public.deal_ledger (deal_id, entry_type);
create index deal_ledger_ref_idx on public.deal_ledger (ref_type, ref_id);

create trigger deal_ledger_immutable
  before update or delete on public.deal_ledger
  for each row execute function public.forbid_mutation();

alter table public.deal_ledger enable row level security;

-- ── سياسات الوصول ──────────────────────────────────────────────────────

create policy deals_select on public.deals
  for select to authenticated using (auth.uid() is not null);
create policy deal_lines_select on public.deal_lines
  for select to authenticated using (auth.uid() is not null);
create policy deal_ledger_select on public.deal_ledger
  for select to authenticated using (auth.uid() is not null);

/*
  لا سياسات كتابة على أي من الثلاثة.

  كل حركة تمس الصفقة تمس المخزون والأرصدة معاً، فلا يمكن أن تكون
  عملية جزئية. المسار الوحيد هو دوال RPC داخل معاملات ذرية (§30).
*/


-- ─── 20260814090700_deal_views.sql ───────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0008 — أرصدة الصفقة المشتقة
--
-- كل رقم في كل شاشة وكل تقرير يخرج من هنا. لا تُحسب أرصدة في الواجهة
-- ولا تُخزَّن في أعمدة (§26)، حتى لا تختلف الأرقام بين اللوحة وكشف
-- الصفقة كما يشترط §27.
--
-- المرجع: §19.1 (المؤشرات)، §24.3 (الحالتان)، §24.6 (المصالحة)، §26
-- ═══════════════════════════════════════════════════════════════════════

-- ── الكمية (§19.1) ─────────────────────────────────────────────────────

create view public.v_deal_quantity
with (security_invoker = true)
as
select
  d.id as deal_id,
  coalesce(sum(dl.delivered_weight_g), 0)::weight_grams as original_weight_g,
  coalesce(sum(dl.settled_weight_g)  filter (where dl.entry_type = 'QTY_SOLD'), 0)::weight_grams
    as sold_weight_g,
  coalesce(sum(dl.settled_weight_g)  filter (where dl.entry_type = 'QTY_RETURNED'), 0)::weight_grams
    as returned_weight_g,
  coalesce(sum(dl.settled_weight_g)  filter (where dl.entry_type = 'WEIGHT_ADJUSTMENT'), 0)::weight_grams
    as adjusted_weight_g,
  -- الوزن المفتوح = المسلَّم - (المباع + المسترد + المسوّى)
  (coalesce(sum(dl.delivered_weight_g), 0) - coalesce(sum(dl.settled_weight_g), 0))::weight_grams
    as open_weight_g,
  -- نسبة تسوية الوزن (§19.1)
  case
    when coalesce(sum(dl.delivered_weight_g), 0) = 0 then 0
    else round(
      coalesce(sum(dl.settled_weight_g), 0) / sum(dl.delivered_weight_g), 6)
  end as settlement_ratio
from public.deals d
left join public.deal_ledger dl on dl.deal_id = d.id
group by d.id;

comment on view public.v_deal_quantity is
  'أوزان الصفقة مشتقة من الدفتر: الأصلي والمباع والمسترد والمسوّى والمفتوح.';

-- ── المال (§19.1) ──────────────────────────────────────────────────────

create view public.v_deal_money
with (security_invoker = true)
as
select
  d.id as deal_id,
  -- القيمة الأصلية: ما ثبت عند التسليم قبل أي استرداد أو تسوية
  coalesce(sum(dl.commercial_value_delta)
    filter (where dl.entry_type in ('DEAL_OPEN', 'QTY_DELIVERED')), 0)::money_amount
    as original_value,
  -- القيمة المعدلة: الأصلية بعد الاستردادات والتسويات التجارية
  coalesce(sum(dl.commercial_value_delta), 0)::money_amount as adjusted_value,
  coalesce(sum(dl.commercial_value_delta)
    filter (where dl.entry_type = 'QTY_RETURNED'), 0)::money_amount
    as returns_value_reduction,
  coalesce(sum(dl.commercial_value_delta)
    filter (where dl.entry_type = 'COMMERCIAL_ADJUSTMENT'), 0)::money_amount
    as commercial_adjustments,
  coalesce(sum(dl.paid_delta), 0)::money_amount as total_paid,
  -- الرصيد المتبقي = القيمة المعدلة - المسدد (§19.1)
  -- سالب يعني رصيداً دائناً للموزع (§24.5)
  (coalesce(sum(dl.commercial_value_delta), 0)
   - coalesce(sum(dl.paid_delta), 0))::money_amount as remaining_balance,
  case
    when coalesce(sum(dl.commercial_value_delta), 0) = 0 then 0
    else round(
      coalesce(sum(dl.paid_delta), 0) / sum(dl.commercial_value_delta), 6)
  end as payment_ratio
from public.deals d
left join public.deal_ledger dl on dl.deal_id = d.id
group by d.id;

comment on view public.v_deal_money is
  'أرصدة الصفقة المالية. رصيد سالب يعني رصيداً دائناً للموزع (§24.5).';

-- ── الربح — داخلي حساس (§24.9) ─────────────────────────────────────────

create view public.v_deal_profit
with (security_invoker = true)
as
select
  d.id as deal_id,
  -- الربح المتوقع الأصلي عند التسليم
  coalesce(sum(dl.expected_profit_delta)
    filter (where dl.entry_type in ('DEAL_OPEN', 'QTY_DELIVERED')), 0)::money_amount
    as original_expected_profit,
  -- الربح المتوقع الملغى بسبب الاستردادات (§18.3) — يظهر موجباً للقراءة
  (-coalesce(sum(dl.expected_profit_delta)
    filter (where dl.entry_type = 'QTY_RETURNED'), 0))::money_amount
    as cancelled_expected_profit,
  -- الربح المتوقع المفتوح: المرتبط بالوزن الذي ما زال لدى الموزع
  coalesce(sum(dl.expected_profit_delta), 0)::money_amount
    as open_expected_profit,
  -- الربح المحقق: يتراكم عند التصريف وحده (§16.1 — القرار المعتمد)
  coalesce(sum(dl.realized_profit_delta), 0)::money_amount as realized_profit,
  -- رأس المال الأصلي وما عاد للمخزون وما بقي مفتوحاً
  coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type in ('DEAL_OPEN', 'QTY_DELIVERED')), 0)::money_amount
    as original_capital_cost,
  (-coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type = 'QTY_RETURNED'), 0))::money_amount
    as returned_capital_cost,
  (-coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type = 'QTY_SOLD'), 0))::money_amount
    as cost_of_goods_sold,
  -- رأس المال المفتوح = المجموع الجاري لحركات التكلفة، لا وزن × تكلفة
  -- الجرام. الضرب ينحرف حين تكون تكلفة الجرام كسراً غير منتهٍ (§26).
  coalesce(sum(dl.cost_delta), 0)::money_amount as open_capital_cost
from public.deals d
left join public.deal_ledger dl on dl.deal_id = d.id
group by d.id;

comment on view public.v_deal_profit is
  '⚠️ بيانات داخلية حساسة: التكلفة ورأس المال والربح. ممنوع ظهورها في '
  'أي مخرج للموزع (V5.3). تقارير الموزع تُبنى من مصدر منفصل لا يحتوي '
  'هذه الأعمدة أصلاً.';

-- ── الحالتان المشتقتان (§24.3) ─────────────────────────────────────────

create view public.v_deal_status
with (security_invoker = true)
as
select
  d.id                     as deal_id,
  d.deal_no,
  d.distributor_id,
  d.status                 as deal_status,
  d.delivery_date,
  d.due_date,
  d.closed_at,

  q.original_weight_g,
  q.sold_weight_g,
  q.returned_weight_g,
  q.adjusted_weight_g,
  q.open_weight_g,
  q.settlement_ratio,

  m.original_value,
  m.adjusted_value,
  m.total_paid,
  m.remaining_balance,
  m.payment_ratio,

  -- حالة الوزن
  case
    when q.open_weight_g < 0                        then 'exception'
    when q.original_weight_g = 0                    then 'open'
    when q.open_weight_g = 0                        then 'fully_settled'
    when q.open_weight_g < q.original_weight_g      then 'partially_settled'
    else 'open'
  end::public.quantity_status as quantity_status,

  -- حالة السداد. الرصيد الدائن حالة مستقلة لا "مدفوع بالكامل" (§24.5)
  case
    when m.remaining_balance < 0                    then 'credit_balance'
    when m.adjusted_value = 0 and m.total_paid = 0  then 'unpaid'
    when m.remaining_balance = 0                    then 'fully_paid'
    when m.total_paid = 0                           then 'unpaid'
    when m.total_paid > 0                           then 'partially_paid'
    else 'exception'
  end::public.payment_status as payment_status,

  -- متأخرة: تجاوزت الاستحقاق وما زال عليها مبلغ (§18.6)
  (d.due_date is not null
   and d.due_date < current_date
   and m.remaining_balance > 0
   and d.status = 'active')                        as is_overdue,

  /*
    جاهزية الإغلاق (§21، §24.6).

    الشرطان معاً لا أحدهما: وزن مفتوح صفر ورصيد مالي صفر. صفقة مدفوعة
    بالكامل مع وزن مفتوح ليست جاهزة، والعكس كذلك — وهذا بالضبط ما
    يختبره §27.
  */
  (q.open_weight_g = 0 and m.remaining_balance = 0) as is_reconciled

from public.deals d
join public.v_deal_quantity q on q.deal_id = d.id
join public.v_deal_money    m on m.deal_id = d.id;

comment on view public.v_deal_status is
  'الحالة الكاملة للصفقة بحالتَي الوزن والمال منفصلتين (§24.3). '
  'لا تحتوي أي بيانات تكلفة أو ربح — تلك في v_deal_profit.';


-- ─── 20260814090800_deal_rpc.sql ─────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0009 — دوال الصفقة: الفتح والتصريف
--
-- المرجع: §18.1، §18.5، §24.9، §30
-- ═══════════════════════════════════════════════════════════════════════

create sequence public.deal_no_seq;

create or replace function public.next_deal_no(p_date date)
returns text
language sql
volatile
as $$
  select 'DEAL-' || to_char(p_date, 'YYYY') || '-'
       || lpad(nextval('public.deal_no_seq')::text, 4, '0');
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- فتح صفقة وتسليم الكمية
--
-- ينقل الوزن من المخزن إلى عهدة الموزع ويثبّت اقتصاديات الصفقة. تسليم
-- كمية ليس تحصيلاً نقدياً (§2) — paid_delta هنا صفر دائماً.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.open_deal(
  p_distributor_id uuid,
  p_lot_id         uuid,
  p_weight_g       weight_grams,
  p_deal_value     money_amount,
  p_delivery_date  date default current_date,
  p_due_date       date default null,
  p_notes          text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal_id       uuid;
  v_deal_line_id  uuid;
  v_deal_no       text;
  v_lot           record;
  v_available     weight_grams;
  v_cost_per_g    rate_per_gram;
  v_value_per_g   rate_per_gram;
  v_profit_per_g  rate_per_gram;
  v_capital_cost  money_amount;
  v_expected      money_amount;
begin
  perform public.assert_permission('deals.deliver');

  -- ── التحقق ───────────────────────────────────────────────────────────

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن التسليم يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_deal_value is null or p_deal_value < 0 then
    raise exception 'قيمة الصفقة لا يمكن أن تكون سالبة.'
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.distributors
    where id = p_distributor_id and is_active
  ) then
    raise exception 'الموزع غير موجود أو غير نشط.'
      using errcode = 'foreign_key_violation';
  end if;

  /*
    قفل الدفعة قبل قراءة رصيدها.

    بدون القفل يمكن لعمليتَي تسليم متزامنتين أن تقرأ كل منهما نفس الرصيد
    فتُسلّما معاً أكثر مما في المخزن. FOR UPDATE يسلسلهما.
  */
  select l.* into v_lot
  from public.lots l
  where l.id = p_lot_id
  for update;

  if not found then
    raise exception 'الدفعة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  select coalesce(sum(weight_delta_g), 0) into v_available
  from public.inventory_ledger
  where lot_id = p_lot_id;

  if p_weight_g > v_available then
    raise exception
      'الوزن المطلوب % ج يتجاوز المتاح في الدفعة % وهو % ج.',
      p_weight_g, v_lot.lot_no, v_available
      using errcode = 'check_violation';
  end if;

  -- ── اقتصاديات الصفقة (§18.1) ─────────────────────────────────────────
  -- تُثبَّت كلقطة على السطر ولا تُقرأ من الدفعة لاحقاً.

  v_cost_per_g   := v_lot.cost_per_g;
  v_value_per_g  := p_deal_value / p_weight_g;
  v_profit_per_g := v_value_per_g - v_cost_per_g;

  /*
    رأس المال المرتبط بالكمية.

    يُحسب بالضرب هنا لأن هذه لحظة التثبيت الوحيدة؛ بعدها لا يُضرب شيء —
    الأرصدة تُشتق من مجموع حركات الدفتر (§26). أي انحراف كسور يبقى
    محصوراً في هذا الرقم الواحد ولا يتراكم.
  */
  v_capital_cost := round(p_weight_g * v_cost_per_g, 4);
  -- الربح المتوقع مشتق طرحاً لا ضرباً، فتبقى معادلة §18.1 دقيقة تماماً:
  -- قيمة الصفقة = رأس المال + الربح المتوقع
  v_expected     := p_deal_value - v_capital_cost;

  -- ── إنشاء الصفقة ─────────────────────────────────────────────────────

  v_deal_no := public.next_deal_no(p_delivery_date);

  insert into public.deals (
    deal_no, distributor_id, status, delivery_date, due_date, notes, opened_by
  )
  values (
    v_deal_no, p_distributor_id, 'active', p_delivery_date, p_due_date,
    coalesce(p_notes, ''), auth.uid()
  )
  returning id into v_deal_id;

  insert into public.deal_lines (
    deal_id, lot_id, weight_g, cost_per_g, deal_value_per_g, expected_profit_per_g
  )
  values (
    v_deal_id, p_lot_id, p_weight_g, v_cost_per_g, v_value_per_g, v_profit_per_g
  )
  returning id into v_deal_line_id;

  -- ── الحركات ──────────────────────────────────────────────────────────

  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    delivered_weight_g, commercial_value_delta, cost_delta, expected_profit_delta,
    ref_type, ref_id, notes, created_by
  )
  values (
    v_deal_id, v_deal_line_id, 'QTY_DELIVERED',
    p_weight_g, p_deal_value, v_capital_cost, v_expected,
    'lot', p_lot_id::text,
    'تسليم من الدفعة ' || v_lot.lot_no, auth.uid()
  );

  -- الوزن يخرج من المخزن إلى عهدة الموزع؛ التكلفة تخرج معه
  insert into public.inventory_ledger (
    lot_id, entry_type, weight_delta_g, cost_delta, ref_type, ref_id, notes, created_by
  )
  values (
    p_lot_id, 'DELIVERED', -p_weight_g, -v_capital_cost,
    'deal', v_deal_id::text,
    'تسليم للصفقة ' || v_deal_no, auth.uid()
  );

  perform public.write_audit(
    'deal.opened', 'deals', v_deal_id::text,
    jsonb_build_object(
      'deal_no',         v_deal_no,
      'distributor_id',  p_distributor_id,
      'lot_id',          p_lot_id,
      'weight_g',        p_weight_g,
      'deal_value',      p_deal_value,
      'capital_cost',    v_capital_cost,
      'expected_profit', v_expected
    )
  );

  return v_deal_id;
end;
$$;

comment on function public.open_deal is
  'ينشئ صفقة وينقل الوزن من المخزن لعهدة الموزع. التسليم ليس تحصيلاً '
  'نقدياً (§2) — لا يمس الرصيد المالي إطلاقاً.';

-- ═══════════════════════════════════════════════════════════════════════
-- تسجيل تصريف (بيع) من الصفقة
--
-- هنا يتحول الربح من متوقع إلى محقق، وفق القرار المعتمد في §16.1.
-- لا يمس هذا الرصيد المالي: البيع لا يعني أن الموزع سدّد (§24.9).
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.record_deal_sale(
  p_deal_id   uuid,
  p_weight_g  weight_grams,
  p_sale_date date default current_date,
  p_notes     text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_line        record;
  v_open_weight weight_grams;
  v_open_cost   money_amount;
  v_open_profit money_amount;
  v_cost        money_amount;
  v_profit      money_amount;
  v_entry_id    bigint;
begin
  perform public.assert_permission('deals.record_sale');

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن التصريف يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception
      'لا يمكن تسجيل حركة على صفقة % — أعد فتحها أولاً أو استخدم حركة عكسية.',
      v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- الأرصدة المفتوحة الحالية، مقروءة من الدفتر لا من حقول مخزَّنة
  select
    coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0),
    coalesce(sum(cost_delta), 0),
    coalesce(sum(expected_profit_delta), 0)
  into v_open_weight, v_open_cost, v_open_profit
  from public.deal_ledger
  where deal_id = p_deal_id;

  if p_weight_g > v_open_weight then
    raise exception
      'وزن التصريف % ج يتجاوز الوزن المفتوح لدى الموزع وهو % ج.',
      p_weight_g, v_open_weight
      using errcode = 'check_violation';
  end if;

  select * into v_line from public.deal_lines where deal_id = p_deal_id limit 1;

  /*
    توزيع التكلفة والربح على الكمية المباعة.

    عند تصريف كامل الوزن المفتوح ننقل الرصيد المفتوح كما هو بدل الضرب،
    فيصل الرصيد إلى صفر تام. هذا ما يجعل المصالحة في §24.6 تعطي
    «فروقات غير مفسرة = صفر» فعلاً لا تقريباً.
  */
  if p_weight_g = v_open_weight then
    v_cost   := v_open_cost;
    v_profit := v_open_profit;
  else
    v_cost   := round(p_weight_g * v_line.cost_per_g, 4);
    v_profit := round(p_weight_g * v_line.expected_profit_per_g, 4);
  end if;

  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    settled_weight_g, cost_delta, expected_profit_delta, realized_profit_delta,
    ref_type, notes, occurred_at, created_by
  )
  values (
    p_deal_id, v_line.id, 'QTY_SOLD',
    p_weight_g, -v_cost, -v_profit, v_profit,
    'sale', coalesce(p_notes, ''), p_sale_date::timestamptz, auth.uid()
  )
  returning id into v_entry_id;

  perform public.write_audit(
    'deal.sale_recorded', 'deals', p_deal_id::text,
    jsonb_build_object(
      'weight_g',        p_weight_g,
      'cost',            v_cost,
      'realized_profit', v_profit
    )
  );

  return v_entry_id;
end;
$$;

comment on function public.record_deal_sale is
  'تصريف فعلي — يحوّل الربح من متوقع إلى محقق (§16.1). لا يمس النقد.';

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.open_deal(
  uuid, uuid, weight_grams, money_amount, date, date, text
) from public, anon;
grant execute on function public.open_deal(
  uuid, uuid, weight_grams, money_amount, date, date, text
) to authenticated;

revoke all on function public.record_deal_sale(uuid, weight_grams, date, text)
  from public, anon;
grant execute on function public.record_deal_sale(uuid, weight_grams, date, text)
  to authenticated;


-- ─── 20260814090900_deal_returns.sql ─────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0010 — استرداد كمية من الموزع
--
-- المبدأ (§18.3): الاسترداد ليس دفعة مالية ولا يُعامل كبيع أو تحصيل.
-- هو عكس جزئي لتسليم المخزون:
--   • الكمية تعود للمخزون بنفس تكلفة رأس المال الأصلية
--   • قيمة الصفقة المتوقعة تنخفض بنسبة الكمية وفق اقتصاديات الصفقة
--   • الربح المتوقع ينخفض بحصة الكمية المستردة
--   • المبلغ المسدد لا يتغير إطلاقاً
--
-- مثال §18.3 الإلزامي: تسليم 500ج بتكلفة 10,000 وقيمة صفقة 12,000،
-- ثم استرداد 100ج ⇒ رأس مال راجع 2,000، ربح متوقع ملغى 400،
-- تخفيض قيمة الصفقة 2,400، والمسدد يبقى صفراً.
--
-- المرجع: §18.3، §18.4، §23، إضافة V5.7
-- ═══════════════════════════════════════════════════════════════════════

create table public.deal_returns (
  id                        uuid         primary key default gen_random_uuid(),
  deal_id                   uuid         not null references public.deals (id) on delete restrict,
  deal_line_id              uuid         not null references public.deal_lines (id) on delete restrict,
  lot_id                    uuid         not null references public.lots (id) on delete restrict,
  return_date               date         not null,
  returned_weight_g         weight_grams not null,
  returned_cost             money_amount not null,
  cancelled_expected_profit money_amount not null,
  deal_value_reduction      money_amount not null,
  reason                    text         not null default '',
  created_by                uuid         references auth.users (id) on delete set null,
  created_at                timestamptz  not null default now(),
  constraint deal_returns_weight_positive check (returned_weight_g > 0),
  -- معادلة §18.3: التخفيض = التكلفة الراجعة + الربح المتوقع الملغى
  constraint deal_returns_value_equation
    check (deal_value_reduction = returned_cost + cancelled_expected_profit)
);

comment on table public.deal_returns is
  'الاستردادات — كل استرداد حركة مستقلة تظهر في التقرير حتى لو تعددت '
  'على نفس الصفقة (§18.4).';

create index deal_returns_deal_idx on public.deal_returns (deal_id, return_date);

-- الاسترداد حركة مثبتة: التصحيح بحركة عكسية لا بتعديلها
create trigger deal_returns_immutable
  before update or delete on public.deal_returns
  for each row execute function public.forbid_mutation();

alter table public.deal_returns enable row level security;

create policy deal_returns_select on public.deal_returns
  for select to authenticated using (auth.uid() is not null);

-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.record_deal_return(
  p_deal_id          uuid,
  p_weight_g         weight_grams,
  p_return_date      date default current_date,
  p_reason           text default '',
  -- تُقرأ فقط حين تكون سياسة التقييم manual_value (V5.7)
  p_commercial_value money_amount default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_line        record;
  v_open_weight weight_grams;
  v_open_cost   money_amount;
  v_open_profit money_amount;
  v_policy      text;
  v_cost        money_amount;
  v_profit      money_amount;
  v_reduction   money_amount;
  v_return_id   uuid;
begin
  perform public.assert_permission('deals.return');

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن الاسترداد يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception
      'لا يمكن الاسترداد من صفقة % — أعد فتحها أولاً.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- الأرصدة المفتوحة من الدفتر
  select
    coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0),
    coalesce(sum(cost_delta), 0),
    coalesce(sum(expected_profit_delta), 0)
  into v_open_weight, v_open_cost, v_open_profit
  from public.deal_ledger
  where deal_id = p_deal_id;

  /*
    §18.4: لا يمكن استرداد وزن أكبر من الوزن غير المصرَّف والمتبقي فعلاً
    لدى الموزع. الوزن المفتوح هو بالضبط هذا المقدار — ما بيع لم يعد
    موجوداً ليُسترد.
  */
  if p_weight_g > v_open_weight then
    raise exception
      'وزن الاسترداد % ج يتجاوز الوزن غير المصرَّف لدى الموزع وهو % ج.',
      p_weight_g, v_open_weight
      using errcode = 'check_violation';
  end if;

  select * into v_line from public.deal_lines where deal_id = p_deal_id limit 1;

  /*
    §18.4: سعر رأس المال للكمية المستردة لا يُعاد احتسابه من سعر البيع؛
    يُستخدم cost_per_g للدفعة الأصلية المثبَّت على سطر الصفقة.

    عند استرداد كامل الوزن المفتوح ننقل الرصيد المفتوح كما هو بدل الضرب،
    فتصل التكلفة والربح المفتوحان إلى صفر تام.
  */
  if p_weight_g = v_open_weight then
    v_cost   := v_open_cost;
    v_profit := v_open_profit;
  else
    v_cost   := round(p_weight_g * v_line.cost_per_g, 4);
    v_profit := round(p_weight_g * v_line.expected_profit_per_g, 4);
  end if;

  -- ── التقييم التجاري تجاه الموزع (V5.7) ───────────────────────────────

  v_policy := public.get_setting_text('return_commercial_valuation');

  if v_policy = 'manual_value' then
    if p_commercial_value is null then
      raise exception
        'سياسة النظام تتطلب تحديد قيمة التسوية التجارية للكمية المستردة.'
        using errcode = 'check_violation';
    end if;
    if p_commercial_value < 0 then
      raise exception 'قيمة التسوية التجارية لا يمكن أن تكون سالبة.'
        using errcode = 'check_violation';
    end if;
    v_reduction := p_commercial_value;
    -- التكلفة الراجعة ثابتة دائماً؛ الفرق يقع كله على الربح المتوقع
    v_profit    := v_reduction - v_cost;
  else
    -- القرار المعتمد: بنفس سعر الجرام في الصفقة
    v_reduction := v_cost + v_profit;
  end if;

  -- ── التسجيل ──────────────────────────────────────────────────────────

  insert into public.deal_returns (
    deal_id, deal_line_id, lot_id, return_date, returned_weight_g,
    returned_cost, cancelled_expected_profit, deal_value_reduction,
    reason, created_by
  )
  values (
    p_deal_id, v_line.id, v_line.lot_id, p_return_date, p_weight_g,
    v_cost, v_profit, v_reduction,
    coalesce(p_reason, ''), auth.uid()
  )
  returning id into v_return_id;

  /*
    الحركة في دفتر الصفقة.

    paid_delta صفر صراحةً: الاسترداد ليس سداداً (§18.3). realized_profit
    صفر أيضاً: الاسترداد يخفض الربح المتوقع ولا يمس الربح المحقق من
    كميات سبق بيعها (§18.4).
  */
  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    settled_weight_g, commercial_value_delta, cost_delta, expected_profit_delta,
    paid_delta, ref_type, ref_id, reason, occurred_at, created_by
  )
  values (
    p_deal_id, v_line.id, 'QTY_RETURNED',
    p_weight_g, -v_reduction, -v_cost, -v_profit,
    0, 'deal_return', v_return_id::text,
    coalesce(p_reason, ''), p_return_date::timestamptz, auth.uid()
  );

  -- §18.4: الكمية تعود إلى نفس الدفعة الأصلية بتكلفتها الأصلية
  insert into public.inventory_ledger (
    lot_id, entry_type, weight_delta_g, cost_delta,
    ref_type, ref_id, notes, created_by
  )
  values (
    v_line.lot_id, 'RETURNED', p_weight_g, v_cost,
    'deal_return', v_return_id::text,
    'استرداد من الصفقة ' || v_deal.deal_no, auth.uid()
  );

  perform public.write_audit(
    'deal.return_recorded', 'deals', p_deal_id::text,
    jsonb_build_object(
      'return_id',                 v_return_id,
      'weight_g',                  p_weight_g,
      'returned_cost',             v_cost,
      'cancelled_expected_profit', v_profit,
      'deal_value_reduction',      v_reduction,
      'valuation_policy',          v_policy
    )
  );

  return v_return_id;
end;
$$;

comment on function public.record_deal_return is
  'استرداد كمية — عكس جزئي لتسليم المخزون لا تحصيل نقدي (§18.3). '
  'التكلفة تعود بسعر الدفعة الأصلي والربح المتوقع ينخفض بحصته.';

revoke all on function public.record_deal_return(
  uuid, weight_grams, date, text, money_amount
) from public, anon;
grant execute on function public.record_deal_return(
  uuid, weight_grams, date, text, money_amount
) to authenticated;


-- ─── 20260814091000_payments.sql ─────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0011 — التحصيل والتخصيص والنقد
--
-- المبدأ (§24.4، §30): الدفعة منفصلة عن تخصيصها.
--   • الدفعة حدث نقدي على مستوى الموزع، لا على مستوى صفقة
--   • التخصيص يربط جزءاً من الدفعة بصفقة، ويمكن عكسه دون حذف الدفعة
--   • دفعة بلا تخصيص تبقى رصيداً غير مخصص ظاهراً في كشف الموزع
--
-- المرجع: §18.5، §24.4، §24.5، §25
-- ═══════════════════════════════════════════════════════════════════════

-- ── حسابات النقد (§25) ─────────────────────────────────────────────────

create type public.cash_account_kind as enum ('cash', 'bank', 'other');

create table public.cash_accounts (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  kind       public.cash_account_kind not null default 'cash',
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  constraint cash_accounts_name_not_blank check (btrim(name) <> '')
);

alter table public.cash_accounts enable row level security;

create table public.cash_transactions (
  id          bigint       generated always as identity primary key,
  account_id  uuid         not null references public.cash_accounts (id) on delete restrict,
  -- موجب داخل للصندوق، سالب خارج منه
  amount      money_amount not null,
  occurred_at timestamptz  not null default now(),
  ref_type    text         not null default '',
  ref_id      text,
  notes       text         not null default '',
  created_by  uuid         references auth.users (id) on delete set null,
  constraint cash_transactions_amount_not_zero check (amount <> 0)
);

comment on table public.cash_transactions is
  'حركات النقد — مصدر الحقيقة لرصيد الصندوق. append-only.';

create index cash_transactions_account_idx
  on public.cash_transactions (account_id, occurred_at);
create index cash_transactions_ref_idx
  on public.cash_transactions (ref_type, ref_id);

create trigger cash_transactions_immutable
  before update or delete on public.cash_transactions
  for each row execute function public.forbid_mutation();

alter table public.cash_transactions enable row level security;

-- ── الدفعات (§24.4) ────────────────────────────────────────────────────

create type public.payment_method as enum ('cash', 'transfer', 'cheque', 'other');

create table public.payments (
  id              uuid         primary key default gen_random_uuid(),
  distributor_id  uuid         not null references public.distributors (id) on delete restrict,
  payment_date    date         not null,
  amount          money_amount not null,
  method          public.payment_method not null default 'cash',
  reference       text         not null default '',
  cash_account_id uuid         references public.cash_accounts (id) on delete restrict,
  notes           text         not null default '',
  created_by      uuid         references auth.users (id) on delete set null,
  created_at      timestamptz  not null default now(),
  constraint payments_amount_positive check (amount > 0)
);

comment on table public.payments is
  'التحصيل من الموزع كحدث نقدي مستقل. ربطه بالصفقات يتم عبر '
  'payment_allocations، فدفعة واحدة قد تُوزَّع على عدة صفقات (§24.4).';

create index payments_distributor_idx
  on public.payments (distributor_id, payment_date desc);

create trigger payments_immutable
  before update or delete on public.payments
  for each row execute function public.forbid_mutation();

alter table public.payments enable row level security;

-- ── التخصيصات (§24.4) ──────────────────────────────────────────────────

create table public.payment_allocations (
  id              uuid         primary key default gen_random_uuid(),
  payment_id      uuid         not null references public.payments (id) on delete restrict,
  deal_id         uuid         not null references public.deals (id) on delete restrict,
  amount          money_amount not null,
  allocated_at    timestamptz  not null default now(),
  created_by      uuid         references auth.users (id) on delete set null,
  -- العكس لا يحذف التخصيص: يوسمه ويضيف حركة مقابلة في دفتر الصفقة
  reversed_at     timestamptz,
  reversed_by     uuid         references auth.users (id) on delete set null,
  reversal_reason text         not null default '',
  constraint payment_allocations_amount_positive check (amount > 0),
  constraint payment_allocations_reversal_consistency
    check ((reversed_at is null) = (reversed_by is null))
);

comment on table public.payment_allocations is
  'ربط جزء من دفعة بصفقة. قابل للعكس دون حذف أصل التحصيل (§24.4).';

create index payment_allocations_payment_idx
  on public.payment_allocations (payment_id);
create index payment_allocations_deal_idx
  on public.payment_allocations (deal_id);

/*
  §24.4: لا يُسمح أن تتجاوز تخصيصات الدفعة قيمة الدفعة نفسها.

  يُفرض بتريجر لا بقيد جدول لأن الشرط يقارن مجموع صفوف بصف آخر.
  القفل على صف الدفعة يمنع تخصيصين متزامنين من تجاوز الحد معاً.
*/
create or replace function public.enforce_allocation_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment_amount money_amount;
  v_allocated      money_amount;
begin
  select amount into v_payment_amount
  from public.payments
  where id = new.payment_id
  for update;

  select coalesce(sum(amount), 0) into v_allocated
  from public.payment_allocations
  where payment_id = new.payment_id
    and reversed_at is null
    and id <> new.id;

  if v_allocated + new.amount > v_payment_amount then
    raise exception
      'مجموع التخصيصات % يتجاوز قيمة الدفعة %.',
      v_allocated + new.amount, v_payment_amount
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger payment_allocations_enforce_limit
  before insert on public.payment_allocations
  for each row execute function public.enforce_allocation_limit();

/*
  التخصيص يُعكس بوسمه فقط.

  نسمح بتحديث حقول العكس وحدها ونمنع أي تعديل آخر — فلا يستطيع أحد
  تغيير مبلغ تخصيص أو صفقته بعد إنشائه.
*/
create or replace function public.guard_allocation_update()
returns trigger
language plpgsql
as $$
begin
  if new.payment_id is distinct from old.payment_id
     or new.deal_id is distinct from old.deal_id
     or new.amount  is distinct from old.amount
     or new.allocated_at is distinct from old.allocated_at then
    raise exception
      'لا يُعدَّل تخصيص قائم. اعكسه ثم أنشئ تخصيصاً جديداً.'
      using errcode = 'restrict_violation';
  end if;

  if old.reversed_at is not null then
    raise exception 'التخصيص معكوس أصلاً.'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger payment_allocations_guard_update
  before update on public.payment_allocations
  for each row execute function public.guard_allocation_update();

create trigger payment_allocations_no_delete
  before delete on public.payment_allocations
  for each row execute function public.forbid_mutation();

alter table public.payment_allocations enable row level security;

-- ── معالجة الرصيد الدائن (§24.5) ───────────────────────────────────────

create type public.credit_resolution_method as enum (
  'refund',                -- إعادة المبلغ للموزع نقداً
  'transfer_to_deal',      -- نقل الرصيد إلى صفقة أخرى لنفس الموزع
  'keep_as_credit',        -- إبقاؤه رصيداً دائناً مفتوحاً لاستخدامه لاحقاً
  'authorized_adjustment'  -- تسوية معتمدة بسبب موثق
);

create table public.credit_resolutions (
  id             uuid         primary key default gen_random_uuid(),
  deal_id        uuid         not null references public.deals (id) on delete restrict,
  target_deal_id uuid         references public.deals (id) on delete restrict,
  method         public.credit_resolution_method not null,
  amount         money_amount not null,
  reason         text         not null,
  resolved_at    timestamptz  not null default now(),
  resolved_by    uuid         references auth.users (id) on delete set null,
  constraint credit_resolutions_amount_positive check (amount > 0),
  constraint credit_resolutions_reason_not_blank check (btrim(reason) <> ''),
  -- النقل يحتاج صفقة هدف؛ بقية الطرق لا تقبلها
  constraint credit_resolutions_target_consistency
    check ((method = 'transfer_to_deal') = (target_deal_id is not null))
);

comment on table public.credit_resolutions is
  'كيف عولج الرصيد الدائن للموزع (§24.5). الرصيد نفسه مشتق من الصفقة '
  'ولا يُخزَّن؛ هذا الجدول يسجل قرار المعالجة وأثره.';

create index credit_resolutions_deal_idx on public.credit_resolutions (deal_id);

create trigger credit_resolutions_immutable
  before update or delete on public.credit_resolutions
  for each row execute function public.forbid_mutation();

alter table public.credit_resolutions enable row level security;

-- ── الأرصدة المشتقة ────────────────────────────────────────────────────

create view public.v_payment_status
with (security_invoker = true)
as
select
  p.id             as payment_id,
  p.distributor_id,
  p.payment_date,
  p.amount,
  p.method,
  p.reference,
  coalesce(sum(a.amount) filter (where a.reversed_at is null), 0)::money_amount
    as allocated_amount,
  -- §24.4: الرصيد غير المخصص يظهر بوضوح في كشف الموزع
  (p.amount - coalesce(sum(a.amount) filter (where a.reversed_at is null), 0))::money_amount
    as unallocated_amount
from public.payments p
left join public.payment_allocations a on a.payment_id = p.id
group by p.id;

comment on view public.v_payment_status is
  'حالة كل دفعة: كم خُصِّص منها وكم بقي غير مخصص (§24.4).';

/*
  الأرصدة الدائنة للموزعين (§24.5).

  الرصيد الدائن ليس جدولاً بل حالة: صفقة قيمتها المعدلة أقل مما سُدِّد
  عليها. يحدث حين يدفع الموزع ثم تُسترد كمية تخفض قيمة الصفقة تحت
  المبلغ المدفوع. الفرق لا يضيع ولا يُسجَّل ربحاً — يظهر هنا حتى يُعالَج.
*/
create view public.v_distributor_credits
with (security_invoker = true)
as
select
  d.id                       as deal_id,
  d.deal_no,
  d.distributor_id,
  (-m.remaining_balance)::money_amount as credit_amount,
  coalesce(sum(cr.amount), 0)::money_amount as resolved_amount,
  ((-m.remaining_balance) - coalesce(sum(cr.amount), 0))::money_amount
                             as unresolved_amount
from public.deals d
join public.v_deal_money m on m.deal_id = d.id
left join public.credit_resolutions cr on cr.deal_id = d.id
where m.remaining_balance < 0
group by d.id, m.remaining_balance;

comment on view public.v_distributor_credits is
  'الأرصدة الدائنة للموزعين ومقدار ما عولج منها (§24.5). الرصيد مشتق '
  'من الصفقة لا مخزَّن (§26).';

create view public.v_cash_balance
with (security_invoker = true)
as
select
  ca.id   as account_id,
  ca.name,
  ca.kind,
  coalesce(sum(ct.amount), 0)::money_amount as balance
from public.cash_accounts ca
left join public.cash_transactions ct on ct.account_id = ca.id
group by ca.id;

-- ── سياسات الوصول ──────────────────────────────────────────────────────

create policy cash_accounts_select on public.cash_accounts
  for select to authenticated using (auth.uid() is not null);
create policy cash_transactions_select on public.cash_transactions
  for select to authenticated using (auth.uid() is not null);
create policy payments_select on public.payments
  for select to authenticated using (auth.uid() is not null);
create policy payment_allocations_select on public.payment_allocations
  for select to authenticated using (auth.uid() is not null);
create policy credit_resolutions_select on public.credit_resolutions
  for select to authenticated using (auth.uid() is not null);

create policy cash_accounts_write on public.cash_accounts
  for all to authenticated
  using (public.has_permission('payments.record'))
  with check (public.has_permission('payments.record'));

-- بقية الجداول بلا سياسات كتابة: المسار الوحيد دوال RPC ذرية (§30).


-- ─── 20260814091100_payments_rpc.sql ─────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0012 — دوال التحصيل والتخصيص ومعالجة الرصيد الدائن
--
-- المرجع: §18.5، §24.4، §24.5، §27، §28، §30
-- ═══════════════════════════════════════════════════════════════════════

-- ── دالة داخلية: تخصيص مبلغ لصفقة ──────────────────────────────────────
-- تُستدعى من record_payment و allocate_payment، فلا يتكرر منطق الكتابة
-- في دفتر الصفقة في موضعين قد يفترقان.

create or replace function public.allocate_payment_internal(
  p_payment_id uuid,
  p_deal_id    uuid,
  p_amount     money_amount
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment       record;
  v_deal          record;
  v_allocation_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ التخصيص يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  select * into v_payment from public.payments where id = p_payment_id;
  if not found then
    raise exception 'الدفعة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  -- دفعة موزع لا تُخصَّص لصفقة موزع آخر
  if v_deal.distributor_id <> v_payment.distributor_id then
    raise exception 'لا يمكن تخصيص دفعة موزع لصفقة موزع آخر.'
      using errcode = 'check_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception
      'لا يمكن التخصيص لصفقة % — أعد فتحها أولاً.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- التريجر على الجدول يمنع تجاوز قيمة الدفعة (§24.4)
  insert into public.payment_allocations (payment_id, deal_id, amount, created_by)
  values (p_payment_id, p_deal_id, p_amount, auth.uid())
  returning id into v_allocation_id;

  /*
    الحركة في دفتر الصفقة.

    PAYMENT_RECEIVED يمس الرصيد المالي وحده: لا وزن ولا تكلفة ولا ربح.
    السداد لا يعني تصريفاً ولا يغيّر شيئاً في الكمية (§24.2، §24.9).
  */
  insert into public.deal_ledger (
    deal_id, entry_type, paid_delta, ref_type, ref_id, reason, occurred_at, created_by
  )
  values (
    p_deal_id, 'PAYMENT_RECEIVED', p_amount,
    'payment_allocation', v_allocation_id::text,
    'تحصيل مرجع ' || coalesce(nullif(v_payment.reference, ''), v_payment.payment_date::text),
    v_payment.payment_date::timestamptz, auth.uid()
  );

  return v_allocation_id;
end;
$$;

-- ── تسجيل دفعة (§24.4) ─────────────────────────────────────────────────

create or replace function public.record_payment(
  p_distributor_id  uuid,
  p_amount          money_amount,
  p_payment_date    date default current_date,
  p_method          public.payment_method default 'cash',
  p_reference       text default '',
  p_cash_account_id uuid default null,
  p_notes           text default '',
  -- سياسة التخصيص: specific أو oldest_first أو unallocated
  p_allocation_mode text default 'unallocated',
  -- للوضع specific: [{"deal_id":"…","amount":1000}]
  p_allocations     jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment_id  uuid;
  v_allocation  jsonb;
  v_remaining   money_amount;
  v_deal        record;
  v_deal_due    money_amount;
  v_take        money_amount;
begin
  perform public.assert_permission('payments.record');

  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ الدفعة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.distributors where id = p_distributor_id) then
    raise exception 'الموزع غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  insert into public.payments (
    distributor_id, payment_date, amount, method, reference,
    cash_account_id, notes, created_by
  )
  values (
    p_distributor_id, p_payment_date, p_amount, p_method,
    coalesce(p_reference, ''), p_cash_account_id, coalesce(p_notes, ''), auth.uid()
  )
  returning id into v_payment_id;

  -- النقد يدخل الصندوق بمجرد استلامه، بغض النظر عن تخصيصه لاحقاً
  if p_cash_account_id is not null then
    insert into public.cash_transactions (
      account_id, amount, occurred_at, ref_type, ref_id, notes, created_by
    )
    values (
      p_cash_account_id, p_amount, p_payment_date::timestamptz,
      'payment', v_payment_id::text, 'تحصيل من موزع', auth.uid()
    );
  end if;

  -- ── التخصيص (§24.4) ──────────────────────────────────────────────────

  if p_allocation_mode = 'specific' then
    perform public.assert_permission('payments.allocate');

    for v_allocation in
      select * from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    loop
      perform public.allocate_payment_internal(
        v_payment_id,
        (v_allocation ->> 'deal_id')::uuid,
        (v_allocation ->> 'amount')::money_amount
      );
    end loop;

  elsif p_allocation_mode = 'oldest_first' then
    perform public.assert_permission('payments.allocate');

    v_remaining := p_amount;

    /*
      التوزيع على أقدم الاستحقاقات.

      نقرأ الرصيد المتبقي من v_deal_money لا من حقل مخزَّن، ونتوقف عند
      نفاد المبلغ. ما يتبقى بلا تخصيص يبقى رصيداً غير مخصص ظاهراً في
      كشف الموزع — لا يُفرض على صفقة لم يخترها المستخدم.
    */
    for v_deal in
      select d.id, d.delivery_date
      from public.deals d
      join public.v_deal_money m on m.deal_id = d.id
      where d.distributor_id = p_distributor_id
        and d.status not in ('closed', 'cancelled')
        and m.remaining_balance > 0
      order by d.delivery_date nulls last, d.created_at
    loop
      exit when v_remaining <= 0;

      select remaining_balance into v_deal_due
      from public.v_deal_money where deal_id = v_deal.id;

      v_take := least(v_remaining, v_deal_due);

      if v_take > 0 then
        perform public.allocate_payment_internal(v_payment_id, v_deal.id, v_take);
        v_remaining := v_remaining - v_take;
      end if;
    end loop;
  end if;
  -- الوضع unallocated: الدفعة تُحفظ بلا تخصيص حتى يقرر المستخدم

  perform public.write_audit(
    'payment.recorded', 'payments', v_payment_id::text,
    jsonb_build_object(
      'distributor_id',  p_distributor_id,
      'amount',          p_amount,
      'method',          p_method,
      'allocation_mode', p_allocation_mode
    )
  );

  return v_payment_id;
end;
$$;

comment on function public.record_payment is
  'تسجيل تحصيل من موزع مع تخصيص اختياري: محدد أو على الأقدم أو بلا '
  'تخصيص يبقى رصيداً مفتوحاً (§24.4).';

-- ── تخصيص لاحق لدفعة قائمة ─────────────────────────────────────────────

create or replace function public.allocate_payment(
  p_payment_id uuid,
  p_deal_id    uuid,
  p_amount     money_amount
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_allocation_id uuid;
begin
  perform public.assert_permission('payments.allocate');

  v_allocation_id := public.allocate_payment_internal(
    p_payment_id, p_deal_id, p_amount);

  perform public.write_audit(
    'payment.allocated', 'payment_allocations', v_allocation_id::text,
    jsonb_build_object(
      'payment_id', p_payment_id,
      'deal_id',    p_deal_id,
      'amount',     p_amount
    )
  );

  return v_allocation_id;
end;
$$;

-- ── عكس تخصيص (§24.4) ──────────────────────────────────────────────────

create or replace function public.reverse_payment_allocation(
  p_allocation_id uuid,
  p_reason        text
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_allocation record;
  v_deal       record;
begin
  perform public.assert_permission('payments.reverse');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'عكس التخصيص يحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_allocation
  from public.payment_allocations
  where id = p_allocation_id
  for update;

  if not found then
    raise exception 'التخصيص غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  if v_allocation.reversed_at is not null then
    raise exception 'التخصيص معكوس أصلاً.' using errcode = 'restrict_violation';
  end if;

  select * into v_deal from public.deals where id = v_allocation.deal_id;

  if v_deal.status = 'closed' then
    raise exception
      'الصفقة مغلقة. أعد فتحها بصلاحية مدير قبل عكس التخصيص.'
      using errcode = 'restrict_violation';
  end if;

  update public.payment_allocations
  set reversed_at = now(), reversed_by = auth.uid(), reversal_reason = p_reason
  where id = p_allocation_id;

  -- العكس حركة تُضاف؛ الحركة الأصلية تبقى في الدفتر كما هي (§24.2)
  insert into public.deal_ledger (
    deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
  )
  values (
    v_allocation.deal_id, 'PAYMENT_REVERSAL', -v_allocation.amount,
    'payment_allocation', p_allocation_id::text, p_reason, auth.uid()
  );

  perform public.write_audit(
    'payment.allocation_reversed', 'payment_allocations', p_allocation_id::text,
    jsonb_build_object(
      'deal_id', v_allocation.deal_id,
      'amount',  v_allocation.amount,
      'reason',  p_reason
    )
  );
end;
$$;

-- ── معالجة الرصيد الدائن (§24.5) ───────────────────────────────────────

create or replace function public.resolve_distributor_credit(
  p_deal_id        uuid,
  p_method         public.credit_resolution_method,
  p_amount         money_amount,
  p_reason         text,
  p_target_deal_id uuid default null,
  p_cash_account_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_target      record;
  v_credit      money_amount;
  v_unresolved  money_amount;
  v_resolution_id uuid;
begin
  perform public.assert_permission('credits.resolve');

  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ المعالجة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'معالجة الرصيد الدائن تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  select credit_amount, unresolved_amount into v_credit, v_unresolved
  from public.v_distributor_credits where deal_id = p_deal_id;

  if v_credit is null then
    raise exception 'لا يوجد رصيد دائن على هذه الصفقة.'
      using errcode = 'check_violation';
  end if;

  if p_amount > v_unresolved then
    raise exception
      'المبلغ % يتجاوز الرصيد الدائن غير المعالج وهو %.',
      p_amount, v_unresolved
      using errcode = 'check_violation';
  end if;

  insert into public.credit_resolutions (
    deal_id, target_deal_id, method, amount, reason, resolved_by
  )
  values (
    p_deal_id,
    case when p_method = 'transfer_to_deal' then p_target_deal_id end,
    p_method, p_amount, p_reason, auth.uid()
  )
  returning id into v_resolution_id;

  /*
    أثر كل طريقة معالجة.

    المشترك بينها جميعاً: المبلغ لا يُسجَّل إيراداً ولا ربحاً للشركة
    (§24.5). هو مال الموزع، إما يُرد أو يُنقل أو يبقى ديناً عليه.
  */
  if p_method = 'refund' then
    -- الرد يخفض ما هو محسوب مسدداً على الصفقة ويُخرج نقداً فعلياً
    insert into public.deal_ledger (
      deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
    )
    values (
      p_deal_id, 'CREDIT_TRANSFER', -p_amount,
      'credit_resolution', v_resolution_id::text,
      'رد رصيد دائن: ' || p_reason, auth.uid()
    );

    if p_cash_account_id is not null then
      insert into public.cash_transactions (
        account_id, amount, ref_type, ref_id, notes, created_by
      )
      values (
        p_cash_account_id, -p_amount,
        'credit_resolution', v_resolution_id::text,
        'رد رصيد دائن لموزع', auth.uid()
      );
    end if;

  elsif p_method = 'transfer_to_deal' then
    select * into v_target from public.deals where id = p_target_deal_id for update;

    if not found then
      raise exception 'الصفقة الهدف غير موجودة.'
        using errcode = 'foreign_key_violation';
    end if;

    if v_target.distributor_id <> v_deal.distributor_id then
      raise exception 'لا يُنقل الرصيد الدائن إلا لصفقة نفس الموزع.'
        using errcode = 'check_violation';
    end if;

    if v_target.status in ('closed', 'cancelled') then
      raise exception 'الصفقة الهدف % — لا يمكن النقل إليها.', v_target.status
        using errcode = 'restrict_violation';
    end if;

    -- النقل حركتان متقابلتان: لا نقد يدخل ولا يخرج
    insert into public.deal_ledger (
      deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
    )
    values
      (p_deal_id, 'CREDIT_TRANSFER', -p_amount,
       'credit_resolution', v_resolution_id::text,
       'نقل رصيد دائن إلى ' || v_target.deal_no, auth.uid()),
      (p_target_deal_id, 'CREDIT_TRANSFER', p_amount,
       'credit_resolution', v_resolution_id::text,
       'رصيد دائن منقول من ' || v_deal.deal_no, auth.uid());

  elsif p_method = 'authorized_adjustment' then
    -- تسوية تجارية معتمدة ترفع قيمة الصفقة فيستوعبها الرصيد الدائن
    insert into public.deal_ledger (
      deal_id, entry_type, commercial_value_delta, ref_type, ref_id, reason, created_by
    )
    values (
      p_deal_id, 'COMMERCIAL_ADJUSTMENT', p_amount,
      'credit_resolution', v_resolution_id::text,
      'تسوية معتمدة: ' || p_reason, auth.uid()
    );
  end if;
  -- keep_as_credit: لا حركة. الرصيد يبقى ظاهراً كالتزام على الشركة
  -- تجاه الموزع، وقد سُجِّل قرار إبقائه.

  perform public.write_audit(
    'credit.resolved', 'credit_resolutions', v_resolution_id::text,
    jsonb_build_object(
      'deal_id',        p_deal_id,
      'method',         p_method,
      'amount',         p_amount,
      'target_deal_id', p_target_deal_id,
      'reason',         p_reason
    )
  );

  return v_resolution_id;
end;
$$;

comment on function public.resolve_distributor_credit is
  'معالجة الرصيد الدائن للموزع: رد أو نقل أو إبقاء أو تسوية معتمدة. '
  'المبلغ لا يُسجَّل إيراداً ولا ربحاً في أي حالة (§24.5).';

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.allocate_payment_internal(uuid, uuid, money_amount)
  from public, anon, authenticated;

revoke all on function public.record_payment(
  uuid, money_amount, date, public.payment_method, text, uuid, text, text, jsonb
) from public, anon;
grant execute on function public.record_payment(
  uuid, money_amount, date, public.payment_method, text, uuid, text, text, jsonb
) to authenticated;

revoke all on function public.allocate_payment(uuid, uuid, money_amount)
  from public, anon;
grant execute on function public.allocate_payment(uuid, uuid, money_amount)
  to authenticated;

revoke all on function public.reverse_payment_allocation(uuid, text)
  from public, anon;
grant execute on function public.reverse_payment_allocation(uuid, text)
  to authenticated;

revoke all on function public.resolve_distributor_credit(
  uuid, public.credit_resolution_method, money_amount, text, uuid, uuid
) from public, anon;
grant execute on function public.resolve_distributor_credit(
  uuid, public.credit_resolution_method, money_amount, text, uuid, uuid
) to authenticated;


-- ─── 20260814091200_settlement.sql ───────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0013 — المصالحة والإغلاق وإعادة الفتح
--
-- §24.6: لا يُسمح بالإغلاق إلا بعد تفسير كل جرام وكل ريال.
--
--   بند المصالحة                      يجب أن يساوي
--   ─────────────────────────────────────────────────────────────────
--   الوزن الأصلي                      مباع + مسترد + تسوية + مفتوح
--   القيمة التجارية المعدلة           دفعات مخصصة + رصيد متبق
--   الوزن المفتوح عند الإغلاق         صفر
--   الرصيد المالي غير المسوى          صفر
--   الفروقات غير المفسرة              صفر
--
-- المرجع: §21، §24.6، §27
-- ═══════════════════════════════════════════════════════════════════════

-- ── لقطة الإغلاق (§21) ─────────────────────────────────────────────────

create table public.deal_closing_snapshots (
  id                       uuid         primary key default gen_random_uuid(),
  deal_id                  uuid         not null references public.deals (id) on delete restrict,
  -- النسخة: إعادة الفتح ثم الإغلاق تنتج لقطة جديدة والقديمة تبقى (§21)
  version                  int          not null,
  closed_at                timestamptz  not null default now(),
  closed_by                uuid         references auth.users (id) on delete set null,

  original_weight_g        weight_grams not null,
  sold_weight_g            weight_grams not null,
  returned_weight_g        weight_grams not null,
  adjusted_weight_g        weight_grams not null,

  original_value           money_amount not null,
  adjusted_value           money_amount not null,
  total_paid               money_amount not null,

  original_capital_cost    money_amount not null,
  returned_capital_cost    money_amount not null,
  cost_of_goods_sold       money_amount not null,
  original_expected_profit money_amount not null,
  cancelled_expected_profit money_amount not null,
  realized_profit          money_amount not null,

  -- نسخة كاملة للتدقيق ولإعادة طباعة التقرير النهائي دون تغيير (§21)
  details                  jsonb        not null default '{}'::jsonb,

  unique (deal_id, version)
);

comment on table public.deal_closing_snapshots is
  'لقطة نهائية ثابتة عند الإغلاق (§21). لا تتغير نتيجة الصفقة لاحقاً '
  'بصمت، ويمكن إعادة طباعة تقريرها دون اختلاف.';

create trigger deal_closing_snapshots_immutable
  before update or delete on public.deal_closing_snapshots
  for each row execute function public.forbid_mutation();

alter table public.deal_closing_snapshots enable row level security;

create policy deal_closing_snapshots_select on public.deal_closing_snapshots
  for select to authenticated using (auth.uid() is not null);

-- ── سجل إعادة الفتح (§21) ──────────────────────────────────────────────

create table public.deal_reopenings (
  id           uuid        primary key default gen_random_uuid(),
  deal_id      uuid        not null references public.deals (id) on delete restrict,
  snapshot_id  uuid        not null references public.deal_closing_snapshots (id) on delete restrict,
  reason       text        not null,
  reopened_at  timestamptz not null default now(),
  reopened_by  uuid        references auth.users (id) on delete set null,
  constraint deal_reopenings_reason_not_blank check (btrim(reason) <> '')
);

create trigger deal_reopenings_immutable
  before update or delete on public.deal_reopenings
  for each row execute function public.forbid_mutation();

alter table public.deal_reopenings enable row level security;

create policy deal_reopenings_select on public.deal_reopenings
  for select to authenticated using (auth.uid() is not null);

-- ── جدول المصالحة (§24.6) ──────────────────────────────────────────────

create view public.v_deal_reconciliation
with (security_invoker = true)
as
select
  d.id as deal_id,

  -- ── محور الوزن ──────────────────────────────────────────────────────
  q.original_weight_g,
  q.sold_weight_g,
  q.returned_weight_g,
  q.adjusted_weight_g,
  q.open_weight_g,

  /*
    الفرق الوزني غير المفسر.

    بنيوياً يجب أن يكون صفراً: المسلَّم = المباع + المسترد + المسوّى +
    المفتوح. نحسبه صراحةً لا افتراضاً، فلو أُضيف نوع حركة جديد يسوّي
    وزناً دون أن يُحتسب في الفئات الثلاث، يظهر هنا فوراً بدل أن يختفي
    في رصيد يبدو سليماً.
  */
  (q.original_weight_g
   - (q.sold_weight_g + q.returned_weight_g + q.adjusted_weight_g + q.open_weight_g)
  )::weight_grams as unexplained_weight,

  -- ── محور المال ──────────────────────────────────────────────────────
  m.original_value,
  m.adjusted_value,
  m.total_paid,
  m.remaining_balance,

  -- الفرق المالي غير المفسر — بنفس منطق الوزن
  (m.adjusted_value - (m.total_paid + m.remaining_balance))::money_amount
    as unexplained_money,

  -- ── شروط الإغلاق (§21، §24.6) ───────────────────────────────────────
  (q.open_weight_g = 0)      as weight_settled,
  (m.remaining_balance = 0)  as payment_settled,
  (q.original_weight_g
   - (q.sold_weight_g + q.returned_weight_g + q.adjusted_weight_g + q.open_weight_g)
   = 0)                      as weight_explained,
  (m.adjusted_value - (m.total_paid + m.remaining_balance) = 0) as money_explained,

  (q.open_weight_g = 0
   and m.remaining_balance = 0
   and q.original_weight_g
       - (q.sold_weight_g + q.returned_weight_g + q.adjusted_weight_g + q.open_weight_g) = 0
   and m.adjusted_value - (m.total_paid + m.remaining_balance) = 0
  ) as can_close

from public.deals d
join public.v_deal_quantity q on q.deal_id = d.id
join public.v_deal_money    m on m.deal_id = d.id;

comment on view public.v_deal_reconciliation is
  'شاشة المصالحة قبل الإغلاق (§24.6). can_close يشترط الشروط الأربعة '
  'معاً: وزن مفتوح صفر، رصيد صفر، ولا فروقات غير مفسرة في أي منهما.';


-- ─── 20260814091300_settlement_rpc.sql ───────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0014 — دوال التسوية والإغلاق
--
-- المرجع: §21، §24.2، §24.6، §27، §28
-- ═══════════════════════════════════════════════════════════════════════

-- ── تسوية وزن معتمدة (§24.2) ───────────────────────────────────────────
-- الطريق النظامي لتفسير وزن ناقص أو زائد لدى الموزع: هدر، فرق ميزان،
-- تلف. بدونه لا يمكن إغلاق صفقة بقي فيها وزن غير مبرَّر.

create or replace function public.record_weight_adjustment(
  p_deal_id  uuid,
  p_weight_g weight_grams,
  p_reason   text,
  p_date     date default current_date
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_line        record;
  v_open_weight weight_grams;
  v_open_cost   money_amount;
  v_open_profit money_amount;
  v_cost        money_amount;
  v_profit      money_amount;
  v_entry_id    bigint;
begin
  -- §28: تسوية وزن أو قيمة = Manager/Admin
  perform public.assert_permission('deals.adjust');

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن التسوية يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'تسوية الوزن تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception 'لا يمكن تسوية وزن صفقة %.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  select
    coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0),
    coalesce(sum(cost_delta), 0),
    coalesce(sum(expected_profit_delta), 0)
  into v_open_weight, v_open_cost, v_open_profit
  from public.deal_ledger
  where deal_id = p_deal_id;

  if p_weight_g > v_open_weight then
    raise exception
      'وزن التسوية % ج يتجاوز الوزن المفتوح وهو % ج.', p_weight_g, v_open_weight
      using errcode = 'check_violation';
  end if;

  select * into v_line from public.deal_lines where deal_id = p_deal_id limit 1;

  -- عند تسوية كامل المتبقي ننقل الرصيد كما هو فيصل إلى صفر تام
  if p_weight_g = v_open_weight then
    v_cost   := v_open_cost;
    v_profit := v_open_profit;
  else
    v_cost   := round(p_weight_g * v_line.cost_per_g, 4);
    v_profit := round(p_weight_g * v_line.expected_profit_per_g, 4);
  end if;

  /*
    التسوية تخرج الوزن من العهدة وتُسقط تكلفته وربحه المتوقع.

    لا تعود الكمية للمخزون — بخلاف الاسترداد — لأنها لم تعد موجودة.
    التكلفة المسقطة خسارة تظهر في الربح النهائي للصفقة.
    ولا تمس القيمة التجارية: ما يدين به الموزع قرار تجاري منفصل يُعالَج
    بتسوية تجارية إن لزم.
  */
  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    settled_weight_g, cost_delta, expected_profit_delta,
    ref_type, reason, occurred_at, created_by
  )
  values (
    p_deal_id, v_line.id, 'WEIGHT_ADJUSTMENT',
    p_weight_g, -v_cost, -v_profit,
    'weight_adjustment', p_reason, p_date::timestamptz, auth.uid()
  )
  returning id into v_entry_id;

  perform public.write_audit(
    'deal.weight_adjusted', 'deals', p_deal_id::text,
    jsonb_build_object('weight_g', p_weight_g, 'cost', v_cost, 'reason', p_reason)
  );

  return v_entry_id;
end;
$$;

-- ── تسوية تجارية معتمدة (§24.2) ────────────────────────────────────────

create or replace function public.record_commercial_adjustment(
  p_deal_id uuid,
  p_amount  money_amount,
  p_reason  text,
  p_date    date default current_date
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal     record;
  v_entry_id bigint;
begin
  perform public.assert_permission('deals.adjust');

  if p_amount is null or p_amount = 0 then
    raise exception 'مبلغ التسوية التجارية لا يمكن أن يكون صفراً.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'التسوية التجارية تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception 'لا يمكن تسوية صفقة %.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- موجب يزيد ما على الموزع، وسالب خصم تجاري معتمد يخفضه
  insert into public.deal_ledger (
    deal_id, entry_type, commercial_value_delta,
    ref_type, reason, occurred_at, created_by
  )
  values (
    p_deal_id, 'COMMERCIAL_ADJUSTMENT', p_amount,
    'commercial_adjustment', p_reason, p_date::timestamptz, auth.uid()
  )
  returning id into v_entry_id;

  perform public.write_audit(
    'deal.commercial_adjusted', 'deals', p_deal_id::text,
    jsonb_build_object('amount', p_amount, 'reason', p_reason)
  );

  return v_entry_id;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- إغلاق الصفقة (§21، §24.6)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.close_deal(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_recon       record;
  v_profit      record;
  v_version     int;
  v_snapshot_id uuid;
begin
  -- §28: إغلاق Deal = Authorized Manager
  perform public.assert_permission('deals.close');

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status = 'closed' then
    raise exception 'الصفقة مغلقة أصلاً.' using errcode = 'restrict_violation';
  end if;

  if v_deal.status = 'cancelled' then
    raise exception 'الصفقة ملغاة.' using errcode = 'restrict_violation';
  end if;

  select * into v_recon from public.v_deal_reconciliation where deal_id = p_deal_id;

  /*
    بوابة الإغلاق (§24.6).

    كل شرط برسالته الخاصة لأن «لا يمكن الإغلاق» وحدها لا تفيد المستخدم
    بشيء؛ عليه أن يعرف أي جرام أو ريال لم يُفسَّر بعد.
  */
  if not v_recon.weight_settled then
    raise exception
      'لا يمكن الإغلاق: ما زال لدى الموزع % ج غير مسوّاة. سجّل تصريفاً أو استرداداً أو تسوية وزن معتمدة.',
      v_recon.open_weight_g
      using errcode = 'restrict_violation';
  end if;

  if not v_recon.payment_settled then
    if v_recon.remaining_balance > 0 then
      raise exception
        'لا يمكن الإغلاق: ما زال على الموزع % غير مسدد. سجّل تحصيلاً أو تسوية تجارية معتمدة.',
        v_recon.remaining_balance
        using errcode = 'restrict_violation';
    else
      raise exception
        'لا يمكن الإغلاق: للموزع رصيد دائن % يحتاج معالجة أولاً.',
        -v_recon.remaining_balance
        using errcode = 'restrict_violation';
    end if;
  end if;

  if not v_recon.weight_explained or not v_recon.money_explained then
    raise exception
      'لا يمكن الإغلاق: توجد فروقات غير مفسرة — وزن % ومال %.',
      v_recon.unexplained_weight, v_recon.unexplained_money
      using errcode = 'restrict_violation';
  end if;

  -- ── اللقطة النهائية (§21) ────────────────────────────────────────────

  select * into v_profit from public.v_deal_profit where deal_id = p_deal_id;

  select coalesce(max(version), 0) + 1 into v_version
  from public.deal_closing_snapshots where deal_id = p_deal_id;

  insert into public.deal_closing_snapshots (
    deal_id, version, closed_by,
    original_weight_g, sold_weight_g, returned_weight_g, adjusted_weight_g,
    original_value, adjusted_value, total_paid,
    original_capital_cost, returned_capital_cost, cost_of_goods_sold,
    original_expected_profit, cancelled_expected_profit, realized_profit,
    details
  )
  values (
    p_deal_id, v_version, auth.uid(),
    v_recon.original_weight_g, v_recon.sold_weight_g,
    v_recon.returned_weight_g, v_recon.adjusted_weight_g,
    v_recon.original_value, v_recon.adjusted_value, v_recon.total_paid,
    v_profit.original_capital_cost, v_profit.returned_capital_cost,
    v_profit.cost_of_goods_sold,
    v_profit.original_expected_profit, v_profit.cancelled_expected_profit,
    v_profit.realized_profit,
    jsonb_build_object(
      'deal_no',            v_deal.deal_no,
      'distributor_id',     v_deal.distributor_id,
      'delivery_date',      v_deal.delivery_date,
      'due_date',           v_deal.due_date,
      'open_capital_cost',  v_profit.open_capital_cost,
      'closed_at',          now()
    )
  )
  returning id into v_snapshot_id;

  insert into public.deal_ledger (
    deal_id, entry_type, ref_type, ref_id, reason, created_by
  )
  values (
    p_deal_id, 'DEAL_CLOSE', 'closing_snapshot', v_snapshot_id::text,
    'إغلاق بعد مصالحة بلا فروقات', auth.uid()
  );

  update public.deals
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = p_deal_id;

  perform public.write_audit(
    'deal.closed', 'deals', p_deal_id::text,
    jsonb_build_object(
      'snapshot_id',     v_snapshot_id,
      'version',         v_version,
      'realized_profit', v_profit.realized_profit
    )
  );

  return v_snapshot_id;
end;
$$;

comment on function public.close_deal is
  'يغلق الصفقة بعد التحقق من المصالحة (§24.6) وينشئ لقطة نهائية ثابتة '
  '(§21). يرفض الإغلاق بوزن مفتوح أو رصيد مالي أو فروقات غير مفسرة.';

-- ── إعادة الفتح (§21، §28: Admin فقط) ──────────────────────────────────

create or replace function public.reopen_deal(
  p_deal_id uuid,
  p_reason  text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_snapshot_id uuid;
  v_reopen_id   uuid;
begin
  perform public.assert_permission('deals.reopen');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'إعادة فتح الصفقة تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status <> 'closed' then
    raise exception 'الصفقة ليست مغلقة.' using errcode = 'restrict_violation';
  end if;

  select id into v_snapshot_id
  from public.deal_closing_snapshots
  where deal_id = p_deal_id
  order by version desc limit 1;

  -- لقطة الإغلاق السابقة تبقى محفوظة (§21)؛ نسجل فقط أنه أُعيد الفتح
  insert into public.deal_reopenings (deal_id, snapshot_id, reason, reopened_by)
  values (p_deal_id, v_snapshot_id, p_reason, auth.uid())
  returning id into v_reopen_id;

  update public.deals
  set status = 'reopened', closed_at = null, closed_by = null
  where id = p_deal_id;

  perform public.write_audit(
    'deal.reopened', 'deals', p_deal_id::text,
    jsonb_build_object(
      'reason',               p_reason,
      'previous_snapshot_id', v_snapshot_id
    )
  );

  return v_reopen_id;
end;
$$;

comment on function public.reopen_deal is
  'إعادة فتح صفقة مغلقة بصلاحية خاصة مع سبب موثق. لقطة الإغلاق السابقة '
  'تبقى محفوظة ويُنشأ إغلاق بنسخة جديدة لاحقاً (§21).';

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.record_weight_adjustment(uuid, weight_grams, text, date)
  from public, anon;
grant execute on function public.record_weight_adjustment(uuid, weight_grams, text, date)
  to authenticated;

revoke all on function public.record_commercial_adjustment(uuid, money_amount, text, date)
  from public, anon;
grant execute on function public.record_commercial_adjustment(uuid, money_amount, text, date)
  to authenticated;

revoke all on function public.close_deal(uuid) from public, anon;
grant execute on function public.close_deal(uuid) to authenticated;

revoke all on function public.reopen_deal(uuid, text) from public, anon;
grant execute on function public.reopen_deal(uuid, text) to authenticated;


-- ─── 20260814091400_reporting.sql ────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0015 — فصل التقارير الداخلية عن تقارير الموزعين
--
-- §V5.12: «ابنِ التقارير الخارجية والداخلية كمسارين منفصلين على مستوى
-- البيانات والصلاحيات، وليس كزر إظهار/إخفاء في الواجهة فقط.»
--
-- §V5.8: «الـPDF الخارجي يتم إنشاؤه من Dataset منفصل لا يحتوي أصلاً على
-- الحقول السرية، بدلاً من إنشاء تقرير كامل ثم إخفاء بعض الأعمدة.»
--
-- المرجع: إضافة V5 بالكامل، §19، §24.7
-- ═══════════════════════════════════════════════════════════════════════

-- ── إحكام الوصول للبيانات الحساسة ──────────────────────────────────────
/*
  فصل التقارير لا معنى له إن استطاع من لا يملك صلاحية التقارير الداخلية
  قراءة التكلفة من الجداول مباشرة. السياسات السابقة كانت تسمح لكل مستخدم
  مسجَّل بقراءة كل شيء — نُحكمها الآن على الجداول التي تحمل تكلفة أو ربحاً.

  مَن يملك reports.internal اليوم: المالك، العمليات، المالي، المدقق.
  ومَن لا يملكها: التحصيل — فلا يرى تكلفة الجرام ولا الربح من أي مسار.
*/

drop policy if exists lots_select on public.lots;
create policy lots_select on public.lots
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists inventory_ledger_select on public.inventory_ledger;
create policy inventory_ledger_select on public.inventory_ledger
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists purchases_select on public.purchases;
create policy purchases_select on public.purchases
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists purchase_expenses_select on public.purchase_expenses;
create policy purchase_expenses_select on public.purchase_expenses
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists deal_lines_select on public.deal_lines;
create policy deal_lines_select on public.deal_lines
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists deal_ledger_select on public.deal_ledger;
create policy deal_ledger_select on public.deal_ledger
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists deal_returns_select on public.deal_returns;
create policy deal_returns_select on public.deal_returns
  for select to authenticated
  using (public.has_permission('reports.internal'));

drop policy if exists deal_closing_snapshots_select on public.deal_closing_snapshots;
create policy deal_closing_snapshots_select on public.deal_closing_snapshots
  for select to authenticated
  using (public.has_permission('reports.internal'));

/*
  حارس صريح على العروض الحساسة.

  إحكام RLS على deal_ledger وحده لا يكفي: v_deal_profit تستخدم LEFT JOIN،
  فحين تُخفي السياسة صفوف الدفتر تُرجع الـ view صفاً لكل صفقة بمجاميع
  أصفار بدل ألا تُرجع شيئاً. ذلك لا يسرّب رقماً حقيقياً لكنه يعرض أرقاماً
  مضللة ويجعل عرضاً داخلياً يبدو متاحاً.

  الشرط أدناه يجعل النتيجة فارغة تماماً لمن لا يملك الصلاحية.
*/
create or replace view public.v_deal_profit
with (security_invoker = true)
as
select
  d.id as deal_id,
  coalesce(sum(dl.expected_profit_delta)
    filter (where dl.entry_type in ('DEAL_OPEN', 'QTY_DELIVERED')), 0)::money_amount
    as original_expected_profit,
  (-coalesce(sum(dl.expected_profit_delta)
    filter (where dl.entry_type = 'QTY_RETURNED'), 0))::money_amount
    as cancelled_expected_profit,
  coalesce(sum(dl.expected_profit_delta), 0)::money_amount
    as open_expected_profit,
  coalesce(sum(dl.realized_profit_delta), 0)::money_amount as realized_profit,
  coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type in ('DEAL_OPEN', 'QTY_DELIVERED')), 0)::money_amount
    as original_capital_cost,
  (-coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type = 'QTY_RETURNED'), 0))::money_amount
    as returned_capital_cost,
  (-coalesce(sum(dl.cost_delta)
    filter (where dl.entry_type = 'QTY_SOLD'), 0))::money_amount
    as cost_of_goods_sold,
  coalesce(sum(dl.cost_delta), 0)::money_amount as open_capital_cost
from public.deals d
left join public.deal_ledger dl on dl.deal_id = d.id
where public.has_permission('reports.internal')
group by d.id;

-- ── قوالب التقارير وسجل التوليد (§V5.10) ───────────────────────────────

create type public.report_audience as enum ('INTERNAL', 'DISTRIBUTOR');

create table public.report_templates (
  code        text        primary key,
  name        text        not null,
  audience    public.report_audience not null,
  description text        not null default '',
  is_active   boolean     not null default true
);

comment on table public.report_templates is
  '§V5.8: لكل قالب Report Type ثابت — INTERNAL أو DISTRIBUTOR. '
  'الجمهور خاصية القالب لا خيار وقت التوليد.';

alter table public.report_templates enable row level security;

create policy report_templates_select on public.report_templates
  for select to authenticated using (auth.uid() is not null);

insert into public.report_templates (code, name, audience, description) values
  ('DEAL_STATEMENT_INTERNAL', 'كشف صفقة داخلي', 'INTERNAL',
   'نسخة مالية وتشغيلية كاملة للإدارة'),
  ('DEAL_STATEMENT_DISTRIBUTOR', 'كشف صفقة للموزع', 'DISTRIBUTOR',
   'نسخة خارجية بدون أرباح أو تكلفة أو رأس مال'),
  ('DEAL_CLOSURE_INTERNAL', 'تقرير إغلاق داخلي', 'INTERNAL',
   'ربحية الصفقة النهائية بعد الإغلاق'),
  ('DEAL_CLOSURE_DISTRIBUTOR', 'تقرير إغلاق للموزع', 'DISTRIBUTOR',
   'إثبات تسوية الصفقة بالكامل دون بيانات داخلية');

create table public.report_generation_log (
  id           bigint      generated always as identity primary key,
  template_code text       not null references public.report_templates (code),
  audience     public.report_audience not null,
  entity_type  text        not null,
  entity_id    text        not null,
  generated_at timestamptz not null default now(),
  generated_by uuid        references auth.users (id) on delete set null,
  was_exported boolean     not null default false
);

comment on table public.report_generation_log is
  '§V5.8: يسجل نوع التقرير والصفقة والمستخدم ووقت الإنشاء. توليد تقرير '
  'داخلي بواسطة مستخدم ذي صلاحية حساسة أحد التنبيهات في §24.11.';

create index report_generation_log_entity_idx
  on public.report_generation_log (entity_type, entity_id, generated_at desc);

create trigger report_generation_log_immutable
  before update or delete on public.report_generation_log
  for each row execute function public.forbid_mutation();

alter table public.report_generation_log enable row level security;

create policy report_generation_log_select on public.report_generation_log
  for select to authenticated
  using (public.has_permission('reports.internal'));

-- ═══════════════════════════════════════════════════════════════════════
-- المسار الداخلي — كل شيء
-- ═══════════════════════════════════════════════════════════════════════

create view public.v_deal_statement_internal
with (security_invoker = true)
as
select
  s.deal_id,
  s.deal_no,
  s.distributor_id,
  dist.name                  as distributor_name,
  dist.code                  as distributor_code,
  it.name                    as item_name,
  l.lot_no,
  s.deal_status,
  s.delivery_date,
  s.due_date,
  s.closed_at,

  s.original_weight_g,
  s.sold_weight_g,
  s.returned_weight_g,
  s.adjusted_weight_g,
  s.open_weight_g,
  s.settlement_ratio,

  s.original_value,
  s.adjusted_value,
  s.total_paid,
  s.remaining_balance,
  s.payment_ratio,

  s.quantity_status,
  s.payment_status,
  s.is_overdue,

  -- الحقول الحساسة (§V5.4)
  dl.cost_per_g,
  dl.deal_value_per_g,
  dl.expected_profit_per_g,
  p.original_capital_cost,
  p.returned_capital_cost,
  p.cost_of_goods_sold,
  p.open_capital_cost,
  p.original_expected_profit,
  p.cancelled_expected_profit,
  p.open_expected_profit,
  p.realized_profit
from public.v_deal_status s
join public.deals d          on d.id = s.deal_id
join public.distributors dist on dist.id = s.distributor_id
join public.v_deal_profit p  on p.deal_id = s.deal_id
left join public.deal_lines dl on dl.deal_id = s.deal_id
left join public.lots l        on l.id = dl.lot_id
left join public.items it      on it.id = l.item_id
-- حارس صريح: من لا يملك صلاحية التقارير الداخلية لا يرى صفاً واحداً،
-- لا صفوفاً بمجاميع أصفار (§V5.11)
where public.has_permission('reports.internal');

comment on view public.v_deal_statement_internal is
  '⚠️ كشف الصفقة الداخلي — يحتوي التكلفة ورأس المال والربح. محمي بـ RLS '
  'عبر deal_lines و deal_ledger اللذين يشترطان reports.internal.';

-- ═══════════════════════════════════════════════════════════════════════
-- المسار الخارجي — Dataset منفصل لا يحتوي الحقول السرية أصلاً
-- ═══════════════════════════════════════════════════════════════════════

/*
  §V5.3 — الحقول الممنوعة نهائياً من مخرجات الموزع:
    سعر شراء الشركة · تكلفة الجرام الداخلية · رأس المال المستخدم ·
    الربح المتوقع أو المحقق · ربح الجرام · هامش الربح أو نسبة العائد ·
    المصاريف الداخلية · أي بيانات شراكة · أرباح الشركة أو أرصدتها ·
    أي مقارنة أو تقييم للموزع

  ما يظهر: ما يخص التعامل بين الطرفين فقط (§V5.2).

  الدالة SECURITY DEFINER لأنها لا تقرأ الجداول الحساسة إطلاقاً — تبني
  النتيجة من v_deal_status وحده الذي لا يحمل تكلفة ولا ربحاً. بذلك
  يستطيع مستخدم بصلاحية تقارير الموزع فقط توليد الكشف، دون أن يُمنح
  وصولاً لأي جدول داخلي.
*/

create type public.distributor_statement as (
  deal_no             text,
  distributor_name    text,
  distributor_code    text,
  item_name           text,
  delivery_date       date,
  due_date            date,
  closed_at           timestamptz,
  deal_status         text,
  original_weight_g   weight_grams,
  returned_weight_g   weight_grams,
  open_weight_g       weight_grams,
  original_value      money_amount,
  value_reduction     money_amount,
  adjusted_value      money_amount,
  total_paid          money_amount,
  remaining_balance   money_amount,
  credit_balance      money_amount
);

create or replace function public.get_distributor_statement(p_deal_id uuid)
returns public.distributor_statement
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_result public.distributor_statement;
begin
  perform public.assert_permission('reports.distributor');

  select
    s.deal_no,
    dist.name,
    dist.code,
    it.name,
    s.delivery_date,
    s.due_date,
    s.closed_at,
    s.deal_status::text,
    s.original_weight_g,
    s.returned_weight_g,
    s.open_weight_g,
    s.original_value,
    -- §V5.5: يظهر أثر الاسترداد كتخفيض تجاري فقط، لا رأس المال ولا الربح
    (s.original_value - s.adjusted_value)::money_amount,
    s.adjusted_value,
    s.total_paid,
    greatest(s.remaining_balance, 0)::money_amount,
    greatest(-s.remaining_balance, 0)::money_amount
  into v_result
  from public.v_deal_status s
  join public.deals d           on d.id = s.deal_id
  join public.distributors dist on dist.id = s.distributor_id
  left join public.deal_lines dl on dl.deal_id = s.deal_id
  left join public.lots l        on l.id = dl.lot_id
  left join public.items it      on it.id = l.item_id
  where s.deal_id = p_deal_id;

  if v_result.deal_no is null then
    raise exception 'الصفقة غير موجودة.' using errcode = 'no_data_found';
  end if;

  return v_result;
end;
$$;

comment on function public.get_distributor_statement is
  '§V5.8: كشف الموزع من Dataset منفصل. النوع نفسه لا يحوي حقل تكلفة أو '
  'ربح أو رأس مال — التسريب مستحيل بالبناء لا بالإخفاء.';

-- ── حركات الصفقة كما تظهر للموزع (§V5.2) ───────────────────────────────

create type public.distributor_movement as (
  occurred_at timestamptz,
  kind        text,
  weight_g    weight_grams,
  amount      money_amount,
  reference   text
);

create or replace function public.get_distributor_movements(p_deal_id uuid)
returns setof public.distributor_movement
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
begin
  perform public.assert_permission('reports.distributor');

  /*
    الحركات التي تخص الموزع فقط.

    نستثني QTY_SOLD صراحةً: ما صرّفه الموزع شأن تشغيلي داخلي لا يغيّر
    التزامه التجاري، وإظهاره في كشفه يخلط بين محورين. ونستثني كل حركة
    تحمل أثراً على التكلفة أو الربح.
  */
  return query
  select
    dl.occurred_at,
    case dl.entry_type
      when 'QTY_DELIVERED'         then 'تسليم كمية'
      when 'QTY_RETURNED'          then 'استرداد كمية'
      when 'PAYMENT_RECEIVED'      then 'دفعة مسددة'
      when 'PAYMENT_REVERSAL'      then 'عكس دفعة'
      when 'COMMERCIAL_ADJUSTMENT' then 'تسوية تجارية'
      when 'CREDIT_TRANSFER'       then 'معالجة رصيد دائن'
      when 'DEAL_CLOSE'            then 'إقفال الصفقة'
      else 'حركة'
    end,
    (dl.delivered_weight_g
     + case when dl.entry_type = 'QTY_RETURNED' then dl.settled_weight_g else 0 end
    )::weight_grams,
    case
      when dl.entry_type in ('PAYMENT_RECEIVED', 'PAYMENT_REVERSAL')
        then dl.paid_delta
      else dl.commercial_value_delta
    end::money_amount,
    dl.reason
  from public.deal_ledger dl
  where dl.deal_id = p_deal_id
    and dl.entry_type in (
      'QTY_DELIVERED', 'QTY_RETURNED', 'PAYMENT_RECEIVED',
      'PAYMENT_REVERSAL', 'COMMERCIAL_ADJUSTMENT', 'CREDIT_TRANSFER',
      'DEAL_CLOSE'
    )
  order by dl.occurred_at, dl.id;
end;
$$;

-- ── تسجيل توليد التقرير (§V5.8) ────────────────────────────────────────

create or replace function public.log_report_generation(
  p_template_code text,
  p_entity_type   text,
  p_entity_id     text,
  p_was_exported  boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_audience public.report_audience;
  v_log_id   bigint;
begin
  select audience into v_audience
  from public.report_templates
  where code = p_template_code and is_active;

  if v_audience is null then
    raise exception 'قالب التقرير % غير معرَّف.', p_template_code
      using errcode = 'no_data_found';
  end if;

  -- الصلاحية تتبع جمهور القالب لا اختيار المستخدم (§V5.8)
  if v_audience = 'INTERNAL' then
    perform public.assert_permission('reports.internal');
  else
    perform public.assert_permission('reports.distributor');
  end if;

  insert into public.report_generation_log (
    template_code, audience, entity_type, entity_id, generated_by, was_exported
  )
  values (
    p_template_code, v_audience, p_entity_type, p_entity_id,
    auth.uid(), coalesce(p_was_exported, false)
  )
  returning id into v_log_id;

  return v_log_id;
end;
$$;

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.get_distributor_statement(uuid) from public, anon;
grant execute on function public.get_distributor_statement(uuid) to authenticated;

revoke all on function public.get_distributor_movements(uuid) from public, anon;
grant execute on function public.get_distributor_movements(uuid) to authenticated;

revoke all on function public.log_report_generation(text, text, text, boolean)
  from public, anon;
grant execute on function public.log_report_generation(text, text, text, boolean)
  to authenticated;


-- ─── 20260814091500_grants.sql ───────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0016 — صلاحيات قاعدة البيانات الصريحة
--
-- Supabase تمنح دور authenticated وصولاً واسعاً على schema public
-- افتراضياً، وسياسات RLS هي ما يصفّي الصفوف بعد ذلك. الاعتماد على ذلك
-- الافتراض ضمنياً يجعل الأمان غير مرئي في الريبو ومختلفاً بين البيئات.
--
-- هنا نثبّت المنح صراحةً: القراءة عبر RLS، ولا كتابة مباشرة على أي
-- جدول حركات — الكتابة كلها عبر دوال RPC (§30).
-- ═══════════════════════════════════════════════════════════════════════

grant usage on schema public to anon, authenticated;

-- ── القراءة: مسموحة على مستوى الجدول، ومصفّاة بـ RLS على مستوى الصف ──
-- كل جدول عليه RLS مفعّل، فالمنح هنا لا يكشف شيئاً بذاته: السياسات هي
-- التي تقرر أي صفوف يراها كل دور.

grant select on all tables in schema public to authenticated;

-- ── الكتابة: على الجداول المرجعية فقط ─────────────────────────────────
-- هذه بيانات تعريفية لا أثر محاسبي لها بذاتها، وسياساتها تشترط
-- الصلاحية المناسبة.

grant insert, update on public.items        to authenticated;
grant insert, update on public.suppliers    to authenticated;
grant insert, update on public.distributors to authenticated;
grant insert, update on public.cash_accounts to authenticated;
grant insert, update on public.profiles     to authenticated;
grant update         on public.app_settings to authenticated;

/*
  لا منح كتابة على: purchases, purchase_expenses, lots, inventory_ledger,
  deals, deal_lines, deal_ledger, deal_returns, payments,
  payment_allocations, credit_resolutions, cash_transactions,
  deal_closing_snapshots, deal_reopenings, audit_log, report_generation_log.

  هذه كلها تُكتب حصراً من دوال SECURITY DEFINER تنفّذ التحقق والمعاملة
  الذرية وسجل التدقيق. غياب المنح هنا هو القفل الفعلي — لا مجرد غياب
  سياسة RLS.
*/

-- ── المتسلسلات ─────────────────────────────────────────────────────────
-- تحتاجها الجداول المرجعية التي تقبل insert مباشرة.

grant usage on all sequences in schema public to authenticated;

-- ── لا وصول مجهول ──────────────────────────────────────────────────────
-- النظام كله خلف تسجيل الدخول؛ لا شيء يُقرأ بدون جلسة.

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;

-- ── المنح الافتراضية للكائنات المستقبلية ──────────────────────────────
-- حتى لا يعتمد ترحيل لاحق على منح ضمنية ينساها.

alter default privileges in schema public
  grant select on tables to authenticated;


-- ─── 20260814091600_dashboard.sql ────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0017 — لوحة السيولة والمركز التشغيلي والتنبيهات
--
-- §24.10: «تضاف لوحة مالية مبسطة توضح أين توجد قيمة النشاط فعلاً، حتى
-- لا يبدو وجود ربح محقق وكأنه سيولة متاحة للسحب.»
--
-- §27: «Dashboard مقابل Deal Statement ⇒ الأرقام متطابقة من نفس مصدر
-- الحساب» — لذلك كل رقم هنا يُشتق من نفس العروض التي تقرأ منها التقارير،
-- لا من استعلام موازٍ قد يفترق عنها.
--
-- المرجع: §24.10، §24.11، §26، §27
-- ═══════════════════════════════════════════════════════════════════════

create view public.v_cash_position
with (security_invoker = true)
as
select
  -- ── الأصول التشغيلية (§24.10) ────────────────────────────────────────

  -- النقد المتاح في الصندوق والبنك
  (select coalesce(sum(balance), 0) from public.v_cash_balance)::money_amount
    as cash_available,

  -- ذمم الموزعين: ما على الموزعين من صفقات غير مغلقة. الأرصدة السالبة
  -- (الدائنة) تُستثنى لأنها التزام لا أصل — تظهر في الجانب الآخر.
  (select coalesce(sum(greatest(m.remaining_balance, 0)), 0)
   from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.status not in ('closed', 'cancelled'))::money_amount
    as distributor_receivables,

  -- §24.10: قيمة المخزون في المخزن ولدى الموزعين منفصلتين
  (select coalesce(sum(on_hand_cost), 0)
   from public.v_lot_stock)::money_amount
    as inventory_at_warehouse,

  (select coalesce(sum(p.open_capital_cost), 0)
   from public.v_deal_profit p
   join public.deals d on d.id = p.deal_id
   where d.status not in ('closed', 'cancelled'))::money_amount
    as inventory_at_distributors,

  -- ── الالتزامات (§24.10) ──────────────────────────────────────────────

  -- الأرصدة الدائنة للموزعين: مال الموزعين لدى الشركة
  (select coalesce(sum(unresolved_amount), 0)
   from public.v_distributor_credits
   where unresolved_amount > 0)::money_amount
    as distributor_credits,

  -- ── مؤشرات الربح الثلاثة منفصلة (§24.9) ──────────────────────────────

  (select coalesce(sum(realized_profit), 0)
   from public.v_deal_profit)::money_amount
    as realized_profit,

  /*
    الربح المتوقع مؤشر تحليلي فقط.

    §24.10 صريح: «يجب ألا يُستخدم Expected Profit في احتساب النقد المتاح
    أو الأرباح القابلة للسحب». يُعرض هنا في عمود مستقل ولا يدخل في أي
    مجموع مع النقد أو الأصول.
  */
  (select coalesce(sum(p.open_expected_profit), 0)
   from public.v_deal_profit p
   join public.deals d on d.id = p.deal_id
   where d.status not in ('closed', 'cancelled'))::money_amount
    as open_expected_profit;

comment on view public.v_cash_position is
  'لوحة السيولة والمركز التشغيلي (§24.10). الربح المتوقع معزول ولا يدخل '
  'في أي مجموع مع النقد أو الأصول.';

-- ── التنبيهات وإدارة الاستثناءات (§24.11) ──────────────────────────────

create type public.alert_severity as enum ('info', 'warning', 'critical');

/*
  التنبيهات مشتقة لا مخزَّنة.

  تنبيه مخزَّن يحتاج مزامنة: إن عولجت حالته دون تحديثه بقي معلَّقاً كذباً.
  اشتقاقه من الحالة الفعلية يعني أنه يظهر ويختفي وحده — الحالة هي التنبيه.

  عتبات الأيام تُقرأ من الإعدادات لتبقى قابلة للتغيير (§24.11).
*/
create view public.v_alerts
with (security_invoker = true)
as
-- صفقة مدفوعة بالكامل لكن وزنها غير مسوّى (§24.11)
select
  'deal.paid_stock_pending'                     as code,
  'warning'::public.alert_severity              as severity,
  'صفقة مسددة بالكامل ووزنها غير مسوّى'         as title,
  d.deal_no || ' — متبقٍ ' || s.open_weight_g || ' ج لدى الموزع' as detail,
  'deal'                                        as entity_type,
  d.id::text                                    as entity_id
from public.deals d
join public.v_deal_status s on s.deal_id = d.id
where d.status not in ('closed', 'cancelled')
  and s.payment_status = 'fully_paid'
  and s.open_weight_g > 0

union all

-- وزن الصفقة مسوّى بالكامل لكن يوجد رصيد مالي (§24.11)
select
  'deal.stock_settled_payment_pending',
  'warning'::public.alert_severity,
  'وزن الصفقة مسوّى ويوجد رصيد مالي',
  d.deal_no || ' — متبقٍ ' || s.remaining_balance,
  'deal',
  d.id::text
from public.deals d
join public.v_deal_status s on s.deal_id = d.id
where d.status not in ('closed', 'cancelled')
  and s.quantity_status = 'fully_settled'
  and s.remaining_balance > 0

union all

-- موزع لديه رصيد دائن غير معالج (§24.11، §24.5)
select
  'distributor.unresolved_credit',
  'critical'::public.alert_severity,
  'رصيد دائن للموزع لم يُعالَج',
  d.deal_no || ' — ' || c.unresolved_amount || ' لصالح الموزع',
  'deal',
  d.id::text
from public.v_distributor_credits c
join public.deals d on d.id = c.deal_id
where c.unresolved_amount > 0

union all

-- صفقة تجاوزت الاستحقاق وما زال عليها مبلغ (§18.6)
select
  'deal.overdue',
  'critical'::public.alert_severity,
  'صفقة متأخرة عن تاريخ الاستحقاق',
  d.deal_no || ' — متبقٍ ' || s.remaining_balance,
  'deal',
  d.id::text
from public.deals d
join public.v_deal_status s on s.deal_id = d.id
where s.is_overdue

union all

-- صفقة لم تُسجَّل عليها دفعة منذ عدد أيام قابل للتحديد (§24.11)
select
  'deal.no_recent_payment',
  'warning'::public.alert_severity,
  'صفقة بلا تحصيل منذ مدة',
  d.deal_no || ' — آخر تحصيل قبل '
    || (current_date - coalesce(
         (select max(p.payment_date)
          from public.payment_allocations a
          join public.payments p on p.id = a.payment_id
          where a.deal_id = d.id and a.reversed_at is null),
         d.delivery_date))::text || ' يوماً',
  'deal',
  d.id::text
from public.deals d
join public.v_deal_status s on s.deal_id = d.id
where d.status not in ('closed', 'cancelled')
  and s.remaining_balance > 0
  and current_date - coalesce(
        (select max(p.payment_date)
         from public.payment_allocations a
         join public.payments p on p.id = a.payment_id
         where a.deal_id = d.id and a.reversed_at is null),
        d.delivery_date)
      > coalesce((public.get_setting('alert_days_without_payment'))::int, 30)

union all

-- موزع تجاوز حد الائتمان (§24.11)
select
  'distributor.over_credit_limit',
  'warning'::public.alert_severity,
  'موزع تجاوز حد الائتمان',
  dist.name || ' — الذمة ' || t.balance || ' والحد ' || dist.credit_limit_value,
  'distributor',
  dist.id::text
from public.distributors dist
join lateral (
  select coalesce(sum(greatest(m.remaining_balance, 0)), 0) as balance
  from public.v_deal_money m
  join public.deals d on d.id = m.deal_id
  where d.distributor_id = dist.id
    and d.status not in ('closed', 'cancelled')
) t on true
where dist.is_active
  and dist.credit_limit_value > 0
  and t.balance > dist.credit_limit_value

union all

-- دفعة عامة غير مخصصة بالكامل (§24.4)
select
  'payment.unallocated',
  'info'::public.alert_severity,
  'دفعة غير مخصصة على صفقة',
  dist.name || ' — ' || ps.unallocated_amount || ' غير مخصص',
  'payment',
  ps.payment_id::text
from public.v_payment_status ps
join public.distributors dist on dist.id = ps.distributor_id
where ps.unallocated_amount > 0

union all

-- فروقات مصالحة غير مفسرة (§24.6) — لا يجب أن تحدث، فظهورها حرج
select
  'deal.reconciliation_gap',
  'critical'::public.alert_severity,
  'فرق مصالحة غير مفسر',
  d.deal_no || ' — وزن ' || r.unexplained_weight || ' ومال ' || r.unexplained_money,
  'deal',
  d.id::text
from public.deals d
join public.v_deal_reconciliation r on r.deal_id = d.id
where r.unexplained_weight <> 0 or r.unexplained_money <> 0;

comment on view public.v_alerts is
  'التنبيهات والاستثناءات (§24.11) — مشتقة من الحالة الفعلية لا مخزَّنة، '
  'فتظهر وتختفي وحدها دون خطر بقاء تنبيه معلَّق بعد معالجته.';

-- ── إعدادات عتبات التنبيه ──────────────────────────────────────────────

insert into public.app_settings (key, value, description) values
  ('alert_days_without_payment', '30'::jsonb,
   'عدد الأيام بلا تحصيل قبل ظهور تنبيه على الصفقة'),
  ('alert_days_deal_open', '90'::jsonb,
   'عدد الأيام قبل اعتبار الصفقة مفتوحة أكثر من اللازم')
on conflict (key) do nothing;


-- ─── 20260814091700_access_code.sql ──────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- 0018 — تدقيق تغيير رمز الدخول
--
-- رمز الدخول هو كلمة مرور حساب المالك في Supabase Auth، وتغييره يتم عبر
-- `auth.updateUser` التي لا تمر بقاعدتنا فلا تكتب في سجل التدقيق.
--
-- §11 يشترط أن تظهر كل حركة حساسة في السجل. تغيير مفتاح الدخول للنظام
-- المالي كله حركة حساسة، فنسجّلها صراحةً.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.log_access_code_changed()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول.' using errcode = 'insufficient_privilege';
  end if;

  /*
    لا يُسجَّل الرمز نفسه ولا أي جزء منه — لا القديم ولا الجديد.
    السجل يثبت أن التغيير حدث ومن نفّذه ومتى، وهذا ما يحتاجه التدقيق.
  */
  perform public.write_audit(
    'access_code.changed',
    'auth',
    auth.uid()::text,
    '{}'::jsonb
  );
end;
$$;

comment on function public.log_access_code_changed is
  'يقيّد تغيير رمز الدخول في سجل التدقيق دون تسجيل الرمز نفسه (§11).';

revoke all on function public.log_access_code_changed() from public, anon;
grant execute on function public.log_access_code_changed() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) حساب المالك ورمز الدخول
-- ═══════════════════════════════════════════════════════════════════════

do $seco_owner$
declare
  v_cfg    record;
  v_id     uuid;
begin
  select * into v_cfg from seco_bootstrap.config limit 1;

  select id into v_id from auth.users where email = v_cfg.owner_email;

  if v_id is null then
    v_id := gen_random_uuid();

    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    )
    values (
      v_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_cfg.owner_email,
      crypt(v_cfg.owner_code, gen_salt('bf')),
      now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      jsonb_build_object('full_name', v_cfg.owner_name),
      now(),
      now()
    );

    -- gotrue يتطلب سجل هوية مطابقاً وإلا رفض تسجيل الدخول بالبريد
    insert into auth.identities (
      provider_id, user_id, identity_data, provider, created_at, updated_at
    )
    values (
      v_id::text,
      v_id,
      jsonb_build_object(
        'sub', v_id::text,
        'email', v_cfg.owner_email,
        'email_verified', true,
        'phone_verified', false
      ),
      'email',
      now(),
      now()
    );
  else
    -- الحساب موجود مسبقاً في auth: نحدّث رمزه بدل أن نفشل
    update auth.users
    set encrypted_password = crypt(v_cfg.owner_code, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_id;
  end if;

  -- تريجر handle_new_user أنشأ الملف بدور auditor؛ نرقّيه إلى المالك
  insert into public.profiles (id, full_name, role)
  values (v_id, v_cfg.owner_name, 'owner')
  on conflict (id) do update
    set role = 'owner', full_name = excluded.full_name;

  raise notice 'تم إنشاء المالك: %', v_cfg.owner_email;
end
$seco_owner$;

-- تنظيف إعدادات التهيئة — لا داعي لبقاء الرمز في القاعدة
drop schema seco_bootstrap cascade;

commit;

-- ═══════════════════════════════════════════════════════════════════════
-- تم. افتح الموقع وادخل بالرمز الذي حددته أعلاه.
-- ═══════════════════════════════════════════════════════════════════════
