import type { Metadata } from "next";

import { PageHeader } from "@/components/domain/layout";

import { ItemForm } from "./item-form";

export const metadata: Metadata = { title: "إضافة صنف" };

export default function NewItemPage() {
  return (
    <div className="mx-auto max-w-xl space-y-6">
      <PageHeader
        title="إضافة صنف"
        description="الصنف تعريف فقط — الكمية والتكلفة تخصان الدفعة"
      />
      <ItemForm />
    </div>
  );
}
