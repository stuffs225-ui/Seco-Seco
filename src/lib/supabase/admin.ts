import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import { SUPABASE_URL } from "@/lib/env";
import type { Database } from "@/types/database";

/**
 * عميل بمفتاح service_role — يتجاوز كل سياسات RLS.
 *
 * `server-only` في أعلى الملف يجعل استيراده من مكوّن عميل خطأ بناء، لا
 * ثغرة تُكتشف بعد النشر.
 *
 * الاستخدام الوحيد المشروع اليوم: إنشاء جلسة المالك تلقائياً عند أول طلب،
 * لأن النظام يفتح بلا شاشة دخول. لا يُستخدم لأي قراءة أو كتابة على بيانات
 * النشاط — تلك تمر عبر RPC بجلسة المستخدم فتخضع لـ RLS وسجل التدقيق.
 *
 * الفحص كسول عمداً: بيئات المعاينة قد لا تحمل المفتاح، ولا يصح أن يفشل
 * البناء كله بسببه — يكفي أن تفشل التهيئة برسالة واضحة في `/setup`.
 */
function requireServiceRoleKey(): string {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";

  if (key === "") {
    throw new Error(
      "متغير البيئة SUPABASE_SERVICE_ROLE_KEY غير معرَّف.\n\n" +
        "النظام يحتاجه لإنشاء جلسة المالك تلقائياً. أضفه في Vercel → " +
        "Settings → Environment Variables بدون أي بادئة — إضافة " +
        "NEXT_PUBLIC_ له تسرّبه لكل متصفح يفتح الموقع.",
    );
  }

  return key;
}

export function createAdminClient() {
  return createSupabaseClient<Database>(SUPABASE_URL, requireServiceRoleKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * بريد الحساب الذي يعمل النظام تحت هويته: أول مالك نشط.
 *
 * يُقرأ على الخادم فقط ولا يصل المتصفح إطلاقاً.
 */
export type AccessAccountResult =
  | { kind: "ok"; email: string }
  /** الترحيلات لم تُطبَّق: جدول profiles غير موجود أصلاً. */
  | { kind: "schema_missing" }
  /** المخطط موجود لكن لا يوجد مالك نشط. */
  | { kind: "no_owner" }
  /** المالك موجود لكن حسابه في auth بلا بريد — لا يمكن توليد جلسة له. */
  | { kind: "owner_without_email" }
  | { kind: "error"; message: string };

export async function getAccessAccountEmail(): Promise<AccessAccountResult> {
  const admin = createAdminClient();

  const { data: owner, error } = await admin
    .from("profiles")
    .select("id")
    .eq("role", "owner")
    .eq("is_active", true)
    .order("created_at")
    .limit(1)
    .maybeSingle<{ id: string }>();

  /*
    التمييز بين «لا يوجد مالك» و«الجدول غير موجود» ليس تفصيلاً تجميلياً:
    الحالتان تعنيان خطوتين مختلفتين تماماً — الأولى تُحل بإنشاء مستخدم،
    والثانية بتطبيق الترحيلات. خلطهما يرسل المالك إلى المكان الخطأ.

    PostgREST يعيد 42P01 من Postgres أو PGRST205 من ذاكرة المخطط حين
    يكون الجدول غير موجود.
  */
  if (error) {
    if (error.code === "42P01" || error.code === "PGRST205") {
      return { kind: "schema_missing" };
    }
    return { kind: "error", message: error.message };
  }

  if (!owner) return { kind: "no_owner" };

  const { data, error: userError } = await admin.auth.admin.getUserById(
    owner.id,
  );

  if (userError) return { kind: "error", message: userError.message };

  const email = data.user?.email;
  return email ? { kind: "ok", email } : { kind: "owner_without_email" };
}

/**
 * ينشئ جلسة للمالك دون كلمة مرور.
 *
 * يولّد رمز رابط سحري بمفتاح الإدارة ثم يستبدله بجلسة. الفائدة أن لا
 * كلمة مرور تُخزَّن في متغير بيئة ولا في قاعدة البيانات لتحقيق الفتح
 * التلقائي — المفتاح الإداري وحده يكفي.
 *
 * تُعاد الرموز ليستبدلها المنادي بجلسة على عميل يملك كتابة الكوكيز؛
 * مكوّن الخادم لا يستطيع ذلك، فالنداء يقع في الـ proxy.
 */
export async function generateOwnerSessionToken(): Promise<
  { ok: true; tokenHash: string; email: string } | { ok: false; reason: string }
> {
  const account = await getAccessAccountEmail();

  if (account.kind !== "ok") {
    return { ok: false, reason: account.kind };
  }

  const admin = createAdminClient();
  const { data, error } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: account.email,
  });

  if (error) return { ok: false, reason: error.message };

  const tokenHash = data.properties?.hashed_token;
  if (!tokenHash) return { ok: false, reason: "لم يُنتج رمز جلسة" };

  return { ok: true, tokenHash, email: account.email };
}
