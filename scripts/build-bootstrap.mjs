#!/usr/bin/env node
/**
 * يولّد `docs/bootstrap.sql` — ملف واحد يبني القاعدة كاملة وينشئ المالك.
 *
 * الغرض: تهيئة مشروع Supabase جديد بلصق واحد في SQL Editor، دون CLI ولا
 * أسرار GitHub. مفيد بوجه خاص من الجوال.
 *
 * ⚠️ ملف مولَّد لا يُحرَّر يدوياً. مصدر الحقيقة يبقى `supabase/migrations/`،
 * وأي تحرير مباشر هنا يضيع عند التوليد التالي. `npm run bootstrap:check`
 * يتحقق في CI أنه مطابق للترحيلات، فلا يتحول إلى وثيقة كاذبة.
 */
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDir = join(root, "supabase", "migrations");
const outputPath = join(root, "docs", "bootstrap.sql");

const files = readdirSync(migrationsDir)
  .filter((name) => name.endsWith(".sql"))
  .sort();

const header = `-- ═══════════════════════════════════════════════════════════════════════
-- سيكو سيكو — تهيئة قاعدة البيانات بلصق واحد
--
-- ⚠️ ملف مولَّد آلياً من supabase/migrations — لا تحرره.
--    لإعادة توليده: npm run bootstrap:build
--
-- الاستخدام:
--   1. عدّل السطور المعلَّمة ✏️ أدناه
--   2. الصق الملف كاملاً في Supabase → SQL Editor
--   3. اضغط Run
--
-- الملف كله معاملة واحدة: إن فشل أي سطر لا يُطبَّق شيء إطلاقاً، فتصحّح
-- وتعيد التشغيل بأمان. وهو مخصص لمشروع جديد فارغ — بعد أول نجاح تُطبَّق
-- الترحيلات اللاحقة عبر workflow أو \`npm run db:push\`.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  ✏️  عدّل هذه السطور قبل التشغيل                                    │
-- └─────────────────────────────────────────────────────────────────────┘

create schema seco_bootstrap;

create table seco_bootstrap.config (
  owner_email text not null,
  owner_code  text not null,
  owner_name  text not null
);

insert into seco_bootstrap.config (owner_email, owner_code, owner_name) values (
  'owner@example.com',   -- ✏️ بريدك الذي ستنشئ به الحساب
  'Aa123123',            -- ✏️ رمز الدخول (8 خانات على الأقل)
  'المالك'               -- ✏️ اسمك كما يظهر في النظام
);

/*
  التحقق يقع هنا قبل أي إنشاء.

  لو تُرك في نهاية الملف لكانت الترحيلات قد طُبِّقت بالفعل عند اكتشاف
  الخطأ، فتفشل إعادة التشغيل على «الجدول موجود». الفحص المبكر مع
  المعاملة الواحدة يجعل الملف قابلاً لإعادة التشغيل فعلاً لا ادعاءً.
*/
do $seco_check$
declare
  v_cfg record;
begin
  select * into v_cfg from seco_bootstrap.config limit 1;

  if v_cfg.owner_email = 'owner@example.com' then
    raise exception
      'لم تُعدّل البريد في أعلى الملف. غيّر owner@example.com إلى بريدك ثم أعد التشغيل. لم يُطبَّق أي تغيير.';
  end if;

  if position('@' in v_cfg.owner_email) = 0 then
    raise exception 'البريد % ليس بصيغة صحيحة.', v_cfg.owner_email;
  end if;

  if length(v_cfg.owner_code) < 8 then
    raise exception 'رمز الدخول يجب أن يكون 8 خانات على الأقل.';
  end if;
end
$seco_check$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) بنية قاعدة البيانات — الترحيلات بترتيبها
-- ═══════════════════════════════════════════════════════════════════════
`;

const migrations = files
  .map((name) => {
    const sql = readFileSync(join(migrationsDir, name), "utf8").trimEnd();
    return `\n\n-- ─── ${name} ${"─".repeat(Math.max(0, 56 - name.length))}\n\n${sql}`;
  })
  .join("\n");

/*
  إنشاء المالك.

  يُكتب مباشرةً في auth.users لأن SQL Editor لا يستطيع نداء واجهة الإدارة.
  هذه هي الطريقة نفسها التي يستخدمها seed.sql محلياً، وهي تعمل لأن gotrue
  يقرأ bcrypt من encrypted_password ويطابق سجل الهوية في auth.identities.

  التنفيذ متسامح مع التكرار: لو كان الحساب موجوداً يُحدَّث رمزه ودوره
  بدل أن يفشل الملف كله.
*/
const owner = `

-- ═══════════════════════════════════════════════════════════════════════
-- 2) حساب المالك ورمز الدخول
-- ═══════════════════════════════════════════════════════════════════════

do $seco_owner$
declare
  v_cfg    record;
  v_id     uuid;
begin
  select * into v_cfg from seco_bootstrap.config limit 1;

  select id into v_id from auth.users where email = v_cfg.owner_email;

  if v_id is null then
    v_id := gen_random_uuid();

    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    )
    values (
      v_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_cfg.owner_email,
      crypt(v_cfg.owner_code, gen_salt('bf')),
      now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      jsonb_build_object('full_name', v_cfg.owner_name),
      now(),
      now()
    );

    -- gotrue يتطلب سجل هوية مطابقاً وإلا رفض تسجيل الدخول بالبريد
    insert into auth.identities (
      provider_id, user_id, identity_data, provider, created_at, updated_at
    )
    values (
      v_id::text,
      v_id,
      jsonb_build_object(
        'sub', v_id::text,
        'email', v_cfg.owner_email,
        'email_verified', true,
        'phone_verified', false
      ),
      'email',
      now(),
      now()
    );
  else
    -- الحساب موجود مسبقاً في auth: نحدّث رمزه بدل أن نفشل
    update auth.users
    set encrypted_password = crypt(v_cfg.owner_code, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_id;
  end if;

  -- تريجر handle_new_user أنشأ الملف بدور auditor؛ نرقّيه إلى المالك
  insert into public.profiles (id, full_name, role)
  values (v_id, v_cfg.owner_name, 'owner')
  on conflict (id) do update
    set role = 'owner', full_name = excluded.full_name;

  raise notice 'تم إنشاء المالك: %', v_cfg.owner_email;
end
$seco_owner$;

-- تنظيف إعدادات التهيئة — لا داعي لبقاء الرمز في القاعدة
drop schema seco_bootstrap cascade;

commit;

-- ═══════════════════════════════════════════════════════════════════════
-- تم. افتح الموقع وادخل بالرمز الذي حددته أعلاه.
-- ═══════════════════════════════════════════════════════════════════════
`;

const generated = header + migrations + owner;
const bytes = Buffer.byteLength(generated, "utf8");
const summary = `${files.length} ترحيلاً، ${(bytes / 1024).toFixed(0)} كيلوبايت`;

/*
  وضع الفحص: يقارن دون أن يكتب.

  لا يعتمد على git: الاعتماد عليه يجعل الفحص يمر بصمت حين يكون الملف
  غير متتبَّع بعد — وهي بالضبط الحالة التي أوقعتني أول مرة.
*/
if (process.argv.includes("--check")) {
  if (!existsSync(outputPath)) {
    console.error(
      "✗ docs/bootstrap.sql غير موجود — شغّل npm run bootstrap:build",
    );
    process.exit(1);
  }

  if (readFileSync(outputPath, "utf8") !== generated) {
    console.error(
      "✗ docs/bootstrap.sql لا يطابق الترحيلات — شغّل npm run bootstrap:build وادفع الناتج",
    );
    process.exit(1);
  }

  console.log(`✓ docs/bootstrap.sql مطابق للترحيلات (${summary})`);
} else {
  writeFileSync(outputPath, generated, "utf8");
  console.log(`✓ docs/bootstrap.sql — ${summary}`);
}
