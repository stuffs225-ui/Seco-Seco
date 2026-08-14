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
