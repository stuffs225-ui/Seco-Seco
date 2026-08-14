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
