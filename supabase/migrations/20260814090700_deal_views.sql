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
