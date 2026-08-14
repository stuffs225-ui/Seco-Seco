"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  createItem,
  updateItem,
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

type EditableItem = { id: string; name: string; description: string };

export function ItemForm({
  item,
  onSaved,
}: {
  /** وجوده يحوّل النموذج لتعديل صنف قائم بدل إنشاء واحد جديد. */
  item?: EditableItem;
  /** يُستدعى بعد نجاح التعديل — يُستخدم لإغلاق نموذج التعديل المضمَّن في القائمة. */
  onSaved?: () => void;
}) {
  const router = useRouter();
  const isEdit = item != null;
  const [state, formAction] = useActionState(
    isEdit ? updateItem : createItem,
    initialState,
  );

  useEffect(() => {
    if (!state.success) return;
    if (isEdit) onSaved?.();
    else router.push("/inventory/new");
  }, [state.success, isEdit, onSaved, router]);

  return (
    <form action={formAction} className="space-y-6">
      {isEdit ? <input type="hidden" name="id" value={item.id} /> : null}

      <Card className="space-y-4 p-5">
        {isEdit ? null : (
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
        )}

        <div className="space-y-1.5">
          <label htmlFor="name" className="block text-sm font-medium">
            اسم الصنف
          </label>
          <input
            id="name"
            name="name"
            required
            defaultValue={item?.name}
            className={fieldClass}
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="description" className="block text-sm font-medium">
            الوصف <span className="text-muted font-normal">(اختياري)</span>
          </label>
          <textarea
            id="description"
            name="description"
            rows={3}
            defaultValue={item?.description}
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
        <SubmitButton label={isEdit ? "حفظ التعديل" : "حفظ الصنف"} />
      </div>
    </form>
  );
}
