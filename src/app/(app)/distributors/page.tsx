import { UserPlus } from "lucide-react";
import type { Metadata } from "next";

import {
  EmptyState,
  PageHeader,
  TableWrap,
  Th,
} from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";
import type { DealStatusRow } from "@/types/deals";
import type { MoneyAmount, WeightGrams } from "@/types/schema";

import { DistributorRow } from "./distributor-row";

export const metadata: Metadata = { title: "الموزعون" };

type Distributor = {
  id: string;
  code: string;
  name: string;
  phone: string;
  notes: string;
  credit_limit_value: MoneyAmount;
  credit_limit_weight: WeightGrams;
  is_active: boolean;
};

export default async function DistributorsPage() {
  const supabase = await createClient();

  const [{ data: distributors, error }, { data: deals }] = await Promise.all([
    supabase
      .from("distributors")
      .select(
        "id, code, name, phone, notes, credit_limit_value, credit_limit_weight, is_active",
      )
      .order("name")
      .returns<Distributor[]>(),
    supabase
      .from("v_deal_status")
      .select("distributor_id, open_weight_g, remaining_balance, deal_status")
      .returns<
        Pick<
          DealStatusRow,
          | "distributor_id"
          | "open_weight_g"
          | "remaining_balance"
          | "deal_status"
        >[]
      >(),
  ]);

  /*
    ذمة الموزع ووزن عهدته مجمَّعان من صفقاته المفتوحة.

    التجميع للعرض فقط ومن قيم مشتقة أصلاً من الدفتر — لا يوجد حقل رصيد
    مخزَّن على الموزع (§26). كشف حساب الموزع الرسمي في M7 يقرأ من نفس
    المصدر حتى تتطابق الأرقام.
  */
  const totals = new Map<string, { weight: number; balance: number }>();
  for (const deal of deals ?? []) {
    if (deal.deal_status === "closed" || deal.deal_status === "cancelled") {
      continue;
    }
    const current = totals.get(deal.distributor_id) ?? {
      weight: 0,
      balance: 0,
    };
    current.weight += Number(deal.open_weight_g);
    current.balance += Number(deal.remaining_balance);
    totals.set(deal.distributor_id, current);
  }

  const rows = distributors ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="الموزعون"
        description="العهدة والذمم — مشتقة من الصفقات المفتوحة"
        action={{ href: "/distributors/new", label: "إضافة موزع" }}
      />

      {error ? (
        <p className="text-negative text-sm">
          تعذّر تحميل الموزعين: {error.message}
        </p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا يوجد موزعون بعد"
          description="أضف موزعاً لتتمكن من تسليم كميات على التصريف."
          action={{ href: "/distributors/new", label: "إضافة موزع" }}
          icon={<UserPlus />}
        />
      ) : (
        <TableWrap>
          <thead className="bg-surface-muted text-muted">
            <tr>
              <Th>الكود</Th>
              <Th>الاسم</Th>
              <Th>الهاتف</Th>
              <Th align="end">وزن العهدة</Th>
              <Th align="end">الذمة المستحقة</Th>
              <Th align="end">حد الائتمان</Th>
              <Th align="end">
                <span className="sr-only">إجراءات</span>
              </Th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            {rows.map((distributor) => {
              const total = totals.get(distributor.id) ?? {
                weight: 0,
                balance: 0,
              };
              const limit = Number(distributor.credit_limit_value);
              // حد صفر يعني بلا حد؛ التجاوز تنبيه لا منع (§24.11)
              const overLimit = limit > 0 && total.balance > limit;

              return (
                <DistributorRow
                  key={distributor.id}
                  distributor={distributor}
                  openWeight={total.weight}
                  balance={total.balance}
                  overLimit={overLimit}
                />
              );
            })}
          </tbody>
        </TableWrap>
      )}
    </div>
  );
}
