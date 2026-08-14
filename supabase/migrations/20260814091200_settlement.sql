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
