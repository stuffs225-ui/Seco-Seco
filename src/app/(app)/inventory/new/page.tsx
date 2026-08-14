import type { Metadata } from "next";
import Link from "next/link";

import { Card, PageHeader } from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";

import { PurchaseForm } from "./purchase-form";

export const metadata: Metadata = { title: "تسجيل شراء" };

export default async function NewPurchasePage() {
  const supabase = await createClient();

  const [{ data: items }, { data: suppliers }] = await Promise.all([
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

  const availableItems = items ?? [];

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="تسجيل شراء"
        description="ينشئ دفعة مستقلة ويحسب تكلفة الجرام آلياً"
      />

      {availableItems.length === 0 ? (
        <Card className="p-6 text-center">
          <p className="font-medium">لا توجد أصناف بعد</p>
          <p className="text-muted mx-auto mt-1.5 max-w-md text-sm">
            الشراء يحتاج صنفاً. أضف الصنف أولاً ثم سجّل الشراء.
          </p>
          <Link
            href="/inventory/items/new"
            className="bg-primary text-primary-foreground mt-4 inline-block rounded-lg px-4 py-2 text-sm font-medium"
          >
            إضافة صنف
          </Link>
        </Card>
      ) : (
        <PurchaseForm items={availableItems} suppliers={suppliers ?? []} />
      )}
    </div>
  );
}
