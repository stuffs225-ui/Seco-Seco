"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  createSupplier,
  updateSupplier,
  type ActionState,
} from "@/lib/actions/inventory";

const initialState: ActionState = { error: null };

const fieldClass =
  "border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-2 text-sm outline-none";

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? "جارٍ الحفظ…" : label}
    </button>
  );
}

type EditableSupplier = {
  id: string;
  name: string;
  phone: string;
  notes: string;
};

export function SupplierForm({
  supplier,
  onSaved,
}: {
  /** وجوده يحوّل النموذج لتعديل مورد قائم بدل إنشاء واحد جديد. */
  supplier?: EditableSupplier;
  onSaved?: () => void;
}) {
  const router = useRouter();
  const isEdit = supplier != null;
  const [state, formAction] = useActionState(
    isEdit ? updateSupplier : createSupplier,
    initialState,
  );

  useEffect(() => {
    if (!state.success) return;
    if (isEdit) onSaved?.();
    else router.push("/inventory/suppliers");
  }, [state.success, isEdit, onSaved, router]);

  return (
    <form action={formAction} className="space-y-6">
      {isEdit ? <input type="hidden" name="id" value={supplier.id} /> : null}

      <Card className="space-y-4 p-5">
        <div className="space-y-1.5">
          <label htmlFor="name" className="block text-sm font-medium">
            اسم المورد
          </label>
          <input
            id="name"
            name="name"
            required
            defaultValue={supplier?.name}
            className={fieldClass}
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="phone" className="block text-sm font-medium">
            الهاتف <span className="text-muted font-normal">(اختياري)</span>
          </label>
          <input
            id="phone"
            name="phone"
            type="tel"
            defaultValue={supplier?.phone}
            className={`${fieldClass} num`}
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="notes" className="block text-sm font-medium">
            ملاحظات <span className="text-muted font-normal">(اختياري)</span>
          </label>
          <textarea
            id="notes"
            name="notes"
            rows={3}
            defaultValue={supplier?.notes}
            className={fieldClass}
          />
        </div>
      </Card>

      {state.error ? (
        <p
          role="alert"
          className="text-negative border-negative/30 bg-negative/5 rounded-lg border px-4 py-3 text-sm"
        >
          {state.error}
        </p>
      ) : null}

      <div className="flex justify-end">
        <SubmitButton label={isEdit ? "حفظ التعديل" : "حفظ المورد"} />
      </div>
    </form>
  );
}
