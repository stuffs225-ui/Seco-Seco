import type { Metadata } from "next";
import Link from "next/link";

import {
  Card,
  EmptyState,
  PageHeader,
  StatCard,
  TableWrap,
  Td,
  Th,
} from "@/components/domain/layout";
import { Money, PerGram, Weight } from "@/components/domain/numeric";
import { formatDate } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import type { MoneyAmount, RatePerGram, WeightGrams } from "@/types/schema";

export const metadata: Metadata = { title: "المخزون" };

type LotStock = {
  lot_id: string;
  lot_no: string;
  item_code: string;
  item_name: string;
  received_date: string;
  purchased_weight_g: WeightGrams;
  purchase_value: MoneyAmount;
  capitalized_expenses: MoneyAmount;
  total_cost: MoneyAmount;
  cost_per_g: RatePerGram;
  on_hand_weight_g: WeightGrams;
  out_weight_g: WeightGrams;
  on_hand_cost: MoneyAmount;
};

export default async function InventoryPage() {
  const supabase = await createClient();

  const { data: lots, error } = await supabase
    .from("v_lot_stock")
    .select("*")
    .order("received_date", { ascending: false })
    .returns<LotStock[]>();

  if (error) {
    return (
      <div className="space-y-6">
        <PageHeader title="المخزون" />
        <Card className="border-negative/40 p-4">
          <p className="text-negative text-sm">
            تعذّر تحميل المخزون: {error.message}
          </p>
        </Card>
      </div>
    );
  }

  const rows = lots ?? [];

  /*
    الإجماليات تُجمع هنا للعرض فقط، من قيم مشتقة أصلاً من دفتر الحركات.
    لا يُشتق منها رصيد محاسبي — لوحة السيولة في M8 تقرأ من v_cash_position
    حتى تتطابق أرقام كل الشاشات (§26).
  */
  const totals = rows.reduce(
    (acc, lot) => ({
      onHandWeight: acc.onHandWeight + Number(lot.on_hand_weight_g),
      outWeight: acc.outWeight + Number(lot.out_weight_g),
      onHandCost: acc.onHandCost + Number(lot.on_hand_cost),
    }),
    { onHandWeight: 0, outWeight: 0, onHandCost: 0 },
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="المخزون"
        description="الدفعات وتكلفة الجرام والرصيد المتاح"
        action={{ href: "/inventory/new", label: "تسجيل شراء" }}
      />

      <div className="no-print -mt-2 flex gap-4 text-sm">
        <Link href="/inventory/items" className="text-accent hover:underline">
          إدارة الأصناف
        </Link>
        <Link
          href="/inventory/suppliers"
          className="text-accent hover:underline"
        >
          إدارة الموردين
        </Link>
      </div>

      {rows.length === 0 ? (
        <EmptyState
          title="لا توجد دفعات بعد"
          description="ابدأ بتسجيل عملية شراء. كل شراء ينشئ دفعة مستقلة بتكلفة جرام خاصة بها، حتى لو تكرر الصنف."
          action={{ href: "/inventory/new", label: "تسجيل شراء" }}
        />
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-3">
            <StatCard
              label="الوزن المتاح في المخزن"
              value={<Weight value={totals.onHandWeight} />}
              hint={`${rows.length} دفعة`}
            />
            <StatCard
              label="الوزن لدى الموزعين"
              value={<Weight value={totals.outWeight} />}
              hint="خارج المخزن ضمن صفقات"
            />
            <StatCard
              label="تكلفة المخزون المتاح"
              value={<Money value={totals.onHandCost} withCurrency />}
              hint="بسعر التكلفة لا سعر البيع"
            />
          </div>

          <TableWrap>
            <thead className="bg-surface-muted text-muted">
              <tr>
                <Th>الدفعة</Th>
                <Th>الصنف</Th>
                <Th>تاريخ الاستلام</Th>
                <Th align="end">الوزن المشترى</Th>
                <Th align="end">تكلفة الجرام</Th>
                <Th align="end">التكلفة الإجمالية</Th>
                <Th align="end">المتاح</Th>
                <Th align="end">لدى الموزعين</Th>
                <Th>
                  <span className="sr-only">إجراءات</span>
                </Th>
              </tr>
            </thead>
            <tbody className="divide-border divide-y">
              {rows.map((lot) => (
                <tr key={lot.lot_id} className="hover:bg-surface-muted/50">
                  <Td className="num font-medium">{lot.lot_no}</Td>
                  <Td>
                    <div className="font-medium">{lot.item_name}</div>
                    <div className="num text-muted text-xs">
                      {lot.item_code}
                    </div>
                  </Td>
                  <Td className="num text-muted">
                    {formatDate(lot.received_date)}
                  </Td>
                  <Td align="end">
                    <Weight value={lot.purchased_weight_g} />
                  </Td>
                  <Td align="end">
                    <PerGram value={lot.cost_per_g} />
                    {Number(lot.capitalized_expenses) > 0 ? (
                      <div className="text-muted text-xs">شامل المصاريف</div>
                    ) : null}
                  </Td>
                  <Td align="end">
                    <Money value={lot.total_cost} />
                  </Td>
                  <Td align="end" className="font-medium">
                    <Weight value={lot.on_hand_weight_g} />
                  </Td>
                  <Td align="end">
                    <Weight value={lot.out_weight_g} className="text-muted" />
                  </Td>
                  <Td align="end">
                    {Number(lot.on_hand_weight_g) ===
                    Number(lot.purchased_weight_g) ? (
                      <Link
                        href={`/inventory/${lot.lot_id}/correct`}
                        className="text-primary text-xs font-medium hover:underline"
                      >
                        تصحيح
                      </Link>
                    ) : null}
                  </Td>
                </tr>
              ))}
            </tbody>
          </TableWrap>
        </>
      )}
    </div>
  );
}
