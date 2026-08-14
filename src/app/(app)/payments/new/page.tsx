import type { Metadata } from "next";
import Link from "next/link";

import { Card, PageHeader } from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";
import type { DealStatusRow } from "@/types/deals";

import { PaymentForm } from "./payment-form";

export const metadata: Metadata = { title: "تسجيل تحصيل" };

export default async function NewPaymentPage() {
  const supabase = await createClient();

  const [{ data: distributors }, { data: deals }, { data: accounts }] =
    await Promise.all([
      supabase
        .from("distributors")
        .select("id, code, name")
        .eq("is_active", true)
        .order("name")
        .returns<{ id: string; code: string; name: string }[]>(),
      supabase
        .from("v_deal_status")
        .select(
          "deal_id, deal_no, distributor_id, delivery_date, remaining_balance, deal_status",
        )
        .gt("remaining_balance", 0)
        .order("delivery_date")
        .returns<
          Pick<
            DealStatusRow,
            | "deal_id"
            | "deal_no"
            | "distributor_id"
            | "delivery_date"
            | "remaining_balance"
            | "deal_status"
          >[]
        >(),
      supabase
        .from("cash_accounts")
        .select("id, name")
        .eq("is_active", true)
        .order("name")
        .returns<{ id: string; name: string }[]>(),
    ]);

  const availableDistributors = distributors ?? [];

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="تسجيل تحصيل"
        description="الدفعة تُسجَّل على الموزع ثم تُخصَّص على صفقاته"
      />

      {availableDistributors.length === 0 ? (
        <Card className="p-6 text-center">
          <p className="font-medium">لا يوجد موزعون</p>
          <p className="text-muted mx-auto mt-1.5 max-w-md text-sm">
            التحصيل يحتاج موزعاً مسجَّلاً.
          </p>
          <Link
            href="/distributors/new"
            className="bg-primary text-primary-foreground mt-4 inline-block rounded-lg px-4 py-2 text-sm font-medium"
          >
            إضافة موزع
          </Link>
        </Card>
      ) : (
        <PaymentForm
          distributors={availableDistributors}
          deals={(deals ?? []).filter(
            (d) => d.deal_status !== "closed" && d.deal_status !== "cancelled",
          )}
          accounts={accounts ?? []}
        />
      )}
    </div>
  );
}
