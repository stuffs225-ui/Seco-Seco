import type { Metadata } from "next";

import { PageHeader } from "@/components/domain/layout";

import { SupplierForm } from "../supplier-form";

export const metadata: Metadata = { title: "إضافة مورد" };

export default function NewSupplierPage() {
  return (
    <div className="mx-auto max-w-xl space-y-6">
      <PageHeader title="إضافة مورد" />
      <SupplierForm />
    </div>
  );
}
