"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";

import { type ActionState, numericString } from "./shared";

export type { ActionState };

/**
 * إجراءات المصالحة والإغلاق (§21، §24.6).
 *
 * شروط الإغلاق تُفحص في قاعدة البيانات لا هنا: الواجهة تعطّل الزر
 * لتوضيح السبب، لكن الرفض الفعلي يقع في close_deal حتى لو استُدعيت
 * من أي مسار آخر.
 */

const dealIdSchema = z.object({ deal_id: z.uuid() });

export async function closeDeal(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = dealIdSchema.safeParse({ deal_id: formData.get("deal_id") });
  if (!parsed.success) return { error: "صفقة غير صحيحة" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("close_deal", {
    p_deal_id: parsed.data.deal_id,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  revalidatePath("/deals");
  return { error: null, success: "تم إغلاق الصفقة" };
}

const reopenSchema = z.object({
  deal_id: z.uuid(),
  reason: z.string().trim().min(1, "سبب إعادة الفتح إلزامي"),
});

export async function reopenDeal(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = reopenSchema.safeParse({
    deal_id: formData.get("deal_id"),
    reason: formData.get("reason") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("reopen_deal", {
    p_deal_id: parsed.data.deal_id,
    p_reason: parsed.data.reason,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  revalidatePath("/deals");
  return { error: null, success: "تمت إعادة فتح الصفقة" };
}

const weightAdjustmentSchema = z.object({
  deal_id: z.uuid(),
  weight_g: numericString,
  reason: z.string().trim().min(1, "سبب تسوية الوزن إلزامي"),
});

export async function recordWeightAdjustment(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = weightAdjustmentSchema.safeParse({
    deal_id: formData.get("deal_id"),
    weight_g: formData.get("weight_g"),
    reason: formData.get("reason") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_weight_adjustment", {
    p_deal_id: parsed.data.deal_id,
    p_weight_g: parsed.data.weight_g,
    p_reason: parsed.data.reason,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  return { error: null, success: "تم تسجيل تسوية الوزن" };
}

/** التسوية التجارية تقبل السالب — الخصم المعتمد يخفض المستحق. */
const signedAmount = z
  .string()
  .trim()
  .min(1, "المبلغ مطلوب")
  .transform((raw) =>
    raw
      .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
      .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
      .replace(/[,\s]/g, ""),
  )
  .refine((v) => /^-?\d+(\.\d+)?$/.test(v), "أدخل رقماً صحيحاً")
  .refine((v) => Number(v) !== 0, "المبلغ لا يمكن أن يكون صفراً");

const commercialAdjustmentSchema = z.object({
  deal_id: z.uuid(),
  amount: signedAmount,
  reason: z.string().trim().min(1, "سبب التسوية التجارية إلزامي"),
});

export async function recordCommercialAdjustment(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = commercialAdjustmentSchema.safeParse({
    deal_id: formData.get("deal_id"),
    amount: formData.get("amount"),
    reason: formData.get("reason") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_commercial_adjustment", {
    p_deal_id: parsed.data.deal_id,
    p_amount: parsed.data.amount,
    p_reason: parsed.data.reason,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  return { error: null, success: "تم تسجيل التسوية التجارية" };
}
