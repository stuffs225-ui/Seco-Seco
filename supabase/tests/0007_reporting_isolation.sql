-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M7 — عزل تقارير الموزع عن البيانات الداخلية
--
-- §V5.11 يجعل هذه اختبارات إلزامية:
--   «إنشاء تقرير موزع لصفقة رابحة والتأكد أن كلمات التكلفة والربح
--    والهامش ورأس المال لا تظهر في الملف أو بياناته المخفية»
--   «التأكد أن مستخدم بصلاحية Distributor Report فقط لا يستطيع الوصول
--    إلى API أو Endpoint خاص بالتقرير الداخلي»
--   «التأكد أن تغيير القالب لا يضيف الحقول الداخلية عن طريق الخطأ»
--
-- المرجع: إضافة V5 (البنود 3، 8، 10، 11، 12)
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select has_table('public', 'report_templates', 'جدول قوالب التقارير موجود');
select has_table('public', 'report_generation_log', 'سجل توليد التقارير موجود');
select has_view('public', 'v_deal_statement_internal', 'الكشف الداخلي موجود');
select has_function('public', 'get_distributor_statement', array['uuid'],
  'كشف الموزع كدالة بمصدر بيانات منفصل');

-- ═══════════════════════════════════════════════════════════════════════
-- §V5.11 — لا حقل سري في نوع كشف الموزع أصلاً
-- ═══════════════════════════════════════════════════════════════════════
/*
  هذا أقوى اختبار في الملف: يفحص تعريف النوع نفسه لا مخرجاته.

  حتى لو غُيِّر القالب أو أُعيدت كتابة الدالة، لا يمكن أن يحمل النوع
  حقل تكلفة أو ربح إلا بتعديل صريح لهذا التعريف — وعندها يفشل الاختبار.
  هذا هو الفرق بين المنع بالبناء والمنع بالإخفاء (§V5.8).
*/

select is_empty(
  $$ select a.attname
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     where c.relname = 'distributor_statement'
       and a.attnum > 0
       and (a.attname like '%cost%'
         or a.attname like '%profit%'
         or a.attname like '%margin%'
         or a.attname like '%capital%'
         or a.attname like '%partner%'
         or a.attname like '%per_g%') $$,
  '§V5.11: نوع كشف الموزع لا يحوي أي حقل تكلفة أو ربح أو هامش أو رأس مال'
);

select is_empty(
  $$ select a.attname
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     where c.relname = 'distributor_movement'
       and a.attnum > 0
       and (a.attname like '%cost%'
         or a.attname like '%profit%'
         or a.attname like '%margin%'
         or a.attname like '%capital%') $$,
  '§V5.11: نوع حركات الموزع خالٍ من الحقول السرية كذلك'
);

-- الكشف الداخلي بالمقابل يجب أن يحملها — وإلا فقدت الإدارة رؤيتها
select isnt_empty(
  $$ select column_name from information_schema.columns
     where table_name = 'v_deal_statement_internal'
       and column_name like '%profit%' $$,
  'الكشف الداخلي يحتوي الربحية — الفصل في اتجاه واحد فقط'
);

-- ── تهيئة صفقة رابحة ───────────────────────────────────────────────────

insert into public.items (id, code, name)
values ('dddd2222-0000-4000-8000-000000000001', 'ITM-RPT', 'صنف التقارير');
insert into public.distributors (id, code, name)
values ('eeee2222-0000-4000-8000-000000000001', 'DST-RPT', 'موزع التقارير');

select public.create_purchase_lot(
  'dddd2222-0000-4000-8000-000000000001'::uuid,
  '2026-09-01'::date, 1000::weight_grams, 20000::money_amount
);

select public.open_deal(
  'eeee2222-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  500::weight_grams, 15000::money_amount, '2026-09-05'::date
);

select public.record_deal_sale(
  (select id from public.deals limit 1), 300::weight_grams);
select public.record_deal_return(
  (select id from public.deals limit 1), 100::weight_grams, '2026-09-20'::date);
select public.record_payment(
  'eeee2222-0000-4000-8000-000000000001'::uuid,
  5000::money_amount, '2026-09-25'::date,
  'cash'::public.payment_method, 'PAY-RPT', null, '', 'oldest_first');

-- الصفقة رابحة فعلاً: تكلفة الجرام 20، قيمة الجرام 30، ربح الجرام 10
select is(
  (select realized_profit from public.v_deal_profit limit 1),
  3000::money_amount,
  'الصفقة رابحة: ربح محقق 3,000 من تصريف 300ج'
);

-- ── §V5.5: أثر الاسترداد كما يظهر لكل طرف ─────────────────────────────

select is(
  (select returned_capital_cost from public.v_deal_profit limit 1),
  2000::money_amount,
  'داخلياً: رأس المال المسترد 2,000 (100ج × 20)'
);

select is(
  (select cancelled_expected_profit from public.v_deal_profit limit 1),
  1000::money_amount,
  'داخلياً: الربح المتوقع الملغى 1,000 (100ج × 10)'
);

select is(
  ((select public.get_distributor_statement(
     (select id from public.deals limit 1))).value_reduction),
  3000::money_amount,
  '§V5.5: للموزع يظهر تخفيض تجاري 3,000 فقط — بلا تفصيل تكلفة أو ربح'
);

select is(
  ((select public.get_distributor_statement(
     (select id from public.deals limit 1))).adjusted_value),
  12000::money_amount,
  'القيمة التجارية المتبقية للموزع 12,000'
);

select is(
  ((select public.get_distributor_statement(
     (select id from public.deals limit 1))).remaining_balance),
  7000::money_amount,
  'المتبقي على الموزع = 12,000 - 5,000 = 7,000'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §V5.11 — مستخدم بصلاحية تقارير الموزع فقط لا يصل للبيانات الداخلية
-- ═══════════════════════════════════════════════════════════════════════

reset role;
insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000f1', 'dist-only@test.local');
update public.profiles set role = 'collections'
where id = '00000000-0000-4000-8000-0000000000f1';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

select ok(
  public.has_permission('reports.distributor'),
  'مسؤول التحصيل يملك صلاحية تقرير الموزع'
);

select ok(
  not public.has_permission('reports.internal'),
  'ولا يملك صلاحية التقارير الداخلية'
);

-- يستطيع توليد كشف الموزع
select lives_ok(
  $$ select public.get_distributor_statement(
       (select deal_id from public.v_deal_status limit 1)) $$,
  'يستطيع توليد كشف الموزع'
);

-- ولا يصل إلى أي مصدر داخلي
select is_empty(
  $$ select 1 from public.deal_ledger $$,
  '§V5.11: لا يرى دفتر الصفقة الذي يحمل التكلفة والربح'
);

select is_empty(
  $$ select 1 from public.deal_lines $$,
  '§V5.11: لا يرى أسطر الصفقة التي تحمل تكلفة الجرام'
);

select is_empty(
  $$ select 1 from public.lots $$,
  '§V5.11: لا يرى الدفعات التي تحمل تكلفة الشراء'
);

select is_empty(
  $$ select 1 from public.v_deal_profit $$,
  '§V5.11: لا يرى ربحية الصفقة'
);

select is_empty(
  $$ select 1 from public.v_deal_statement_internal $$,
  '§V5.11: لا يرى الكشف الداخلي'
);

select is_empty(
  $$ select 1 from public.purchases $$,
  '§V5.11: لا يرى المشتريات'
);

-- ويستطيع مع ذلك رؤية ما يخص عمله: حالة الصفقة التجارية
select isnt_empty(
  $$ select 1 from public.v_deal_status $$,
  'لكنه يرى الحالة التجارية للصفقة — عمله يتطلبها'
);

-- ── §V5.8: الصلاحية تتبع جمهور القالب لا اختيار المستخدم ──────────────

select throws_ok(
  $$ select public.log_report_generation(
       'DEAL_STATEMENT_INTERNAL', 'deal',
       (select deal_id::text from public.v_deal_status limit 1)) $$,
  '42501',  -- insufficient_privilege
  null,
  '§V5.11: لا يستطيع توليد تقرير داخلي حتى لو طلب قالبه صراحةً'
);

select lives_ok(
  $$ select public.log_report_generation(
       'DEAL_STATEMENT_DISTRIBUTOR', 'deal',
       (select deal_id::text from public.v_deal_status limit 1)) $$,
  'ويستطيع توليد تقرير الموزع'
);

-- ── العودة للمالك ──────────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select isnt_empty(
  $$ select 1 from public.v_deal_statement_internal $$,
  'المالك يرى الكشف الداخلي كاملاً'
);

select is(
  (select audience::text from public.report_generation_log limit 1),
  'DISTRIBUTOR',
  '§V5.8: سجل التوليد يحفظ جمهور التقرير'
);

select is(
  (select generated_by from public.report_generation_log limit 1),
  '00000000-0000-4000-8000-0000000000f1'::uuid,
  'ومن أنشأه'
);

-- ── قالب مجهول مرفوض ───────────────────────────────────────────────────

select throws_ok(
  $$ select public.log_report_generation('QALEB_MAJHOOL', 'deal', 'x') $$,
  'P0002',  -- no_data_found
  null,
  'قالب غير معرَّف مرفوض — لا جمهور مجهول'
);

-- ── حركات الموزع لا تكشف التصريف ولا التكلفة (§V5.2، §V5.3) ──────────

select is_empty(
  $$ select 1 from public.get_distributor_movements(
       (select id from public.deals limit 1))
     where kind = 'تصريف' $$,
  '§V5.2: التصريف شأن داخلي لا يظهر في كشف الموزع'
);

select isnt_empty(
  $$ select 1 from public.get_distributor_movements(
       (select id from public.deals limit 1))
     where kind = 'استرداد كمية' $$,
  '§V5.2: الاسترداد يظهر للموزع كحركة كمية'
);

select isnt_empty(
  $$ select 1 from public.get_distributor_movements(
       (select id from public.deals limit 1))
     where kind = 'دفعة مسددة' $$,
  '§V5.2: دفعاته تظهر في كشفه'
);

select * from finish();
rollback;
