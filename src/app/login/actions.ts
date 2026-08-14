"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

const loginSchema = z.object({
  email: z.email("صيغة البريد الإلكتروني غير صحيحة"),
  password: z.string().min(1, "كلمة المرور مطلوبة"),
  next: z.string().optional(),
});

export type LoginState = { error: string | null };

/** المسار الآمن الوحيد لإنشاء جلسة. */
export async function login(
  _prevState: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const parsed = loginSchema.safeParse({
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

  // نقبل المسارات الداخلية فقط؛ المسار المطلق يسمح بإعادة توجيه لموقع خارجي.
  const target = parsed.data.next;
  const safeTarget =
    target && target.startsWith("/") && !target.startsWith("//")
      ? target
      : "/dashboard";

  revalidatePath("/", "layout");
  redirect(safeTarget);
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/login");
}
