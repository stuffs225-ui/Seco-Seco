import { Handshake } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";

import {
  Card,
  EmptyState,
  PageHeader,
  TableWrap,
  Td,
  Th,
} from "@/components/domain/layout";
import { Money, Weight } from "@/components/domain/numeric";
import {
  OverdueBadge,
  PaymentStatusBadge,
  QuantityStatusBadge,
} from "@/components/domain/status-badge";
import { formatDate } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import type { DealStatusRow } from "@/types/deals";

export const metadata: Metadata = { title: "الصفقات" };

type DistributorName = { id: string; name: string };

export default async function DealsPage() {
  const supabase = await createClient();

  const [{ data: deals, error }, { data: distributors }] = await Promise.all([
    supabase
      .from("v_deal_status")
      .select("*")
      .order("delivery_date", { ascending: false })
      .returns<DealStatusRow[]>(),
    supabase
      .from("distributors")
      .select("id, name")
      .returns<DistributorName[]>(),
  ]);

  const nameById = new Map((distributors ?? []).map((d) => [d.id, d.name]));
  const rows = deals ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="الصفقات"
        description="كل تسليم لموزع صفقة مستقلة بحالتَي وزن ومال منفصلتين"
        action={{ href: "/deals/new", label: "تسليم كمية" }}
      />

      {error ? (
        <p className="text-negative text-sm">
          تعذّر تحميل الصفقات: {error.message}
        </p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا توجد صفقات بعد"
          description="كل تسليم كمية لموزع ينشئ صفقة مستقلة تجمع الوزن والقيمة والدفعات والاستردادات في مكان واحد."
          action={{ href: "/deals/new", label: "تسليم كمية" }}
          icon={<Handshake />}
        />
      ) : (
        <>
          {/* بطاقات الجوال — الجدول أدناه للشاشات الكبيرة فقط */}
          <ul className="space-y-2 sm:hidden">
            {rows.map((deal) => (
              <li key={deal.deal_id}>
                <Link href={`/deals/${deal.deal_id}`} className="block">
                  <Card interactive className="p-4">
                    <div className="flex items-start justify-between gap-2">
                      <span className="num text-accent font-medium">
                        {deal.deal_no}
                      </span>
                      <div className="flex flex-wrap justify-end gap-1">
                        <QuantityStatusBadge status={deal.quantity_status} />
                        <PaymentStatusBadge status={deal.payment_status} />
                        {deal.is_overdue ? <OverdueBadge /> : null}
                      </div>
                    </div>
                    <p className="text-muted mt-1 text-sm">
                      {nameById.get(deal.distributor_id) ?? "—"}
                      <span className="num">
                        {" "}
                        · {formatDate(deal.delivery_date)}
                      </span>
                    </p>
                    <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
                      <div>
                        <div className="text-muted text-xs">الوزن المفتوح</div>
                        <div className="mt-0.5 font-medium">
                          <Weight value={deal.open_weight_g} />
                        </div>
                      </div>
                      <div>
                        <div className="text-muted text-xs">المتبقي</div>
                        <div className="mt-0.5 font-medium">
                          <Money value={deal.remaining_balance} signed />
                        </div>
                      </div>
                    </div>
                  </Card>
                </Link>
              </li>
            ))}
          </ul>

          <div className="hidden sm:block">
            <TableWrap>
              <thead className="bg-surface-muted text-muted">
                <tr>
                  <Th>رقم الصفقة</Th>
                  <Th>الموزع</Th>
                  <Th>التسليم</Th>
                  <Th align="end">الوزن الأصلي</Th>
                  <Th align="end">الوزن المفتوح</Th>
                  <Th align="end">القيمة المعدلة</Th>
                  <Th align="end">المتبقي</Th>
                  <Th>الحالة</Th>
                </tr>
              </thead>
              <tbody className="divide-border divide-y">
                {rows.map((deal) => (
                  <tr key={deal.deal_id} className="hover:bg-surface-muted/50">
                    <Td>
                      <Link
                        href={`/deals/${deal.deal_id}`}
                        className="num text-accent font-medium hover:underline"
                      >
                        {deal.deal_no}
                      </Link>
                    </Td>
                    <Td>{nameById.get(deal.distributor_id) ?? "—"}</Td>
                    <Td className="num text-muted">
                      {formatDate(deal.delivery_date)}
                    </Td>
                    <Td align="end">
                      <Weight value={deal.original_weight_g} />
                    </Td>
                    <Td align="end" className="font-medium">
                      <Weight value={deal.open_weight_g} />
                    </Td>
                    <Td align="end">
                      <Money value={deal.adjusted_value} />
                    </Td>
                    <Td align="end" className="font-medium">
                      <Money value={deal.remaining_balance} signed />
                    </Td>
                    <Td>
                      <div className="flex flex-wrap gap-1">
                        <QuantityStatusBadge status={deal.quantity_status} />
                        <PaymentStatusBadge status={deal.payment_status} />
                        {deal.is_overdue ? <OverdueBadge /> : null}
                      </div>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </TableWrap>
          </div>
        </>
      )}
    </div>
  );
}
