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
 * الاستخدام الوحيد المشروع اليوم: معرفة بريد حساب الدخول قبل وجود جلسة،
 * حتى تكفي شاشة الدخول برمز واحد دون أن يكتب المستخدم بريداً. لا يُستخدم
 * لأي قراءة أو كتابة على بيانات النشاط — تلك تمر عبر RPC بجلسة المستخدم.
 *
 * الفحص كسول عمداً: بيئات المعاينة قد لا تحمل المفتاح، ولا يصح أن يفشل
 * البناء كله بسببه — يكفي أن يفشل مسار الدخول بالرمز برسالة واضحة.
 */
function requireServiceRoleKey(): string {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";

  if (key === "") {
    throw new Error(
      "متغير البيئة SUPABASE_SERVICE_ROLE_KEY غير معرَّف.\n\n" +
        "الدخول بالرمز يحتاجه لمعرفة حساب المالك. أضفه في Vercel → " +
        "Settings → Environment Variables بدون أي بادئة — إضافة " +
        "NEXT_PUBLIC_ له تسرّبه لكل متصفح يفتح الموقع.\n\n" +
        "حتى تضيفه، يمكن الدخول من /login/email بالبريد وكلمة المرور.",
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
 * بريد الحساب الذي يفتحه رمز الدخول: أول مالك نشط.
 *
 * يُقرأ على الخادم فقط ولا يصل المتصفح إطلاقاً. لو عُرِّض كنقطة عامة
 * لأصبح اسم الحساب معلوماً لأي أحد، وهو نصف ما يحتاجه المهاجم.
 */
export async function getAccessAccountEmail(): Promise<string | null> {
  const admin = createAdminClient();

  const { data: owner } = await admin
    .from("profiles")
    .select("id")
    .eq("role", "owner")
    .eq("is_active", true)
    .order("created_at")
    .limit(1)
    .maybeSingle<{ id: string }>();

  if (!owner) return null;

  const { data } = await admin.auth.admin.getUserById(owner.id);
  return data.user?.email ?? null;
}
