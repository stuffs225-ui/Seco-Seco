import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { Card, StatCard, TableWrap, Td, Th } from "@/components/domain/layout";
import { Money, PerGram, Weight } from "@/components/domain/numeric";
import {
  DealStatusBadge,
  OverdueBadge,
  PaymentStatusBadge,
  QuantityStatusBadge,
} from "@/components/domain/status-badge";
import { formatDate, formatDateTime, formatPercent } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import {
  ENTRY_TYPE_LABELS,
  type DealLedgerRow,
  type DealLineRow,
  type DealProfitRow,
  type DealStatusRow,
} from "@/types/deals";

import { CreditResolution } from "./credit-resolution";
import { QuantityActions } from "./quantity-actions";

export const metadata: Metadata = { title: "ملف الصفقة" };

export default async function DealWorkspacePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: deal } = await supabase
    .from("v_deal_status")
    .select("*")
    .eq("deal_id", id)
    .maybeSingle<DealStatusRow>();

  if (!deal) notFound();

  const [
    { data: profit },
    { data: ledger },
    { data: line },
    { data: distributor },
  ] = await Promise.all([
    supabase
      .from("v_deal_profit")
      .select("*")
      .eq("deal_id", id)
      .single<DealProfitRow>(),
    supabase
      .from("deal_ledger")
      .select(
        "id, entry_type, delivered_weight_g, settled_weight_g, commercial_value_delta, cost_delta, expected_profit_delta, realized_profit_delta, paid_delta, reason, notes, occurred_at",
      )
      .eq("deal_id", id)
      .order("occurred_at")
      .order("id")
      .returns<DealLedgerRow[]>(),
    supabase
      .from("deal_lines")
      .select(
        "id, lot_id, weight_g, cost_per_g, deal_value_per_g, expected_profit_per_g",
      )
      .eq("deal_id", id)
      .maybeSingle<DealLineRow>(),
    supabase
      .from("distributors")
      .select("name, code")
      .eq("id", deal.distributor_id)
      .maybeSingle<{ name: string; code: string }>(),
  ]);

  // الرصيد الدائن حالة مشتقة من الصفقة، لا جدول (§24.5)
  const hasCredit = Number(deal.remaining_balance) < 0;

  const [{ data: credit }, { data: siblingDeals }, { data: accounts }] =
    hasCredit
      ? await Promise.all([
          supabase
            .from("v_distributor_credits")
            .select("unresolved_amount")
            .eq("deal_id", id)
            .maybeSingle<{ unresolved_amount: string }>(),
          supabase
            .from("v_deal_status")
            .select("deal_id, deal_no")
            .eq("distributor_id", deal.distributor_id)
            .neq("deal_id", id)
            .not("deal_status", "in", '("closed","cancelled")')
            .returns<{ deal_id: string; deal_no: string }[]>(),
          supabase
            .from("cash_accounts")
            .select("id, name")
            .eq("is_active", true)
            .returns<{ id: string; name: string }[]>(),
        ])
      : [{ data: null }, { data: [] }, { data: [] }];

  const canSell =
    Number(deal.open_weight_g) > 0 &&
    !["closed", "cancelled"].includes(deal.deal_status);

  return (
    <div className="space-y-6">
      {/* ── ترويسة الصفقة ─────────────────────────────────────────── */}
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="num text-2xl font-bold">{deal.deal_no}</h1>
            <DealStatusBadge status={deal.deal_status} />
            {deal.is_overdue ? <OverdueBadge /> : null}
          </div>
          <p className="text-muted mt-1 text-sm">
            {distributor?.name ?? "—"}
            {distributor?.code ? (
              <span className="num"> · {distributor.code}</span>
            ) : null}
            <span className="num">
              {" "}
              · تسليم {formatDate(deal.delivery_date)}
            </span>
            {deal.due_date ? (
              <span className="num">
                {" "}
                · استحقاق {formatDate(deal.due_date)}
              </span>
            ) : null}
          </p>
        </div>
        <div className="flex gap-2">
          <QuantityStatusBadge status={deal.quantity_status} />
          <PaymentStatusBadge status={deal.payment_status} />
        </div>
      </div>

      {/* ── مؤشرات الصفقة (§19.1) ─────────────────────────────────── */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">الكمية</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="الوزن الأصلي"
            value={<Weight value={deal.original_weight_g} />}
          />
          <StatCard
            label="المصرَّف"
            value={<Weight value={deal.sold_weight_g} />}
          />
          <StatCard
            label="المسترد"
            value={<Weight value={deal.returned_weight_g} />}
          />
          <StatCard
            label="الوزن المفتوح لدى الموزع"
            value={<Weight value={deal.open_weight_g} />}
            hint={`نسبة التسوية ${formatPercent(deal.settlement_ratio)}`}
          />
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">المال</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="القيمة الأصلية"
            value={<Money value={deal.original_value} />}
          />
          <StatCard
            label="القيمة المعدلة"
            value={<Money value={deal.adjusted_value} />}
            hint="بعد الاستردادات والتسويات"
          />
          <StatCard
            label="إجمالي المسدد"
            value={<Money value={deal.total_paid} />}
            hint={`نسبة السداد ${formatPercent(deal.payment_ratio)}`}
          />
          <StatCard
            label={
              Number(deal.remaining_balance) < 0
                ? "رصيد دائن للموزع"
                : "المتبقي على الموزع"
            }
            value={<Money value={deal.remaining_balance} signed />}
            hint={
              Number(deal.remaining_balance) < 0
                ? "يحتاج معالجة: رد أو نقل أو إبقاء كرصيد"
                : undefined
            }
          />
        </div>
      </section>

      {/*
        القسم الداخلي الحساس.

        الشريط الملون ليس زينة: هو الفصل البصري الذي يطلبه §V5.8 بين
        ما يخص الشركة وما يُشارك مع الموزع. هذه الأرقام لا تدخل أي
        مخرج للموزع — تقارير الموزع تُبنى من مصدر بيانات منفصل.
      */}
      <section className="space-y-3">
        <div className="flex items-center gap-2">
          <span className="bg-internal/10 text-internal rounded-md px-2 py-0.5 text-xs font-semibold">
            داخلي — سري
          </span>
          <h2 className="text-lg font-semibold">التكلفة والربحية</h2>
        </div>

        <Card className="border-internal/30 p-4">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <div className="text-muted text-xs">رأس المال الأصلي</div>
              <div className="mt-1 font-semibold">
                <Money value={profit?.original_capital_cost} />
              </div>
            </div>
            <div>
              <div className="text-muted text-xs">رأس المال المفتوح</div>
              <div className="mt-1 font-semibold">
                <Money value={profit?.open_capital_cost} />
              </div>
            </div>
            <div>
              <div className="text-muted text-xs">الربح المتوقع المفتوح</div>
              <div className="mt-1 font-semibold">
                <Money value={profit?.open_expected_profit} />
              </div>
            </div>
            <div>
              <div className="text-muted text-xs">الربح المحقق</div>
              <div className="text-positive mt-1 font-semibold">
                <Money value={profit?.realized_profit} />
              </div>
            </div>
          </div>

          {line ? (
            <div className="border-border mt-4 grid gap-4 border-t pt-4 sm:grid-cols-3">
              <div>
                <div className="text-muted text-xs">تكلفة الجرام</div>
                <div className="mt-1 text-sm">
                  <PerGram value={line.cost_per_g} />
                </div>
              </div>
              <div>
                <div className="text-muted text-xs">قيمة الجرام للموزع</div>
                <div className="mt-1 text-sm">
                  <PerGram value={line.deal_value_per_g} />
                </div>
              </div>
              <div>
                <div className="text-muted text-xs">الربح المتوقع لكل جرام</div>
                <div className="mt-1 text-sm">
                  <PerGram value={line.expected_profit_per_g} />
                </div>
              </div>
            </div>
          ) : null}

          <p className="text-muted mt-4 text-xs">
            الربح المتوقع مؤشر تحليلي لا يدخل في السيولة ولا في الأرباح القابلة
            للسحب. الربح يصبح محققاً عند تسجيل التصريف، والنقد المحصل مؤشر ثالث
            مستقل.
          </p>
        </Card>
      </section>

      {/* ── معالجة الرصيد الدائن (§24.5) ──────────────────────────── */}
      {hasCredit && credit && Number(credit.unresolved_amount) > 0 ? (
        <CreditResolution
          dealId={deal.deal_id}
          unresolvedAmount={credit.unresolved_amount}
          siblingDeals={siblingDeals ?? []}
          accounts={accounts ?? []}
        />
      ) : null}

      {/* ── حركات الكمية: التصريف والاسترداد (§18.3) ──────────────── */}
      {canSell && line ? (
        <section className="space-y-3">
          <h2 className="text-lg font-semibold">حركات الكمية</h2>
          <QuantityActions
            dealId={deal.deal_id}
            openWeight={deal.open_weight_g}
            costPerGram={line.cost_per_g}
            expectedProfitPerGram={line.expected_profit_per_g}
          />
        </section>
      ) : null}

      {/* ── دفتر الحركات (§24.2) ──────────────────────────────────── */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">دفتر الحركات</h2>
        <p className="text-muted text-sm">
          كل رصيد أعلاه مشتق من هذه الحركات. لا تُعدَّل حركة ولا تُحذف — التصحيح
          يكون بحركة عكسية تُضاف.
        </p>

        <TableWrap>
          <thead className="bg-surface-muted text-muted">
            <tr>
              <Th>التاريخ</Th>
              <Th>الحركة</Th>
              <Th align="end">وزن داخل</Th>
              <Th align="end">وزن مسوّى</Th>
              <Th align="end">أثر القيمة</Th>
              <Th align="end">نقد</Th>
              <Th>ملاحظة</Th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            {(ledger ?? []).map((entry) => (
              <tr key={entry.id}>
                <Td className="num text-muted whitespace-nowrap">
                  {formatDateTime(entry.occurred_at)}
                </Td>
                <Td className="font-medium">
                  {ENTRY_TYPE_LABELS[entry.entry_type]}
                </Td>
                <Td align="end">
                  {Number(entry.delivered_weight_g) !== 0 ? (
                    <Weight value={entry.delivered_weight_g} />
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </Td>
                <Td align="end">
                  {Number(entry.settled_weight_g) !== 0 ? (
                    <Weight value={entry.settled_weight_g} />
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </Td>
                <Td align="end">
                  {Number(entry.commercial_value_delta) !== 0 ? (
                    <Money value={entry.commercial_value_delta} signed />
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </Td>
                <Td align="end">
                  {Number(entry.paid_delta) !== 0 ? (
                    <Money value={entry.paid_delta} signed />
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </Td>
                <Td className="text-muted text-xs">
                  {entry.reason || entry.notes || "—"}
                </Td>
              </tr>
            ))}
          </tbody>
        </TableWrap>
      </section>
    </div>
  );
}
