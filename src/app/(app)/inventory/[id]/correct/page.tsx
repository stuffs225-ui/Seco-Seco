import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Card, PageHeader } from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";
import type { MoneyAmount, RatePerGram, WeightGrams } from "@/types/schema";

import { PurchaseForm } from "../../new/purchase-form";

export const metadata: Metadata = { title: "تصحيح دفعة" };

type Lot = {
  id: string;
  lot_no: string;
  item_id: string;
  purchase_id: string;
  received_date: string;
  purchased_weight_g: WeightGrams;
  purchase_value: MoneyAmount;
  total_cost: MoneyAmount;
  cost_per_g: RatePerGram;
  notes: string;
};

export default async function CorrectLotPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: lot } = await supabase
    .from("lots")
    .select(
      "id, lot_no, item_id, purchase_id, received_date, purchased_weight_g, purchase_value, total_cost, cost_per_g, notes",
    )
    .eq("id", id)
    .maybeSingle<Lot>();

  if (!lot) notFound();

  const [
    { data: purchase },
    { data: stock },
    { data: items },
    { data: suppliers },
  ] = await Promise.all([
    supabase
      .from("purchases")
      .select("supplier_id, invoice_ref")
      .eq("id", lot.purchase_id)
      .maybeSingle<{ supplier_id: string | null; invoice_ref: string }>(),
    supabase
      .from("v_lot_stock")
      .select("on_hand_weight_g")
      .eq("lot_id", id)
      .maybeSingle<{ on_hand_weight_g: WeightGrams }>(),
    supabase
      .from("items")
      .select("id, code, name")
      .eq("is_active", true)
      .order("name")
      .returns<{ id: string; code: string; name: string }[]>(),
    supabase
      .from("suppliers")
      .select("id, name")
      .eq("is_active", true)
      .order("name")
      .returns<{ id: string; name: string }[]>(),
  ]);

  /*
    نفس الحارس الموجود في correct_purchase_lot، مكرَّر هنا للعرض المبكر —
    القاعدة تبقى المرجع النهائي (RLS + الدالة)، وهذا يمنع فقط عرض نموذج
    لا يمكن حفظه أصلاً.
  */
  const untouched =
    stock != null &&
    Number(stock.on_hand_weight_g) === Number(lot.purchased_weight_g);

  if (!untouched) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <PageHeader title="تصحيح دفعة" />
        <Card className="border-warning/40 bg-warning/5 p-6 text-center">
          <p className="font-medium">لا يمكن تصحيح هذه الدفعة</p>
          <p className="text-muted mx-auto mt-1.5 max-w-md text-sm">
            صُرِّف من دفعة {lot.lot_no} أو أُرجِع إليها شيء بالفعل — تصحيح دفعة
            لمسها أي حركة يمس أرباحاً محقَّقة على صفقات. التصحيح متاح فقط
            للدفعات التي لم يخرج منها وزن بعد.
          </p>
          <Link
            href="/inventory"
            className="bg-primary text-primary-foreground mt-4 inline-block rounded-lg px-4 py-2 text-sm font-medium"
          >
            العودة إلى المخزون
          </Link>
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title={`تصحيح دفعة ${lot.lot_no}`}
        description="إلغاء الدفعة الحالية وإنشاء دفعة جديدة بالقيم الصحيحة"
      />

      <PurchaseForm
        items={items ?? []}
        suppliers={suppliers ?? []}
        correction={{
          oldLotId: lot.id,
          oldLotNo: lot.lot_no,
          weightG: lot.purchased_weight_g,
          purchaseValue: lot.purchase_value,
          costPerGram: lot.cost_per_g,
          totalCost: lot.total_cost,
          itemId: lot.item_id,
          supplierId: purchase?.supplier_id ?? "",
          purchaseDate: lot.received_date,
          invoiceRef: purchase?.invoice_ref ?? "",
          notes: lot.notes,
        }}
      />
    </div>
  );
}
