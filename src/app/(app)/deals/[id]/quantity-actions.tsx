"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { recordDealReturn, type ActionState } from "@/lib/actions/deals";
import { formatMoney, formatWeight } from "@/lib/format";
import { cn } from "@/lib/utils";

const initialState: ActionState = { error: null };

const fieldClass =
  "border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-2 text-sm outline-none";

type Restock = "restock" | "self";

const RESTOCK_OPTIONS: { value: Restock; label: string; effect: string }[] = [
  {
    value: "restock",
    label: "استرداد للمخزون",
    effect: "تعود الكمية قابلة للبيع من جديد في نفس الدفعة",
  },
  {
    value: "self",
    label: "استرداد لنفسي",
    effect: "تخرج الكمية نهائياً — لن تعود للمخزون ولن تكون قابلة للبيع",
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
      {pending ? "جارٍ التسجيل…" : "تسجيل الاسترداد"}
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

function ErrorNote({ message }: { message: string }) {
  return (
    <p
      role="alert"
      className="text-negative border-negative/30 bg-negative/5 rounded-lg border px-4 py-3 text-sm"
    >
      {message}
    </p>
  );
}

/**
 * استرداد كمية غير مصرَّفة من الموزع (§18.3).
 *
 * لا تسجيل تصريف هنا: المالك لا يتتبع كمية التصريف الفعلية، يهمه
 * التحصيل فقط — الربح يتحقق تلقائياً عند الإغلاق بضغطة واحدة. الاسترداد
 * وحده حركة يدوية على الكمية، واختيار وجهته (مخزون أو لنفسي) يحدد فقط
 * أثر المخزون؛ أثر التكلفة والربح المتوقع على الصفقة واحد في الحالتين.
 */
export function QuantityActions({
  dealId,
  openWeight,
  costPerGram,
  expectedProfitPerGram,
}: {
  dealId: string;
  openWeight: string;
  costPerGram: string;
  expectedProfitPerGram: string;
}) {
  const router = useRouter();
  const [returnState, returnAction] = useActionState(
    recordDealReturn,
    initialState,
  );
  const [returnWeight, setReturnWeight] = useState("");
  const [restock, setRestock] = useState<Restock>("restock");

  useEffect(() => {
    if (returnState.success) router.refresh();
  }, [returnState.success, router]);

  /*
    معاينة أثر الاسترداد قبل الحفظ (§5.4).

    القيم من اقتصاديات الصفقة المثبَّتة، وقاعدة البيانات هي من يحسبها
    فعلياً عند الحفظ. المعاينة تجعل أثر §18.3 مرئياً قبل التنفيذ: كم
    يعود رأس مال وكم يُلغى ربح متوقع وكم تنخفض قيمة الصفقة.
  */
  const returnPreview = (() => {
    const w = parseNumber(returnWeight);
    if (w <= 0) return null;
    const cost = w * Number(costPerGram);
    const profit = w * Number(expectedProfitPerGram);
    return {
      cost,
      profit,
      reduction: cost + profit,
      exceeds: w > Number(openWeight),
    };
  })();

  return (
    <Card className="p-5">
      <form action={returnAction} className="space-y-4">
        <input type="hidden" name="deal_id" value={dealId} />
        <input
          type="hidden"
          name="restock"
          value={restock === "restock" ? "true" : "false"}
        />

        <p className="text-muted text-sm">
          إرجاع كمية غير مصرَّفة من عهدة الموزع. الاسترداد ليس سداداً: تنخفض
          قيمة الصفقة والربح المتوقع بحصة الكمية، بينما يبقى المبلغ المسدد كما
          هو.
        </p>

        <div className="grid gap-2 sm:grid-cols-2">
          {RESTOCK_OPTIONS.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => setRestock(option.value)}
              className={cn(
                "rounded-lg border p-3 text-start transition-colors",
                restock === option.value
                  ? "border-primary bg-primary/5"
                  : "border-border bg-surface hover:border-muted",
              )}
            >
              <div className="text-sm font-medium">{option.label}</div>
              <div className="text-muted mt-1 text-xs">{option.effect}</div>
            </button>
          ))}
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-1.5">
            <label
              htmlFor="return_weight"
              className="block text-sm font-medium"
            >
              الوزن المسترد
            </label>
            <input
              id="return_weight"
              name="weight_g"
              inputMode="decimal"
              required
              value={returnWeight}
              onChange={(e) => setReturnWeight(e.target.value)}
              className={`${fieldClass} num`}
            />
            <p className="text-muted text-xs">
              غير المصرَّف: {formatWeight(openWeight)}
            </p>
          </div>

          <div className="space-y-1.5">
            <label htmlFor="return_date" className="block text-sm font-medium">
              تاريخ الاسترداد
            </label>
            <input
              id="return_date"
              name="return_date"
              type="date"
              required
              defaultValue={new Date().toISOString().slice(0, 10)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="reason" className="block text-sm font-medium">
              السبب
            </label>
            <input
              id="reason"
              name="reason"
              type="text"
              className={fieldClass}
            />
          </div>
        </div>

        {returnPreview ? (
          <div className="border-border bg-surface-muted rounded-lg border p-4">
            <div className="text-sm font-medium">أثر الاسترداد</div>
            <dl className="mt-2 grid gap-3 sm:grid-cols-3">
              <div>
                <dt className="text-muted text-xs">
                  {restock === "restock"
                    ? "رأس مال يعود للمخزون"
                    : "رأس مال يخرج نهائياً"}
                </dt>
                <dd className="num mt-0.5 font-medium">
                  {formatMoney(returnPreview.cost)}
                </dd>
              </div>
              <div>
                <dt className="text-muted text-xs">ربح متوقع يُلغى</dt>
                <dd className="num mt-0.5 font-medium">
                  {formatMoney(returnPreview.profit)}
                </dd>
              </div>
              <div>
                <dt className="text-muted text-xs">تخفيض قيمة الصفقة</dt>
                <dd className="num mt-0.5 font-medium">
                  {formatMoney(returnPreview.reduction)}
                </dd>
              </div>
            </dl>
            {returnPreview.exceeds ? (
              <p className="text-negative mt-3 text-sm">
                الوزن يتجاوز الكمية غير المصرَّفة — سيُرفض الاسترداد.
              </p>
            ) : null}
            <p className="text-muted mt-2 text-xs">
              {restock === "restock"
                ? "المبلغ المسدد لا يتغير — الاسترداد ليس تحصيلاً."
                : "المبلغ المسدد لا يتغير، والكمية لن تكون قابلة للبيع لاحقاً."}
            </p>
          </div>
        ) : null}

        {returnState.error ? <ErrorNote message={returnState.error} /> : null}

        <div className="flex justify-end">
          <SubmitButton />
        </div>
      </form>
    </Card>
  );
}
