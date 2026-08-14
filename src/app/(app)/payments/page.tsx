import { Receipt } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";

import {
  Card,
  EmptyState,
  PageHeader,
  TableWrap,
  Td,
  Th,
} from "@/components/domain/layout";
import { Money } from "@/components/domain/numeric";
import { formatDate } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import type { MoneyAmount } from "@/types/schema";

export const metadata: Metadata = { title: "التحصيل" };

const METHOD_LABELS: Record<string, string> = {
  cash: "نقد",
  transfer: "تحويل",
  cheque: "شيك",
  other: "أخرى",
};

type PaymentStatusRow = {
  payment_id: string;
  distributor_id: string;
  payment_date: string;
  amount: MoneyAmount;
  method: string;
  reference: string;
  allocated_amount: MoneyAmount;
  unallocated_amount: MoneyAmount;
};

type CreditRow = {
  deal_id: string;
  deal_no: string;
  distributor_id: string;
  credit_amount: MoneyAmount;
  unresolved_amount: MoneyAmount;
};

export default async function PaymentsPage() {
  const supabase = await createClient();

  const [{ data: payments, error }, { data: credits }, { data: distributors }] =
    await Promise.all([
      supabase
        .from("v_payment_status")
        .select("*")
        .order("payment_date", { ascending: false })
        .returns<PaymentStatusRow[]>(),
      supabase
        .from("v_distributor_credits")
        .select("*")
        .gt("unresolved_amount", 0)
        .returns<CreditRow[]>(),
      supabase
        .from("distributors")
        .select("id, name")
        .returns<{ id: string; name: string }[]>(),
    ]);

  const nameById = new Map((distributors ?? []).map((d) => [d.id, d.name]));
  const rows = payments ?? [];
  const openCredits = credits ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="التحصيل"
        description="الدفعات وتخصيصها على الصفقات"
        action={{ href: "/payments/new", label: "تسجيل تحصيل" }}
      />

      {/*
        الأرصدة الدائنة غير المعالجة تُعرض أولاً وبلون تحذيري.

        هذا مال الموزع لدى الشركة لا ربح لها (§24.5)، وتركه دون معالجة
        أحد الاستثناءات التي يطلب §24.11 التنبيه عليها.
      */}
      {openCredits.length > 0 ? (
        <Card className="border-warning/40 bg-warning/5 p-4">
          <h2 className="text-warning font-semibold">
            أرصدة دائنة تحتاج معالجة
          </h2>
          <p className="text-muted mt-1 text-sm">
            مبالغ سدّدها الموزعون تتجاوز القيمة المعدلة لصفقاتهم. لا تُعتبر
            إيراداً — يجب ردها أو نقلها لصفقة أخرى أو إبقاؤها كرصيد معلن.
          </p>
          <ul className="mt-3 space-y-1.5">
            {openCredits.map((credit) => (
              <li key={credit.deal_id} className="text-sm">
                <Link
                  href={`/deals/${credit.deal_id}`}
                  className="num text-accent hover:underline"
                >
                  {credit.deal_no}
                </Link>
                <span className="text-muted">
                  {" "}
                  · {nameById.get(credit.distributor_id) ?? "—"} ·{" "}
                </span>
                <Money value={credit.unresolved_amount} withCurrency />
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {error ? (
        <p className="text-negative text-sm">
          تعذّر تحميل التحصيلات: {error.message}
        </p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا توجد تحصيلات بعد"
          description="الدفعة تُسجَّل على مستوى الموزع ثم تُخصَّص على صفقاته، أو تبقى رصيداً غير مخصص حتى تقرر توزيعها."
          action={{ href: "/payments/new", label: "تسجيل تحصيل" }}
          icon={<Receipt />}
        />
      ) : (
        <TableWrap>
          <thead className="bg-surface-muted text-muted">
            <tr>
              <Th>التاريخ</Th>
              <Th>الموزع</Th>
              <Th>الطريقة</Th>
              <Th>المرجع</Th>
              <Th align="end">المبلغ</Th>
              <Th align="end">المخصص</Th>
              <Th align="end">غير المخصص</Th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            {rows.map((payment) => {
              const unallocated = Number(payment.unallocated_amount);
              return (
                <tr
                  key={payment.payment_id}
                  className="hover:bg-surface-muted/50"
                >
                  <Td className="num text-muted">
                    {formatDate(payment.payment_date)}
                  </Td>
                  <Td>{nameById.get(payment.distributor_id) ?? "—"}</Td>
                  <Td>{METHOD_LABELS[payment.method] ?? payment.method}</Td>
                  <Td className="num text-muted">{payment.reference || "—"}</Td>
                  <Td align="end" className="font-medium">
                    <Money value={payment.amount} />
                  </Td>
                  <Td align="end">
                    <Money value={payment.allocated_amount} />
                  </Td>
                  <Td align="end">
                    {unallocated > 0 ? (
                      <Money
                        value={payment.unallocated_amount}
                        className="text-warning font-medium"
                      />
                    ) : (
                      <span className="text-muted">—</span>
                    )}
                  </Td>
                </tr>
              );
            })}
          </tbody>
        </TableWrap>
      )}
    </div>
  );
}
