"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import type { ActionState } from "@/lib/actions/shared";

const initialState: ActionState = { error: null };

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="text-muted hover:text-foreground text-xs underline-offset-2 hover:underline disabled:opacity-50"
    >
      {pending ? "…" : label}
    </button>
  );
}

/**
 * تفعيل/تعطيل بيانات مرجعية (صنف، مورد، موزع) — لا حذف حقيقي ممكن أصلاً
 * (on delete restrict على من له سجل تاريخي). التعطيل يخفيه من قوائم
 * الإنشاء الجديدة دون أن يمس أي سجل قديم.
 *
 * مشترك بين الثلاثة لأن الشكل والسلوك متطابقان تماماً؛ يختلف فقط الـ
 * action الممرَّر.
 */
export function ToggleActiveButton({
  id,
  isActive,
  action,
  onDone,
}: {
  id: string;
  isActive: boolean;
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  onDone?: () => void;
}) {
  const [state, formAction] = useActionState(action, initialState);

  useEffect(() => {
    if (state.success) onDone?.();
  }, [state.success, onDone]);

  return (
    <form action={formAction} className="inline-flex items-center gap-2">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="is_active" value={String(!isActive)} />
      <SubmitButton label={isActive ? "تعطيل" : "تفعيل"} />
      {state.error ? (
        <span className="text-negative text-xs">{state.error}</span>
      ) : null}
    </form>
  );
}
