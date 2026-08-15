"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  correctPurchaseLot,
  createPurchaseLot,
  type ActionState,
} from "@/lib/actions/inventory";
import { formatMoney, formatPerGram, formatWeight } from "@/lib/format";

type Item = { id: string; code: string; name: string };
type Supplier = { id: string; name: string };
type Expense = {
  expense_type: string;
  amount: string;
  include_in_cost: boolean;
};

/** قيم الدفعة القديمة المطلوب تصحيحها — تُعبّئ النموذج وتُبنى منها لوحة المقارنة. */
type CorrectionSource = {
  oldLotId: string;
  oldLotNo: string;
  weightG: string;
  purchaseValue: string;
  costPerGram: string;
  totalCost: string;
  itemId: string;
  supplierId: string;
  purchaseDate: string;
  invoiceRef: string;
  notes: string;
};

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

/** يقبل الأرقام العربية والفواصل الألفية كما قد يكتبها المستخدم. */
function parseNumber(raw: string): number {
  const normalized = raw
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[,\s]/g, "");
  const n = Number(normalized);
  return Number.isFinite(n) ? n : 0;
}

export function PurchaseForm({
  items,
  suppliers,
  correction,
}: {
  items: Item[];
  suppliers: Supplier[];
  /** وجوده يحوّل النموذج لوضع تصحيح دفعة قائمة بدل إنشاء واحدة جديدة. */
  correction?: CorrectionSource;
}) {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const isCorrection = correction != null;

  const [state, formAction] = useActionState(
    isCorrection ? correctPurchaseLot : createPurchaseLot,
    initialState,
  );

  const [weight, setWeight] = useState(correction?.weightG ?? "");
  const [value, setValue] = useState(correction?.purchaseValue ?? "");
  const [expenses, setExpenses] = useState<Expense[]>([]);

  /*
    خطوة التأكيد قبل اعتماد التصحيح — طلب صريح: النموذج لا يحفظ عند
    أول ضغط، بل يعرض مقارنة قبل/بعد ويطلب تأكيداً ثانياً. تغيير الوزن
    أو القيمة بعد المراجعة يلغي التأكيد فيعرض القيم الجديدة لا القديمة.
  */
  const [confirmed, setConfirmed] = useState(false);

  useEffect(() => {
    if (state.success) router.push("/inventory");
  }, [state.success, router]);

  /*
    معاينة تكلفة الجرام قبل الحفظ.

    هذا العرض الوحيد الذي تحسبه الواجهة، وهو مقصود: الخطة تطلب معاينة
    آلية قبل الحفظ (§5.4). القيمة هنا لا تُرسل ولا تُخزَّن — الحفظ يمر
    عبر create_purchase_lot وقاعدة البيانات هي من يحسب cost_per_g فعلياً،
    وما يظهر بعد الحفظ هو قيمتها هي.
  */
  const preview = useMemo(() => {
    const w = parseNumber(weight);
    const v = parseNumber(value);
    const capitalized = expenses
      .filter((e) => e.include_in_cost)
      .reduce((sum, e) => sum + parseNumber(e.amount), 0);

    if (w <= 0) return null;

    return {
      totalCost: v + capitalized,
      capitalized,
      costPerGram: (v + capitalized) / w,
    };
  }, [weight, value, expenses]);

  const validExpenses = expenses
    .filter((e) => e.expense_type.trim() !== "" && parseNumber(e.amount) > 0)
    .map((e) => ({
      expense_type: e.expense_type.trim(),
      amount: parseNumber(e.amount),
      include_in_cost: e.include_in_cost,
    }));

  return (
    <form ref={formRef} action={formAction} className="space-y-6">
      <input
        type="hidden"
        name="expenses"
        value={JSON.stringify(validExpenses)}
      />
      {isCorrection ? (
        <input type="hidden" name="old_lot_id" value={correction.oldLotId} />
      ) : null}

      <Card className="space-y-4 p-5">
        <h2 className="font-semibold">
          {isCorrection ? `تصحيح دفعة ${correction.oldLotNo}` : "بيانات الشراء"}
        </h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label htmlFor="item_id" className="block text-sm font-medium">
              الصنف
            </label>
            <select
              id="item_id"
              name="item_id"
              required
              defaultValue={correction?.itemId ?? ""}
              className={fieldClass}
            >
              <option value="">اختر الصنف</option>
              {items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} ({item.code})
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label htmlFor="supplier_id" className="block text-sm font-medium">
              المورد <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <select
              id="supplier_id"
              name="supplier_id"
              defaultValue={correction?.supplierId ?? ""}
              className={fieldClass}
            >
              <option value="">بدون مورد محدد</option>
              {suppliers.map((supplier) => (
                <option key={supplier.id} value={supplier.id}>
                  {supplier.name}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="purchase_date"
              className="block text-sm font-medium"
            >
              تاريخ الشراء
            </label>
            <input
              id="purchase_date"
              name="purchase_date"
              type="date"
              required
              defaultValue={
                correction?.purchaseDate ??
                new Date().toISOString().slice(0, 10)
              }
              className={`${fieldClass} num`}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="invoice_ref" className="block text-sm font-medium">
              مرجع الفاتورة{" "}
              <span className="text-muted font-normal">(اختياري)</span>
            </label>
            <input
              id="invoice_ref"
              name="invoice_ref"
              type="text"
              defaultValue={correction?.invoiceRef ?? ""}
              className={fieldClass}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="weight_g" className="block text-sm font-medium">
              الوزن بالجرام
            </label>
            <input
              id="weight_g"
              name="weight_g"
              inputMode="decimal"
              required
              value={weight}
              onChange={(e) => {
                setWeight(e.target.value);
                setConfirmed(false);
              }}
              placeholder="1200"
              className={`${fieldClass} num`}
            />
            {isCorrection ? (
              <p className="text-muted text-xs">
                كان: {formatWeight(correction.weightG)}
              </p>
            ) : null}
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="purchase_value"
              className="block text-sm font-medium"
            >
              قيمة الشراء
            </label>
            <input
              id="purchase_value"
              name="purchase_value"
              inputMode="decimal"
              required
              value={value}
              onChange={(e) => {
                setValue(e.target.value);
                setConfirmed(false);
              }}
              placeholder="21000"
              className={`${fieldClass} num`}
            />
            {isCorrection ? (
              <p className="text-muted text-xs">
                كانت: {formatMoney(correction.purchaseValue)}
              </p>
            ) : null}
          </div>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="notes" className="block text-sm font-medium">
            ملاحظات
          </label>
          <textarea
            id="notes"
            name="notes"
            rows={2}
            defaultValue={correction?.notes ?? ""}
            className={fieldClass}
          />
        </div>

        {isCorrection ? (
          <div className="space-y-1.5">
            <label htmlFor="reason" className="block text-sm font-medium">
              سبب التصحيح <span className="text-negative">*</span>
            </label>
            <input
              id="reason"
              name="reason"
              required
              placeholder="سبب التصحيح — إلزامي ويظهر في سجل التدقيق"
              onChange={() => setConfirmed(false)}
              className={fieldClass}
            />
          </div>
        ) : null}
      </Card>

      <Card className="space-y-4 p-5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 className="font-semibold">المصاريف المرتبطة</h2>
            <p className="text-muted mt-1 text-sm">
              المصروف المفعَّل يدخل في تكلفة الدفعة ويرفع تكلفة الجرام. غير
              المفعَّل يُحفظ كمصروف تشغيلي يخصم من الربح لاحقاً.
            </p>
          </div>
          <button
            type="button"
            onClick={() =>
              setExpenses((prev) => [
                ...prev,
                { expense_type: "", amount: "", include_in_cost: true },
              ])
            }
            className="border-border rounded-lg border px-3 py-1.5 text-sm"
          >
            إضافة مصروف
          </button>
        </div>

        {expenses.length === 0 ? (
          <p className="text-muted text-sm">لا توجد مصاريف مضافة.</p>
        ) : (
          <div className="space-y-3">
            {expenses.map((expense, index) => (
              <div
                key={index}
                className="border-border grid items-end gap-3 rounded-lg border p-3 sm:grid-cols-[1fr_1fr_auto_auto] sm:border-0 sm:p-0"
              >
                <input
                  type="text"
                  value={expense.expense_type}
                  onChange={(e) =>
                    setExpenses((prev) =>
                      prev.map((item, i) =>
                        i === index
                          ? { ...item, expense_type: e.target.value }
                          : item,
                      ),
                    )
                  }
                  placeholder="نوع المصروف (نقل، تخزين…)"
                  className={fieldClass}
                />
                <input
                  inputMode="decimal"
                  value={expense.amount}
                  onChange={(e) =>
                    setExpenses((prev) =>
                      prev.map((item, i) =>
                        i === index
                          ? { ...item, amount: e.target.value }
                          : item,
                      ),
                    )
                  }
                  placeholder="المبلغ"
                  className={`${fieldClass} num`}
                />
                <label className="flex items-center gap-2 py-2 text-sm whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={expense.include_in_cost}
                    onChange={(e) =>
                      setExpenses((prev) =>
                        prev.map((item, i) =>
                          i === index
                            ? { ...item, include_in_cost: e.target.checked }
                            : item,
                        ),
                      )
                    }
                  />
                  يدخل في التكلفة
                </label>
                <button
                  type="button"
                  onClick={() =>
                    setExpenses((prev) => prev.filter((_, i) => i !== index))
                  }
                  className="text-negative px-2 py-2 text-sm"
                >
                  حذف
                </button>
              </div>
            ))}
          </div>
        )}
      </Card>

      {preview && !isCorrection ? (
        <Card className="border-primary/30 bg-primary/5 p-5">
          <h2 className="font-semibold">معاينة قبل الحفظ</h2>
          <dl className="mt-3 grid gap-4 sm:grid-cols-3">
            <div>
              <dt className="text-muted text-xs">المصاريف المرسملة</dt>
              <dd className="num mt-1 font-medium">
                {formatMoney(preview.capitalized)}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">التكلفة الإجمالية للدفعة</dt>
              <dd className="num mt-1 font-medium">
                {formatMoney(preview.totalCost)}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">تكلفة الجرام</dt>
              <dd className="num mt-1 text-lg font-semibold">
                {formatPerGram(preview.costPerGram)}
              </dd>
            </div>
          </dl>
          <p className="text-muted mt-3 text-xs">
            القيمة النهائية تحسبها قاعدة البيانات عند الحفظ؛ هذه معاينة فقط.
          </p>
        </Card>
      ) : null}

      {/*
        لوحة قبل/بعد للتصحيح — الخطوة التي طلبها المالك صراحة: لا حفظ
        عند أول ضغط، بل مراجعة الأثر ثم تأكيد منفصل. القيم النهائية
        تحسبها قاعدة البيانات عند الحفظ الفعلي؛ هذه معاينة فقط.
      */}
      {isCorrection && preview ? (
        <Card className="border-warning/40 bg-warning/5 p-5">
          <h2 className="font-semibold">مقارنة قبل ← بعد</h2>
          <dl className="mt-3 grid gap-4 sm:grid-cols-3">
            <div>
              <dt className="text-muted text-xs">الوزن</dt>
              <dd className="num mt-1 font-medium">
                {formatWeight(correction.weightG)} ←{" "}
                <span className="font-semibold">{formatWeight(weight)}</span>
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">التكلفة الإجمالية</dt>
              <dd className="num mt-1 font-medium">
                {formatMoney(correction.totalCost)} ←{" "}
                <span className="font-semibold">
                  {formatMoney(preview.totalCost)}
                </span>
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">تكلفة الجرام</dt>
              <dd className="num mt-1 font-medium">
                {formatPerGram(correction.costPerGram)} ←{" "}
                <span className="font-semibold">
                  {formatPerGram(preview.costPerGram)}
                </span>
              </dd>
            </div>
          </dl>

          {confirmed ? (
            <p className="text-warning mt-4 text-sm font-medium">
              الدفعة القديمة ستُلغى نهائياً وتُستبدل بدفعة جديدة بهذه القيم —
              هذا الإجراء لا يمكن التراجع عنه بعد الحفظ.
            </p>
          ) : null}
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

      <div className="flex justify-end gap-3">
        {isCorrection ? (
          confirmed ? (
            <>
              <button
                type="button"
                onClick={() => setConfirmed(false)}
                className="border-border rounded-lg border px-5 py-2.5 text-sm font-medium"
              >
                تراجع
              </button>
              <SubmitButton label="تأكيد وحفظ التصحيح" />
            </>
          ) : (
            <button
              type="button"
              onClick={() => {
                if (formRef.current?.reportValidity()) setConfirmed(true);
              }}
              className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90"
            >
              مراجعة التصحيح قبل الحفظ
            </button>
          )
        ) : (
          <SubmitButton label="حفظ الشراء وإنشاء الدفعة" />
        )}
      </div>
    </form>
  );
}
