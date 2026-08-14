-- ═══════════════════════════════════════════════════════════════════════
-- بيانات تجريبية — اختيارية
--
-- ⚠️ لا تُطبَّق تلقائياً مع `db reset`، وهذا مقصود: اختبارات pgTAP تعمل
-- على نفس القاعدة المحلية، وبيانات تجريبية مسبقة تجعلها تلتقط صفوفاً
-- ليست من تجهيزها فتصبح نتائجها غير موثوقة.
--
-- للتحميل:  npm run db:demo
-- ═══════════════════════════════════════════════════════════════════════

-- تُبنى بنداء نفس دوال RPC التي يستخدمها التطبيق، لا بإدخال مباشر في
-- الجداول. بذلك تبقى متسقة مع كل القيود، ويعمل السيناريو كاختبار دخان
-- لكل مسار في النظام.

do $$
declare
  v_lot_a  uuid;
  v_lot_b  uuid;
  v_deal_1 uuid;
  v_deal_2 uuid;
  v_deal_3 uuid;
begin
  -- ننتحل هوية المالك المبذور لتمر فحوص الصلاحيات في الدوال
  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
    true);

  insert into public.cash_accounts (id, name, kind) values
    ('00000000-0000-4000-8000-00000000000a', 'الصندوق النقدي', 'cash'),
    ('00000000-0000-4000-8000-00000000000b', 'الحساب البنكي', 'bank');

  insert into public.suppliers (id, name, phone) values
    ('00000000-0000-4000-8000-00000000001a', 'مورد الجنوب', '770000001');

  insert into public.items (id, code, name, description) values
    ('00000000-0000-4000-8000-00000000002a', 'ITM-001', 'صنف ممتاز', 'درجة أولى'),
    ('00000000-0000-4000-8000-00000000002b', 'ITM-002', 'صنف عادي', 'درجة ثانية');

  insert into public.distributors
    (id, code, name, phone, credit_limit_value) values
    ('00000000-0000-4000-8000-00000000003a', 'DST-001', 'أحمد الموزع', '770000010', 30000),
    ('00000000-0000-4000-8000-00000000003b', 'DST-002', 'سالم للتوزيع', '770000011', 15000),
    ('00000000-0000-4000-8000-00000000003c', 'DST-003', 'مؤسسة النور', '770000012', 0);

  -- ── دفعتان بتكلفتَي جرام مختلفتين لنفس النشاط (§2) ────────────────────

  -- 1,200ج بـ21,000 ⇒ 17.50 للجرام — مثال §3 الأساسي
  v_lot_a := public.create_purchase_lot(
    '00000000-0000-4000-8000-00000000002a'::uuid,
    current_date - 60, 1200, 21000,
    '00000000-0000-4000-8000-00000000001a'::uuid,
    'INV-1001', 'دفعة الافتتاح');

  -- 800ج بـ15,000 + نقل 600 مرسمل ⇒ 19.50 للجرام
  v_lot_b := public.create_purchase_lot(
    '00000000-0000-4000-8000-00000000002b'::uuid,
    current_date - 40, 800, 15000,
    '00000000-0000-4000-8000-00000000001a'::uuid,
    'INV-1002', '',
    '[{"expense_type":"نقل","amount":600,"include_in_cost":true},
      {"expense_type":"ضيافة","amount":150,"include_in_cost":false}]'::jsonb);

  -- ── صفقة جارية: صُرِّف بعضها وسُدِّد بعضها ────────────────────────────

  v_deal_1 := public.open_deal(
    '00000000-0000-4000-8000-00000000003a'::uuid, v_lot_a,
    500, 12000, current_date - 30, current_date + 5);

  perform public.record_deal_sale(v_deal_1, 300, current_date - 20);
  perform public.record_payment(
    '00000000-0000-4000-8000-00000000003a'::uuid, 5000, current_date - 15,
    'cash', 'REC-001', '00000000-0000-4000-8000-00000000000a'::uuid, '',
    'specific', jsonb_build_array(
      jsonb_build_object('deal_id', v_deal_1, 'amount', 5000)));

  -- ── صفقة فيها استرداد: تُظهر أثر §18.3 مباشرة في الواجهة ─────────────

  v_deal_2 := public.open_deal(
    '00000000-0000-4000-8000-00000000003b'::uuid, v_lot_b,
    300, 7500, current_date - 25, current_date - 2);

  perform public.record_deal_sale(v_deal_2, 100, current_date - 10);
  perform public.record_deal_return(
    v_deal_2, 50, current_date - 5, 'كمية غير مصرَّفة أعادها الموزع');

  -- ── صفقة مغلقة بالكامل: تُظهر اللقطة النهائية والتقارير ──────────────

  v_deal_3 := public.open_deal(
    '00000000-0000-4000-8000-00000000003c'::uuid, v_lot_a,
    200, 5000, current_date - 50, current_date - 20);

  perform public.record_deal_sale(v_deal_3, 200, current_date - 35);
  perform public.record_payment(
    '00000000-0000-4000-8000-00000000003c'::uuid, 5000, current_date - 30,
    'transfer', 'TRF-77', '00000000-0000-4000-8000-00000000000b'::uuid, '',
    'specific', jsonb_build_array(
      jsonb_build_object('deal_id', v_deal_3, 'amount', 5000)));

  perform public.close_deal(v_deal_3);

  -- ── دفعة غير مخصصة: تُظهر تنبيه §24.4 ────────────────────────────────

  perform public.record_payment(
    '00000000-0000-4000-8000-00000000003a'::uuid, 1200, current_date - 3,
    'cash', 'REC-002', '00000000-0000-4000-8000-00000000000a'::uuid,
    'دفعة على الحساب', 'unallocated');

  perform set_config('request.jwt.claims', '', true);
end
$$;
