-- ═══════════════════════════════════════════════════════════════════════
-- 0003 — إعدادات النظام
--
-- القرارات القابلة للتغيير من §16 وإضافة V5.7، مخزَّنة كإعدادات لا كثوابت
-- في الشيفرة — لأن تغيير أي منها قرار عمل، لا نشرة برمجية.
-- ═══════════════════════════════════════════════════════════════════════

create table public.app_settings (
  key         text        primary key,
  value       jsonb       not null,
  description text        not null default '',
  updated_by  uuid        references auth.users (id) on delete set null,
  updated_at  timestamptz not null default now(),
  constraint app_settings_key_not_blank check (btrim(key) <> '')
);

comment on table public.app_settings is
  'إعدادات النظام — القرارات المحاسبية والتشغيلية القابلة للتغيير (§16).';

alter table public.app_settings enable row level security;

-- ── قراءة إعداد ────────────────────────────────────────────────────────

create or replace function public.get_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select s.value from public.app_settings s where s.key = p_key;
$$;

comment on function public.get_setting is
  'قراءة إعداد. security definer لأن قواعد الأعمال تحتاجه بغض النظر عن دور المنفّذ.';

/*
  قراءة إعداد نصي مع رفض المفتاح المجهول.

  الصمت هنا خطر: إعداد ناقص يعني أن قاعدة عمل ستتصرف بقيمة افتراضية
  لم يقررها أحد. الاستثناء أفضل من حساب مالي بقيمة مفترضة.
*/
create or replace function public.get_setting_text(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_value jsonb;
begin
  v_value := public.get_setting(p_key);

  if v_value is null then
    raise exception 'الإعداد % غير معرَّف في النظام.', p_key
      using errcode = 'no_data_found';
  end if;

  return v_value #>> '{}';
end;
$$;

-- ── تدقيق تغييرات الإعدادات ────────────────────────────────────────────
-- تغيير إعداد يغيّر سلوك حسابات مالية، فيجب أن يبقى أثره واضحاً (§11).

create or replace function public.audit_setting_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();

  if new.value is distinct from old.value then
    perform public.write_audit(
      'setting.changed',
      'app_settings',
      new.key,
      jsonb_build_object('from', old.value, 'to', new.value)
    );
  end if;

  return new;
end;
$$;

create trigger app_settings_audit
  before update on public.app_settings
  for each row execute function public.audit_setting_change();

-- ── سياسات الوصول ──────────────────────────────────────────────────────

-- كل مستخدم مسجَّل يقرأ الإعدادات — الشاشات تحتاجها لتعرف كيف تتصرف
create policy app_settings_select
  on public.app_settings for select
  to authenticated
  using (auth.uid() is not null);

-- المالك وحده يغيّرها
create policy app_settings_update_owner
  on public.app_settings for update
  to authenticated
  using (public.current_role() = 'owner')
  with check (public.current_role() = 'owner');

-- لا insert ولا delete من العميل: مجموعة المفاتيح تُعرَّف في الترحيلات،
-- فلا يستطيع أحد إنشاء مفتاح لا تعرفه قواعد الأعمال أو حذف مفتاح تعتمد عليه.

-- ── القيم المعتمدة ─────────────────────────────────────────────────────

insert into public.app_settings (key, value, description) values

  -- §16.1 + §24.9 — القرار المعتمد: الربح يتحقق عند التصريف الفعلي.
  -- النقد المحصل يبقى مؤشراً مستقلاً تماماً ولا يخلط بالربح.
  ('profit_recognition', '"on_sale"'::jsonb,
   'متى يصبح الربح محققاً: on_sale عند تسجيل التصريف، on_collection عند التحصيل'),

  -- §16.7 — القرار المعتمد: كل مصروف يحمل مفتاحه الخاص، فالمصاريف
  -- المفعّلة ترفع تكلفة الجرام والباقي مصروف تشغيلي.
  ('expense_capitalization', '"per_expense_flag"'::jsonb,
   'رسملة مصاريف الشراء: per_expense_flag بمفتاح لكل مصروف، always دائماً، never أبداً'),

  -- إضافة V5.7 — القرار المعتمد: الاسترداد يُقيَّم تجارياً بسعر الجرام
  -- في الصفقة نفسها (مثال الخطة: 100ج × 24 = 2,400).
  ('return_commercial_valuation', '"deal_price_per_gram"'::jsonb,
   'تقييم الكمية المستردة تجاه الموزع: deal_price_per_gram أو manual_value'),

  -- §24.1 — القرار المعتمد: صفقة واحدة من دفعة واحدة. جدول deal_lines
  -- مبني للتوسع، والقيد يُرفع بتغيير هذا الإعداد وحده.
  ('deal_multi_lot', 'false'::jsonb,
   'هل يُسمح للصفقة بأسطر من أكثر من دفعة؟'),

  -- §V5.1 — التأكيد عند كل تصدير يقلل احتمال إرسال تقرير داخلي بالخطأ
  ('report_type_confirmation_required', 'true'::jsonb,
   'هل يؤكد المستخدم نوع التقرير عند كل تصدير حتى مع وجود افتراضي؟'),

  ('currency_label', '"ريال"'::jsonb,
   'رمز العملة المعروض في الشاشات والتقارير');
