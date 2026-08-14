import type { Metadata } from "next";

import {
  EmptyState,
  PageHeader,
  TableWrap,
  Th,
} from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";

import { SupplierRow } from "./supplier-row";

export const metadata: Metadata = { title: "الموردون" };

type Supplier = {
  id: string;
  name: string;
  phone: string;
  notes: string;
  is_active: boolean;
};

export default async function SuppliersPage() {
  const supabase = await createClient();

  const { data: suppliers, error } = await supabase
    .from("suppliers")
    .select("id, name, phone, notes, is_active")
    .order("name")
    .returns<Supplier[]>();

  const rows = suppliers ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="الموردون"
        description="التعديل والتعطيل — لا حذف، حتى لا تنكسر مشتريات قديمة"
        action={{ href: "/inventory/suppliers/new", label: "إضافة مورد" }}
      />

      {error ? (
        <p className="text-negative text-sm">
          تعذّر تحميل الموردين: {error.message}
        </p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا يوجد موردون بعد"
          description="المورد اختياري لكل شراء — أضفه إن أردت ربط الفواتير به."
          action={{ href: "/inventory/suppliers/new", label: "إضافة مورد" }}
        />
      ) : (
        <TableWrap>
          <thead className="bg-surface-muted text-muted">
            <tr>
              <Th>الاسم</Th>
              <Th>الهاتف</Th>
              <Th>ملاحظات</Th>
              <Th align="end">
                <span className="sr-only">إجراءات</span>
              </Th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            {rows.map((supplier) => (
              <SupplierRow key={supplier.id} supplier={supplier} />
            ))}
          </tbody>
        </TableWrap>
      )}
    </div>
  );
}
