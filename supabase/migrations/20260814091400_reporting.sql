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
