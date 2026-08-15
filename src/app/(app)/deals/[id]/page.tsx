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

import { CancelDealButton } from "./cancel-deal-button";
import { CreditResolution } from "./credit-resolution";
import { PaymentQuickForm } from "./payment-quick-form";
import { ReverseAllocationButton } from "./reverse-allocation-button";
import { SettlementPanel, type Reconciliation } from "./settlement-panel";
import { QuantityActions } from "./quantity-actions";
import { ReportPicker } from "./report-picker";

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

  /*
    مرحلة شبكة واحدة لا ثلاث.

    الرصيد الدائن حالة مشتقة من `deal` (§24.5) لا تحتاج استعلاماً منفصلاً
    لتحديدها، فاستعلاماتها تُجلب هنا دون شرط مع البقية بدل مرحلة لاحقة
    منفصلة — استعلامات مفهرَسة رخيصة، وتفادي مرحلة شبكة كاملة يستحق كلفتها
    حتى حين لا حاجة فعلية للنتيجة.
  */
  const [
    { data: profit },
    { data: ledger },
    { data: line },
    { data: distributor },
    { data: recon },
    { data: credit },
    { data: siblingDeals },
    { data: accounts },
  ] = await Promise.all([
    supabase
      .from("v_deal_profit")
      .select("*")
      .eq("deal_id", id)
      .single<DealProfitRow>(),
    supabase
      .from("deal_ledger")
      .select(
        "id, entry_type, delivered_weight_g, settled_weight_g, commercial_value_delta, cost_delta, expected_profit_delta, realized_profit_delta, paid_delta, ref_type, ref_id, reason, notes, occurred_at",
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
    supabase
      .from("v_deal_reconciliation")
      .select("*")
      .eq("deal_id", id)
      .single<Reconciliation>(),
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
  ]);

  const hasCredit = Number(deal.remaining_balance) < 0;

  const canReturn =
    Number(deal.open_weight_g) > 0 &&
    !["closed", "cancelled"].includes(deal.deal_status);
  const canRecordPayment = !["closed", "cancelled"].includes(deal.deal_status);
  // نسخة مبكرة من حارس cancel_deal في القاعدة: صفقة غير مغلقة/ملغاة
  // ولم يُسجَّل عليها بيع حقيقي (QTY_SOLD) — لا يهم عدد الدفعات أو
  // الاستردادات، فتلك كلها قابلة للعكس عند الإلغاء
  const canCancel =
    !["closed", "cancelled"].includes(deal.deal_status) &&
    !(ledger ?? []).some((entry) => entry.entry_type === "QTY_SOLD");

  // تخصيصات عُكست بالفعل — لا يُعرض زر عكس ثانٍ لها (نفس ref_id يتكرر
  // في حركة PAYMENT_REVERSAL المقابلة)
  const reversedAllocationIds = new Set(
    (ledger ?? [])
      .filter((entry) => entry.entry_type === "PAYMENT_REVERSAL")
      .map((entry) => entry.ref_id),
  );
  const canReverseAllocations = deal.deal_status !== "closed";

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
        <div className="flex flex-col items-end gap-2">
          <div className="flex gap-2">
            <QuantityStatusBadge status={deal.quantity_status} />
            <PaymentStatusBadge status={deal.payment_status} />
          </div>
          <CancelDealButton dealId={deal.deal_id} eligible={canCancel} />
        </div>
      </div>

      {/* ── مؤشرات الصفقة (§19.1) ─────────────────────────────────── */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">الكمية</h2>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
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
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
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

      {/* ── تسجيل دفعة مباشرة على هذه الصفقة (§24.4) ──────────────── */}
      {canRecordPayment ? (
        <PaymentQuickForm
          dealId={deal.deal_id}
          distributorId={deal.distributor_id}
          remainingBalance={deal.remaining_balance}
          accounts={accounts ?? []}
        />
      ) : null}

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
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
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
            <div className="border-border mt-4 grid grid-cols-2 gap-4 border-t pt-4 sm:grid-cols-3">
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

      {/* ── استرداد كمية غير مصرَّفة (§18.3) ──────────────────────── */}
      {canReturn && line ? (
        <section className="space-y-3">
          <h2 className="text-lg font-semibold">استرداد كمية</h2>
          <QuantityActions
            dealId={deal.deal_id}
            openWeight={deal.open_weight_g}
            costPerGram={line.cost_per_g}
            expectedProfitPerGram={line.expected_profit_per_g}
          />
        </section>
      ) : null}

      {/* ── المصالحة والإغلاق (§24.6) ─────────────────────────────── */}
      {recon ? (
        <section className="space-y-3">
          <SettlementPanel
            dealId={deal.deal_id}
            recon={recon}
            isClosed={deal.deal_status === "closed"}
          />
        </section>
      ) : null}

      {/* ── التقارير: الاختيار إلزامي قبل التوليد (§V5.1) ─────────── */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">التقارير</h2>
        <ReportPicker dealId={deal.deal_id} />
      </section>

      {/* ── دفتر الحركات (§24.2) ──────────────────────────────────── */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">دفتر الحركات</h2>
        <p className="text-muted text-sm">
          كل رصيد أعلاه مشتق من هذه الحركات. لا تُعدَّل حركة ولا تُحذف — التصحيح
          يكون بحركة عكسية تُضاف.
        </p>

        {/* بطاقات الجوال — الجدول أدناه للشاشات الكبيرة فقط */}
        <ul className="space-y-2 sm:hidden">
          {(ledger ?? []).map((entry) => {
            const canReverse =
              entry.entry_type === "PAYMENT_RECEIVED" &&
              canReverseAllocations &&
              entry.ref_id &&
              !reversedAllocationIds.has(entry.ref_id);

            return (
              <li key={entry.id}>
                <Card className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <span className="font-medium">
                      {ENTRY_TYPE_LABELS[entry.entry_type]}
                    </span>
                    <span className="num text-muted text-xs whitespace-nowrap">
                      {formatDateTime(entry.occurred_at)}
                    </span>
                  </div>

                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1.5 text-sm">
                    {Number(entry.delivered_weight_g) !== 0 ? (
                      <div>
                        <span className="text-muted text-xs">وزن داخل </span>
                        <Weight value={entry.delivered_weight_g} />
                      </div>
                    ) : null}
                    {Number(entry.settled_weight_g) !== 0 ? (
                      <div>
                        <span className="text-muted text-xs">وزن مسوّى </span>
                        <Weight value={entry.settled_weight_g} />
                      </div>
                    ) : null}
                    {Number(entry.commercial_value_delta) !== 0 ? (
                      <div>
                        <span className="text-muted text-xs">أثر القيمة </span>
                        <Money value={entry.commercial_value_delta} signed />
                      </div>
                    ) : null}
                    {Number(entry.paid_delta) !== 0 ? (
                      <div>
                        <span className="text-muted text-xs">نقد </span>
                        <Money value={entry.paid_delta} signed />
                      </div>
                    ) : null}
                  </div>

                  {entry.reason || entry.notes ? (
                    <p className="text-muted mt-2 text-xs">
                      {entry.reason || entry.notes}
                    </p>
                  ) : null}

                  {canReverse && entry.ref_id ? (
                    <div className="mt-3 flex justify-end">
                      <ReverseAllocationButton allocationId={entry.ref_id} />
                    </div>
                  ) : null}
                </Card>
              </li>
            );
          })}
        </ul>

        <div className="hidden sm:block">
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
                <Th>
                  <span className="sr-only">إجراءات</span>
                </Th>
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
                  <Td align="end">
                    {entry.entry_type === "PAYMENT_RECEIVED" &&
                    canReverseAllocations &&
                    entry.ref_id &&
                    !reversedAllocationIds.has(entry.ref_id) ? (
                      <ReverseAllocationButton allocationId={entry.ref_id} />
                    ) : null}
                  </Td>
                </tr>
              ))}
            </tbody>
          </TableWrap>
        </div>
      </section>
    </div>
  );
}
