"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { recordPayment, type ActionState } from "@/lib/actions/payments";
import { formatDate, formatMoney } from "@/lib/format";
import { cn } from "@/lib/utils";

type Distributor = { id: string; code: string; name: string };
type Deal = {
  deal_id: string;
  deal_no: string;
  distributor_id: string;
  delivery_date: string | null;
  remaining_balance: string;
};
type Account = { id: string; name: string };

type AllocationMode = "unallocated" | "oldest_first" | "specific";

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
      {pending ? "جارٍ التسجيل…" : "تسجيل التحصيل"}
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

/** الطرق الثلاث التي يسمح بها §24.4 لتخصيص دفعة. */
const MODES: { value: AllocationMode; label: string; hint: string }[] = [
  {
    value: "oldest_first",
    label: "على أقدم الاستحقاقات",
    hint: "يوزّع المبلغ على الصفقات الأقدم أولاً حتى ينفد",
  },
  {
    value: "specific",
    label: "توزيع يدوي",
    hint: "تحدد المبلغ لكل صفقة بنفسك",
  },
  {
    value: "unallocated",
    label: "بلا تخصيص",
    hint: "يبقى رصيداً مفتوحاً للموزع تخصصه لاحقاً",
  },
];

export function PaymentForm({
  distributors,
  deals,
  accounts,
}: {
  distributors: Distributor[];
  deals: Deal[];
  accounts: Account[];
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(recordPayment, initialState);

  const [distributorId, setDistributorId] = useState("");
  const [amount, setAmount] = useState("");
  const [mode, setMode] = useState<AllocationMode>("oldest_first");
  const [manual, setManual] = useState<Record<string, string>>({});

  useEffect(() => {
    if (state.success) router.push("/payments");
  }, [state.success, router]);

  const distributorDeals = deals.filter(
    (deal) => deal.distributor_id === distributorId,
  );

  const allocations =
    mode === "specific"
      ? distributorDeals
          .map((deal) => ({
            deal_id: deal.deal_id,
            amount: parseNumber(manual[deal.deal_id] ?? ""),
          }))
          .filter((a) => a.amount > 0)
      : [];

  const allocatedTotal = allocations.reduce((sum, a) => sum + a.amount, 0);
  const paymentAmount = parseNumber(amount);
  const overAllocated = allocatedTotal > paymentAmount && paymentAmount > 0;

  return (
    <form action={formAction} className="space-y-6">
      <input
        type="hidden"
        name="allocations"
        value={JSON.stringify(allocations)}
      />
      <input type="hidden" name="allocation_mode" value={mode} />

      <Card className="space-y-4 p-5">
        <h2 className="font-semibold">بيانات التحصيل</h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label
              htmlFor="distributor_id"
              className="block text-sm font-medium"
            >
              الموزع
            </label>
            <select
              id="distributor_id"
              name="distributor_id"
              required
              value={distributorId}
              onChange={(e) => {
                setDistributorId(e.target.value);
                setManual({});
              }}
              className={fieldClass}
            >
              <option value="">اختر الموزع</option>
              {distributors.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name} ({d.code})
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label htmlFor="amount" className="block text-sm font-medium">
              المبلغ المحصَّل
            </label>
            <input
              id="amount"
              name="amount"
              inputMode="decimal"
              required
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="payment_date" className="block text-sm font-medium">
              تاريخ التحصيل
            </label>
            <input
              id="payment_date"
              name="payment_date"
              type="date"
              required
              defaultValue={new Date().toISOString().slice(0, 10)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="method" className="block text-sm font-medium">
              طريقة الدفع
            </label>
            <select
              id="method"
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
            <label htmlFor="reference" className="block text-sm font-medium">
              المرجع <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input
              id="reference"
              name="reference"
              type="text"
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="cash_account_id"
              className="block text-sm font-medium"
            >
              حساب الإيداع{" "}
              <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <select
              id="cash_account_id"
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
        </div>

        <div className="space-y-1.5">
          <label htmlFor="notes" className="block text-sm font-medium">
            ملاحظات
          </label>
          <textarea id="notes" name="notes" rows={2} className={fieldClass} />
        </div>
      </Card>

      <Card className="space-y-4 p-5">
        <div>
          <h2 className="font-semibold">تخصيص الدفعة</h2>
          <p className="text-muted mt-1 text-sm">
            الدفعة حدث نقدي على مستوى الموزع. ربطها بصفقة قرار منفصل قابل للعكس
            لاحقاً دون حذف التحصيل نفسه.
          </p>
        </div>

        <div className="grid gap-2 sm:grid-cols-3">
          {MODES.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => setMode(option.value)}
              className={cn(
                "rounded-lg border p-3 text-start transition-colors",
                mode === option.value
                  ? "border-primary bg-primary/5"
                  : "border-border hover:border-muted",
              )}
            >
              <div className="text-sm font-medium">{option.label}</div>
              <div className="text-muted mt-1 text-xs">{option.hint}</div>
            </button>
          ))}
        </div>

        {mode === "specific" ? (
          !distributorId ? (
            <p className="text-muted text-sm">اختر الموزع أولاً.</p>
          ) : distributorDeals.length === 0 ? (
            <p className="text-muted text-sm">
              لا توجد صفقات مفتوحة عليها رصيد لهذا الموزع.
            </p>
          ) : (
            <div className="space-y-3">
              {distributorDeals.map((deal) => (
                <div
                  key={deal.deal_id}
                  className="grid items-center gap-3 sm:grid-cols-[1fr_auto_10rem]"
                >
                  <div>
                    <div className="num text-sm font-medium">
                      {deal.deal_no}
                    </div>
                    <div className="text-muted num text-xs">
                      تسليم {formatDate(deal.delivery_date)}
                    </div>
                  </div>
                  <div className="text-muted num text-sm">
                    المتبقي {formatMoney(deal.remaining_balance)}
                  </div>
                  <input
                    inputMode="decimal"
                    value={manual[deal.deal_id] ?? ""}
                    onChange={(e) =>
                      setManual((prev) => ({
                        ...prev,
                        [deal.deal_id]: e.target.value,
                      }))
                    }
                    placeholder="0"
                    className={`${fieldClass} num`}
                  />
                </div>
              ))}

              <div className="border-border flex justify-between border-t pt-3 text-sm">
                <span className="text-muted">إجمالي المخصص</span>
                <span
                  className={cn(
                    "num font-medium",
                    overAllocated && "text-negative",
                  )}
                >
                  {formatMoney(allocatedTotal)}
                  {paymentAmount > 0 ? (
                    <span className="text-muted">
                      {" "}
                      من {formatMoney(paymentAmount)}
                    </span>
                  ) : null}
                </span>
              </div>

              {overAllocated ? (
                <p className="text-negative text-sm">
                  المخصص يتجاوز قيمة الدفعة — سيُرفض التسجيل.
                </p>
              ) : null}
            </div>
          )
        ) : null}
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
