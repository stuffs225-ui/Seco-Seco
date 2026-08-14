import type { Metadata } from "next";
import Link from "next/link";

import { Card, PageHeader, StatCard } from "@/components/domain/layout";
import { Money } from "@/components/domain/numeric";
import { createClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";
import type { MoneyAmount } from "@/types/schema";

export const metadata: Metadata = { title: "لوحة التحكم" };

type CashPosition = {
  cash_available: MoneyAmount;
  distributor_receivables: MoneyAmount;
  inventory_at_warehouse: MoneyAmount;
  inventory_at_distributors: MoneyAmount;
  distributor_credits: MoneyAmount;
  realized_profit: MoneyAmount;
  open_expected_profit: MoneyAmount;
};

type Alert = {
  code: string;
  severity: "info" | "warning" | "critical";
  title: string;
  detail: string;
  entity_type: string;
  entity_id: string;
};

const SEVERITY_ORDER: Record<Alert["severity"], number> = {
  critical: 0,
  warning: 1,
  info: 2,
};

export default async function DashboardPage() {
  const supabase = await createClient();

  const [{ data: position }, { data: alerts }] = await Promise.all([
    supabase.from("v_cash_position").select("*").maybeSingle<CashPosition>(),
    supabase.from("v_alerts").select("*").returns<Alert[]>(),
  ]);

  const sortedAlerts = [...(alerts ?? [])].sort(
    (a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity],
  );

  /*
    مجموع الأصول التشغيلية.

    الربح المتوقع مستثنى عمداً (§24.10): «يجب ألا يُستخدم Expected Profit
    في احتساب النقد المتاح أو الأرباح القابلة للسحب». جمعه هنا يجعل
    النشاط يبدو أثرى مما هو، وهو بالضبط الالتباس الذي وُضعت هذه اللوحة
    لمنعه.
  */
  const totalAssets = position
    ? Number(position.cash_available) +
      Number(position.distributor_receivables) +
      Number(position.inventory_at_warehouse) +
      Number(position.inventory_at_distributors)
    : 0;

  return (
    <div className="space-y-8">
      <PageHeader
        title="لوحة التحكم"
        description="أين توجد قيمة النشاط فعلاً"
      />

      {sortedAlerts.length > 0 ? (
        <section className="space-y-3">
          <h2 className="text-lg font-semibold">
            تنبيهات تحتاج انتباهاً
            <span className="text-muted num ms-2 text-sm font-normal">
              ({sortedAlerts.length})
            </span>
          </h2>
          <div className="space-y-2">
            {sortedAlerts.slice(0, 8).map((alert, index) => (
              <Link
                key={`${alert.code}-${alert.entity_id}-${index}`}
                href={
                  alert.entity_type === "deal"
                    ? `/deals/${alert.entity_id}`
                    : alert.entity_type === "distributor"
                      ? "/distributors"
                      : "/payments"
                }
                className={cn(
                  "block rounded-lg border p-3 transition-colors",
                  alert.severity === "critical" &&
                    "border-negative/40 bg-negative/5 hover:bg-negative/10",
                  alert.severity === "warning" &&
                    "border-warning/40 bg-warning/5 hover:bg-warning/10",
                  alert.severity === "info" &&
                    "border-border bg-surface hover:bg-surface-muted",
                )}
              >
                <div className="text-sm font-medium">{alert.title}</div>
                <div className="text-muted num mt-0.5 text-xs">
                  {alert.detail}
                </div>
              </Link>
            ))}
            {sortedAlerts.length > 8 ? (
              <p className="text-muted num text-xs">
                و{sortedAlerts.length - 8} تنبيهاً آخر
              </p>
            ) : null}
          </div>
        </section>
      ) : null}

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">أين قيمة النشاط</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="النقد المتاح"
            value={<Money value={position?.cash_available} withCurrency />}
            hint="في الصندوق والبنك"
          />
          <StatCard
            label="ذمم الموزعين"
            value={
              <Money value={position?.distributor_receivables} withCurrency />
            }
            hint="مستحق على الصفقات المفتوحة"
          />
          <StatCard
            label="المخزون في المخزن"
            value={
              <Money value={position?.inventory_at_warehouse} withCurrency />
            }
            hint="بالتكلفة"
          />
          <StatCard
            label="المخزون لدى الموزعين"
            value={
              <Money value={position?.inventory_at_distributors} withCurrency />
            }
            hint="بالتكلفة — خارج المخزن"
          />
        </div>

        <Card className="p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <span className="text-sm font-medium">إجمالي الأصول التشغيلية</span>
            <Money
              value={totalAssets}
              withCurrency
              className="text-lg font-semibold"
            />
          </div>
          <p className="text-muted mt-2 text-xs">
            نقد + ذمم + مخزون. الربح المتوقع غير مشمول عمداً — ليس أصلاً بعد.
          </p>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">الالتزامات</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <StatCard
            label="أرصدة دائنة للموزعين"
            value={<Money value={position?.distributor_credits} withCurrency />}
            hint="مال الموزعين لدى الشركة — يحتاج معالجة"
          />
          <StatCard
            label="مستحقات الشركاء"
            value={<span className="text-muted text-base">قيد الإنشاء</span>}
            hint="تُفعَّل مع وحدة الشراكة"
          />
        </div>
      </section>

      {/*
        مراحل الربح الثلاث معروضة منفصلة (§24.9).

        الفصل البصري مقصود: الربح المتوقع تحليلي، والمحقق ناتج تصريف فعلي،
        والنقد شيء ثالث. دمجها في رقم واحد يجعل ربحاً على الورق يبدو
        سيولة قابلة للسحب.
      */}
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">مراحل الربح</h2>
        <div className="grid gap-4 sm:grid-cols-3">
          <StatCard
            label="ربح متوقع مفتوح"
            value={
              <Money
                value={position?.open_expected_profit}
                withCurrency
                className="text-muted"
              />
            }
            hint="مؤشر تحليلي — لا يدخل السيولة ولا التوزيع"
          />
          <StatCard
            label="ربح محقق"
            value={
              <Money
                value={position?.realized_profit}
                withCurrency
                className="text-positive"
              />
            }
            hint="من كميات صُرِّفت فعلاً"
          />
          <StatCard
            label="نقد محصَّل"
            value={<Money value={position?.cash_available} withCurrency />}
            hint="ما دخل الصندوق فعلاً"
          />
        </div>
      </section>
    </div>
  );
}
