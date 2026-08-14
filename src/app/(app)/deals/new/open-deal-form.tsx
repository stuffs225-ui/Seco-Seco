"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useMemo, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import { openDeal, type ActionState } from "@/lib/actions/deals";
import { formatMoney, formatPerGram, formatWeight } from "@/lib/format";

type Distributor = { id: string; code: string; name: string };
type Lot = {
  lot_id: string;
  lot_no: string;
  item_name: string;
  on_hand_weight_g: string;
  cost_per_g: string;
};

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
      {pending ? "جارٍ التسليم…" : "تسليم وإنشاء الصفقة"}
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

export function OpenDealForm({
  distributors,
  lots,
}: {
  distributors: Distributor[];
  lots: Lot[];
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(openDeal, initialState);

  const [lotId, setLotId] = useState("");
  const [weight, setWeight] = useState("");
  const [value, setValue] = useState("");

  useEffect(() => {
    if (state.success) router.push(`/deals/${state.success}`);
  }, [state.success, router]);

  const selectedLot = lots.find((lot) => lot.lot_id === lotId);

  /*
    معاينة اقتصاديات الصفقة قبل التسليم (§5.4).

    القيم النهائية تحسبها open_deal في قاعدة البيانات؛ هذه معاينة تساعد
    المستخدم على تسعير الصفقة قبل تثبيتها، ولا تُرسل ولا تُخزَّن.
  */
  const preview = useMemo(() => {
    if (!selectedLot) return null;

    const w = parseNumber(weight);
    const v = parseNumber(value);
    if (w <= 0) return null;

    const costPerG = Number(selectedLot.cost_per_g);
    const capitalCost = w * costPerG;
    const valuePerG = v / w;

    return {
      capitalCost,
      expectedProfit: v - capitalCost,
      valuePerG,
      profitPerG: valuePerG - costPerG,
      exceedsStock: w > Number(selectedLot.on_hand_weight_g),
      belowCost: v > 0 && v < capitalCost,
    };
  }, [selectedLot, weight, value]);

  return (
    <form action={formAction} className="space-y-6">
      <Card className="space-y-4 p-5">
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
            <label htmlFor="lot_id" className="block text-sm font-medium">
              الدفعة
            </label>
            <select
              id="lot_id"
              name="lot_id"
              required
              value={lotId}
              onChange={(e) => setLotId(e.target.value)}
              className={fieldClass}
            >
              <option value="">اختر الدفعة</option>
              {lots.map((lot) => (
                <option key={lot.lot_id} value={lot.lot_id}>
                  {lot.lot_no} — {lot.item_name} (متاح{" "}
                  {formatWeight(lot.on_hand_weight_g)})
                </option>
              ))}
            </select>
            <p className="text-muted text-xs">
              الصفقة من دفعة واحدة. للتسليم من دفعتين أنشئ صفقتين.
            </p>
          </div>

          <div className="space-y-1.5">
            <label htmlFor="weight_g" className="block text-sm font-medium">
              الوزن المسلَّم
            </label>
            <input
              id="weight_g"
              name="weight_g"
              inputMode="decimal"
              required
              value={weight}
              onChange={(e) => setWeight(e.target.value)}
              placeholder="500"
              className={`${fieldClass} num`}
            />
            {selectedLot ? (
              <p className="text-muted text-xs">
                المتاح في {selectedLot.lot_no}:{" "}
                {formatWeight(selectedLot.on_hand_weight_g)}
              </p>
            ) : null}
          </div>

          <div className="space-y-1.5">
            <label htmlFor="deal_value" className="block text-sm font-medium">
              قيمة الصفقة
            </label>
            <input
              id="deal_value"
              name="deal_value"
              inputMode="decimal"
              required
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder="12000"
              className={`${fieldClass} num`}
            />
            <p className="text-muted text-xs">
              المبلغ المتفق أن يسدده الموزع بعد التصريف
            </p>
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="delivery_date"
              className="block text-sm font-medium"
            >
              تاريخ التسليم
            </label>
            <input
              id="delivery_date"
              name="delivery_date"
              type="date"
              required
              defaultValue={new Date().toISOString().slice(0, 10)}
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="due_date" className="block text-sm font-medium">
              تاريخ الاستحقاق{" "}
              <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input
              id="due_date"
              name="due_date"
              type="date"
              className={`${fieldClass} num`}
            />
          </div>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="notes" className="block text-sm font-medium">
            ملاحظات
          </label>
          <textarea id="notes" name="notes" rows={2} className={fieldClass} />
        </div>
      </Card>

      {preview ? (
        <Card className="border-primary/30 bg-primary/5 p-5">
          <h2 className="font-semibold">معاينة اقتصاديات الصفقة</h2>
          <dl className="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <dt className="text-muted text-xs">تكلفة رأس المال</dt>
              <dd className="num mt-1 font-medium">
                {formatMoney(preview.capitalCost)}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">الربح المتوقع</dt>
              <dd className="num mt-1 font-medium">
                {formatMoney(preview.expectedProfit)}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">قيمة الجرام للموزع</dt>
              <dd className="num mt-1 font-medium">
                {formatPerGram(preview.valuePerG)}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">الربح المتوقع للجرام</dt>
              <dd className="num mt-1 font-medium">
                {formatPerGram(preview.profitPerG)}
              </dd>
            </div>
          </dl>

          {preview.exceedsStock ? (
            <p className="text-negative mt-3 text-sm">
              الوزن المطلوب يتجاوز المتاح في الدفعة — سيُرفض التسليم.
            </p>
          ) : null}
          {preview.belowCost ? (
            <p className="text-warning mt-3 text-sm">
              قيمة الصفقة أقل من تكلفة الكمية: الربح المتوقع سالب.
            </p>
          ) : null}

          <p className="text-muted mt-3 text-xs">
            القيم النهائية تحسبها قاعدة البيانات عند التسليم؛ هذه معاينة فقط.
          </p>
        </Card>
      ) : null}

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
