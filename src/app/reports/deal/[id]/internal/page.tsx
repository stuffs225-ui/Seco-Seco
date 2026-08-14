import type { Metadata } from "next";
import { notFound } from "next/navigation";

import {
  ReportGrid,
  ReportSection,
  ReportShell,
} from "@/components/domain/report-shell";
import {
  formatCurrency,
  formatDate,
  formatDateTime,
  formatPerGram,
  formatPercent,
  formatWeight,
} from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import {
  DEAL_STATUS_LABELS,
  PAYMENT_STATUS_LABELS,
  QUANTITY_STATUS_LABELS,
  type DealStatus,
  type PaymentStatus,
  type QuantityStatus,
} from "@/types/deals";

export const metadata: Metadata = { title: "كشف صفقة داخلي" };

/**
 * كشف الصفقة الداخلي (§V5.4) — النسخة الكاملة للإدارة.
 *
 * محمي بطبقتين: RLS على `v_deal_statement_internal` التي تشترط صلاحية
 * التقارير الداخلية، و`log_report_generation` التي ترفض القالب الداخلي
 * لمن لا يملكها. مستخدم بصلاحية تقارير الموزع فقط يصل لصفحة فارغة.
 */

type InternalStatement = {
  deal_no: string;
  distributor_name: string;
  distributor_code: string;
  item_name: string | null;
  lot_no: string | null;
  deal_status: DealStatus;
  delivery_date: string | null;
  due_date: string | null;
  closed_at: string | null;
  original_weight_g: string;
  sold_weight_g: string;
  returned_weight_g: string;
  adjusted_weight_g: string;
  open_weight_g: string;
  settlement_ratio: string;
  original_value: string;
  adjusted_value: string;
  total_paid: string;
  remaining_balance: string;
  payment_ratio: string;
  quantity_status: QuantityStatus;
  payment_status: PaymentStatus;
  cost_per_g: string | null;
  deal_value_per_g: string | null;
  expected_profit_per_g: string | null;
  original_capital_cost: string;
  returned_capital_cost: string;
  cost_of_goods_sold: string;
  open_capital_cost: string;
  original_expected_profit: string;
  cancelled_expected_profit: string;
  open_expected_profit: string;
  realized_profit: string;
};

export default async function InternalReportPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: s } = await supabase
    .from("v_deal_statement_internal")
    .select("*")
    .eq("deal_id", id)
    .maybeSingle<InternalStatement>();

  if (!s) notFound();

  await supabase.rpc("log_report_generation", {
    p_template_code: "DEAL_STATEMENT_INTERNAL",
    p_entity_type: "deal",
    p_entity_id: id,
  });

  const money = (v: string | null) => (
    <span className="num">{formatCurrency(v)}</span>
  );
  const weight = (v: string | null) => (
    <span className="num">{formatWeight(v)}</span>
  );

  return (
    <ReportShell
      audience="INTERNAL"
      title={`كشف صفقة داخلي ${s.deal_no}`}
      subtitle={`${s.distributor_name} · ${s.distributor_code}`}
    >
      <ReportSection title="بيانات الصفقة">
        <ReportGrid
          items={[
            {
              label: "رقم الصفقة",
              value: <span className="num">{s.deal_no}</span>,
            },
            { label: "الموزع", value: s.distributor_name },
            { label: "الصنف", value: s.item_name ?? "—" },
            {
              label: "الدفعة",
              value: <span className="num">{s.lot_no ?? "—"}</span>,
            },
            {
              label: "تاريخ التسليم",
              value: <span className="num">{formatDate(s.delivery_date)}</span>,
            },
            {
              label: "تاريخ الاستحقاق",
              value: <span className="num">{formatDate(s.due_date)}</span>,
            },
            {
              label: "حالة الصفقة",
              value: DEAL_STATUS_LABELS[s.deal_status] ?? "—",
            },
            {
              label: "حالة الوزن",
              value: QUANTITY_STATUS_LABELS[s.quantity_status] ?? "—",
            },
            {
              label: "حالة السداد",
              value: PAYMENT_STATUS_LABELS[s.payment_status] ?? "—",
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="ملخص الكمية">
        <ReportGrid
          items={[
            { label: "الوزن الأصلي", value: weight(s.original_weight_g) },
            { label: "المصرَّف", value: weight(s.sold_weight_g) },
            { label: "المسترد", value: weight(s.returned_weight_g) },
            { label: "المسوّى بتسوية", value: weight(s.adjusted_weight_g) },
            { label: "المفتوح لدى الموزع", value: weight(s.open_weight_g) },
            {
              label: "نسبة تسوية الوزن",
              value: (
                <span className="num">{formatPercent(s.settlement_ratio)}</span>
              ),
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="اقتصاديات الجرام">
        <ReportGrid
          items={[
            {
              label: "تكلفة الجرام",
              value: <span className="num">{formatPerGram(s.cost_per_g)}</span>,
            },
            {
              label: "قيمة الجرام للموزع",
              value: (
                <span className="num">{formatPerGram(s.deal_value_per_g)}</span>
              ),
            },
            {
              label: "الربح المتوقع للجرام",
              value: (
                <span className="num">
                  {formatPerGram(s.expected_profit_per_g)}
                </span>
              ),
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="ملخص التكلفة ورأس المال">
        <ReportGrid
          items={[
            {
              label: "رأس المال الأصلي",
              value: money(s.original_capital_cost),
            },
            {
              label: "رأس المال المسترد للمخزون",
              value: money(s.returned_capital_cost),
            },
            {
              label: "تكلفة الكمية المباعة",
              value: money(s.cost_of_goods_sold),
            },
            { label: "رأس المال المفتوح", value: money(s.open_capital_cost) },
          ]}
        />
      </ReportSection>

      <ReportSection title="ملخص الربح">
        <ReportGrid
          items={[
            {
              label: "الربح المتوقع الأصلي",
              value: money(s.original_expected_profit),
            },
            {
              label: "الربح المتوقع الملغى بالاسترداد",
              value: money(s.cancelled_expected_profit),
            },
            {
              label: "الربح المتوقع المفتوح",
              value: money(s.open_expected_profit),
            },
            { label: "الربح المحقق", value: money(s.realized_profit) },
          ]}
        />
        <p className="text-muted mt-3 text-xs">
          الربح المتوقع مؤشر تحليلي لا يدخل في السيولة ولا في الأرباح القابلة
          للتوزيع. الربح يصبح محققاً عند تسجيل التصريف، والنقد المحصل مؤشر ثالث
          مستقل.
        </p>
      </ReportSection>

      <ReportSection title="الملخص المالي">
        <ReportGrid
          items={[
            { label: "القيمة الأصلية", value: money(s.original_value) },
            { label: "القيمة المعدلة", value: money(s.adjusted_value) },
            { label: "إجمالي المسدد", value: money(s.total_paid) },
            { label: "الرصيد المتبقي", value: money(s.remaining_balance) },
            {
              label: "نسبة السداد",
              value: (
                <span className="num">{formatPercent(s.payment_ratio)}</span>
              ),
            },
          ]}
        />
      </ReportSection>

      {s.closed_at ? (
        <ReportSection title="نتيجة الإغلاق">
          <ReportGrid
            items={[
              {
                label: "تاريخ الإغلاق",
                value: <span className="num">{formatDate(s.closed_at)}</span>,
              },
              {
                label: "إجمالي الربح المحقق",
                value: money(s.realized_profit),
              },
            ]}
          />
        </ReportSection>
      ) : null}

      <p className="text-muted border-border mt-8 border-t pt-3 text-xs">
        صدر هذا التقرير بتاريخ{" "}
        <span className="num">{formatDateTime(new Date())}</span> · تم تسجيل
        إنشائه في سجل التدقيق.
      </p>
    </ReportShell>
  );
}
