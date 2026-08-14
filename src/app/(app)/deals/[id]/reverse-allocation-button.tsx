"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  reversePaymentAllocation,
  type ActionState,
} from "@/lib/actions/payments";

const initialState: ActionState = { error: null };

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="text-negative text-xs font-medium disabled:opacity-50"
    >
      {pending ? "جارٍ العكس…" : "تأكيد العكس"}
    </button>
  );
}

/**
 * عكس تخصيص دفعة واحد من صف "PAYMENT_RECEIVED" في دفتر حركات الصفقة.
 * الدالة والـ action موجودان ومختبران فعلاً (§24.4) — هذا الزر الوحيد
 * الذي يستدعيهما في أي واجهة.
 */
export function ReverseAllocationButton({
  allocationId,
}: {
  allocationId: string;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(
    reversePaymentAllocation,
    initialState,
  );
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (state.success) router.refresh();
  }, [state.success, router]);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="text-muted hover:text-negative text-xs underline-offset-2 hover:underline"
      >
        عكس
      </button>
    );
  }

  return (
    <form action={formAction} className="flex flex-col items-end gap-1.5">
      <input type="hidden" name="allocation_id" value={allocationId} />
      <input
        name="reason"
        required
        placeholder="سبب العكس — إلزامي"
        className="border-border bg-background w-40 rounded-md border px-2 py-1 text-xs outline-none"
      />
      {state.error ? (
        <p role="alert" className="text-negative text-xs">
          {state.error}
        </p>
      ) : null}
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="text-muted text-xs"
        >
          تراجع
        </button>
        <SubmitButton />
      </div>
    </form>
  );
}
