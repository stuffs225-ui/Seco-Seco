"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import { loginWithCode, type LoginState } from "./actions";

const initialState: LoginState = { error: null };

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-primary text-primary-foreground w-full rounded-lg px-4 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? "جارٍ الدخول…" : "دخول"}
    </button>
  );
}

export function CodeForm({ next }: { next?: string }) {
  const [state, formAction] = useActionState(loginWithCode, initialState);

  return (
    <form action={formAction} className="space-y-4">
      {next ? <input type="hidden" name="next" value={next} /> : null}

      <div className="space-y-1.5">
        <label htmlFor="code" className="block text-sm font-medium">
          رمز الدخول
        </label>
        <input
          id="code"
          name="code"
          type="password"
          autoComplete="current-password"
          required
          autoFocus
          dir="ltr"
          /*
            الرمز يُدخل من الجوال غالباً: النص تلقائياً LTR وبمسافة أحرف
            مريحة للقراءة، مع تعطيل التصحيح التلقائي الذي يفسد الإدخال.
          */
          autoCapitalize="off"
          autoCorrect="off"
          spellCheck={false}
          className="border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-3 text-center text-lg tracking-widest outline-none"
        />
      </div>

      {state.error ? (
        <p
          role="alert"
          className="text-negative border-negative/30 bg-negative/5 rounded-lg border px-3 py-2 text-sm whitespace-pre-line"
        >
          {state.error}
        </p>
      ) : null}

      <SubmitButton />
    </form>
  );
}
