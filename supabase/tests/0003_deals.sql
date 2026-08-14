-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M3 — نواة الصفقة والـ Deal Ledger
--
-- المرجع: §3 (المثال الأساسي)، §14، §18.1، §24.1–24.3، §24.9، §26
-- ═══════════════════════════════════════════════════════════════════════

begin;
-- عدد الاختبارات يُحصى آلياً؛ أي خطأ فادح يُجهض المعاملة ويُفشل الملف
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- ── البنية ─────────────────────────────────────────────────────────────

select has_table('public', 'deals', 'جدول الصفقات موجود');
select has_table('public', 'deal_lines', 'جدول أسطر الصفقة موجود');
select has_table('public', 'deal_ledger', 'دفتر حركات الصفقة موجود');
select has_view('public', 'v_deal_quantity', 'أوزان الصفقة كـ view');
select has_view('public', 'v_deal_money', 'أموال الصفقة كـ view');
select has_view('public', 'v_deal_profit', 'أرباح الصفقة كـ view');
select has_view('public', 'v_deal_status', 'حالة الصفقة كـ view');

-- ── تهيئة المثال الأساسي (§3) ─────────────────────────────────────────
--   شراء 1,200ج بـ21,000 ⇒ تكلفة الجرام 17.50

insert into public.items (id, code, name)
values ('cccccccc-0000-4000-8000-000000000001', 'ITM-D', 'صنف الصفقات');

insert into public.distributors (id, code, name)
values ('dddddddd-0000-4000-8000-000000000001', 'DST-001', 'موزع الاختبار');

select public.create_purchase_lot(
  'cccccccc-0000-4000-8000-000000000001'::uuid,
  '2026-01-01'::date, 1200::weight_grams, 21000::money_amount
);

-- ── §14: تسليم 500ج بـ12,000 ⇒ ربح متوقع 3,250 ورصيد المخزون 700ج ────

select lives_ok(
  $$ select public.open_deal(
       'dddddddd-0000-4000-8000-000000000001'::uuid,
       (select id from public.lots limit 1),
       500::weight_grams,
       12000::money_amount,
       '2026-01-10'::date
     ) $$,
  'فتح صفقة بتسليم 500ج بقيمة 12,000 ينجح'
);

select is(
  (select open_expected_profit from public.v_deal_profit
   where deal_id = (select id from public.deals limit 1)),
  3250::money_amount,
  '§14: تكلفة 500ج = 8,750 وقيمة الصفقة 12,000 ⇒ ربح متوقع 3,250'
);

select is(
  (select original_capital_cost from public.v_deal_profit
   where deal_id = (select id from public.deals limit 1)),
  8750::money_amount,
  'رأس المال المرتبط بالكمية = 500 × 17.50 = 8,750'
);

select is(
  (select on_hand_weight_g from public.v_lot_stock),
  700::weight_grams,
  '§14: رصيد المخزون بعد التسليم = 1,200 - 500 = 700ج'
);

select is(
  (select on_hand_cost from public.v_lot_stock),
  12250::money_amount,
  'تكلفة المخزون المتبقي = 21,000 - 8,750 = 12,250'
);

-- الربح المتوقع للجرام (§3): 6.50
select is(
  (select expected_profit_per_g from public.deal_lines),
  6.5::rate_per_gram,
  '§3: الربح المتوقع لكل جرام = 24.00 - 17.50 = 6.50'
);

select is(
  (select deal_value_per_g from public.deal_lines),
  24::rate_per_gram,
  '§3: قيمة الجرام للموزع = 12,000 ÷ 500 = 24.00'
);

-- ── التسليم ليس تحصيلاً نقدياً (§2) ───────────────────────────────────

select is(
  (select total_paid from public.v_deal_money
   where deal_id = (select id from public.deals limit 1)),
  0::money_amount,
  '§2: تسليم الكمية لا يُسجَّل كتحصيل — المسدد صفر'
);

select is(
  (select remaining_balance from public.v_deal_money
   where deal_id = (select id from public.deals limit 1)),
  12000::money_amount,
  'الرصيد المتبقي على الموزع = كامل قيمة الصفقة'
);

-- ── ترقيم الصفقات (§18.1) ──────────────────────────────────────────────

select matches(
  (select deal_no from public.deals limit 1),
  '^DEAL-2026-[0-9]{4}$',
  'رقم الصفقة بالصيغة DEAL-YYYY-NNNN'
);

-- ── الحالتان منفصلتان (§24.3) ─────────────────────────────────────────

select is(
  (select quantity_status::text from public.v_deal_status limit 1),
  'open',
  'حالة الوزن: مفتوحة قبل أي تصريف'
);

select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'unpaid',
  'حالة السداد: غير مسددة — منفصلة عن حالة الوزن'
);

select is(
  (select is_reconciled from public.v_deal_status limit 1),
  false,
  'الصفقة غير جاهزة للإغلاق: وزن مفتوح ورصيد مالي معاً'
);

-- ── التصريف يحوّل الربح من متوقع إلى محقق (§16.1، §24.9) ──────────────

select lives_ok(
  $$ select public.record_deal_sale(
       (select id from public.deals limit 1), 200::weight_grams) $$,
  'تسجيل تصريف 200ج ينجح'
);

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  1300::money_amount,
  '§16.1: تصريف 200ج ⇒ ربح محقق = 200 × 6.50 = 1,300'
);

select is(
  (select open_expected_profit from public.v_deal_profit limit 1),
  1950::money_amount,
  'الربح المتوقع المفتوح ينخفض للمتبقي: 3,250 - 1,300 = 1,950'
);

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  300::weight_grams,
  'الوزن المفتوح = 500 - 200 = 300ج'
);

select is(
  (select cost_of_goods_sold from public.v_deal_profit limit 1),
  3500::money_amount,
  'تكلفة البضاعة المباعة = 200 × 17.50 = 3,500'
);

select is(
  (select open_capital_cost from public.v_deal_profit limit 1),
  5250::money_amount,
  'رأس المال المفتوح = 8,750 - 3,500 = 5,250'
);

-- التصريف لا يمس النقد إطلاقاً (§24.9)
select is(
  (select total_paid from public.v_deal_money limit 1),
  0::money_amount,
  '§24.9: التصريف لا يعني السداد — النقد المحصل مؤشر مستقل'
);

select is(
  (select quantity_status::text from public.v_deal_status limit 1),
  'partially_settled',
  'حالة الوزن صارت جزئية بعد التصريف'
);

select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'unpaid',
  'حالة السداد لم تتغير بالتصريف — الفصل بين المحورين'
);

-- ── قيود الحماية ───────────────────────────────────────────────────────

select throws_ok(
  $$ select public.record_deal_sale(
       (select id from public.deals limit 1), 400::weight_grams) $$,
  '23514',  -- check_violation
  null,
  'تصريف أكثر من الوزن المفتوح مرفوض'
);

select throws_ok(
  $$ select public.open_deal(
       'dddddddd-0000-4000-8000-000000000001'::uuid,
       (select id from public.lots limit 1),
       900::weight_grams, 20000::money_amount) $$,
  '23514',
  null,
  'تسليم أكثر من المتاح في الدفعة مرفوض'
);

/*
  الحماية طبقتان مستقلتان:
    1. المنح: دور authenticated لا يملك UPDATE ولا DELETE على جداول
       الحركات إطلاقاً، فيُرفض قبل الوصول للتريجر (42501).
    2. التريجر: يرفض حتى لمن يملك المنح — مالك القاعدة مثلاً (23001).

  نختبر الاثنتين: الأولى بدور authenticated، والثانية بدور مرتفع.
*/

select throws_ok(
  $$ update public.deal_ledger set reason = 'x' $$,
  '42501',  -- insufficient_privilege
  null,
  'الطبقة الأولى: دور authenticated لا يملك أصلاً منح التعديل على دفتر الصفقة'
);

reset role;

select throws_ok(
  $$ update public.deal_ledger set paid_delta = 99999 $$,
  '23001',  -- restrict_violation
  null,
  'تعديل دفتر الصفقة مرفوض — التصحيح بحركة عكسية (§24.2)'
);

select throws_ok(
  $$ delete from public.deal_ledger $$,
  '23001',
  null,
  'حذف حركة من دفتر الصفقة مرفوض'
);

-- ── معادلة §18.1: القيمة = رأس المال + الربح المتوقع ──────────────────

select throws_ok(
  $$ insert into public.deal_ledger
       (deal_id, entry_type, delivered_weight_g,
        commercial_value_delta, cost_delta, expected_profit_delta)
     values ((select id from public.deals limit 1), 'QTY_DELIVERED',
             100, 5000, 3000, 1000) $$,
  '23514',
  null,
  '§18.1: حركة تسليم قيمتها ≠ التكلفة + الربح المتوقع مرفوضة'
);

-- ── دفعة واحدة لكل صفقة (§24.1 — القرار المعتمد) ──────────────────────

select throws_ok(
  $$ insert into public.deal_lines
       (deal_id, lot_id, weight_g, cost_per_g, deal_value_per_g, expected_profit_per_g)
     values ((select id from public.deals limit 1),
             (select id from public.lots limit 1), 10, 17.5, 24, 6.5) $$,
  '23001',
  null,
  '§24.1: سطر ثانٍ في نفس الصفقة مرفوض ما دام deal_multi_lot معطلاً'
);

-- ── الصلاحيات (§28) ────────────────────────────────────────────────────

reset role;
insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000b1', 'collections@test.local');
update public.profiles set role = 'collections'
where id = '00000000-0000-4000-8000-0000000000b1';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}';

select throws_ok(
  $$ select public.open_deal(
       'dddddddd-0000-4000-8000-000000000001'::uuid,
       (select id from public.lots limit 1), 10::weight_grams, 300::money_amount) $$,
  '42501',  -- insufficient_privilege
  null,
  'مسؤول التحصيل لا يسلّم كميات — التسليم للعمليات (§28)'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- ── سجل التدقيق ────────────────────────────────────────────────────────

select is(
  (select count(*)::int from public.audit_log
   where action in ('deal.opened', 'deal.sale_recorded')),
  2,
  'فتح الصفقة والتصريف كلاهما مُقيَّد في سجل التدقيق'
);

select * from finish();
rollback;
