import {
  DEAL_STATUS_LABELS,
  PAYMENT_STATUS_LABELS,
  QUANTITY_STATUS_LABELS,
  type DealStatus,
  type PaymentStatus,
  type QuantityStatus,
} from "@/types/deals";
import { cn } from "@/lib/utils";

/**
 * شارات الحالة.
 *
 * حالتا الوزن والمال تُعرضان دائماً كشارتين منفصلتين لا شارة واحدة —
 * الفصل بينهما مبدأ في §24.3، ودمجهما بصرياً يعيد الالتباس الذي تمنعه
 * الخطة: صفقة مدفوعة بالكامل قد يكون وزنها غير مسوّى.
 */

const base =
  "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap";

function Badge({
  children,
  tone,
}: {
  children: React.ReactNode;
  tone: "neutral" | "positive" | "warning" | "negative" | "info";
}) {
  return (
    <span
      className={cn(
        base,
        tone === "neutral" && "bg-surface-muted text-muted",
        tone === "positive" && "bg-positive/10 text-positive",
        tone === "warning" && "bg-warning/10 text-warning",
        tone === "negative" && "bg-negative/10 text-negative",
        tone === "info" && "bg-info/10 text-info",
      )}
    >
      {children}
    </span>
  );
}

export function QuantityStatusBadge({ status }: { status: QuantityStatus }) {
  const tone =
    status === "fully_settled"
      ? "positive"
      : status === "partially_settled"
        ? "warning"
        : status === "exception"
          ? "negative"
          : "neutral";

  return <Badge tone={tone}>{QUANTITY_STATUS_LABELS[status]}</Badge>;
}

export function PaymentStatusBadge({ status }: { status: PaymentStatus }) {
  const tone =
    status === "fully_paid"
      ? "positive"
      : status === "partially_paid"
        ? "warning"
        : // الرصيد الدائن ليس نجاحاً: مبلغ للموزع يحتاج معالجة (§24.5)
          status === "credit_balance"
          ? "info"
          : status === "exception"
            ? "negative"
            : "neutral";

  return <Badge tone={tone}>{PAYMENT_STATUS_LABELS[status]}</Badge>;
}

export function DealStatusBadge({ status }: { status: DealStatus }) {
  const tone =
    status === "closed"
      ? "positive"
      : status === "cancelled"
        ? "negative"
        : status === "ready_to_close" || status === "in_settlement"
          ? "warning"
          : status === "active"
            ? "info"
            : "neutral";

  return <Badge tone={tone}>{DEAL_STATUS_LABELS[status]}</Badge>;
}

export function OverdueBadge() {
  return <Badge tone="negative">متأخرة</Badge>;
}
