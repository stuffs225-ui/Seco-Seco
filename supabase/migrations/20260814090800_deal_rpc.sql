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
