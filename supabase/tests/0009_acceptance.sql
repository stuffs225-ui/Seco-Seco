-- ═══════════════════════════════════════════════════════════════════════
-- اختبار القبول الشامل — دورة حياة صفقة كاملة
--
-- الملفات السابقة تختبر كل وحدة على حدة. هذا الملف يشغّل السيناريو
-- التشغيلي كاملاً من الشراء حتى الإغلاق دفعةً واحدة، لأن الأخطاء التي
-- تنجو من اختبارات الوحدات هي أخطاء التفاعل بين الوحدات.
--
-- يخدم أيضاً كوثيقة تتبّع: كل تأكيد يسمّي البند الذي يغطيه من §14 و§27.
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

insert into public.items (id, code, name)
values ('99990000-0000-4000-8000-000000000001', 'ITM-E2E', 'صنف السيناريو');
insert into public.distributors (id, code, name)
values ('99990000-0000-4000-8000-000000000002', 'DST-E2E', 'موزع السيناريو');
insert into public.cash_accounts (id, name)
values ('99990000-0000-4000-8000-000000000003', 'الصندوق');

-- ═══════════════════════════════════════════════════════════════════════
-- 1) الشراء — §14 السطر الأول
-- ═══════════════════════════════════════════════════════════════════════

select public.create_purchase_lot(
  '99990000-0000-4000-8000-000000000001'::uuid,
  '2026-11-01'::date, 1200::weight_grams, 21000::money_amount
);

select is(
  (select cost_per_g from public.lots limit 1),
  17.5::rate_per_gram,
  '§14/1: شراء 1,200g بـ21,000 ⇒ تكلفة الجرام 17.50'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) التسليم — §14 السطر الثاني
-- ═══════════════════════════════════════════════════════════════════════

select public.open_deal(
  '99990000-0000-4000-8000-000000000002'::uuid,
  (select id from public.lots limit 1),
  500::weight_grams, 12000::money_amount, '2026-11-05'::date,
  '2026-12-05'::date
);

select is(
  (select open_expected_profit from public.v_deal_profit limit 1),
  3250::money_amount,
  '§14/2: تسليم 500g بـ12,000 ⇒ ربح متوقع 3,250'
);

select is(
  (select on_hand_weight_g from public.v_lot_stock limit 1),
  700::weight_grams,
  '§14/2: ورصيد المخزون 700g'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) §27/6 — كمية إضافية لنفس الموزع تنشئ صفقة مستقلة
-- ═══════════════════════════════════════════════════════════════════════
/*
  §24.1 يطلب أن يسأل النظام: إضافة للصفقة الحالية أم صفقة جديدة؟

  مع القرار المعتمد (دفعة واحدة لكل صفقة) الجواب محسوم بنيوياً: الإضافة
  للصفقة القائمة مستحيلة، وكل تسليم ينشئ صفقة مستقلة. الواجهة تنبّه
  المستخدم بالصفقات المفتوحة قبل التسليم بدل أن تسأله سؤالاً بلا خيارين.
*/

select public.open_deal(
  '99990000-0000-4000-8000-000000000002'::uuid,
  (select id from public.lots limit 1),
  100::weight_grams, 2600::money_amount, '2026-11-10'::date
);

select is(
  (select count(*)::int from public.deals
   where distributor_id = '99990000-0000-4000-8000-000000000002'),
  2,
  '§27/6: الكمية الإضافية أنشأت صفقة مستقلة لا سطراً في القائمة'
);

select throws_ok(
  $$ insert into public.deal_lines
       (deal_id, lot_id, weight_g, cost_per_g, deal_value_per_g, expected_profit_per_g)
     values ((select id from public.deals order by created_at limit 1),
             (select id from public.lots limit 1), 50, 17.5, 24, 6.5) $$,
  '42501',  -- insufficient_privilege
  null,
  '§24.1: الطبقة الأولى — لا منح كتابة على أسطر الصفقة لأي مستخدم'
);

reset role;

select throws_ok(
  $$ insert into public.deal_lines
       (deal_id, lot_id, weight_g, cost_per_g, deal_value_per_g, expected_profit_per_g)
     values ((select id from public.deals order by created_at limit 1),
             (select id from public.lots limit 1), 50, 17.5, 24, 6.5) $$,
  '23001',  -- restrict_violation
  null,
  '§24.1: الطبقة الثانية — التريجر يرفض حتى بصلاحيات كاملة'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- ═══════════════════════════════════════════════════════════════════════
-- 4) التصريف والتحصيل الجزئي — §14 السطر الثالث
-- ═══════════════════════════════════════════════════════════════════════

select public.record_deal_sale(
  (select id from public.deals order by created_at limit 1),
  300::weight_grams);

select public.record_payment(
  '99990000-0000-4000-8000-000000000002'::uuid,
  5000::money_amount, '2026-11-15'::date,
  'cash'::public.payment_method, 'E2E-1',
  '99990000-0000-4000-8000-000000000003'::uuid, '',
  'specific',
  jsonb_build_array(jsonb_build_object(
    'deal_id', (select id from public.deals order by created_at limit 1),
    'amount', 5000)));

select is(
  (select open_weight_g from public.v_deal_quantity
   where deal_id = (select id from public.deals order by created_at limit 1)),
  200::weight_grams,
  '§14/3: التحصيل الجزئي لم يغيّر الوزن — ما زال 200g مفتوحاً بعد التصريف'
);

select is(
  (select remaining_balance from public.v_deal_money
   where deal_id = (select id from public.deals order by created_at limit 1)),
  7000::money_amount,
  '§14/3: بينما تغيّر الرصيد المالي إلى 7,000'
);

select is(
  (select realized_profit from public.v_deal_profit
   where deal_id = (select id from public.deals order by created_at limit 1)),
  1950::money_amount,
  'الربح المحقق من تصريف 300g = 1,950'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 5) §27/7 — تقرير الموزع بعد نشوء رصيد دائن
-- ═══════════════════════════════════════════════════════════════════════
-- استرداد 200g يخفض القيمة 4,800 ⇒ 7,200، والمسدد 5,000 ⇒ متبقٍ 2,200
-- ثم تحصيل 3,000 يقلبها إلى رصيد دائن 800

select public.record_deal_return(
  (select id from public.deals order by created_at limit 1),
  200::weight_grams, '2026-11-20'::date, 'إرجاع المتبقي');

select public.record_payment(
  '99990000-0000-4000-8000-000000000002'::uuid,
  3000::money_amount, '2026-11-22'::date,
  'cash'::public.payment_method, 'E2E-2',
  '99990000-0000-4000-8000-000000000003'::uuid, '',
  'specific',
  jsonb_build_array(jsonb_build_object(
    'deal_id', (select id from public.deals order by created_at limit 1),
    'amount', 3000)));

select is(
  (select remaining_balance from public.v_deal_money
   where deal_id = (select id from public.deals order by created_at limit 1)),
  (-800)::money_amount,
  'الرصيد صار دائناً 800 لصالح الموزع'
);

-- التقرير الخارجي يعرض الرصيد التجاري ومعالجته بلا أي تكلفة أو ربح
select is(
  ((select public.get_distributor_statement(
     (select id from public.deals order by created_at limit 1))).credit_balance),
  800::money_amount,
  '§27/7: كشف الموزع يظهر الرصيد الدائن 800'
);

select is(
  ((select public.get_distributor_statement(
     (select id from public.deals order by created_at limit 1))).remaining_balance),
  0::money_amount,
  'ولا يظهر مبلغاً مستحقاً عليه في الوقت نفسه'
);

select is(
  ((select public.get_distributor_statement(
     (select id from public.deals order by created_at limit 1))).value_reduction),
  4800::money_amount,
  '§V5.5: يظهر تخفيض تجاري 4,800 دون تفصيل التكلفة أو الربح الملغى'
);

-- بينما التقرير الداخلي يفصّل الأثر كاملاً
select is(
  (select returned_capital_cost from public.v_deal_statement_internal
   where deal_id = (select id from public.deals order by created_at limit 1)),
  3500::money_amount,
  '§V5.5: داخلياً — رأس مال مسترد 3,500 (200g × 17.50)'
);

select is(
  (select cancelled_expected_profit from public.v_deal_statement_internal
   where deal_id = (select id from public.deals order by created_at limit 1)),
  1300::money_amount,
  '§V5.5: وربح متوقع ملغى 1,300 (200g × 6.50)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 6) §27/3 و§27/4 — بوابة الإغلاق
-- ═══════════════════════════════════════════════════════════════════════

select throws_ok(
  $$ select public.close_deal(
       (select id from public.deals order by created_at limit 1)) $$,
  '23001',
  null,
  '§27/4: رصيد دائن غير معالج ⇒ الإغلاق مرفوض'
);

select public.resolve_distributor_credit(
  (select id from public.deals order by created_at limit 1),
  'refund'::public.credit_resolution_method,
  800::money_amount, 'رد الفائض للموزع', null,
  '99990000-0000-4000-8000-000000000003'::uuid);

select is(
  (select can_close from public.v_deal_reconciliation
   where deal_id = (select id from public.deals order by created_at limit 1)),
  true,
  '§24.6: بعد المعالجة اكتملت المصالحة بلا فروقات'
);

select is(
  (select unexplained_weight from public.v_deal_reconciliation
   where deal_id = (select id from public.deals order by created_at limit 1)),
  0::weight_grams,
  '§27/8: الفرق الوزني غير المفسر = صفر'
);

select is(
  (select unexplained_money from public.v_deal_reconciliation
   where deal_id = (select id from public.deals order by created_at limit 1)),
  0::money_amount,
  '§27/8: الفرق المالي غير المفسر = صفر'
);

select lives_ok(
  $$ select public.close_deal(
       (select id from public.deals order by created_at limit 1)) $$,
  'الإغلاق ينجح'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 7) §27/5 — لا تعديل بعد الإغلاق
-- ═══════════════════════════════════════════════════════════════════════

select throws_ok(
  $$ select public.reverse_payment_allocation(
       (select a.id from public.payment_allocations a
        join public.payments p on p.id = a.payment_id
        where p.reference = 'E2E-1'),
       'محاولة تعديل') $$,
  '23001',
  null,
  '§27/5: تعديل دفعة على صفقة مغلقة مرفوض ويتطلب إعادة فتح'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 8) §27/9 — أرقام اللوحة تطابق كشوف الصفقات
-- ═══════════════════════════════════════════════════════════════════════

select is(
  (select realized_profit from public.v_cash_position),
  (select sum(realized_profit)::money_amount from public.v_deal_profit),
  '§27/9: الربح المحقق في اللوحة = مجموعه في الصفقات'
);

select is(
  (select distributor_receivables from public.v_cash_position),
  (select coalesce(sum(greatest(m.remaining_balance, 0)), 0)::money_amount
   from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.status not in ('closed', 'cancelled')),
  '§27/9: ذمم اللوحة = مجموع أرصدة الصفقات المفتوحة'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 9) سلامة المخزون عبر الدورة كاملة
-- ═══════════════════════════════════════════════════════════════════════
-- 1,200 مشترى − 500 مسلَّم − 100 مسلَّم + 200 مسترد = 800g

select is(
  (select on_hand_weight_g from public.v_lot_stock),
  800::weight_grams,
  'رصيد المخزون متسق عبر كل حركات الدورة'
);

-- التكلفة أيضاً: 21,000 − 8,750 − 1,750 + 3,500 = 14,000
select is(
  (select on_hand_cost from public.v_lot_stock),
  14000::money_amount,
  'وتكلفة المخزون متسقة بلا انحراف كسور'
);

-- الوزن الكلي محفوظ: ما في المخزن + ما لدى الموزعين + ما بيع + ما سُوّي
select is(
  ((select on_hand_weight_g from public.v_lot_stock)
   + (select coalesce(sum(open_weight_g + sold_weight_g + adjusted_weight_g), 0)
      from public.v_deal_quantity))::weight_grams,
  1200::weight_grams,
  'حفظ الوزن: المخزن + المفتوح + المباع + المسوّى = المشترى'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 10) سجل التدقيق يغطي الدورة (§11)
-- ═══════════════════════════════════════════════════════════════════════

select ok(
  (select count(distinct action)::int from public.audit_log) >= 7,
  '§11: سجل التدقيق يغطي كل أنواع الحركات في الدورة'
);

select is_empty(
  $$ select 1 from public.audit_log where actor_id is null $$,
  'كل حركة في السجل منسوبة لمستخدم'
);

select * from finish();
rollback;
