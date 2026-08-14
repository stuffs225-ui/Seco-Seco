"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { createItem, type ActionState } from "@/lib/actions/inventory";

const initialState: ActionState = { error: null };

const fieldClass =
  "border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-2 text-sm outline-none";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? "جارٍ الحفظ…" : "حفظ الصنف"}
    </button>
  );
}

export function ItemForm() {
  const router = useRouter();
  const [state, formAction] = useActionState(createItem, initialState);

  useEffect(() => {
    if (state.success) router.push("/inventory/new");
  }, [state.success, router]);

  return (
    <form action={formAction} className="space-y-6">
      <Card className="space-y-4 p-5">
        <div className="space-y-1.5">
          <label htmlFor="code" className="block text-sm font-medium">
            كود الصنف
          </label>
          <input
            id="code"
            name="code"
            required
            placeholder="ITM-001"
            className={`${fieldClass} num`}
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="name" className="block text-sm font-medium">
            اسم الصنف
          </label>
          <input id="name" name="name" required className={fieldClass} />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="description" className="block text-sm font-medium">
            الوصف <span className="text-muted font-normal">(اختياري)</span>
          </label>
          <textarea
            id="description"
            name="description"
            rows={3}
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
        <SubmitButton />
      </div>
    </form>
  );
}
