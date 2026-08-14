"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { getAccessAccountEmail } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export type LoginState = { error: string | null };

/** نقبل المسارات الداخلية فقط؛ المسار المطلق يسمح بإعادة توجيه لموقع خارجي. */
function safeRedirectTarget(target: string | null | undefined): string {
  return target && target.startsWith("/") && !target.startsWith("//")
    ? target
    : "/dashboard";
}

const codeSchema = z.object({
  code: z.string().min(1, "الرمز مطلوب"),
  next: z.string().nullish(),
});

/**
 * الدخول برمز واحد.
 *
 * الرمز هو كلمة مرور حساب المالك في Supabase Auth، والبريد يُقرأ على
 * الخادم. النتيجة أن المستخدم يكتب حقلاً واحداً بينما تبقى الجلسة جلسة
 * Supabase حقيقية: `auth.uid()` يعمل، وسياسات RLS تُطبَّق، وسجل التدقيق
 * ينسب كل حركة لصاحبها. لو استبدلنا المصادقة بحارس رمز خاص بنا لسقط
 * ذلك كله.
 */
export async function loginWithCode(
  _prevState: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const parsed = codeSchema.safeParse({
    code: formData.get("code"),
    next: formData.get("next"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  let email: string | null;
  try {
    email = await getAccessAccountEmail();
  } catch (error) {
    // خطأ تهيئة لا خطأ مستخدم — نعرضه كما هو ليصلحه المالك
    return {
      error: error instanceof Error ? error.message : "تعذّر الوصول للنظام",
    };
  }

  if (!email) {
    return {
      error:
        "لا يوجد حساب مالك نشط في النظام بعد. أنشئ المستخدم في Supabase ثم " +
        "اضبط دوره على owner.",
    };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email,
    password: parsed.data.code,
  });

  if (error) return { error: "الرمز غير صحيح" };

  revalidatePath("/", "layout");
  redirect(safeRedirectTarget(parsed.data.next));
}

const emailSchema = z.object({
  email: z.email("صيغة البريد الإلكتروني غير صحيحة"),
  password: z.string().min(1, "كلمة المرور مطلوبة"),
  next: z.string().nullish(),
});

/**
 * الدخول بالبريد وكلمة المرور.
 *
 * مسار احتياطي: يعمل حين لا يكون مفتاح service_role مضبوطاً، وهو أيضاً
 * المسار الذي ستستخدمه بقية الأدوار عند تفعيلها — الرمز الواحد يفتح
 * حساب المالك وحده.
 */
export async function login(
  _prevState: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const parsed = emailSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    next: formData.get("next"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) {
    // رسالة واحدة لكل حالات الفشل — التمييز بينها يكشف أي بريد مسجَّل في النظام.
    return { error: "بيانات الدخول غير صحيحة" };
  }

  revalidatePath("/", "layout");
  redirect(safeRedirectTarget(parsed.data.next));
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/login");
}
