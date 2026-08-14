-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M8 — لوحة السيولة والتنبيهات
--
-- §27: «Dashboard مقابل Deal Statement ⇒ الأرقام متطابقة من نفس مصدر
--       الحساب»
-- §24.10: «يجب ألا يُستخدم Expected Profit في احتساب النقد المتاح»
--
-- المرجع: §24.10، §24.11، §27
-- ═══════════════════════════════════════════════════════════════════════

begin;
select * from no_plan();

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select has_view('public', 'v_cash_position', 'لوحة السيولة موجودة');
select has_view('public', 'v_alerts', 'التنبيهات كـ view مشتق لا جدول');

-- ── التهيئة ────────────────────────────────────────────────────────────

insert into public.items (id, code, name)
values ('aaaa3333-0000-4000-8000-000000000001', 'ITM-DSH', 'صنف اللوحة');
insert into public.distributors (id, code, name, credit_limit_value)
values ('bbbb3333-0000-4000-8000-000000000001', 'DST-DSH', 'موزع اللوحة', 5000);
insert into public.cash_accounts (id, name)
values ('cccc3333-0000-4000-8000-000000000001', 'الصندوق');

-- دفعة 1,000ج بـ20,000 ⇒ تكلفة الجرام 20
select public.create_purchase_lot(
  'aaaa3333-0000-4000-8000-000000000001'::uuid,
  '2026-10-01'::date, 1000::weight_grams, 20000::money_amount
);

select is(
  (select inventory_at_warehouse from public.v_cash_position),
  20000::money_amount,
  'المخزون في المخزن بالتكلفة 20,000'
);

select is(
  (select cash_available from public.v_cash_position),
  0::money_amount,
  'لا نقد بعد — الشراء لم يُسجَّل كحركة صندوق في هذه المرحلة'
);

-- تسليم 400ج بقيمة 12,000 (تكلفة 8,000، ربح متوقع 4,000)
select public.open_deal(
  'bbbb3333-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  400::weight_grams, 12000::money_amount, '2026-10-05'::date
);

-- ── §24.10: المخزون في المخزن ولدى الموزعين منفصلان ───────────────────

select is(
  (select inventory_at_warehouse from public.v_cash_position),
  12000::money_amount,
  '§24.10: المخزون في المخزن انخفض إلى 12,000 (600ج × 20)'
);

select is(
  (select inventory_at_distributors from public.v_cash_position),
  8000::money_amount,
  '§24.10: المخزون لدى الموزعين 8,000 — معروض منفصلاً'
);

select is(
  (select distributor_receivables from public.v_cash_position),
  12000::money_amount,
  'ذمم الموزعين 12,000'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §24.10 — الربح المتوقع لا يدخل في النقد ولا في الأصول
-- ═══════════════════════════════════════════════════════════════════════

select is(
  (select open_expected_profit from public.v_cash_position),
  4000::money_amount,
  'الربح المتوقع المفتوح 4,000 معروض في عمود مستقل'
);

select is(
  (select cash_available from public.v_cash_position),
  0::money_amount,
  '§24.10: النقد المتاح صفر رغم وجود ربح متوقع 4,000'
);

select is(
  (select realized_profit from public.v_cash_position),
  0::money_amount,
  'الربح المحقق صفر — لم يُسجَّل تصريف بعد'
);

-- تصريف يحوّل الربح إلى محقق دون أن يخلق سيولة
select public.record_deal_sale(
  (select id from public.deals limit 1), 200::weight_grams);

select is(
  (select realized_profit from public.v_cash_position),
  2000::money_amount,
  'الربح المحقق 2,000 بعد تصريف 200ج'
);

select is(
  (select cash_available from public.v_cash_position),
  0::money_amount,
  '§24.10: ربح محقق 2,000 والنقد ما زال صفراً — الفصل الذي تطلبه الخطة'
);

-- التحصيل وحده هو ما يخلق سيولة
select public.record_payment(
  'bbbb3333-0000-4000-8000-000000000001'::uuid,
  7000::money_amount, '2026-10-20'::date,
  'cash'::public.payment_method, 'PAY-DSH',
  'cccc3333-0000-4000-8000-000000000001'::uuid, '', 'oldest_first');

select is(
  (select cash_available from public.v_cash_position),
  7000::money_amount,
  'النقد المتاح 7,000 بعد التحصيل الفعلي'
);

select is(
  (select distributor_receivables from public.v_cash_position),
  5000::money_amount,
  'الذمم انخفضت إلى 5,000'
);

-- ═══════════════════════════════════════════════════════════════════════
-- §27 — أرقام اللوحة تطابق كشف الصفقة من نفس المصدر
-- ═══════════════════════════════════════════════════════════════════════

select is(
  (select distributor_receivables from public.v_cash_position),
  (select sum(greatest(remaining_balance, 0))::money_amount from public.v_deal_money m
   join public.deals d on d.id = m.deal_id
   where d.status not in ('closed', 'cancelled')),
  '§27: ذمم اللوحة = مجموع أرصدة الصفقات من نفس المصدر'
);

select is(
  (select realized_profit from public.v_cash_position),
  (select sum(realized_profit)::money_amount from public.v_deal_profit),
  '§27: ربح اللوحة = مجموع أرباح الصفقات من نفس المصدر'
);

select is(
  (select inventory_at_distributors from public.v_cash_position),
  (select sum(p.open_capital_cost)::money_amount from public.v_deal_profit p
   join public.deals d on d.id = p.deal_id
   where d.status not in ('closed', 'cancelled')),
  '§27: مخزون الموزعين في اللوحة = رأس المال المفتوح في الصفقات'
);

-- ── التنبيهات (§24.11) ─────────────────────────────────────────────────

-- الموزع تجاوز حد الائتمان 5,000؟ ذمته الآن 5,000 بالضبط — لا تجاوز
select is_empty(
  $$ select 1 from public.v_alerts where code = 'distributor.over_credit_limit' $$,
  'لا تنبيه تجاوز ائتمان عند بلوغ الحد تماماً'
);

-- صفقة ثانية ترفع الذمة فوق الحد
select public.open_deal(
  'bbbb3333-0000-4000-8000-000000000001'::uuid,
  (select id from public.lots limit 1),
  100::weight_grams, 3000::money_amount, '2026-10-25'::date);

select isnt_empty(
  $$ select 1 from public.v_alerts where code = 'distributor.over_credit_limit' $$,
  '§24.11: تنبيه عند تجاوز الموزع حد الائتمان'
);

-- وزن مسوّى بالكامل مع رصيد مالي
select public.record_deal_sale(
  (select id from public.deals where delivery_date = '2026-10-25'),
  100::weight_grams);

select isnt_empty(
  $$ select 1 from public.v_alerts
     where code = 'deal.stock_settled_payment_pending' $$,
  '§24.11: تنبيه عند تسوية الوزن بالكامل مع بقاء رصيد مالي'
);

-- رصيد دائن غير معالج
select public.record_payment(
  'bbbb3333-0000-4000-8000-000000000001'::uuid,
  4000::money_amount, '2026-10-26'::date,
  'cash'::public.payment_method, 'PAY-OVER', null, '',
  'specific',
  jsonb_build_array(jsonb_build_object(
    'deal_id', (select id from public.deals where delivery_date = '2026-10-25'),
    'amount', 4000)));

select isnt_empty(
  $$ select 1 from public.v_alerts where code = 'distributor.unresolved_credit' $$,
  '§24.11: تنبيه عند وجود رصيد دائن غير معالج'
);

select is(
  (select severity::text from public.v_alerts
   where code = 'distributor.unresolved_credit' limit 1),
  'critical',
  'الرصيد الدائن غير المعالج تنبيه حرج — مال موزع لدى الشركة'
);

-- الرصيد الدائن يظهر كالتزام في لوحة السيولة (§24.10)
select is(
  (select distributor_credits from public.v_cash_position),
  1000::money_amount,
  '§24.10: الرصيد الدائن للموزع 1,000 يظهر كالتزام'
);

-- ── لا فروقات مصالحة في أي صفقة ───────────────────────────────────────

select is_empty(
  $$ select 1 from public.v_alerts where code = 'deal.reconciliation_gap' $$,
  '§24.6: لا فروقات مصالحة غير مفسرة في أي صفقة'
);

-- ── دفعة غير مخصصة ─────────────────────────────────────────────────────

select public.record_payment(
  'bbbb3333-0000-4000-8000-000000000001'::uuid,
  500::money_amount, '2026-10-27'::date,
  'cash'::public.payment_method, 'PAY-UNALLOC', null, '', 'unallocated');

select isnt_empty(
  $$ select 1 from public.v_alerts where code = 'payment.unallocated' $$,
  '§24.4: تنبيه على دفعة غير مخصصة'
);

-- ── التنبيهات مشتقة: معالجة الحالة تُخفي التنبيه وحدها ────────────────

select public.resolve_distributor_credit(
  (select id from public.deals where delivery_date = '2026-10-25'),
  'refund'::public.credit_resolution_method,
  1000::money_amount, 'رد للموزع', null,
  'cccc3333-0000-4000-8000-000000000001'::uuid);

select is_empty(
  $$ select 1 from public.v_alerts where code = 'distributor.unresolved_credit' $$,
  'التنبيه اختفى وحده بعد معالجة الرصيد — لا حاجة لتحديث يدوي'
);

select * from finish();
rollback;
