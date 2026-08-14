"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { createDistributor, type ActionState } from "@/lib/actions/deals";

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
      {pending ? "جارٍ الحفظ…" : "حفظ الموزع"}
    </button>
  );
}

export function DistributorForm() {
  const router = useRouter();
  const [state, formAction] = useActionState(createDistributor, initialState);

  useEffect(() => {
    if (state.success) router.push("/distributors");
  }, [state.success, router]);

  return (
    <form action={formAction} className="space-y-6">
      <Card className="space-y-4 p-5">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label htmlFor="code" className="block text-sm font-medium">
              كود الموزع
            </label>
            <input
              id="code"
              name="code"
              required
              placeholder="DST-001"
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="name" className="block text-sm font-medium">
              اسم الموزع
            </label>
            <input id="name" name="name" required className={fieldClass} />
          </div>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="phone" className="block text-sm font-medium">
            الهاتف <span className="text-muted font-normal">(اختياري)</span>
          </label>
          <input
            id="phone"
            name="phone"
            type="tel"
            dir="ltr"
            className={`${fieldClass} num text-start`}
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="notes" className="block text-sm font-medium">
            ملاحظات
          </label>
          <textarea id="notes" name="notes" rows={2} className={fieldClass} />
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
