import "server-only";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";

import { createClient } from "@/lib/supabase/server";

/**
 * طبقة الوصول للبيانات (DAL).
 *
 * كل صفحة وكل Server Action تبدأ من هنا. الـ proxy ينشئ جلسة المالك تلقائياً؛
 * هذا هو الفحص الذي يُعتمد عليه فعلياً، ومن خلفه سياسات RLS في قاعدة البيانات
 * كخط دفاع أخير لا يمكن تجاوزه حتى لو نُسي استدعاء هذه الدالة.
 *
 * `cache` يمنع تكرار نداء الشبكة عندما تستدعيه عدة مكونات في نفس الطلب.
 *
 * `getUser()` هنا يتحقق من التوكن عبر الشبكة لدى Supabase — ضروري عادةً
 * لأن `getSession()` وحدها تقرأ الكوكي دون تحقق. لكن الـ proxy يكون قد
 * فعل هذا التحقق بالضبط قبل لحظات لنفس الطلب، ويضع هيدراً موثوقاً
 * (`x-seco-verified`) يستبدل أي قيمة يرسلها العميل دون شرط — فحين يكون
 * موجوداً، فك الكوكي محلياً بلا شبكة آمن تماماً لأنه مبني على تحقق حديث
 * فعلي لا على ثقة عمياء بالكوكي. هذا يزيل نداء شبكة مكرراً في كل تنقل.
 */
export const getUser = cache(async () => {
  const supabase = await createClient();
  const verified = (await headers()).get("x-seco-verified") === "1";

  if (verified) {
    const {
      data: { session },
    } = await supabase.auth.getSession();
    return session?.user ?? null;
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
});

/**
 * يعيد المستخدم، أو يحوّل إلى صفحة التهيئة إن تعذّر إنشاء الجلسة.
 *
 * لا شاشة دخول: الوصول إلى هنا بلا جلسة يعني أن النظام غير مهيَّأ بعد
 * (ترحيلات غير مطبَّقة، أو لا مالك، أو مفتاح إدارة ناقص) — و`/setup`
 * تقول أيّها بالضبط بدل «صفحة لا تعمل».
 */
export async function requireUser() {
  const user = await getUser();
  if (!user) redirect("/setup");
  return user;
}
