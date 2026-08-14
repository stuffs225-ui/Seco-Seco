-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M6 — المصالحة والإغلاق وإعادة الفتح
--
-- §27 يجعل هذه اختبارات قبول:
--   «صفقة مدفوعة بالكامل و100g ما زالت مفتوحة ⇒ عدم السماح بالإغلاق»
--   «كل الوزن مسوى وباقي 500 ريال ⇒ عدم السماح بالإغلاق»
--   «إغلاق صفقة ثم محاولة تعديل دفعة قديمة ⇒ رفض وطلب Reverse/Reopen»
--   «مصالحة Deal ⇒ الفروقات غير المفسرة في الوزن والمال = صفر»
--
-- المرجع: §21، §24.6، §27، §28
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select has_table('public', 'deal_closing_snapshots', 'جدول لقطات الإغلاق موجود');
select has_table('public', 'deal_reopenings', 'سجل إعادة الفتح موجود');
select has_view('public', 'v_deal_reconciliation', 'جدول المصالحة كـ view');

-- ── التهيئة ────────────────────────────────────────────────────────────

insert into public.items (id, code, name)
values ('aaaa1111-0000-4000-8000-000000000001', 'ITM-S', 'صنف الإغلاق');
insert into public.distributors (id, code, name)
values ('bbbb1111-0000-4000-8000-000000000001', 'DST-S', 'موزع الإغلاق');
insert into public.cash_accounts (id, name)
values ('cccc1111-0000-4000-8000-000000000001', 'الصندوق');

select public.create_purchase_lot(
  'aaaa1111-0000-4000-8000-000000000001'::uuid,
  '2026-07-01'::date, 2000::weight_grams, 40000::money_amount
);

-- ═══════════════════════════════════════════════════════════════════════
-- §27 — الحالة الأولى: مدفوعة بالكامل ووزن مفتوح ⇒ لا إغلاق
-- ═══════════════════════════════════════════════════════════════════════

select public.open_deal(
  'bbbb1111-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  500::weight_grams, 12000::money_amount, '2026-07-05'::date
);

-- تصريف 400ج وسداد كامل القيمة، مع بقاء 100ج مفتوحة
select public.record_deal_sale(
  (select id from public.deals limit 1), 400::weight_grams);

select public.record_payment(
  'bbbb1111-0000-4000-8000-000000000001'::uuid,
  12000::money_amount, '2026-07-20'::date,
  'cash'::public.payment_method, 'PAY-FULL',
  'cccc1111-0000-4000-8000-000000000001'::uuid, '',
  'oldest_first');

select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'fully_paid',
  'الصفقة مسددة بالكامل'
);

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  100::weight_grams,
  'وما زال 100ج مفتوحاً لدى الموزع'
);

select is(
  (select can_close from public.v_deal_reconciliation limit 1),
  false,
  '§24.6: المصالحة تقول لا يمكن الإغلاق'
);

select throws_ok(
  $$ select public.close_deal((select id from public.deals limit 1)) $$,
  '23001',  -- restrict_violation
  null,
  '§27: صفقة مدفوعة بالكامل و100ج مفتوحة ⇒ الإغلاق مرفوض'
);

-- ── المصالحة بلا فروقات غير مفسرة (§24.6) ─────────────────────────────

select is(
  (select unexplained_weight from public.v_deal_reconciliation limit 1),
  0::weight_grams,
  '§24.6: الفرق الوزني غير المفسر = صفر'
);

select is(
  (select unexplained_money from public.v_deal_reconciliation limit 1),
  0::money_amount,
  '§24.6: الفرق المالي غير المفسر = صفر'
);

-- ── تسوية الوزن المتبقي تفتح الباب للإغلاق ────────────────────────────

select throws_ok(
  $$ select public.record_weight_adjustment(
       (select id from public.deals limit 1), 100::weight_grams, '') $$,
  '23514',  -- check_violation
  null,
  'تسوية الوزن بلا سبب موثق مرفوضة'
);

select lives_ok(
  $$ select public.record_weight_adjustment(
       (select id from public.deals limit 1), 100::weight_grams,
       'فرق ميزان موثق') $$,
  'تسوية وزن معتمدة بسبب موثق تنجح'
);

select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  0::weight_grams,
  'الوزن المفتوح صار صفراً بعد التسوية'
);

select is(
  (select can_close from public.v_deal_reconciliation limit 1),
  true,
  'الصفقة صارت جاهزة للإغلاق: الوزن والمال صفر بلا فروقات'
);

select lives_ok(
  $$ select public.close_deal((select id from public.deals limit 1)) $$,
  'الإغلاق ينجح بعد اكتمال المصالحة'
);

select is(
  (select status::text from public.deals limit 1),
  'closed',
  'حالة الصفقة صارت مغلقة'
);

-- ── لقطة الإغلاق (§21) ─────────────────────────────────────────────────

select is(
  (select count(*)::int from public.deal_closing_snapshots),
  1,
  '§21: الإغلاق أنشأ لقطة نهائية'
);

select is(
  (select version from public.deal_closing_snapshots limit 1),
  1,
  'اللقطة الأولى نسخة رقم 1'
);

select is(
  (select realized_profit from public.deal_closing_snapshots limit 1),
  (select realized_profit from public.v_deal_profit limit 1),
  'اللقطة حفظت الربح المحقق كما هو لحظة الإغلاق'
);

/*
  الحماية طبقتان مستقلتان:
    1. المنح: دور authenticated لا يملك UPDATE ولا DELETE على جداول
       الحركات إطلاقاً، فيُرفض قبل الوصول للتريجر (42501).
    2. التريجر: يرفض حتى لمن يملك المنح — مالك القاعدة مثلاً (23001).

  نختبر الاثنتين: الأولى بدور authenticated، والثانية بدور مرتفع.
*/

select throws_ok(
  $$ update public.deal_closing_snapshots set id = id $$,
  '42501',  -- insufficient_privilege
  null,
  'الطبقة الأولى: دور authenticated لا يملك أصلاً منح التعديل على لقطات الإغلاق'
);

reset role;

select throws_ok(
  $$ update public.deal_closing_snapshots set realized_profit = 0 $$,
  '23001',
  null,
  '§21: لقطة الإغلاق لا تُعدَّل بصمت'
);

-- ── §27: بعد الإغلاق لا تعديل مباشر ───────────────────────────────────

select throws_ok(
  $$ select public.record_deal_sale(
       (select id from public.deals limit 1), 10::weight_grams) $$,
  '23001',
  null,
  '§27: تسجيل حركة على صفقة مغلقة مرفوض'
);

select throws_ok(
  $$ select public.reverse_payment_allocation(
       (select id from public.payment_allocations limit 1), 'تصحيح') $$,
  '23001',
  null,
  '§27: عكس تخصيص على صفقة مغلقة مرفوض — يتطلب إعادة الفتح أولاً'
);

select throws_ok(
  $$ select public.close_deal((select id from public.deals limit 1)) $$,
  '23001',
  null,
  'إغلاق صفقة مغلقة أصلاً مرفوض'
);

-- ── إعادة الفتح (§21، §28) ─────────────────────────────────────────────

select throws_ok(
  $$ select public.reopen_deal((select id from public.deals limit 1), '') $$,
  '23514',
  null,
  'إعادة الفتح بلا سبب موثق مرفوضة'
);

select lives_ok(
  $$ select public.reopen_deal(
       (select id from public.deals limit 1), 'تصحيح خطأ في التصريف') $$,
  'إعادة الفتح بصلاحية المالك وسبب موثق تنجح'
);

select is(
  (select status::text from public.deals limit 1),
  'reopened',
  'حالة الصفقة صارت «أُعيد فتحها»'
);

select is(
  (select count(*)::int from public.deal_closing_snapshots),
  1,
  '§21: لقطة الإغلاق السابقة ما زالت محفوظة بعد إعادة الفتح'
);

select is(
  (select count(*)::int from public.deal_reopenings),
  1,
  'إعادة الفتح مسجَّلة بسببها ومستخدمها'
);

-- الإغلاق مرة أخرى ينتج نسخة ثانية لا يستبدل الأولى
select public.close_deal((select id from public.deals limit 1));

select is(
  (select count(*)::int from public.deal_closing_snapshots),
  2,
  '§21: الإغلاق الثاني أنشأ نسخة جديدة والقديمة باقية'
);

select is(
  (select max(version) from public.deal_closing_snapshots),
  2,
  'النسخة الثانية مرقَّمة 2'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §27 — الحالة الثانية: الوزن مسوّى بالكامل وباقٍ 500 ريال ⇒ لا إغلاق
-- ═══════════════════════════════════════════════════════════════════════

select public.open_deal(
  'bbbb1111-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  200::weight_grams, 5000::money_amount, '2026-08-01'::date
);

-- تصريف كامل الوزن، وسداد 4,500 من 5,000
select public.record_deal_sale(
  (select id from public.deals where delivery_date = '2026-08-01'),
  200::weight_grams);

select public.record_payment(
  'bbbb1111-0000-4000-8000-000000000001'::uuid,
  4500::money_amount, '2026-08-10'::date,
  'cash'::public.payment_method, 'PAY-PART', null, '',
  'specific',
  jsonb_build_array(jsonb_build_object(
    'deal_id', (select id from public.deals where delivery_date = '2026-08-01'),
    'amount', 4500)));

select is(
  (select open_weight_g from public.v_deal_quantity
   where deal_id = (select id from public.deals where delivery_date = '2026-08-01')),
  0::weight_grams,
  'الوزن مسوّى بالكامل'
);

select is(
  (select remaining_balance from public.v_deal_money
   where deal_id = (select id from public.deals where delivery_date = '2026-08-01')),
  500::money_amount,
  'وباقٍ 500 ريال على الموزع'
);

select throws_ok(
  $$ select public.close_deal(
       (select id from public.deals where delivery_date = '2026-08-01')) $$,
  '23001',
  null,
  '§27: كل الوزن مسوّى وباقٍ 500 ريال ⇒ الإغلاق مرفوض'
);

-- تسوية تجارية معتمدة تخفض المستحق فتكتمل المصالحة
select lives_ok(
  $$ select public.record_commercial_adjustment(
       (select id from public.deals where delivery_date = '2026-08-01'),
       (-500)::money_amount, 'خصم تجاري معتمد') $$,
  'تسوية تجارية معتمدة تنجح'
);

select is(
  (select remaining_balance from public.v_deal_money
   where deal_id = (select id from public.deals where delivery_date = '2026-08-01')),
  0::money_amount,
  'الرصيد صار صفراً بعد التسوية التجارية'
);

select lives_ok(
  $$ select public.close_deal(
       (select id from public.deals where delivery_date = '2026-08-01')) $$,
  'الإغلاق ينجح بعد التسوية'
);

-- ── الصلاحيات (§28) ────────────────────────────────────────────────────

reset role;
insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000e1', 'fin@test.local');
update public.profiles set role = 'finance'
where id = '00000000-0000-4000-8000-0000000000e1';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}';

select throws_ok(
  $$ select public.close_deal((select id from public.deals limit 1)) $$,
  '42501',  -- insufficient_privilege
  null,
  '§28: إغلاق الصفقة يحتاج مديراً مخوَّلاً لا مسؤولاً مالياً'
);

select throws_ok(
  $$ select public.reopen_deal((select id from public.deals limit 1), 'محاولة') $$,
  '42501',
  null,
  '§28: إعادة فتح صفقة مغلقة لمن يملك صلاحية خاصة فقط'
);

select throws_ok(
  $$ select public.record_weight_adjustment(
       (select id from public.deals limit 1), 1::weight_grams, 'محاولة') $$,
  '42501',
  null,
  '§28: تسوية الوزن تحتاج مديراً'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from public.audit_log
   where action in ('deal.closed', 'deal.reopened', 'deal.weight_adjusted',
                    'deal.commercial_adjusted')),
  6,
  'كل الإغلاقات وإعادات الفتح والتسويات مُقيَّدة في سجل التدقيق'
);

select * from finish();
rollback;
