"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  recordDealReturn,
  recordDealSale,
  type ActionState,
} from "@/lib/actions/deals";
import { formatMoney, formatWeight } from "@/lib/format";
import { cn } from "@/lib/utils";

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
      {pending ? "جارٍ التسجيل…" : label}
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
 * حركات الكمية على الصفقة.
 *
 * التصريف والاسترداد في مكان واحد لأنهما الطريقان الوحيدان لخروج وزن من
 * عهدة الموزع — لكن أثرهما مختلف جذرياً، والواجهة تشرح الفرق بدل أن
 * تتركه للمستخدم: التصريف يحقق ربحاً، والاسترداد يعيد بضاعة ويلغي ربحاً
 * متوقعاً، وكلاهما لا يمس النقد.
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
  const [tab, setTab] = useState<"sale" | "return">("sale");

  const [saleState, saleAction] = useActionState(recordDealSale, initialState);
  const [returnState, returnAction] = useActionState(
    recordDealReturn,
    initialState,
  );
  const [returnWeight, setReturnWeight] = useState("");

  useEffect(() => {
    if (saleState.success || returnState.success) router.refresh();
  }, [saleState.success, returnState.success, router]);

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

  const tabClass = (active: boolean) =>
    cn(
      "rounded-lg px-4 py-2 text-sm font-medium transition-colors",
      active
        ? "bg-surface-muted text-foreground"
        : "text-muted hover:text-foreground",
    );

  return (
    <Card className="p-5">
      <div className="mb-4 flex gap-1">
        <button
          type="button"
          onClick={() => setTab("sale")}
          className={tabClass(tab === "sale")}
        >
          تسجيل تصريف
        </button>
        <button
          type="button"
          onClick={() => setTab("return")}
          className={tabClass(tab === "return")}
        >
          استرداد كمية
        </button>
      </div>

      {tab === "sale" ? (
        <form action={saleAction} className="space-y-4">
          <input type="hidden" name="deal_id" value={dealId} />

          <p className="text-muted text-sm">
            تسجيل ما صرّفه الموزع فعلاً. هذه الحركة تحوّل الربح من متوقع إلى
            محقق، ولا تعني أن الموزع سدّد — التحصيل حركة منفصلة.
          </p>

          <div className="grid gap-4 sm:grid-cols-3">
            <div className="space-y-1.5">
              <label
                htmlFor="sale_weight"
                className="block text-sm font-medium"
              >
                الوزن المصرَّف
              </label>
              <input
                id="sale_weight"
                name="weight_g"
                inputMode="decimal"
                required
                className={`${fieldClass} num`}
              />
              <p className="text-muted text-xs">
                المتاح: {formatWeight(openWeight)}
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
              <label htmlFor="sale_notes" className="block text-sm font-medium">
                ملاحظة
              </label>
              <input
                id="sale_notes"
                name="notes"
                type="text"
                className={fieldClass}
              />
            </div>
          </div>

          {saleState.error ? <ErrorNote message={saleState.error} /> : null}

          <div className="flex justify-end">
            <SubmitButton label="تسجيل التصريف" />
          </div>
        </form>
      ) : (
        <form action={returnAction} className="space-y-4">
          <input type="hidden" name="deal_id" value={dealId} />

          <p className="text-muted text-sm">
            إرجاع كمية غير مصرَّفة إلى المخزون. الاسترداد ليس سداداً: الكمية
            تعود بتكلفتها الأصلية وتنخفض قيمة الصفقة والربح المتوقع بحصتها،
            بينما يبقى المبلغ المسدد كما هو.
          </p>

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
              <label
                htmlFor="return_date"
                className="block text-sm font-medium"
              >
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
                  <dt className="text-muted text-xs">رأس مال يعود للمخزون</dt>
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
                المبلغ المسدد لا يتغير — الاسترداد ليس تحصيلاً.
              </p>
            </div>
          ) : null}

          {returnState.error ? <ErrorNote message={returnState.error} /> : null}

          <div className="flex justify-end">
            <SubmitButton label="تسجيل الاسترداد" />
          </div>
        </form>
      )}
    </Card>
  );
}
