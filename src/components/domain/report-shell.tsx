"use client";

import { cn } from "@/lib/utils";

/**
 * إطار التقرير المشترك.
 *
 * §V5.8 يشترط شريطاً واضحاً في شاشة المعاينة: «تقرير داخلي - سري» أو
 * «تقرير موزع - خارجي». الشريط يظهر على الشاشة وفي الطباعة معاً — إخفاؤه
 * عند الطباعة يعيد بالضبط الخطر الذي وُضع لمنعه: ورقة داخلية تصل
 * لطرف خارجي بلا علامة تميّزها.
 */
export function ReportShell({
  audience,
  title,
  subtitle,
  children,
}: {
  audience: "INTERNAL" | "DISTRIBUTOR";
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  const internal = audience === "INTERNAL";

  return (
    <div className="mx-auto max-w-4xl px-6 print:px-0">
      <div
        className={cn(
          "mb-6 flex flex-wrap items-center justify-between gap-2 rounded-lg border px-4 py-2.5 print:rounded-none",
          internal
            ? "border-internal/40 bg-internal/10 text-internal"
            : "border-external/40 bg-external/10 text-external",
        )}
      >
        <span className="text-sm font-bold">
          {internal ? "تقرير داخلي — سري" : "تقرير موزع — خارجي"}
        </span>
        <span className="text-xs">
          {internal
            ? "يحتوي التكلفة ورأس المال والربحية. لا يُشارك خارج الشركة."
            : "لا يحتوي أي بيانات تكلفة أو ربح أو رأس مال."}
        </span>
      </div>

      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{title}</h1>
          {subtitle ? (
            <p className="text-muted mt-1 text-sm">{subtitle}</p>
          ) : null}
        </div>

        <button
          type="button"
          onClick={() => window.print()}
          className="bg-primary text-primary-foreground no-print rounded-lg px-4 py-2 text-sm font-medium"
        >
          طباعة / حفظ PDF
        </button>
      </div>

      {children}
    </div>
  );
}

export function ReportSection({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="print-keep mb-6">
      <h2 className="border-border mb-3 border-b pb-1.5 text-sm font-bold">
        {title}
      </h2>
      {children}
    </section>
  );
}

export function ReportGrid({
  items,
}: {
  items: { label: string; value: React.ReactNode }[];
}) {
  return (
    <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <div key={item.label} className="flex justify-between gap-3">
          <dt className="text-muted text-sm">{item.label}</dt>
          <dd className="text-sm font-medium">{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}
