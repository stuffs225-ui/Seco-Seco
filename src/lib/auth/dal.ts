import "server-only";

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
 */
export const getUser = cache(async () => {
  const supabase = await createClient();
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
