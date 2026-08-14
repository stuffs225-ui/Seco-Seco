import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";

import { createClient } from "@/lib/supabase/server";

/**
 * طبقة الوصول للبيانات (DAL).
 *
 * كل صفحة وكل Server Action تبدأ من هنا. الـ proxy يقوم بفحص متفائل سريع فقط؛
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

/** يعيد المستخدم أو يحوّله لتسجيل الدخول. استخدمها في كل صفحة محمية. */
export async function requireUser() {
  const user = await getUser();
  if (!user) redirect("/login");
  return user;
}
