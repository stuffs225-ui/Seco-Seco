"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";

import { type ActionState, numericString } from "./shared";

export type { ActionState };

/**
 * إجراءات التحصيل.
 *
 * الدفعة منفصلة عن تخصيصها (§24.4): تُسجَّل على مستوى الموزع، ثم تُوزَّع
 * على صفقاته — يدوياً أو على الأقدم — أو تبقى رصيداً غير مخصص. التوزيع
 * كله يجري في قاعدة البيانات داخل معاملة واحدة.
 */

const allocationSchema = z.object({
  deal_id: z.uuid(),
  amount: z.number().positive(),
});

const recordPaymentSchema = z.object({
  distributor_id: z.uuid("اختر الموزع"),
  amount: numericString,
  payment_date: z.string().min(1, "تاريخ التحصيل مطلوب"),
  method: z.enum(["cash", "transfer", "cheque", "other"]),
  reference: z.string().trim().default(""),
  cash_account_id: z.union([z.uuid(), z.literal("")]).optional(),
  notes: z.string().trim().default(""),
  allocation_mode: z.enum(["unallocated", "oldest_first", "specific"]),
  allocations: z.array(allocationSchema).default([]),
});

export async function recordPayment(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  let allocations: unknown = [];
  const raw = formData.get("allocations");
  if (typeof raw === "string" && raw.trim() !== "") {
    try {
      allocations = JSON.parse(raw);
    } catch {
      return { error: "تعذّرت قراءة بيانات التخصيص" };
    }
  }

  const parsed = recordPaymentSchema.safeParse({
    distributor_id: formData.get("distributor_id"),
    amount: formData.get("amount"),
    payment_date: formData.get("payment_date"),
    method: formData.get("method"),
    reference: formData.get("reference") ?? "",
    cash_account_id: formData.get("cash_account_id") ?? "",
    notes: formData.get("notes") ?? "",
    allocation_mode: formData.get("allocation_mode"),
    allocations,
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_payment", {
    p_distributor_id: parsed.data.distributor_id,
    p_amount: parsed.data.amount,
    p_payment_date: parsed.data.payment_date,
    p_method: parsed.data.method,
    p_reference: parsed.data.reference,
    p_cash_account_id: parsed.data.cash_account_id || null,
    p_notes: parsed.data.notes,
    p_allocation_mode: parsed.data.allocation_mode,
    p_allocations: parsed.data.allocations,
  });

  if (error) return { error: error.message };

  revalidatePath("/payments");
  revalidatePath("/deals");
  return { error: null, success: "تم تسجيل التحصيل" };
}

const resolveCreditSchema = z.object({
  deal_id: z.uuid(),
  method: z.enum([
    "refund",
    "transfer_to_deal",
    "keep_as_credit",
    "authorized_adjustment",
  ]),
  amount: numericString,
  reason: z.string().trim().min(1, "السبب إلزامي لمعالجة الرصيد الدائن"),
  target_deal_id: z.union([z.uuid(), z.literal("")]).optional(),
  cash_account_id: z.union([z.uuid(), z.literal("")]).optional(),
});

/** معالجة الرصيد الدائن للموزع — رد أو نقل أو إبقاء أو تسوية (§24.5). */
export async function resolveDistributorCredit(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = resolveCreditSchema.safeParse({
    deal_id: formData.get("deal_id"),
    method: formData.get("method"),
    amount: formData.get("amount"),
    reason: formData.get("reason") ?? "",
    target_deal_id: formData.get("target_deal_id") ?? "",
    cash_account_id: formData.get("cash_account_id") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_distributor_credit", {
    p_deal_id: parsed.data.deal_id,
    p_method: parsed.data.method,
    p_amount: parsed.data.amount,
    p_reason: parsed.data.reason,
    p_target_deal_id: parsed.data.target_deal_id || null,
    p_cash_account_id: parsed.data.cash_account_id || null,
  });

  if (error) return { error: error.message };

  revalidatePath(`/deals/${parsed.data.deal_id}`);
  revalidatePath("/payments");
  return { error: null, success: "تمت معالجة الرصيد الدائن" };
}

const reverseAllocationSchema = z.object({
  allocation_id: z.uuid(),
  reason: z.string().trim().min(1, "السبب إلزامي لعكس التخصيص"),
});

export async function reversePaymentAllocation(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireUser();

  const parsed = reverseAllocationSchema.safeParse({
    allocation_id: formData.get("allocation_id"),
    reason: formData.get("reason") ?? "",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "بيانات غير صحيحة" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("reverse_payment_allocation", {
    p_allocation_id: parsed.data.allocation_id,
    p_reason: parsed.data.reason,
  });

  if (error) return { error: error.message };

  revalidatePath("/payments");
  revalidatePath("/deals");
  return { error: null, success: "تم عكس التخصيص" };
}
