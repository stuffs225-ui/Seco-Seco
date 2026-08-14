"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { recordDealSale, type ActionState } from "@/lib/actions/deals";
import { formatWeight } from "@/lib/format";

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
      {pending ? "جارٍ التسجيل…" : "تسجيل التصريف"}
    </button>
  );
}

export function RecordSaleForm({
  dealId,
  openWeight,
}: {
  dealId: string;
  openWeight: string;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(recordDealSale, initialState);

  useEffect(() => {
    if (state.success) router.refresh();
  }, [state.success, router]);

  return (
    <Card className="p-5">
      <form action={formAction} className="space-y-4">
        <input type="hidden" name="deal_id" value={dealId} />

        <p className="text-muted text-sm">
          تسجيل ما صرّفه الموزع فعلاً. هذه الحركة تحوّل الربح من متوقع إلى محقق،
          ولا تعني أن الموزع سدّد — التحصيل حركة منفصلة.
        </p>

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-1.5">
            <label htmlFor="weight_g" className="block text-sm font-medium">
              الوزن المصرَّف
            </label>
            <input
              id="weight_g"
              name="weight_g"
              inputMode="decimal"
              required
              placeholder={formatWeight(openWeight, false)}
              className={`${fieldClass} num`}
            />
            <p className="text-muted text-xs">
              المتاح للتصريف: {formatWeight(openWeight)}
            </p>
          </div>

          <div className="space-y-1.5">
            <label htmlFor="sale_date" className="block text-sm font-medium">
              تاريخ التصريف
            </label>
            <input
              id="sale_date"
              name="sale_date"
              type="date"
              required
              defaultValue={new Date().toISOString().slice(0, 10)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="notes" className="block text-sm font-medium">
              ملاحظة <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input id="notes" name="notes" type="text" className={fieldClass} />
          </div>
        </div>

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
    </Card>
  );
}
