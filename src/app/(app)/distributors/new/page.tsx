import type { Metadata } from "next";

import { PageHeader } from "@/components/domain/layout";

import { DistributorForm } from "./distributor-form";

export const metadata: Metadata = { title: "إضافة موزع" };

export default function NewDistributorPage() {
  return (
    <div className="mx-auto max-w-xl space-y-6">
      <PageHeader
        title="إضافة موزع"
        description="الأرصدة تُشتق من صفقاته — لا تُدخل يدوياً"
      />
      <DistributorForm />
    </div>
  );
}
