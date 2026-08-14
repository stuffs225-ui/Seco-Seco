"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  resolveDistributorCredit,
  type ActionState,
} from "@/lib/actions/payments";
import { formatMoney } from "@/lib/format";

type Method =
  "refund" | "transfer_to_deal" | "keep_as_credit" | "authorized_adjustment";

const initialState: ActionState = { error: null };

const fieldClass =
  "border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-2 text-sm outline-none";

/** الطرق الأربع في §24.5 وأثر كل منها. */
const METHODS: { value: Method; label: string; effect: string }[] = [
  {
    value: "refund",
    label: "رد المبلغ",
    effect: "يخرج نقداً من الصندوق ويعود المال للموزع",
  },
  {
    value: "transfer_to_deal",
    label: "نقل لصفقة أخرى",
    effect: "ينتقل الرصيد لصفقة أخرى لنفس الموزع دون حركة نقد",
  },
  {
    value: "keep_as_credit",
    label: "إبقاؤه رصيداً دائناً",
    effect: "يبقى معلناً كالتزام على الشركة لاستخدامه لاحقاً",
  },
  {
    value: "authorized_adjustment",
    label: "تسوية معتمدة",
    effect: "ترفع القيمة التجارية للصفقة بسبب موثق",
  },
];

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? "جارٍ المعالجة…" : "تنفيذ المعالجة"}
    </button>
  );
}

export function CreditResolution({
  dealId,
  unresolvedAmount,
  siblingDeals,
  accounts,
}: {
  dealId: string;
  unresolvedAmount: string;
  siblingDeals: { deal_id: string; deal_no: string }[];
  accounts: { id: string; name: string }[];
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(
    resolveDistributorCredit,
    initialState,
  );
  const [method, setMethod] = useState<Method>("refund");

  useEffect(() => {
    if (state.success) router.refresh();
  }, [state.success, router]);

  return (
    <Card className="border-warning/40 bg-warning/5 p-5">
      <h2 className="text-warning font-semibold">
        رصيد دائن للموزع يحتاج معالجة
      </h2>
      <p className="text-muted mt-1 text-sm">
        سدّد الموزع أكثر من القيمة المعدلة للصفقة بمقدار{" "}
        <span className="num text-foreground font-medium">
          {formatMoney(unresolvedAmount)}
        </span>
        . هذا مال الموزع لا إيراد للشركة، ولا يُسجَّل ربحاً في أي حالة.
      </p>

      <form action={formAction} className="mt-4 space-y-4">
        <input type="hidden" name="deal_id" value={dealId} />
        <input type="hidden" name="method" value={method} />

        <div className="grid gap-2 sm:grid-cols-2">
          {METHODS.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => setMethod(option.value)}
              className={`rounded-lg border p-3 text-start transition-colors ${
                method === option.value
                  ? "border-primary bg-primary/5"
                  : "border-border bg-surface hover:border-muted"
              }`}
            >
              <div className="text-sm font-medium">{option.label}</div>
              <div className="text-muted mt-1 text-xs">{option.effect}</div>
            </button>
          ))}
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label
              htmlFor="credit_amount"
              className="block text-sm font-medium"
            >
              المبلغ
            </label>
            <input
              id="credit_amount"
              name="amount"
              inputMode="decimal"
              required
              defaultValue={unresolvedAmount}
              className={`${fieldClass} num`}
            />
          </div>

          {method === "transfer_to_deal" ? (
            <div className="space-y-1.5">
              <label
                htmlFor="target_deal_id"
                className="block text-sm font-medium"
              >
                الصفقة الهدف
              </label>
              <select
                id="target_deal_id"
                name="target_deal_id"
                required
                className={fieldClass}
              >
                <option value="">اختر صفقة</option>
                {siblingDeals.map((deal) => (
                  <option key={deal.deal_id} value={deal.deal_id}>
                    {deal.deal_no}
                  </option>
                ))}
              </select>
              {siblingDeals.length === 0 ? (
                <p className="text-muted text-xs">
                  لا توجد صفقات أخرى مفتوحة لهذا الموزع.
                </p>
              ) : null}
            </div>
          ) : null}

          {method === "refund" ? (
            <div className="space-y-1.5">
              <label
                htmlFor="credit_account"
                className="block text-sm font-medium"
              >
                حساب الصرف
              </label>
              <select
                id="credit_account"
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
          ) : null}
        </div>

        <div className="space-y-1.5">
          <label htmlFor="credit_reason" className="block text-sm font-medium">
            السبب <span className="text-negative">*</span>
          </label>
          <input
            id="credit_reason"
            name="reason"
            required
            placeholder="سبب المعالجة — إلزامي ويظهر في سجل التدقيق"
            className={fieldClass}
          />
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
