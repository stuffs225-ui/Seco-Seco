/**
 * تنسيق موحّد للأرقام في كل الشاشات والتقارير.
 *
 * قاعدة: الواجهة تنسّق فقط ولا تحسب. كل قيمة تصل من View في قاعدة البيانات
 * كسلسلة نصية (numeric في Postgres يصل كـ string حفاظاً على الدقة)،
 * والتحويل إلى number يتم هنا للعرض فقط — لا لإعادة الحساب.
 */

/** رمز العملة — يُقرأ لاحقاً من الإعدادات عند دعم عملات متعددة. */
export const CURRENCY = "ريال";

/** خانات عشرية للعرض: مبلغان للمال، ثلاثة للوزن بالجرام. */
const MONEY_DECIMALS = 2;
const WEIGHT_DECIMALS = 3;

const moneyFormatter = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: MONEY_DECIMALS,
  maximumFractionDigits: MONEY_DECIMALS,
});

const weightFormatter = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 0,
  maximumFractionDigits: WEIGHT_DECIMALS,
});

const perGramFormatter = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

/** يحوّل قيمة numeric قادمة من Postgres (string | number | null) إلى رقم للعرض. */
export function toNumber(value: string | number | null | undefined): number {
  if (value === null || value === undefined || value === "") return 0;
  return typeof value === "number" ? value : Number(value);
}

/** مبلغ بدون رمز العملة — للجداول الكثيفة. */
export function formatMoney(value: string | number | null | undefined): string {
  return moneyFormatter.format(toNumber(value));
}

/** مبلغ مع رمز العملة — للبطاقات والملخصات. */
export function formatCurrency(
  value: string | number | null | undefined,
): string {
  return `${formatMoney(value)} ${CURRENCY}`;
}

/** وزن بالجرام. */
export function formatWeight(
  value: string | number | null | undefined,
  withUnit = true,
): string {
  const formatted = weightFormatter.format(toNumber(value));
  return withUnit ? `${formatted} ج` : formatted;
}

/** سعر أو تكلفة الجرام — دقة أعلى لأن الكسور هنا مؤثرة. */
export function formatPerGram(
  value: string | number | null | undefined,
): string {
  return `${perGramFormatter.format(toNumber(value))} ${CURRENCY}/ج`;
}

/** نسبة مئوية من كسر عشري (0.35 ⇒ "35.0%"). */
export function formatPercent(
  value: string | number | null | undefined,
  fractionDigits = 1,
): string {
  return `${(toNumber(value) * 100).toFixed(fractionDigits)}%`;
}

const dateFormatter = new Intl.DateTimeFormat("ar", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  numberingSystem: "latn",
});

const dateTimeFormatter = new Intl.DateTimeFormat("ar", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  numberingSystem: "latn",
});

export function formatDate(value: string | Date | null | undefined): string {
  if (!value) return "—";
  return dateFormatter.format(new Date(value));
}

export function formatDateTime(
  value: string | Date | null | undefined,
): string {
  if (!value) return "—";
  return dateTimeFormatter.format(new Date(value));
}
