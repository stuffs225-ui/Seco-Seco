"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";

import { type ActionState, numericString } from "./shared";

export type { ActionState };

/**
 * إجراءات المخزون.
 *
 * هذه الدوال لا تحسب شيئاً: لا تكلفة جرام، لا رصيد، لا تجميع. مهمتها
 * التحقق من شكل المدخلات ثم استدعاء دالة RPC تنفّذ المنطق كاملاً داخل
 * معاملة ذرية في قاعدة البيانات (§30).
 *
 * التحقق هنا لراحة المستخدم فقط؛ المرجع النهائي قيود قاعدة البيانات،
 * فحتى لو تجاوز أحد هذه الطبقة تبقى البيانات سليمة.
 */

const expenseSchema = z.object({
  expense_type: z.string().trim().min(1),
  amount: z.number().positive(),
  include_in_cost: z.boolean(),
});

const createLotSchema = z.object({
  item_id: z.uuid("اختر صنفاً"),
  supplier_id: z.union([z.uuid(), z.literal("")]).optional(),
  purchase_date: z.string().min(1, "التاريخ مطلوب"),
  weight_g: numericString,
  purchase_value: numericString,
  invoice_ref: z.string().trim().default(""),
  notes: z.string().trim().default(""),
  expenses: z.array(expenseSchema).default([]),
});

export async function createPurchaseLot(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  // المصاريف تصل كـ JSON من حقل مخفي يديره العميل
  let expenses: unknown = [];
  const rawExpenses = formData.get("expenses");
  if (typeof rawExpenses === "string" && rawExpenses.trim() !== "") {
    try {
      expenses = JSON.parse(rawExpenses);
    } catch {
      return { error: "تعذّرت قراءة بيانات المصاريف" };
    }
  }

  const parsed = createLotSchema.safeParse({
    item_id: formData.get("item_id"),
    supplier_id: formData.get("supplier_id") ?? "",
    purchase_date: formData.get("purchase_date"),
    weight_g: formData.get("weight_g"),
    purchase_value: formData.get("purchase_value"),
    invoice_ref: formData.get("invoice_ref") ?? "",
    notes: formData.get("notes") ?? "",
    expenses,
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_purchase_lot", {
    p_item_id: parsed.data.item_id,
    p_purchase_date: parsed.data.purchase_date,
    p_weight_g: parsed.data.weight_g,
    p_purchase_value: parsed.data.purchase_value,
    p_supplier_id: parsed.data.supplier_id || null,
    p_invoice_ref: parsed.data.invoice_ref,
    p_notes: parsed.data.notes,
    p_expenses: parsed.data.expenses,
  });

  if (error) {
    // رسائل قاعدة البيانات مكتوبة بالعربية ومقصودة للمستخدم
    return { error: error.message };
  }

  revalidatePath("/inventory");
  return { error: null, success: String(data) };
}

const createItemSchema = z.object({
  code: z.string().trim().min(1, "كود الصنف مطلوب"),
  name: z.string().trim().min(1, "اسم الصنف مطلوب"),
  description: z.string().trim().default(""),
});

export async function createItem(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = createItemSchema.safeParse({
    code: formData.get("code"),
    name: formData.get("name"),
    description: formData.get("description") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("items").insert(parsed.data);

  if (error) {
    if (error.code === "23505") {
      return { error: "كود الصنف مستخدم بالفعل" };
    }
    if (error.code === "42501") {
      return { error: "لا تملك صلاحية إضافة صنف" };
    }
    return { error: error.message };
  }

  revalidatePath("/inventory");
  return { error: null, success: "تمت إضافة الصنف" };
}
