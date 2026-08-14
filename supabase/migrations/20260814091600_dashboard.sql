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
