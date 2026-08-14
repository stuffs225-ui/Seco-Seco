"use client";

import { useActionState, useRef } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { changeAccessCode, type ActionState } from "@/lib/actions/access-code";
import { MIN_CODE_LENGTH } from "@/lib/actions/shared";

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
      {pending ? "جارٍ التغيير…" : "تغيير الرمز"}
    </button>
  );
}

export function AccessCodeForm() {
  const [state, formAction] = useActionState(changeAccessCode, initialState);
  const formRef = useRef<HTMLFormElement>(null);

  return (
    <Card className="p-5">
      <h2 className="font-semibold">رمز الدخول</h2>
      <p className="text-muted mt-1 text-sm">
        الرمز الذي تُفتح به شاشة الدخول. تغييره هنا يغيّره فوراً على كل الأجهزة،
        ويُسجَّل في سجل التدقيق دون تسجيل الرمز نفسه.
      </p>

      <form
        ref={formRef}
        action={async (formData) => {
          await formAction(formData);
          formRef.current?.reset();
        }}
        className="mt-4 space-y-4"
      >
        <div className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-1.5">
            <label htmlFor="current_code" className="block text-sm font-medium">
              الرمز الحالي
            </label>
            <input
              id="current_code"
              name="current_code"
              type="password"
              autoComplete="current-password"
              required
              dir="ltr"
              className={`${fieldClass} text-start`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="new_code" className="block text-sm font-medium">
              الرمز الجديد
            </label>
            <input
              id="new_code"
              name="new_code"
              type="password"
              autoComplete="new-password"
              required
              minLength={MIN_CODE_LENGTH}
              dir="ltr"
              className={`${fieldClass} text-start`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="confirm_code" className="block text-sm font-medium">
              تأكيد الرمز الجديد
            </label>
            <input
              id="confirm_code"
              name="confirm_code"
              type="password"
              autoComplete="new-password"
              required
              dir="ltr"
              className={`${fieldClass} text-start`}
            />
          </div>
        </div>

        <p className="text-muted text-xs">
          {MIN_CODE_LENGTH} خانات على الأقل. النظام يحمل بيانات مالية — تجنّب
          الأنماط المتوقعة.
        </p>

        {state.error ? (
          <p
            role="alert"
            className="text-negative border-negative/30 bg-negative/5 rounded-lg border px-4 py-3 text-sm whitespace-pre-line"
          >
            {state.error}
          </p>
        ) : null}

        {state.success ? (
          <p
            role="status"
            className="text-positive border-positive/30 bg-positive/5 rounded-lg border px-4 py-3 text-sm"
          >
            {state.success}
          </p>
        ) : null}

        <div className="flex justify-end">
          <SubmitButton />
        </div>
      </form>
    </Card>
  );
}
