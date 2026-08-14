import {
  formatCurrency,
  formatMoney,
  formatPerGram,
  formatWeight,
  toNumber,
} from "@/lib/format";
import { cn } from "@/lib/utils";

/**
 * عرض القيم الرقمية.
 *
 * كل رقم يخرج داخل `.num` ليبقى اتجاهه LTR داخل النص العربي — وإلا
 * انقلبت الفواصل والإشارات. هذه المكونات هي الطريقة الوحيدة المعتمدة
 * لعرض مبلغ أو وزن، حتى لا يتسرب تنسيق يدوي مختلف إلى شاشة.
 *
 * لا تحسب هذه المكونات شيئاً — تعرض ما يصل من قاعدة البيانات فقط.
 */

type NumericValue = string | number | null | undefined;

/** يلوّن حسب الإشارة: الموجب أخضر والسالب أحمر. للأرصدة والفروقات. */
function signClass(value: NumericValue, signed: boolean) {
  if (!signed) return "";
  const n = toNumber(value);
  if (n > 0) return "text-positive";
  if (n < 0) return "text-negative";
  return "";
}

export function Money({
  value,
  withCurrency = false,
  signed = false,
  className,
}: {
  value: NumericValue;
  withCurrency?: boolean;
  signed?: boolean;
  className?: string;
}) {
  return (
    <span className={cn("num", signClass(value, signed), className)}>
      {withCurrency ? formatCurrency(value) : formatMoney(value)}
    </span>
  );
}

export function Weight({
  value,
  withUnit = true,
  signed = false,
  className,
}: {
  value: NumericValue;
  withUnit?: boolean;
  signed?: boolean;
  className?: string;
}) {
  return (
    <span className={cn("num", signClass(value, signed), className)}>
      {formatWeight(value, withUnit)}
    </span>
  );
}

export function PerGram({
  value,
  className,
}: {
  value: NumericValue;
  className?: string;
}) {
  return <span className={cn("num", className)}>{formatPerGram(value)}</span>;
}
