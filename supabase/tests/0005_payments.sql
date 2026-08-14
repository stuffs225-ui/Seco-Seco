-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M5 — التحصيل والتخصيص والرصيد الدائن
--
-- §27 يجعل هذين السيناريوهين اختبارَي قبول:
--   «دفع موزع 8,000 ثم استرداد كمية تخفض الصفقة إلى 6,000 ⇒ إنشاء
--    Distributor Credit بقيمة 2,000 وعدم اعتباره ربحاً»
--   «دفعة عامة 10,000 لموزع لديه صفقتان ⇒ إمكانية توزيعها يدوياً أو
--    على الأقدم مع حفظ التخصيصات»
--
-- المرجع: §18.5، §24.4، §24.5، §27، §28
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select has_table('public', 'payments', 'جدول الدفعات موجود');
select has_table('public', 'payment_allocations', 'جدول التخصيصات موجود');
select has_table('public', 'credit_resolutions', 'جدول معالجة الأرصدة الدائنة موجود');
select has_view('public', 'v_distributor_credits', 'الأرصدة الدائنة كـ view مشتق');
select has_view('public', 'v_payment_status', 'حالة تخصيص الدفعة كـ view');

-- ── التهيئة ────────────────────────────────────────────────────────────

insert into public.items (id, code, name)
values ('11111111-aaaa-4000-8000-000000000001', 'ITM-P', 'صنف التحصيل');

insert into public.distributors (id, code, name)
values ('22222222-aaaa-4000-8000-000000000001', 'DST-P', 'موزع التحصيل');

insert into public.cash_accounts (id, name, kind)
values ('33333333-aaaa-4000-8000-000000000001', 'الصندوق', 'cash');

-- دفعة 1,000ج بـ20,000 ⇒ تكلفة الجرام 20.00
select public.create_purchase_lot(
  '11111111-aaaa-4000-8000-000000000001'::uuid,
  '2026-05-01'::date, 1000::weight_grams, 20000::money_amount
);

-- ═══════════════════════════════════════════════════════════════════════
-- §27 — السيناريو الأول: دفع 8,000 ثم استرداد يخفض الصفقة إلى 6,000
-- ═══════════════════════════════════════════════════════════════════════
--   تسليم 500ج بقيمة 12,000 (تكلفة 10,000، ربح متوقع 2,000)
--   دفع 8,000
--   استرداد 250ج ⇒ تخفيض 6,000 ⇒ القيمة المعدلة 6,000
--   ⇒ رصيد دائن للموزع 2,000

select public.open_deal(
  '22222222-aaaa-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  500::weight_grams, 12000::money_amount, '2026-05-05'::date
);

select lives_ok(
  $$ select public.record_payment(
       '22222222-aaaa-4000-8000-000000000001'::uuid,
       8000::money_amount,
       '2026-05-10'::date,
       'cash'::public.payment_method,
       'REC-001',
       '33333333-aaaa-4000-8000-000000000001'::uuid,
       '',
       'specific',
       jsonb_build_array(jsonb_build_object(
         'deal_id', (select id from public.deals limit 1),
         'amount', 8000))
     ) $$,
  'تسجيل دفعة 8,000 مخصصة للصفقة ينجح'
);

select is(
  (select total_paid from public.v_deal_money limit 1),
  8000::money_amount,
  'المسدد على الصفقة 8,000'
);

select is(
  (select remaining_balance from public.v_deal_money limit 1),
  4000::money_amount,
  'المتبقي = 12,000 - 8,000 = 4,000'
);

select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'partially_paid',
  'حالة السداد: مسددة جزئياً'
);

-- التحصيل لا يمس الوزن (§27: «تحصيل جزئي ⇒ يتغير الرصيد المالي دون
-- تغيير الوزن»)
select is(
  (select open_weight_g from public.v_deal_quantity limit 1),
  500::weight_grams,
  '§14: التحصيل الجزئي لا يغيّر الوزن'
);

-- النقد دخل الصندوق
select is(
  (select balance from public.v_cash_balance limit 1),
  8000::money_amount,
  'رصيد الصندوق 8,000 بعد التحصيل'
);

-- الآن الاسترداد الذي يخفض القيمة تحت المدفوع
select lives_ok(
  $$ select public.record_deal_return(
       (select id from public.deals limit 1),
       250::weight_grams, '2026-05-20'::date, 'إرجاع نصف الكمية') $$,
  'استرداد 250ج ينجح'
);

select is(
  (select adjusted_value from public.v_deal_money limit 1),
  6000::money_amount,
  '§27: القيمة المعدلة انخفضت إلى 6,000'
);

select is(
  (select remaining_balance from public.v_deal_money limit 1),
  (-2000)::money_amount,
  'الرصيد صار سالباً: 6,000 - 8,000 = -2,000'
);

select is(
  (select payment_status::text from public.v_deal_status limit 1),
  'credit_balance',
  '§24.5: الحالة «رصيد دائن» لا «مسددة بالكامل»'
);

-- ⚠️ جوهر §27: الفرق رصيد دائن للموزع، لا ربح للشركة
select is(
  (select unresolved_amount from public.v_distributor_credits limit 1),
  2000::money_amount,
  '§27: رصيد دائن للموزع 2,000'
);

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  0::money_amount,
  '§27: الرصيد الدائن لا يُسجَّل ربحاً — الربح المحقق ما زال صفراً'
);

-- ── معالجة الرصيد الدائن (§24.5) ───────────────────────────────────────

select throws_ok(
  $$ select public.resolve_distributor_credit(
       (select id from public.deals limit 1),
       'refund'::public.credit_resolution_method,
       5000::money_amount, 'رد') $$,
  '23514',  -- check_violation
  null,
  'معالجة مبلغ يتجاوز الرصيد الدائن مرفوضة'
);

select throws_ok(
  $$ select public.resolve_distributor_credit(
       (select id from public.deals limit 1),
       'refund'::public.credit_resolution_method,
       1000::money_amount, '') $$,
  '23514',
  null,
  'معالجة الرصيد الدائن بلا سبب موثق مرفوضة'
);

select lives_ok(
  $$ select public.resolve_distributor_credit(
       (select id from public.deals limit 1),
       'refund'::public.credit_resolution_method,
       2000::money_amount,
       'رد نقدي للموزع',
       null,
       '33333333-aaaa-4000-8000-000000000001'::uuid) $$,
  'رد الرصيد الدائن نقداً ينجح'
);

select is(
  (select remaining_balance from public.v_deal_money limit 1),
  0::money_amount,
  'بعد الرد: رصيد الصفقة صفر'
);

select is(
  (select balance from public.v_cash_balance limit 1),
  6000::money_amount,
  'الصندوق انخفض 2,000 بالرد الفعلي'
);

select is(
  (select realized_profit from public.v_deal_profit limit 1),
  0::money_amount,
  'الرد لم يُنشئ ربحاً — مال الموزع عاد لصاحبه'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §27 — السيناريو الثاني: دفعة عامة 10,000 على صفقتين
-- ═══════════════════════════════════════════════════════════════════════

insert into public.distributors (id, code, name)
values ('22222222-bbbb-4000-8000-000000000001', 'DST-Q', 'موزع الدفعة العامة');

-- صفقتان: الأقدم بـ4,000 والأحدث بـ9,000
select public.open_deal(
  '22222222-bbbb-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  100::weight_grams, 4000::money_amount, '2026-06-01'::date
);
select public.open_deal(
  '22222222-bbbb-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  200::weight_grams, 9000::money_amount, '2026-06-15'::date
);

select lives_ok(
  $$ select public.record_payment(
       '22222222-bbbb-4000-8000-000000000001'::uuid,
       10000::money_amount, '2026-06-20'::date,
       'transfer'::public.payment_method, 'TRF-9', null, '',
       'oldest_first') $$,
  '§24.4: تسجيل دفعة عامة 10,000 بتوزيع على الأقدم ينجح'
);

select is(
  (select m.total_paid from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.delivery_date = '2026-06-01'),
  4000::money_amount,
  'الأقدم استوفت كامل استحقاقها 4,000'
);

select is(
  (select m.total_paid from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.delivery_date = '2026-06-15'),
  6000::money_amount,
  'الباقي 6,000 ذهب للصفقة التالية'
);

select is(
  (select unallocated_amount from public.v_payment_status
   where reference = 'TRF-9'),
  0::money_amount,
  'الدفعة خُصِّصت بالكامل'
);

select is(
  (select count(*)::int from public.payment_allocations a
   join public.payments p on p.id = a.payment_id
   where p.reference = 'TRF-9'),
  2,
  '§24.4: التخصيصات محفوظة كسجلات مستقلة'
);

-- ── دفعة بلا تخصيص تبقى رصيداً مفتوحاً (§24.4) ────────────────────────

select public.record_payment(
  '22222222-bbbb-4000-8000-000000000001'::uuid,
  1500::money_amount, '2026-06-25'::date,
  'cash'::public.payment_method, 'UNALLOC-1', null, '', 'unallocated');

select is(
  (select unallocated_amount from public.v_payment_status
   where reference = 'UNALLOC-1'),
  1500::money_amount,
  '§24.4: الدفعة غير المخصصة تظهر كرصيد غير مخصص كامل'
);

-- ── §24.4: التخصيصات لا تتجاوز قيمة الدفعة ────────────────────────────

select throws_ok(
  $$ select public.allocate_payment(
       (select id from public.payments where reference = 'UNALLOC-1'),
       (select id from public.deals where delivery_date = '2026-06-15'),
       2000::money_amount) $$,
  '23514',
  null,
  '§24.4: تخصيص يتجاوز قيمة الدفعة مرفوض'
);

-- ── دفعة موزع لا تُخصَّص لصفقة موزع آخر ───────────────────────────────

select throws_ok(
  $$ select public.allocate_payment(
       (select id from public.payments where reference = 'UNALLOC-1'),
       (select id from public.deals where delivery_date = '2026-05-05'),
       100::money_amount) $$,
  '23514',
  null,
  'تخصيص دفعة موزع لصفقة موزع آخر مرفوض'
);

-- ── عكس التخصيص دون حذف أصل التحصيل (§24.4) ──────────────────────────

select throws_ok(
  $$ select public.reverse_payment_allocation(
       (select a.id from public.payment_allocations a
        join public.payments p on p.id = a.payment_id
        where p.reference = 'TRF-9' limit 1),
       '') $$,
  '23514',
  null,
  'عكس تخصيص بلا سبب موثق مرفوض'
);

select lives_ok(
  $$ select public.reverse_payment_allocation(
       (select a.id from public.payment_allocations a
        join public.payments p on p.id = a.payment_id
        join public.deals d on d.id = a.deal_id
        where p.reference = 'TRF-9' and d.delivery_date = '2026-06-01'),
       'خطأ في التخصيص') $$,
  'عكس التخصيص ينجح مع سبب موثق'
);

select is(
  (select m.total_paid from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.delivery_date = '2026-06-01'),
  0::money_amount,
  'الصفقة عادت غير مسددة بعد عكس التخصيص'
);

select is(
  (select count(*)::int from public.payments where reference = 'TRF-9'),
  1,
  '§24.4: أصل التحصيل باقٍ — العكس لم يحذف الدفعة'
);

select is(
  (select unallocated_amount from public.v_payment_status
   where reference = 'TRF-9'),
  4000::money_amount,
  'المبلغ المعكوس عاد رصيداً غير مخصص قابلاً لإعادة التخصيص'
);

select is(
  (select count(*)::int from public.deal_ledger
   where entry_type = 'PAYMENT_REVERSAL'),
  1,
  '§24.2: العكس حركة تُضاف لا تعديل لحركة سابقة'
);

-- ── الدفعات والتخصيصات لا تُحذف ───────────────────────────────────────

select throws_ok(
  $$ delete from public.payments $$,
  '23001',  -- restrict_violation
  null,
  'حذف دفعة مرفوض'
);

select throws_ok(
  $$ delete from public.payment_allocations $$,
  '23001',
  null,
  'حذف تخصيص مرفوض'
);

select throws_ok(
  $$ update public.payment_allocations set amount = 1 $$,
  '23001',
  null,
  'تعديل مبلغ تخصيص قائم مرفوض'
);

-- ── الصلاحيات (§28) ────────────────────────────────────────────────────

insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000d1', 'ops@test.local');
update public.profiles set role = 'operations'
where id = '00000000-0000-4000-8000-0000000000d1';

set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}';

select throws_ok(
  $$ select public.record_payment(
       '22222222-bbbb-4000-8000-000000000001'::uuid, 100::money_amount) $$,
  '42501',  -- insufficient_privilege
  null,
  '§28: العمليات لا تسجل تحصيلاً'
);

set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}';
insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000c1', 'coll3@test.local')
on conflict (id) do nothing;
update public.profiles set role = 'collections'
where id = '00000000-0000-4000-8000-0000000000c1';

select throws_ok(
  $$ select public.reverse_payment_allocation(
       (select id from public.payment_allocations
        where reversed_at is null limit 1),
       'محاولة') $$,
  '42501',
  null,
  '§28: عكس الدفعة يحتاج مشرفاً مالياً لا مسؤول تحصيل'
);

set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select * from finish();
rollback;
