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
