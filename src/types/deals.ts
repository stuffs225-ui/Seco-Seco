import type { MoneyAmount, RatePerGram, WeightGrams } from "./schema";

/** دورة حياة الصفقة — قرار إداري مخزَّن (§24.3). */
export type DealStatus =
  | "draft"
  | "active"
  | "in_settlement"
  | "ready_to_close"
  | "closed"
  | "reopened"
  | "cancelled";

/** حالة تسوية الوزن — مشتقة من الدفتر (§24.3). */
export type QuantityStatus =
  "open" | "partially_settled" | "fully_settled" | "exception";

/** حالة السداد — مشتقة ومنفصلة تماماً عن حالة الوزن (§24.3). */
export type PaymentStatus =
  "unpaid" | "partially_paid" | "fully_paid" | "credit_balance" | "exception";

export const DEAL_STATUS_LABELS: Record<DealStatus, string> = {
  draft: "مسودة",
  active: "جارية",
  in_settlement: "قيد المصالحة",
  ready_to_close: "جاهزة للإغلاق",
  closed: "مغلقة",
  reopened: "أُعيد فتحها",
  cancelled: "ملغاة",
};

export const QUANTITY_STATUS_LABELS: Record<QuantityStatus, string> = {
  open: "وزن مفتوح",
  partially_settled: "مسوّى جزئياً",
  fully_settled: "الوزن مسوّى",
  exception: "استثناء يحتاج مراجعة",
};

export const PAYMENT_STATUS_LABELS: Record<PaymentStatus, string> = {
  unpaid: "غير مسددة",
  partially_paid: "مسددة جزئياً",
  fully_paid: "مسددة بالكامل",
  credit_balance: "رصيد دائن للموزع",
  exception: "استثناء يحتاج مراجعة",
};

/** أنواع حركات الدفتر (§24.2). */
export type DealEntryType =
  | "DEAL_OPEN"
  | "QTY_DELIVERED"
  | "QTY_SOLD"
  | "PAYMENT_RECEIVED"
  | "QTY_RETURNED"
  | "COMMERCIAL_ADJUSTMENT"
  | "WEIGHT_ADJUSTMENT"
  | "PAYMENT_REVERSAL"
  | "CREDIT_TRANSFER"
  | "DEAL_CLOSE";

export const ENTRY_TYPE_LABELS: Record<DealEntryType, string> = {
  DEAL_OPEN: "فتح الصفقة",
  QTY_DELIVERED: "تسليم كمية",
  QTY_SOLD: "تصريف",
  PAYMENT_RECEIVED: "تحصيل",
  QTY_RETURNED: "استرداد كمية",
  COMMERCIAL_ADJUSTMENT: "تسوية تجارية",
  WEIGHT_ADJUSTMENT: "تسوية وزن",
  PAYMENT_REVERSAL: "عكس دفعة",
  CREDIT_TRANSFER: "نقل رصيد دائن",
  DEAL_CLOSE: "إغلاق الصفقة",
};

/** صف `v_deal_status` — لا يحتوي أي تكلفة أو ربح. */
export type DealStatusRow = {
  deal_id: string;
  deal_no: string;
  distributor_id: string;
  deal_status: DealStatus;
  delivery_date: string | null;
  due_date: string | null;
  closed_at: string | null;
  original_weight_g: WeightGrams;
  sold_weight_g: WeightGrams;
  returned_weight_g: WeightGrams;
  adjusted_weight_g: WeightGrams;
  open_weight_g: WeightGrams;
  settlement_ratio: string;
  original_value: MoneyAmount;
  adjusted_value: MoneyAmount;
  total_paid: MoneyAmount;
  remaining_balance: MoneyAmount;
  payment_ratio: string;
  quantity_status: QuantityStatus;
  payment_status: PaymentStatus;
  is_overdue: boolean;
  is_reconciled: boolean;
};

/**
 * صف `v_deal_profit`.
 *
 * ⚠️ بيانات داخلية حساسة. ممنوع تمريرها إلى أي مخرج للموزع (V5.3).
 * تقارير الموزع تُبنى من مصدر منفصل لا يحتوي هذه الحقول أصلاً.
 */
export type DealProfitRow = {
  deal_id: string;
  original_expected_profit: MoneyAmount;
  cancelled_expected_profit: MoneyAmount;
  open_expected_profit: MoneyAmount;
  realized_profit: MoneyAmount;
  original_capital_cost: MoneyAmount;
  returned_capital_cost: MoneyAmount;
  cost_of_goods_sold: MoneyAmount;
  open_capital_cost: MoneyAmount;
};

export type DealLedgerRow = {
  id: number;
  entry_type: DealEntryType;
  delivered_weight_g: WeightGrams;
  settled_weight_g: WeightGrams;
  commercial_value_delta: MoneyAmount;
  cost_delta: MoneyAmount;
  expected_profit_delta: MoneyAmount;
  realized_profit_delta: MoneyAmount;
  paid_delta: MoneyAmount;
  ref_type: string;
  ref_id: string | null;
  reason: string;
  notes: string;
  occurred_at: string;
};

export type DealLineRow = {
  id: string;
  lot_id: string;
  weight_g: WeightGrams;
  cost_per_g: RatePerGram;
  deal_value_per_g: RatePerGram;
  expected_profit_per_g: RatePerGram;
};
