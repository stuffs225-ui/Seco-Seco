"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";

import { MIN_CODE_LENGTH, type ActionState } from "./shared";

export type { ActionState };

const changeCodeSchema = z
  .object({
    current_code: z.string().min(1, "الرمز الحالي مطلوب"),
    new_code: z
      .string()
      .min(
        MIN_CODE_LENGTH,
        `الرمز الجديد يجب أن يكون ${MIN_CODE_LENGTH} خانات على الأقل`,
      ),
    confirm_code: z.string().min(1, "تأكيد الرمز مطلوب"),
  })
  .refine((data) => data.new_code === data.confirm_code, {
    message: "الرمز الجديد وتأكيده غير متطابقين",
    path: ["confirm_code"],
  })
  .refine((data) => data.new_code !== data.current_code, {
    message: "الرمز الجديد مطابق للحالي",
    path: ["new_code"],
  });

/**
 * تغيير رمز الدخول.
 *
 * الرمز هو كلمة مرور حساب المستخدم في Supabase Auth، فتغييره يمر عبر
 * `auth.updateUser` بجلسته هو — لا بمفتاح إداري.
 *
 * نتحقق من الرمز الحالي أولاً رغم أن Supabase لا يشترطه: جلسة مفتوحة على
 * جهاز غير مقفل تكفي وإلا لتغيير مفتاح النظام المالي كله.
 */
export async function changeAccessCode(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const user = await requireUser();

  const parsed = changeCodeSchema.safeParse({
    current_code: formData.get("current_code"),
    new_code: formData.get("new_code"),
    confirm_code: formData.get("confirm_code"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();

  if (!user.email) {
    return { error: "الحساب الحالي بلا بريد — تعذّر التحقق من الرمز الحالي" };
  }

  // التحقق من الرمز الحالي بمحاولة دخول بها
  const { error: verifyError } = await supabase.auth.signInWithPassword({
    email: user.email,
    password: parsed.data.current_code,
  });

  if (verifyError) return { error: "الرمز الحالي غير صحيح" };

  const { error: updateError } = await supabase.auth.updateUser({
    password: parsed.data.new_code,
  });

  if (updateError) {
    // رسائل Supabase عن سياسة كلمة المرور إنجليزية — نترجم الشائع منها
    if (/password/i.test(updateError.message)) {
      return {
        error:
          `الرمز الجديد لا يحقق سياسة كلمة المرور في Supabase. ` +
          `اجعله ${MIN_CODE_LENGTH} خانات على الأقل، أو خفّض الحد من ` +
          `Supabase → Authentication → Policies.`,
      };
    }
    return { error: updateError.message };
  }

  // §11: التغيير يُقيَّد في سجل التدقيق دون تسجيل الرمز نفسه
  await supabase.rpc("log_access_code_changed");

  revalidatePath("/settings");
  return { error: null, success: "تم تغيير الرمز" };
}
