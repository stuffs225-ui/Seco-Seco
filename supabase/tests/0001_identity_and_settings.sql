-- ═══════════════════════════════════════════════════════════════════════
-- اختبارات المرحلة M1 — الهوية والصلاحيات والإعدادات
--
-- المرجع: §11 (الحوكمة)، §12 (الصلاحيات)، §16 (القرارات)، §28 (المصفوفة)
-- ═══════════════════════════════════════════════════════════════════════

begin;
-- عدد الاختبارات يُحصى آلياً؛ أي خطأ فادح يُجهض المعاملة ويُفشل الملف
select * from no_plan();

-- ── البنية الأساسية موجودة ─────────────────────────────────────────────

select has_table('public', 'profiles', 'جدول ملفات المستخدمين موجود');
select has_table('public', 'audit_log', 'سجل التدقيق موجود');
select has_table('public', 'app_settings', 'جدول الإعدادات موجود');

select has_function('public', 'assert_permission', array['text'],
  'حارس الصلاحية موجود');
select has_function('public', 'forbid_mutation', array[]::text[],
  'تريجر منع التعديل موجود');
select has_function('public', 'write_audit',
  array['text', 'text', 'text', 'jsonb'],
  'دالة كتابة التدقيق موجودة');

-- RLS مفعّل على كل جدول — بدونه أي مستخدم مسجَّل يقرأ كل شيء
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS مفعّل على profiles'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.audit_log'::regclass),
  'RLS مفعّل على audit_log'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.app_settings'::regclass),
  'RLS مفعّل على app_settings'
);

-- ── سجل التدقيق غير قابل للتغيير (§11) ────────────────────────────────

insert into public.audit_log (action, entity_type, entity_id, details)
values ('test.action', 'test', '1', '{}'::jsonb);

select throws_ok(
  $$ update public.audit_log set action = 'tampered' where entity_type = 'test' $$,
  '23001',  -- restrict_violation
  null,
  'تعديل سجل التدقيق مرفوض'
);

select throws_ok(
  $$ delete from public.audit_log where entity_type = 'test' $$,
  '23001',  -- restrict_violation
  null,
  'حذف سجل التدقيق مرفوض'
);

-- ── مصفوفة الصلاحيات (§28) ─────────────────────────────────────────────

-- المالك يملك كل شيء ضمناً
select ok(
  public.role_has_permission('owner', 'deals.close'),
  'المالك يملك إغلاق الصفقة'
);
select ok(
  public.role_has_permission('owner', 'أي.صلاحية.مهما.كانت'),
  'المالك يملك أي صلاحية دون تعدادها'
);

-- العمليات: المخزون والتسليم نعم، المال لا
select ok(
  public.role_has_permission('operations', 'purchases.manage'),
  'العمليات تدير المشتريات'
);
select ok(
  public.role_has_permission('operations', 'deals.return'),
  'العمليات تسجل استرداد الكمية'
);
select ok(
  not public.role_has_permission('operations', 'payments.reverse'),
  'العمليات لا تعكس دفعة — تحتاج مشرفاً مالياً'
);
select ok(
  not public.role_has_permission('operations', 'deals.close'),
  'العمليات لا تغلق صفقة — الإغلاق لمدير مخوَّل'
);

-- التحصيل: يسجل ويخصص، ولا يعكس ولا يرى التقارير الداخلية
select ok(
  public.role_has_permission('collections', 'payments.allocate'),
  'التحصيل يخصص الدفعات'
);
select ok(
  not public.role_has_permission('collections', 'payments.reverse'),
  'التحصيل لا يعكس دفعة'
);
select ok(
  not public.role_has_permission('collections', 'reports.internal'),
  'التحصيل لا يصل للتقارير الداخلية — لا يرى التكلفة والربح'
);
select ok(
  public.role_has_permission('collections', 'reports.distributor'),
  'التحصيل ينشئ تقرير الموزع'
);

-- المالي: يعكس ويعالج الأرصدة الدائنة
select ok(
  public.role_has_permission('finance', 'payments.reverse'),
  'المالي يعكس دفعة'
);
select ok(
  public.role_has_permission('finance', 'credits.resolve'),
  'المالي يعالج الرصيد الدائن'
);
select ok(
  not public.role_has_permission('finance', 'purchases.manage'),
  'المالي لا يدير المشتريات'
);

-- المدقق: قراءة فقط ولا يغيّر شيئاً
select ok(
  public.role_has_permission('auditor', 'reports.internal'),
  'المدقق يقرأ التقارير الداخلية'
);
select ok(
  not public.role_has_permission('auditor', 'purchases.manage'),
  'المدقق لا يدير المشتريات'
);
select ok(
  not public.role_has_permission('auditor', 'payments.record'),
  'المدقق لا يسجل تحصيلاً'
);

-- دور غير معرَّف لا يمنح شيئاً
select ok(
  not public.role_has_permission(null, 'reports.internal'),
  'غياب الدور يعني غياب الصلاحية'
);

-- ── الملف يُنشأ تلقائياً بأقل صلاحية ──────────────────────────────────

reset role;
insert into auth.users (id, email, raw_user_meta_data)
values (
  '11111111-1111-1111-1111-111111111111',
  'test@example.com',
  '{"full_name": "مستخدم اختبار"}'::jsonb
);

select is(
  (select role::text from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  'auditor',
  'المستخدم الجديد يبدأ بأقل صلاحية — الترقية قرار صريح'
);

select is(
  (select full_name from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  'مستخدم اختبار',
  'الاسم يُنقل من بيانات المستخدم'
);

-- ── القرارات المثبتة في الإعدادات (§16، V5.7) ─────────────────────────

select is(
  public.get_setting_text('profit_recognition'),
  'on_sale',
  'الربح يتحقق عند التصريف الفعلي (§16.1 + §24.9)'
);

select is(
  public.get_setting_text('expense_capitalization'),
  'per_expense_flag',
  'مصاريف الشراء ترسمل بمفتاح لكل مصروف (§16.7)'
);

select is(
  public.get_setting_text('return_commercial_valuation'),
  'deal_price_per_gram',
  'الاسترداد يُقيَّم بسعر الجرام في الصفقة (V5.7)'
);

select is(
  public.get_setting('deal_multi_lot'),
  'false'::jsonb,
  'الصفقة من دفعة واحدة (§24.1)'
);

-- إعداد مجهول يرفع استثناء بدل أن يعيد null بصمت — حساب مالي بقيمة
-- مفترضة أخطر من فشل صريح
select throws_ok(
  $$ select public.get_setting_text('مفتاح.غير.موجود') $$,
  'P0002',  -- no_data_found
  null,
  'الإعداد المجهول يرفع استثناء ولا يعيد قيمة افتراضية'
);

-- ── تغيير الإعداد يُقيَّد في سجل التدقيق (§11) ────────────────────────

update public.app_settings
set value = '"on_collection"'::jsonb
where key = 'profit_recognition';

select is(
  (select count(*)::int from public.audit_log
   where action = 'setting.changed' and entity_id = 'profit_recognition'),
  1,
  'تغيير إعداد محاسبي يُسجَّل في التدقيق'
);

-- ── تدقيق تغيير رمز الدخول (§11) ──────────────────────────────────────
-- بقية هذا الملف تعمل بصلاحيات كاملة لأنها تختبر دوالّ نقية وقيوداً.
-- هذا القسم يحتاج هوية فعلية: الدالة تنسب التغيير إلى auth.uid().

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';


select has_function('public', 'log_access_code_changed', array[]::text[],
  'دالة تقييد تغيير رمز الدخول موجودة');

select lives_ok(
  $$ select public.log_access_code_changed() $$,
  'تقييد تغيير الرمز ينجح للمستخدم المسجَّل'
);

select is(
  (select count(*)::int from public.audit_log
   where action = 'access_code.changed'),
  1,
  '§11: تغيير رمز الدخول مُقيَّد في سجل التدقيق'
);

-- الرمز نفسه لا يُسجَّل — لا القديم ولا الجديد
select is(
  (select details from public.audit_log
   where action = 'access_code.changed' limit 1),
  '{}'::jsonb,
  'السجل يثبت حدوث التغيير دون تسجيل الرمز نفسه'
);

select is(
  (select actor_id from public.audit_log
   where action = 'access_code.changed' limit 1),
  '00000000-0000-4000-8000-000000000001'::uuid,
  'التغيير منسوب لمن نفّذه'
);

select * from finish();
rollback;
