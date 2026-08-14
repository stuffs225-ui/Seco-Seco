"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";

import { Card } from "@/components/domain/layout";
import {
  closeDeal,
  recordCommercialAdjustment,
  recordWeightAdjustment,
  reopenDeal,
  type ActionState,
} from "@/lib/actions/settlement";
import { formatMoney, formatWeight } from "@/lib/format";
import { cn } from "@/lib/utils";

const initialState: ActionState = { error: null };

const fieldClass =
  "border-border bg-background focus:border-primary w-full rounded-lg border px-3 py-2 text-sm outline-none";

export type Reconciliation = {
  original_weight_g: string;
  sold_weight_g: string;
  returned_weight_g: string;
  adjusted_weight_g: string;
  open_weight_g: string;
  unexplained_weight: string;
  adjusted_value: string;
  total_paid: string;
  remaining_balance: string;
  unexplained_money: string;
  weight_settled: boolean;
  payment_settled: boolean;
  weight_explained: boolean;
  money_explained: boolean;
  can_close: boolean;
};

function CheckRow({
  label,
  value,
  ok,
  requirement,
}: {
  label: string;
  value: string;
  ok: boolean;
  requirement: string;
}) {
  return (
    <tr>
      <td className="px-4 py-2.5">{label}</td>
      <td className="num px-4 py-2.5 text-end font-medium">{value}</td>
      <td className="text-muted px-4 py-2.5 text-xs">{requirement}</td>
      <td className="px-4 py-2.5 text-end">
        <span
          className={cn(
            "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium",
            ok
              ? "bg-positive/10 text-positive"
              : "bg-negative/10 text-negative",
          )}
        >
          {ok ? "مطابق" : "غير مكتمل"}
        </span>
      </td>
    </tr>
  );
}

function ActionButton({ label, busy }: { label: string; busy: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:opacity-50"
    >
      {pending ? busy : label}
    </button>
  );
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
 * شاشة المصالحة والإغلاق (§24.6).
 *
 * تعرض بنود المصالحة الأربعة وحالة كل بند، وتترك زر الإغلاق معطلاً حتى
 * تتحقق كلها. الرفض في قاعدة البيانات على أي حال — لكن تعطيل الزر مع
 * بيان السبب أوضح من ترك المستخدم يضغط ثم يقرأ خطأ.
 */
export function SettlementPanel({
  dealId,
  recon,
  isClosed,
}: {
  dealId: string;
  recon: Reconciliation;
  isClosed: boolean;
}) {
  const router = useRouter();
  const [closeState, closeAction] = useActionState(closeDeal, initialState);
  const [reopenState, reopenAction] = useActionState(reopenDeal, initialState);
  const [weightState, weightAction] = useActionState(
    recordWeightAdjustment,
    initialState,
  );
  const [commercialState, commercialAction] = useActionState(
    recordCommercialAdjustment,
    initialState,
  );
  const [showAdjust, setShowAdjust] = useState(false);

  useEffect(() => {
    if (
      closeState.success ||
      reopenState.success ||
      weightState.success ||
      commercialState.success
    ) {
      router.refresh();
    }
  }, [
    closeState.success,
    reopenState.success,
    weightState.success,
    commercialState.success,
    router,
  ]);

  if (isClosed) {
    return (
      <Card className="border-positive/40 bg-positive/5 p-5">
        <h2 className="text-positive font-semibold">الصفقة مغلقة</h2>
        <p className="text-muted mt-1 text-sm">
          نتيجتها محفوظة في لقطة نهائية لا تتغير. أي تصحيح يحتاج إعادة فتح
          بصلاحية خاصة، ويبقى أثر ذلك في سجل التدقيق مع حفظ اللقطة السابقة.
        </p>

        <form action={reopenAction} className="mt-4 space-y-3">
          <input type="hidden" name="deal_id" value={dealId} />
          <div className="space-y-1.5">
            <label
              htmlFor="reopen_reason"
              className="block text-sm font-medium"
            >
              سبب إعادة الفتح <span className="text-negative">*</span>
            </label>
            <input
              id="reopen_reason"
              name="reason"
              required
              placeholder="السبب إلزامي ويُسجَّل في التدقيق"
              className={fieldClass}
            />
          </div>

          {reopenState.error ? <ErrorNote message={reopenState.error} /> : null}

          <div className="flex justify-end">
            <ActionButton label="إعادة فتح الصفقة" busy="جارٍ الفتح…" />
          </div>
        </form>
      </Card>
    );
  }

  return (
    <Card className="p-5">
      <h2 className="font-semibold">المصالحة والإغلاق</h2>
      <p className="text-muted mt-1 text-sm">
        الإغلاق لا يتم حتى يُفسَّر كل جرام وكل ريال. البنود الأربعة أدناه يجب أن
        تكون مطابقة جميعاً.
      </p>

      <div className="mt-4 overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-surface-muted text-muted">
            <tr>
              <th className="px-4 py-2.5 text-start font-medium">البند</th>
              <th className="px-4 py-2.5 text-end font-medium">القيمة</th>
              <th className="px-4 py-2.5 text-start font-medium">المطلوب</th>
              <th className="px-4 py-2.5 text-end font-medium">الحالة</th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            <CheckRow
              label="الوزن المفتوح لدى الموزع"
              value={formatWeight(recon.open_weight_g)}
              ok={recon.weight_settled}
              requirement="صفر"
            />
            <CheckRow
              label="الرصيد المالي المتبقي"
              value={formatMoney(recon.remaining_balance)}
              ok={recon.payment_settled}
              requirement="صفر إلا بتسوية معتمدة"
            />
            <CheckRow
              label="فرق وزني غير مفسر"
              value={formatWeight(recon.unexplained_weight)}
              ok={recon.weight_explained}
              requirement="صفر"
            />
            <CheckRow
              label="فرق مالي غير مفسر"
              value={formatMoney(recon.unexplained_money)}
              ok={recon.money_explained}
              requirement="صفر"
            />
          </tbody>
        </table>
      </div>

      <div className="border-border mt-4 border-t pt-4">
        <div className="text-muted grid gap-3 text-xs sm:grid-cols-4">
          <div>
            الوزن الأصلي
            <div className="num text-foreground mt-0.5 text-sm">
              {formatWeight(recon.original_weight_g)}
            </div>
          </div>
          <div>
            المصرَّف
            <div className="num text-foreground mt-0.5 text-sm">
              {formatWeight(recon.sold_weight_g)}
            </div>
          </div>
          <div>
            المسترد
            <div className="num text-foreground mt-0.5 text-sm">
              {formatWeight(recon.returned_weight_g)}
            </div>
          </div>
          <div>
            المسوّى بتسوية
            <div className="num text-foreground mt-0.5 text-sm">
              {formatWeight(recon.adjusted_weight_g)}
            </div>
          </div>
        </div>
      </div>

      {!recon.can_close ? (
        <div className="mt-4">
          <button
            type="button"
            onClick={() => setShowAdjust((prev) => !prev)}
            className="border-border rounded-lg border px-3 py-1.5 text-sm"
          >
            {showAdjust ? "إخفاء التسويات" : "تسجيل تسوية معتمدة"}
          </button>

          {showAdjust ? (
            <div className="mt-4 grid gap-4 lg:grid-cols-2">
              <form
                action={weightAction}
                className="border-border space-y-3 rounded-lg border p-4"
              >
                <input type="hidden" name="deal_id" value={dealId} />
                <div className="text-sm font-medium">تسوية وزن</div>
                <p className="text-muted text-xs">
                  لتفسير وزن لم يُصرَّف ولم يُسترد — هدر أو فرق ميزان أو تلف.
                  الكمية لا تعود للمخزون وتكلفتها تصبح خسارة.
                </p>
                <input
                  name="weight_g"
                  inputMode="decimal"
                  required
                  placeholder={formatWeight(recon.open_weight_g, false)}
                  className={`${fieldClass} num`}
                />
                <input
                  name="reason"
                  required
                  placeholder="السبب — إلزامي"
                  className={fieldClass}
                />
                {weightState.error ? (
                  <ErrorNote message={weightState.error} />
                ) : null}
                <div className="flex justify-end">
                  <ActionButton label="تسجيل التسوية" busy="جارٍ…" />
                </div>
              </form>

              <form
                action={commercialAction}
                className="border-border space-y-3 rounded-lg border p-4"
              >
                <input type="hidden" name="deal_id" value={dealId} />
                <div className="text-sm font-medium">تسوية تجارية</div>
                <p className="text-muted text-xs">
                  تعديل ما يلتزم به الموزع. سالب يعني خصماً معتمداً يخفض
                  المستحق، وموجب يزيده.
                </p>
                <input
                  name="amount"
                  inputMode="decimal"
                  required
                  placeholder={`مثال: -${formatMoney(recon.remaining_balance)}`}
                  className={`${fieldClass} num`}
                />
                <input
                  name="reason"
                  required
                  placeholder="السبب — إلزامي"
                  className={fieldClass}
                />
                {commercialState.error ? (
                  <ErrorNote message={commercialState.error} />
                ) : null}
                <div className="flex justify-end">
                  <ActionButton label="تسجيل التسوية" busy="جارٍ…" />
                </div>
              </form>
            </div>
          ) : null}
        </div>
      ) : null}

      <form action={closeAction} className="mt-4 space-y-3">
        <input type="hidden" name="deal_id" value={dealId} />

        {closeState.error ? <ErrorNote message={closeState.error} /> : null}

        <div className="flex items-center justify-between gap-4">
          <p className="text-muted text-xs">
            {recon.can_close
              ? "المصالحة مكتملة. الإغلاق ينشئ لقطة نهائية لا تتغير."
              : "أكمل بنود المصالحة أعلاه لتفعيل الإغلاق."}
          </p>
          <button
            type="submit"
            disabled={!recon.can_close}
            className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
          >
            إغلاق الصفقة
          </button>
        </div>
      </form>
    </Card>
  );
}
