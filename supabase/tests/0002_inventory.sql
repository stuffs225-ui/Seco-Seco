-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M2 — المخزون والدفعات وتكلفة الجرام
--
-- المرجع: §2 (المبادئ المحاسبية)، §3 (المثال الأساسي)، §14 (قواعد التحقق)،
--         §16.7 (رسملة المصاريف)، §26 (مصدر الحقيقة)
-- ═══════════════════════════════════════════════════════════════════════

begin;
-- عدد الاختبارات يُحصى آلياً؛ أي خطأ فادح يُجهض المعاملة ويُفشل الملف
select * from no_plan();

-- ننتحل هوية المالك المبذور حتى تمر فحوص assert_permission
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- ── البنية ─────────────────────────────────────────────────────────────

select has_table('public', 'items', 'جدول الأصناف موجود');
select has_table('public', 'lots', 'جدول الدفعات موجود');
select has_table('public', 'inventory_ledger', 'دفتر حركات المخزون موجود');
select has_view('public', 'v_lot_stock', 'رصيد المخزون كـ view لا كحقل مخزَّن');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.lots'::regclass),
  'RLS مفعّل على الدفعات'
);

-- ── المثال الأساسي من §3 و §14 ────────────────────────────────────────
--   شراء 1,200 جرام بقيمة 21,000 ريال ⇒ تكلفة الجرام 17.50

insert into public.items (id, code, name)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'ITM-001', 'صنف الاختبار');

select lives_ok(
  $$ select public.create_purchase_lot(
       'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
       '2026-01-15'::date,
       1200::weight_grams,
       21000::money_amount
     ) $$,
  'إنشاء دفعة شراء ينجح'
);

select is(
  (select cost_per_g from public.lots order by created_at desc limit 1),
  17.5::rate_per_gram,
  '§14: شراء 1,200ج بـ21,000 ⇒ تكلفة الجرام 17.50'
);

select is(
  (select total_cost from public.lots order by created_at desc limit 1),
  21000::money_amount,
  'التكلفة الإجمالية 21,000 بلا مصاريف مرسملة'
);

-- الكمية دخلت المخزون فعلاً، والرصيد مشتق من الـ ledger لا مخزَّن
select is(
  (select on_hand_weight_g from public.v_lot_stock
   where lot_id = (select id from public.lots order by created_at desc limit 1)),
  1200::weight_grams,
  'الوزن المتاح 1,200ج مشتقاً من دفتر الحركات'
);

select is(
  (select count(*)::int from public.inventory_ledger
   where entry_type = 'LOT_RECEIVED'),
  1,
  'الاستلام قُيِّد كحركة واحدة في دفتر المخزون'
);

-- تكلفة المخزون تُشتق من مجموع حركات التكلفة لا بالضرب (§26).
-- الضرب هنا كان يعطي 21,500.0004 لأن تكلفة الجرام كسر غير منتهٍ.
select is(
  (select on_hand_cost from public.v_lot_stock
   where lot_id = (select id from public.lots order by created_at desc limit 1)),
  21000::money_amount,
  'تكلفة المخزون المتاح تطابق تكلفة الدفعة تماماً بلا انحراف كسور'
);

-- ── ترقيم الدفعات ──────────────────────────────────────────────────────

select matches(
  (select lot_no from public.lots order by created_at desc limit 1),
  '^LOT-2026-[0-9]{4}$',
  'رقم الدفعة بالصيغة LOT-YYYY-NNNN'
);

-- ── رسملة المصاريف (§16.7 — القرار المعتمد) ───────────────────────────
--   نقل 800 يُرسمل، وضيافة 200 لا يُرسمل
--   ⇒ التكلفة = 10,000 + 800 = 10,800 على 500ج = 21.60 للجرام

select lives_ok(
  $$ select public.create_purchase_lot(
       'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
       '2026-02-01'::date,
       500::weight_grams,
       10000::money_amount,
       null, '', '',
       '[{"expense_type":"نقل","amount":800,"include_in_cost":true},
         {"expense_type":"ضيافة","amount":200,"include_in_cost":false}]'::jsonb
     ) $$,
  'إنشاء دفعة بمصاريف مختلطة ينجح'
);

select is(
  (select capitalized_expenses from public.lots where received_date = '2026-02-01'),
  800::money_amount,
  'المصروف المفعَّل وحده يُرسمل — 800 لا 1,000'
);

select is(
  (select cost_per_g from public.lots where received_date = '2026-02-01'),
  21.6::rate_per_gram,
  'تكلفة الجرام ترتفع بالمصروف المرسمل: (10,000+800)÷500 = 21.60'
);

select is(
  (select count(*)::int from public.purchase_expenses),
  2,
  'المصروف غير المرسمل يُحفظ أيضاً — يخصم من الربح لاحقاً لا من التكلفة'
);

-- الدفعة ذات تكلفة الجرام الكسرية: 10,800 ÷ 500 = 21.60 (منتهٍ هنا)،
-- لكن الاختبار يثبت أن المصدر هو مجموع الحركات في كل الحالات
select is(
  (select on_hand_cost from public.v_lot_stock
   where lot_id = (select id from public.lots where received_date = '2026-02-01')),
  10800::money_amount,
  'تكلفة المخزون تشمل المصاريف المرسملة وحدها'
);

-- ── دفتر المخزون غير قابل للتغيير (§26) ───────────────────────────────

/*
  الحماية طبقتان مستقلتان:
    1. المنح: دور authenticated لا يملك UPDATE ولا DELETE على جداول
       الحركات إطلاقاً، فيُرفض قبل الوصول للتريجر (42501).
    2. التريجر: يرفض حتى لمن يملك المنح — مالك القاعدة مثلاً (23001).

  نختبر الاثنتين: الأولى بدور authenticated، والثانية بدور مرتفع.
*/

select throws_ok(
  $$ update public.inventory_ledger set notes = 'x' $$,
  '42501',  -- insufficient_privilege
  null,
  'الطبقة الأولى: دور authenticated لا يملك أصلاً منح التعديل على دفتر المخزون'
);

reset role;

select throws_ok(
  $$ update public.inventory_ledger set weight_delta_g = 999 $$,
  '23001',  -- restrict_violation
  null,
  'تعديل حركة مخزون مرفوض — التصحيح بحركة عكسية'
);

select throws_ok(
  $$ delete from public.inventory_ledger $$,
  '23001',
  null,
  'حذف حركة مخزون مرفوض'
);

-- ── التحقق من المدخلات ─────────────────────────────────────────────────

select throws_ok(
  $$ select public.create_purchase_lot(
       'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
       '2026-01-01'::date, 0::weight_grams, 1000::money_amount) $$,
  '23514',  -- check_violation
  null,
  'وزن صفر مرفوض — لا تُقسم القيمة على صفر'
);

select throws_ok(
  $$ select public.create_purchase_lot(
       'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
       '2026-01-01'::date, 100::weight_grams, -5::money_amount) $$,
  '23514',
  null,
  'قيمة شراء سالبة مرفوضة'
);

select throws_ok(
  $$ select public.create_purchase_lot(
       '00000000-0000-4000-8000-999999999999'::uuid,
       '2026-01-01'::date, 100::weight_grams, 1000::money_amount) $$,
  '23503',  -- foreign_key_violation
  null,
  'صنف غير موجود مرفوض'
);

-- ── الصلاحيات (§28) ────────────────────────────────────────────────────

reset role;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a2', 'auditor@test.local');
-- التريجر أنشأ الملف بدور auditor

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}';

select throws_ok(
  $$ select public.create_purchase_lot(
       'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
       '2026-01-01'::date, 100::weight_grams, 1000::money_amount) $$,
  '42501',  -- insufficient_privilege
  null,
  'المدقق لا يستطيع إنشاء دفعة'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- ── سجل التدقيق (§11) ──────────────────────────────────────────────────

select is(
  (select count(*)::int from public.audit_log where action = 'lot.created'),
  2,
  'كل إنشاء دفعة يُقيَّد في سجل التدقيق'
);

select ok(
  (select (details ->> 'cost_per_g')::numeric = 17.5
   from public.audit_log
   where action = 'lot.created'
   order by occurred_at asc limit 1),
  'سجل التدقيق يحفظ تكلفة الجرام المحسوبة لحظة الإنشاء'
);

-- ── كل شراء ينشئ دفعة مستقلة (§2) ─────────────────────────────────────

select is(
  (select count(distinct cost_per_g)::int from public.lots
   where item_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  2,
  'نفس الصنف بدفعتين وتكلفتَي جرام مختلفتين — لا متوسط مرجّح (§2)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- تصحيح دفعة شراء (0018) — §26: لا تعديل مباشر، حركة عكسية فقط
-- ═══════════════════════════════════════════════════════════════════════

insert into public.items (id, code, name)
values ('bbbbbbbb-0000-4000-8000-000000000001', 'ITM-COR', 'صنف التصحيح');

-- ── تصحيح دفعة غير مُستهلَكة ينجح ──────────────────────────────────────

select public.create_purchase_lot(
  'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
  '2026-03-01'::date, 1000::weight_grams, 17500::money_amount
);

/*
  تاريخ الدفعة المصححة مختلف عمداً عن الأصلية (03-02 لا 03-01) — الملف
  كله معاملة pgTAP واحدة و`now()` مجمَّد طوالها، فالدفعتان تتشاركان
  created_at ولا يصح تمييزهما به. تاريخ استلام مختلف يجعل كل دفعة قابلة
  للتحديد بدقة بلا لبس، دون حاجة للاعتماد على ترتيب الإنشاء.
*/
select lives_ok(
  $$ select public.correct_purchase_lot(
       (select id from public.lots
        where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
          and received_date = '2026-03-01'),
       'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
       '2026-03-02'::date, 1000::weight_grams, 18000::money_amount,
       'خطأ إدخال: القيمة الصحيحة 18,000 لا 17,500'
     ) $$,
  'تصحيح دفعة غير مُستهلَكة ينجح'
);

select is(
  (select on_hand_weight_g from public.v_lot_stock
   where lot_id = (
     select id from public.lots
     where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
       and received_date = '2026-03-01'
   )),
  0::weight_grams,
  'الدفعة القديمة أُلغيت بالكامل — رصيدها صفر'
);

select is(
  (select cost_per_g from public.lots
   where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
     and received_date = '2026-03-02'),
  18::rate_per_gram,
  'الدفعة الجديدة بالقيمة المصححة: 18,000 ÷ 1,000 = 18.00'
);

select is(
  (select count(*)::int from public.inventory_ledger le
   join public.lots l on l.id = le.lot_id
   where l.item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
     and le.entry_type = 'ADJUSTMENT'),
  1,
  'حركة عكسية واحدة تُلغي الدفعة القديمة — لا UPDATE مباشر'
);

select is(
  (select count(*)::int from public.audit_log
   where action = 'lot.corrected'),
  1,
  'التصحيح يُقيَّد في سجل التدقيق'
);

select ok(
  (select (details ->> 'corrects_lot_id') is not null
   from public.audit_log where action = 'lot.corrected'),
  'سجل التدقيق يحفظ معرّف الدفعة الملغاة'
);

-- ── السبب إلزامي ───────────────────────────────────────────────────────
-- فحص السبب يقع قبل أي بحث عن الدفعة، فحالتها هنا (مُصحَّحة سلفاً) لا تؤثر

select throws_ok(
  $$ select public.correct_purchase_lot(
       (select id from public.lots
        where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
          and received_date = '2026-03-01'),
       'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
       '2026-03-01'::date, 1000::weight_grams, 18000::money_amount,
       ''
     ) $$,
  '23514',  -- check_violation
  null,
  'سبب فارغ مرفوض'
);

-- ── دفعة خرج منها وزن لا يمكن تصحيحها ──────────────────────────────────

insert into public.distributors (id, code, name)
values ('bbbbbbbb-0000-4000-8000-000000000002', 'DST-COR', 'موزع التصحيح');

select public.create_purchase_lot(
  'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
  '2026-03-05'::date, 800::weight_grams, 14000::money_amount
);

select public.open_deal(
  'bbbbbbbb-0000-4000-8000-000000000002'::uuid,
  (select id from public.lots
   where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
     and received_date = '2026-03-05'),
  300::weight_grams, 8000::money_amount, '2026-03-06'::date
);

select throws_ok(
  $$ select public.correct_purchase_lot(
       (select id from public.lots
        where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
          and received_date = '2026-03-05'),
       'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
       '2026-03-05'::date, 800::weight_grams, 15000::money_amount,
       'محاولة تصحيح دفعة مُستهلكة جزئياً'
     ) $$,
  '23514',
  null,
  'دفعة سُلِّم جزء منها لموزع لا يمكن تصحيحها'
);

-- ── الصلاحيات (§28) ────────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}';

select throws_ok(
  $$ select public.correct_purchase_lot(
       (select id from public.lots
        where item_id = 'bbbbbbbb-0000-4000-8000-000000000001'
          and received_date = '2026-03-01'),
       'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
       '2026-03-01'::date, 1000::weight_grams, 18000::money_amount,
       'المدقق يحاول التصحيح'
     ) $$,
  '42501',  -- insufficient_privilege
  null,
  'المدقق لا يستطيع تصحيح دفعة'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select * from finish();
rollback;
