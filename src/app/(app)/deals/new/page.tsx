import type { Metadata } from "next";
import Link from "next/link";

import { Card, PageHeader } from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";

import { OpenDealForm } from "./open-deal-form";

export const metadata: Metadata = { title: "تسليم كمية" };

export default async function NewDealPage() {
  const supabase = await createClient();

  const [{ data: distributors }, { data: lots }, { data: openDeals }] =
    await Promise.all([
      supabase
        .from("distributors")
        .select("id, code, name")
        .eq("is_active", true)
        .order("name")
        .returns<{ id: string; code: string; name: string }[]>(),
      supabase
        .from("v_lot_stock")
        .select("lot_id, lot_no, item_name, on_hand_weight_g, cost_per_g")
        .gt("on_hand_weight_g", 0)
        .order("received_date")
        .returns<
          {
            lot_id: string;
            lot_no: string;
            item_name: string;
            on_hand_weight_g: string;
            cost_per_g: string;
          }[]
        >(),
      // §27/6: قبل التسليم يجب أن يعرف المستخدم أن للموزع صفقات مفتوحة
      supabase
        .from("v_deal_status")
        .select(
          "deal_id, deal_no, distributor_id, open_weight_g, remaining_balance",
        )
        .not("deal_status", "in", '("closed","cancelled")')
        .returns<
          {
            deal_id: string;
            deal_no: string;
            distributor_id: string;
            open_weight_g: string;
            remaining_balance: string;
          }[]
        >(),
    ]);

  const availableDistributors = distributors ?? [];
  const availableLots = lots ?? [];
  const blocker =
    availableDistributors.length === 0
      ? {
          title: "لا يوجد موزعون",
          body: "التسليم يحتاج موزعاً مسجَّلاً.",
          href: "/distributors/new",
          label: "إضافة موزع",
        }
      : availableLots.length === 0
        ? {
            title: "لا توجد دفعات بها رصيد",
            body: "التسليم يحتاج دفعة فيها وزن متاح في المخزن.",
            href: "/inventory/new",
            label: "تسجيل شراء",
          }
        : null;

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="تسليم كمية لموزع"
        description="ينشئ صفقة مستقلة وينقل الوزن من المخزن إلى عهدة الموزع"
      />

      {blocker ? (
        <Card className="p-6 text-center">
          <p className="font-medium">{blocker.title}</p>
          <p className="text-muted mx-auto mt-1.5 max-w-md text-sm">
            {blocker.body}
          </p>
          <Link
            href={blocker.href}
            className="bg-primary text-primary-foreground mt-4 inline-block rounded-lg px-4 py-2 text-sm font-medium"
          >
            {blocker.label}
          </Link>
        </Card>
      ) : (
        <OpenDealForm
          distributors={availableDistributors}
          lots={availableLots}
          openDeals={openDeals ?? []}
        />
      )}
    </div>
  );
}
