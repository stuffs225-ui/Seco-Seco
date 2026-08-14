-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M4 — استرداد كمية من الموزع
--
-- §23 يجعل هذا السيناريو اختباراً إلزامياً بالنص:
--   «استخدم المثال 500 جرام: تكلفة 10,000 وقيمة صفقة 12,000 ثم استرداد
--    100 جرام كاختبار Unit/Integration إلزامي، وتحقق أن رأس المال يعود
--    2,000 وأن الربح المتوقع ينخفض 400 وأن المبلغ المسدد يبقى صفراً»
--
-- المرجع: §18.3، §18.4، §23، إضافة V5.5، V5.7
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select has_table('public', 'deal_returns', 'جدول الاستردادات موجود');

-- ── تهيئة مثال §18.3 بالضبط ───────────────────────────────────────────
--   دفعة 1,000ج بـ20,000 ⇒ تكلفة الجرام 20.00
--   تسليم 500ج ⇒ تكلفة الكمية 10,000
--   قيمة الصفقة 12,000 ⇒ قيمة الجرام 24.00، ربح الجرام المتوقع 4.00

insert into public.items (id, code, name)
values ('eeeeeeee-0000-4000-8000-000000000001', 'ITM-R', 'صنف الاسترداد');

insert into public.distributors (id, code, name)
values ('ffffffff-0000-4000-8000-000000000001', 'DST-R', 'موزع الاسترداد');

select public.create_purchase_lot(
  'eeeeeeee-0000-4000-8000-000000000001'::uuid,
  '2026-03-01'::date, 1000::weight_grams, 20000::money_amount
);

select public.open_deal(
  'ffffffff-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  500::weight_grams,
  12000::money_amount,
  '2026-03-05'::date
);

-- ── الحالة قبل الاسترداد (جدول §18.3) ─────────────────────────────────

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  500::weight_grams,
  'قبل الاسترداد: الوزن 500ج'
);

select is(
  (select open_capital_cost from public.v_deal_profit limit 1),
  10000::money_amount,
  'قبل الاسترداد: رأس المال المرتبط 10,000'
);

select is(
  (select adjusted_value from public.v_deal_money limit 1),
  12000::money_amount,
  'قبل الاسترداد: قيمة الصفقة المتوقعة 12,000'
);

select is(
  (select open_expected_profit from public.v_deal_profit limit 1),
  2000::money_amount,
  'قبل الاسترداد: الربح المتوقع 2,000'
);

select is(
  (select cost_per_g from public.deal_lines limit 1),
  20::rate_per_gram,
  'تكلفة الجرام 20.00'
);

select is(
  (select expected_profit_per_g from public.deal_lines limit 1),
  4::rate_per_gram,
  'الربح المتوقع للجرام 4.00'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §23 — الاختبار الإلزامي: استرداد 100 جرام
-- ═══════════════════════════════════════════════════════════════════════

select lives_ok(
  $$ select public.record_deal_return(
       (select id from public.deals limit 1),
       100::weight_grams,
       '2026-03-20'::date,
       'إرجاع كمية غير مصرَّفة'
     ) $$,
  'تسجيل استرداد 100ج ينجح'
);

select is(
  (select returned_cost from public.deal_returns limit 1),
  2000::money_amount,
  '§23: رأس المال الراجع = 100 × 20.00 = 2,000'
);

select is(
  (select cancelled_expected_profit from public.deal_returns limit 1),
  400::money_amount,
  '§23: الربح المتوقع الملغى = 100 × 4.00 = 400'
);

select is(
  (select deal_value_reduction from public.deal_returns limit 1),
  2400::money_amount,
  '§18.3: تخفيض قيمة الصفقة = 2,000 + 400 = 2,400'
);

-- ── الحالة بعد الاسترداد (جدول §18.3) ─────────────────────────────────

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  400::weight_grams,
  '§18.3: الوزن بعد الاسترداد = 400ج'
);

select is(
  (select open_capital_cost from public.v_deal_profit limit 1),
  8000::money_amount,
  '§18.3: رأس المال المرتبط بعد الاسترداد = 8,000'
);

select is(
  (select adjusted_value from public.v_deal_money limit 1),
  9600::money_amount,
  '§18.3: قيمة الصفقة المعدلة = 12,000 - 2,400 = 9,600'
);

select is(
  (select open_expected_profit from public.v_deal_profit limit 1),
  1600::money_amount,
  '§18.3: الربح المتوقع بعد الاسترداد = 1,600'
);

-- ⚠️ الشرط الأهم في §23: الاسترداد ليس تحصيلاً
select is(
  (select total_paid from public.v_deal_money limit 1),
  0::money_amount,
  '§23: المبلغ المسدد نقداً يبقى صفراً — الاسترداد ليس سداداً'
);

select is(
  (select remaining_balance from public.v_deal_money limit 1),
  9600::money_amount,
  'المتبقي على الموزع = القيمة المعدلة كاملة، فلم يسدد شيئاً'
);

-- ── §18.4: الكمية تعود لنفس الدفعة بتكلفتها الأصلية ───────────────────

select is(
  (select on_hand_weight_g from public.v_lot_stock limit 1),
  600::weight_grams,
  '§18.4: المخزون = 500 المتبقي + 100 المسترد = 600ج'
);

select is(
  (select on_hand_cost from public.v_lot_stock limit 1),
  12000::money_amount,
  'تكلفة المخزون = 10,000 المتبقي + 2,000 الراجع = 12,000'
);

select is(
  (select entry_type::text from public.inventory_ledger
   order by id desc limit 1),
  'RETURNED',
  'الاسترداد قُيِّد في دفتر المخزون كإرجاع لا كشراء جديد'
);

-- ── §18.4: الاسترداد لا يمس الربح المحقق ──────────────────────────────

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  0::money_amount,
  '§18.4: لا ربح محقق — لم يُسجَّل تصريف'
);

-- تصريف 200ج ثم استرداد آخر: الربح المحقق يبقى كما هو
select public.record_deal_sale(
  (select id from public.deals limit 1), 200::weight_grams);

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  800::money_amount,
  'تصريف 200ج ⇒ ربح محقق 800'
);

select public.record_deal_return(
  (select id from public.deals limit 1), 50::weight_grams, '2026-03-25'::date);

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  800::money_amount,
  '§18.4: الاسترداد الثاني لم يمس الربح المحقق من الكمية المباعة'
);

select is(
  (select count(*)::int from public.deal_returns),
  2,
  '§18.4: كل استرداد حركة مستقلة محفوظة'
);

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  150::weight_grams,
  'الوزن المفتوح = 500 - 100 مسترد - 200 مباع - 50 مسترد = 150ج'
);

-- ── §18.4: لا استرداد فوق الوزن غير المصرَّف ──────────────────────────

select throws_ok(
  $$ select public.record_deal_return(
       (select id from public.deals limit 1), 200::weight_grams) $$,
  '23514',  -- check_violation
  null,
  '§18.4: استرداد أكثر من الوزن غير المصرَّف مرفوض'
);

-- ── انعدام الانحراف عند استرداد كامل الوزن المفتوح ────────────────────

select lives_ok(
  $$ select public.record_deal_return(
       (select id from public.deals limit 1), 150::weight_grams) $$,
  'استرداد كامل الوزن المفتوح ينجح'
);

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  0::weight_grams,
  'الوزن المفتوح صار صفراً تاماً'
);

select is(
  (select open_capital_cost from public.v_deal_profit limit 1),
  0::money_amount,
  'رأس المال المفتوح صار صفراً تاماً — لا بقايا كسور'
);

select is(
  (select open_expected_profit from public.v_deal_profit limit 1),
  0::money_amount,
  'الربح المتوقع المفتوح صار صفراً تاماً'
);

select is(
  (select quantity_status::text from public.v_deal_status limit 1),
  'fully_settled',
  'حالة الوزن: مسوّى بالكامل'
);

-- الوزن مسوّى لكن المال لم يُسدَّد — الصفقة ليست جاهزة للإغلاق (§24.3)
select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'unpaid',
  'حالة السداد ما زالت غير مسددة — الفصل بين المحورين'
);

select is(
  (select is_reconciled from public.v_deal_status limit 1),
  false,
  '§24.3: وزن مسوّى بالكامل مع رصيد مالي ⇒ غير جاهزة للإغلاق'
);

-- ── الاسترداد لا يُعدَّل ولا يُحذف ────────────────────────────────────

/*
  الحماية طبقتان مستقلتان:
    1. المنح: دور authenticated لا يملك UPDATE ولا DELETE على جداول
       الحركات إطلاقاً، فيُرفض قبل الوصول للتريجر (42501).
    2. التريجر: يرفض حتى لمن يملك المنح — مالك القاعدة مثلاً (23001).

  نختبر الاثنتين: الأولى بدور authenticated، والثانية بدور مرتفع.
*/

select throws_ok(
  $$ update public.deal_returns set id = id $$,
  '42501',  -- insufficient_privilege
  null,
  'الطبقة الأولى: دور authenticated لا يملك أصلاً منح التعديل على الاستردادات'
);

reset role;

select throws_ok(
  $$ update public.deal_returns set returned_cost = 1 $$,
  '23001',  -- restrict_violation
  null,
  'تعديل حركة استرداد مرفوض'
);

-- ── معادلة §18.3 مفروضة على مستوى القاعدة ─────────────────────────────

select throws_ok(
  $$ insert into public.deal_returns
       (deal_id, deal_line_id, lot_id, return_date, returned_weight_g,
        returned_cost, cancelled_expected_profit, deal_value_reduction)
     values ((select id from public.deals limit 1),
             (select id from public.deal_lines limit 1),
             (select id from public.lots limit 1),
             '2026-04-01', 10, 200, 40, 999) $$,
  '23514',
  null,
  '§18.3: تخفيض قيمة لا يساوي التكلفة + الربح الملغى مرفوض'
);

-- ── الصلاحيات (§28: استرداد كمية = Operations مع توثيق) ───────────────

reset role;
insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000c1', 'collect2@test.local');
update public.profiles set role = 'collections'
where id = '00000000-0000-4000-8000-0000000000c1';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}';

select throws_ok(
  $$ select public.record_deal_return(
       (select id from public.deals limit 1), 10::weight_grams) $$,
  '42501',  -- insufficient_privilege
  null,
  '§28: مسؤول التحصيل لا يسجل استرداد كمية'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from public.audit_log
   where action = 'deal.return_recorded'),
  3,
  'كل استرداد مُقيَّد في سجل التدقيق'
);

select * from finish();
rollback;
