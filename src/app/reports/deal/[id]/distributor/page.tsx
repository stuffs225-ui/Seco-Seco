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
  formatWeight,
} from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { DEAL_STATUS_LABELS, type DealStatus } from "@/types/deals";

export const metadata: Metadata = { title: "كشف صفقة للموزع" };

/**
 * كشف الصفقة للموزع — النسخة الخارجية (§V5.2).
 *
 * تُبنى كاملة من `get_distributor_statement` و`get_distributor_movements`،
 * وكلتاهما تُرجعان أنواعاً لا تحوي حقل تكلفة أو ربح أو رأس مال أصلاً
 * (§V5.8). هذه الصفحة لا تستطيع تسريب بيانات داخلية حتى لو أراد كاتبها،
 * لأن البيانات لا تصلها من الأساس.
 */

type Statement = {
  deal_no: string;
  distributor_name: string;
  distributor_code: string;
  item_name: string | null;
  delivery_date: string | null;
  due_date: string | null;
  closed_at: string | null;
  deal_status: DealStatus;
  original_weight_g: string;
  returned_weight_g: string;
  open_weight_g: string;
  original_value: string;
  value_reduction: string;
  adjusted_value: string;
  total_paid: string;
  remaining_balance: string;
  credit_balance: string;
};

type Movement = {
  occurred_at: string;
  kind: string;
  weight_g: string;
  amount: string;
  reference: string;
};

export default async function DistributorReportPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [statementResult, movementsResult] = await Promise.all([
    supabase.rpc("get_distributor_statement", { p_deal_id: id }).single(),
    supabase.rpc("get_distributor_movements", { p_deal_id: id }),
  ]);

  const statement = statementResult.data as Statement | null;
  const movements = (movementsResult.data ?? []) as Movement[];

  if (statementResult.error || !statement) notFound();

  // §V5.8: كل توليد يُسجَّل — من ومتى ولأي صفقة
  await supabase.rpc("log_report_generation", {
    p_template_code: "DEAL_STATEMENT_DISTRIBUTOR",
    p_entity_type: "deal",
    p_entity_id: id,
  });

  const credit = Number(statement.credit_balance);

  return (
    <ReportShell
      audience="DISTRIBUTOR"
      title={`كشف صفقة ${statement.deal_no}`}
      subtitle={`${statement.distributor_name} · ${statement.distributor_code}`}
    >
      <ReportSection title="بيانات الصفقة">
        <ReportGrid
          items={[
            {
              label: "رقم الصفقة",
              value: <span className="num">{statement.deal_no}</span>,
            },
            { label: "الموزع", value: statement.distributor_name },
            { label: "الصنف", value: statement.item_name ?? "—" },
            {
              label: "تاريخ التسليم",
              value: (
                <span className="num">
                  {formatDate(statement.delivery_date)}
                </span>
              ),
            },
            {
              label: "تاريخ الاستحقاق",
              value: (
                <span className="num">{formatDate(statement.due_date)}</span>
              ),
            },
            {
              label: "حالة الصفقة",
              value: DEAL_STATUS_LABELS[statement.deal_status] ?? "—",
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="ملخص الكمية">
        <ReportGrid
          items={[
            {
              label: "الوزن المسلَّم",
              value: (
                <span className="num">
                  {formatWeight(statement.original_weight_g)}
                </span>
              ),
            },
            {
              label: "الوزن المسترد",
              value: (
                <span className="num">
                  {formatWeight(statement.returned_weight_g)}
                </span>
              ),
            },
            {
              label: "الوزن المتبقي لديكم",
              value: (
                <span className="num">
                  {formatWeight(statement.open_weight_g)}
                </span>
              ),
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="الملخص المالي">
        <ReportGrid
          items={[
            {
              label: "القيمة المتفق عليها",
              value: (
                <span className="num">
                  {formatCurrency(statement.original_value)}
                </span>
              ),
            },
            {
              label: "تخفيض بسبب الاسترداد",
              value: (
                <span className="num">
                  {formatCurrency(statement.value_reduction)}
                </span>
              ),
            },
            {
              label: "القيمة المعدلة",
              value: (
                <span className="num">
                  {formatCurrency(statement.adjusted_value)}
                </span>
              ),
            },
            {
              label: "إجمالي المسدد",
              value: (
                <span className="num">
                  {formatCurrency(statement.total_paid)}
                </span>
              ),
            },
            {
              label: credit > 0 ? "رصيد لكم لدى الشركة" : "المبلغ المتبقي",
              value: (
                <span className="num font-bold">
                  {formatCurrency(
                    credit > 0
                      ? statement.credit_balance
                      : statement.remaining_balance,
                  )}
                </span>
              ),
            },
          ]}
        />
      </ReportSection>

      <ReportSection title="سجل الحركات">
        {/* بطاقات الجوال — الجدول أدناه للشاشات الكبيرة فقط */}
        <ul className="space-y-2 sm:hidden print:hidden">
          {movements.map((movement, index) => (
            <li
              key={index}
              className="border-border rounded-lg border px-3 py-2"
            >
              <div className="flex items-start justify-between gap-2">
                <span className="text-sm font-medium">{movement.kind}</span>
                <span className="num text-muted text-xs whitespace-nowrap">
                  {formatDateTime(movement.occurred_at)}
                </span>
              </div>
              <div className="mt-1 flex flex-wrap gap-x-4 text-sm">
                {Number(movement.weight_g) !== 0 ? (
                  <span className="num">{formatWeight(movement.weight_g)}</span>
                ) : null}
                {Number(movement.amount) !== 0 ? (
                  <span className="num">{formatCurrency(movement.amount)}</span>
                ) : null}
              </div>
              {movement.reference ? (
                <div className="text-muted mt-1 text-xs">
                  {movement.reference}
                </div>
              ) : null}
            </li>
          ))}
        </ul>

        <div className="hidden overflow-x-auto sm:block print:block">
          <table className="w-full text-sm">
            <thead className="border-border border-b">
              <tr>
                <th className="py-2 text-start font-medium">التاريخ</th>
                <th className="py-2 text-start font-medium">الحركة</th>
                <th className="py-2 text-end font-medium">الوزن</th>
                <th className="py-2 text-end font-medium">المبلغ</th>
                <th className="py-2 text-start font-medium">المرجع</th>
              </tr>
            </thead>
            <tbody className="divide-border divide-y">
              {movements.map((movement, index) => (
                <tr key={index}>
                  <td className="num py-2">
                    {formatDateTime(movement.occurred_at)}
                  </td>
                  <td className="py-2">{movement.kind}</td>
                  <td className="num py-2 text-end">
                    {Number(movement.weight_g) !== 0
                      ? formatWeight(movement.weight_g)
                      : "—"}
                  </td>
                  <td className="num py-2 text-end">
                    {Number(movement.amount) !== 0
                      ? formatCurrency(movement.amount)
                      : "—"}
                  </td>
                  <td className="py-2 text-xs">{movement.reference || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </ReportSection>

      {statement.closed_at ? (
        <ReportSection title="نتيجة الإغلاق">
          <p className="text-sm">
            سُوّيت هذه الصفقة بالكامل بتاريخ{" "}
            <span className="num font-medium">
              {formatDate(statement.closed_at)}
            </span>
            ، ولا يوجد أي رصيد متبقٍ على الطرفين.
          </p>
        </ReportSection>
      ) : null}

      <p className="text-muted border-border mt-8 border-t pt-3 text-xs">
        صدر هذا الكشف بتاريخ{" "}
        <span className="num">{formatDateTime(new Date())}</span>
      </p>
    </ReportShell>
  );
}
