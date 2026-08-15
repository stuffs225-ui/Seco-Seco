"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";

import { type ActionState, numericString, optionalDate } from "./shared";

export type { ActionState };

/**
 * إجراءات الصفقات والموزعين.
 *
 * لا حساب هنا: التكلفة والربح المتوقع وقيمة الجرام كلها تحسبها دوال
 * قاعدة البيانات داخل معاملة واحدة، لأن كل عملية تمس المخزون والصفقة
 * والدفتر معاً (§30).
 */

const createDistributorSchema = z.object({
  code: z.string().trim().min(1, "كود الموزع مطلوب"),
  name: z.string().trim().min(1, "اسم الموزع مطلوب"),
  phone: z.string().trim().default(""),
  notes: z.string().trim().default(""),
});

export async function createDistributor(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = createDistributorSchema.safeParse({
    code: formData.get("code"),
    name: formData.get("name"),
    phone: formData.get("phone") ?? "",
    notes: formData.get("notes") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("distributors").insert(parsed.data);

  if (error) {
    if (error.code === "23505") return { error: "كود الموزع مستخدم بالفعل" };
    if (error.code === "42501") return { error: "لا تملك صلاحية إضافة موزع" };
    return { error: error.message };
  }

  revalidatePath("/distributors");
  return { error: null, success: "تمت إضافة الموزع" };
}

const updateDistributorSchema = z.object({
  id: z.uuid(),
  name: z.string().trim().min(1, "اسم الموزع مطلوب"),
  phone: z.string().trim().default(""),
  notes: z.string().trim().default(""),
});

/** الكود لا يُعدَّل — قد تُشير إليه تقارير موزعين مطبوعة سابقاً. */
export async function updateDistributor(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = updateDistributorSchema.safeParse({
    id: formData.get("id"),
    name: formData.get("name"),
    phone: formData.get("phone") ?? "",
    notes: formData.get("notes") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("distributors")
    .update({
      name: parsed.data.name,
      phone: parsed.data.phone,
      notes: parsed.data.notes,
    })
    .eq("id", parsed.data.id);

  if (error) {
    if (error.code === "42501") return { error: "لا تملك صلاحية تعديل موزع" };
    return { error: error.message };
  }

  revalidatePath("/distributors");
  return { error: null, success: "تم تحديث الموزع" };
}

const setDistributorActiveSchema = z.object({
  id: z.uuid(),
  is_active: z.enum(["true", "false"]).transform((v) => v === "true"),
});

/**
 * تفعيل/تعطيل موزع — لا حذف حقيقي. موزع له صفقات لا يمكن حذفه أصلاً
 * (on delete restrict)؛ التعطيل يمنع تسليم كميات جديدة له (open_deal
 * يتحقق من is_active) دون أن يمس أي صفقة قديمة.
 */
export async function setDistributorActive(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = setDistributorActiveSchema.safeParse({
    id: formData.get("id"),
    is_active: formData.get("is_active"),
  });

  if (!parsed.success) return { error: "بيانات غير صحيحة" };

  const supabase = await createClient();
  const { error } = await supabase
    .from("distributors")
    .update({ is_active: parsed.data.is_active })
    .eq("id", parsed.data.id);

  if (error) {
    if (error.code === "42501") return { error: "لا تملك صلاحية تعديل موزع" };
    return { error: error.message };
  }

  revalidatePath("/distributors");
  return {
    error: null,
    success: parsed.data.is_active ? "تم تفعيل الموزع" : "تم تعطيل الموزع",
  };
}

const openDealSchema = z.object({
  distributor_id: z.uuid("اختر الموزع"),
  lot_id: z.uuid("اختر الدفعة"),
  weight_g: numericString,
  deal_value: numericString,
  delivery_date: z.string().min(1, "تاريخ التسليم مطلوب"),
  due_date: optionalDate,
  notes: z.string().trim().default(""),
});

export async function openDeal(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = openDealSchema.safeParse({
    distributor_id: formData.get("distributor_id"),
    lot_id: formData.get("lot_id"),
    weight_g: formData.get("weight_g"),
    deal_value: formData.get("deal_value"),
    delivery_date: formData.get("delivery_date"),
    due_date: formData.get("due_date") ?? "",
    notes: formData.get("notes") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("open_deal", {
    p_distributor_id: parsed.data.distributor_id,
    p_lot_id: parsed.data.lot_id,
    p_weight_g: parsed.data.weight_g,
    p_deal_value: parsed.data.deal_value,
    p_delivery_date: parsed.data.delivery_date,
    p_due_date: parsed.data.due_date,
    p_notes: parsed.data.notes,
  });

  if (error) return { error: error.message };

  revalidatePath("/deals");
  revalidatePath("/inventory");
  return { error: null, success: String(data) };
}

const recordReturnSchema = z.object({
  deal_id: z.uuid(),
  weight_g: numericString,
  return_date: z.string().min(1, "تاريخ الاسترداد مطلوب"),
  reason: z.string().trim().default(""),
  restock: z.enum(["true", "false"]).transform((v) => v === "true"),
});

/**
 * استرداد كمية — عكس جزئي لتسليم المخزون لا تحصيل نقدي (§18.3).
 *
 * التكلفة الراجعة والربح المتوقع الملغى وتخفيض قيمة الصفقة تحسبها
 * قاعدة البيانات من اقتصاديات الصفقة المثبَّتة، فلا تُرسل من هنا.
 * `restock` وحده يحدد أثر المخزون: تعود الكمية قابلة للبيع أم تُسلَّم
 * للمالك مباشرة دون أن تعود.
 */
export async function recordDealReturn(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = recordReturnSchema.safeParse({
    deal_id: formData.get("deal_id"),
    weight_g: formData.get("weight_g"),
    return_date: formData.get("return_date"),
    reason: formData.get("reason") ?? "",
    restock: formData.get("restock") ?? "true",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_deal_return", {
    p_deal_id: parsed.data.deal_id,
    p_weight_g: parsed.data.weight_g,
    p_return_date: parsed.data.return_date,
    p_reason: parsed.data.reason,
    p_restock: parsed.data.restock,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  revalidatePath("/deals");
  revalidatePath("/inventory");
  return { error: null, success: "تم تسجيل الاسترداد" };
}
