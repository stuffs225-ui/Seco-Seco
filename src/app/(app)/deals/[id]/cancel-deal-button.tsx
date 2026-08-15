"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { cancelDeal, type ActionState } from "@/lib/actions/settlement";

const initialState: ActionState = { error: null };

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-negative rounded-lg px-4 py-2 text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? "جارٍ الإلغاء…" : "تأكيد الإلغاء"}
    </button>
  );
}

/**
 * إلغاء صفقة لم يُسجَّل عليها بيع حقيقي بعد — خطأ إدخال (موزع غلط، وزن
 * غلط) أو ببساطة صفقة يريد المالك التراجع عنها بالكامل. `eligible` مبنية
 * في الصفحة نفسها من دفتر الحركات المجلوب أصلاً — لا استعلام إضافي،
 * ومجرد نسخة مبكرة من حارس القاعدة الحقيقي في cancel_deal.
 */
export function CancelDealButton({
  dealId,
  eligible,
}: {
  dealId: string;
  eligible: boolean;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(cancelDeal, initialState);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (state.success) router.push("/deals");
  }, [state.success, router]);

  if (!eligible) return null;

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="text-muted hover:text-negative text-xs underline-offset-2 hover:underline"
      >
        إلغاء الصفقة
      </button>
    );
  }

  return (
    <form
      action={formAction}
      className="border-negative/30 bg-negative/5 w-full max-w-sm space-y-2 rounded-lg border p-3"
    >
      <input type="hidden" name="deal_id" value={dealId} />
      <p className="text-negative text-xs font-medium">
        سيُلغى التسليم بالكامل، ويعود الوزن المفتوح للمخزون، وتُعكس أي دفعات
        مخصَّصة على الصفقة (تعود غير مخصصة لا تُحذف) — لا تراجع بعد التأكيد.
      </p>
      <input
        name="reason"
        required
        placeholder="سبب الإلغاء — إلزامي"
        className="border-border bg-background w-full rounded-lg border px-3 py-1.5 text-sm outline-none"
      />
      {state.error ? (
        <p role="alert" className="text-negative text-xs">
          {state.error}
        </p>
      ) : null}
      <div className="flex justify-end gap-2">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="border-border rounded-lg border px-3 py-1.5 text-xs"
        >
          تراجع
        </button>
        <SubmitButton />
      </div>
    </form>
  );
}
