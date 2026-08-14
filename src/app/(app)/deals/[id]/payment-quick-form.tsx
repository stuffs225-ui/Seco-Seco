"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { recordPayment, type ActionState } from "@/lib/actions/payments";
import { formatMoney } from "@/lib/format";

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
      {pending ? "جارٍ التسجيل…" : "تسجيل الدفعة"}
    </button>
  );
}

function parseNumber(raw: string): number {
  const normalized = raw
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[,\s]/g, "");
  const n = Number(normalized);
  return Number.isFinite(n) ? n : 0;
}

/**
 * تسجيل دفعة مباشرة من صفحة الصفقة، دون المرور بـ /payments/new.
 *
 * غلاف مبسّط فوق `recordPayment` نفسها — الموزع مثبَّت من الصفقة، ونمط
 * التخصيص مثبَّت على "specific" بتخصيص واحد لهذه الصفقة. §24.4 يسمح
 * بتحصيل غير مخصص أو موزَّع على عدة صفقات؛ ذلك المسار العام يبقى في
 * /payments/new، وهذا مختصر للحالة الأشيع: دفعة لهذه الصفقة بالذات.
 */
export function PaymentQuickForm({
  dealId,
  distributorId,
  remainingBalance,
  accounts,
}: {
  dealId: string;
  distributorId: string;
  remainingBalance: string;
  accounts: { id: string; name: string }[];
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(recordPayment, initialState);
  const [amount, setAmount] = useState("");

  useEffect(() => {
    if (state.success) router.refresh();
  }, [state.success, router]);

  const parsedAmount = parseNumber(amount);
  const allocations =
    parsedAmount > 0 ? [{ deal_id: dealId, amount: parsedAmount }] : [];

  return (
    <Card className="space-y-4 p-5">
      <div>
        <h2 className="font-semibold">تسجيل دفعة</h2>
        <p className="text-muted mt-1 text-sm">
          المتبقي على الموزع لهذه الصفقة:{" "}
          <span className="num text-foreground font-medium">
            {formatMoney(remainingBalance)}
          </span>
        </p>
      </div>

      <form action={formAction} className="space-y-4">
        <input type="hidden" name="distributor_id" value={distributorId} />
        <input type="hidden" name="allocation_mode" value="specific" />
        <input
          type="hidden"
          name="allocations"
          value={JSON.stringify(allocations)}
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label htmlFor="quick_amount" className="block text-sm font-medium">
              المبلغ
            </label>
            <input
              id="quick_amount"
              name="amount"
              inputMode="decimal"
              required
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="quick_payment_date"
              className="block text-sm font-medium"
            >
              تاريخ التحصيل
            </label>
            <input
              id="quick_payment_date"
              name="payment_date"
              type="date"
              required
              defaultValue={new Date().toISOString().slice(0, 10)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="quick_method" className="block text-sm font-medium">
              طريقة الدفع
            </label>
            <select
              id="quick_method"
              name="method"
              defaultValue="cash"
              className={fieldClass}
            >
              <option value="cash">نقد</option>
              <option value="transfer">تحويل</option>
              <option value="cheque">شيك</option>
              <option value="other">أخرى</option>
            </select>
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="quick_cash_account_id"
              className="block text-sm font-medium"
            >
              حساب الإيداع{" "}
              <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <select
              id="quick_cash_account_id"
              name="cash_account_id"
              className={fieldClass}
            >
              <option value="">بدون تسجيل في الصندوق</option>
              {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="quick_reference"
              className="block text-sm font-medium"
            >
              المرجع <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input
              id="quick_reference"
              name="reference"
              type="text"
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="quick_notes" className="block text-sm font-medium">
              ملاحظة <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input
              id="quick_notes"
              name="notes"
              type="text"
              className={fieldClass}
            />
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
