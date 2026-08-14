"use client";

import Link from "next/link";
import { useState } from "react";

import { Card } from "@/components/domain/layout";
import { cn } from "@/lib/utils";

type Audience = "INTERNAL" | "DISTRIBUTOR";

/**
 * اختيار نوع التقرير قبل التوليد (§V5.1).
 *
 * الخطة تشترط أن يؤكد المستخدم النوع عند كل تصدير «لتقليل احتمال إرسال
 * تقرير داخلي بالخطأ». لذلك لا يوجد رابط مباشر لأي تقرير: الاختيار
 * إجباري، والنوعان معروضان بأثرهما لا باسمهما فقط، ولا يوجد افتراضي
 * مختار مسبقاً يمكن الضغط عبره بلا انتباه.
 */
export function ReportPicker({ dealId }: { dealId: string }) {
  const [choice, setChoice] = useState<Audience | null>(null);

  const options: {
    value: Audience;
    label: string;
    href: string;
    shows: string;
    hides: string;
  }[] = [
    {
      value: "DISTRIBUTOR",
      label: "تقرير خارجي — للموزع",
      href: `/reports/deal/${dealId}/distributor`,
      shows:
        "الكميات والقيم المتفق عليها والدفعات والمستردات والرصيد المتبقي وحالة الصفقة.",
      hides:
        "لا يظهر أي سعر شراء أو تكلفة جرام أو رأس مال أو ربح أو هامش أو بيانات شراكة.",
    },
    {
      value: "INTERNAL",
      label: "تقرير داخلي — للشركة",
      href: `/reports/deal/${dealId}/internal`,
      shows:
        "كل تفاصيل الصفقة: التكلفة ورأس المال والربح المتوقع والمحقق وربح الجرام والهوامش.",
      hides: "سري — لا يُشارك خارج الشركة بأي حال.",
    },
  ];

  return (
    <Card className="p-5">
      <h2 className="font-semibold">إنشاء تقرير الصفقة</h2>
      <p className="text-muted mt-1 text-sm">
        اختر نوع التقرير. الاختيار إلزامي في كل مرة، ولكل نوع مصدر بيانات منفصل
        — التقرير الخارجي لا يحتوي الحقول السرية أصلاً.
      </p>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {options.map((option) => {
          const selected = choice === option.value;
          const internal = option.value === "INTERNAL";

          return (
            <button
              key={option.value}
              type="button"
              onClick={() => setChoice(option.value)}
              aria-pressed={selected}
              className={cn(
                "rounded-lg border p-4 text-start transition-colors",
                selected
                  ? internal
                    ? "border-internal bg-internal/5"
                    : "border-external bg-external/5"
                  : "border-border hover:border-muted",
              )}
            >
              <div
                className={cn(
                  "text-sm font-semibold",
                  internal ? "text-internal" : "text-external",
                )}
              >
                {option.label}
              </div>
              <p className="text-muted mt-2 text-xs">{option.shows}</p>
              <p
                className={cn(
                  "mt-1.5 text-xs font-medium",
                  internal ? "text-internal" : "text-muted",
                )}
              >
                {option.hides}
              </p>
            </button>
          );
        })}
      </div>

      <div className="mt-4 flex items-center justify-between gap-4">
        <p className="text-muted text-xs">
          كل توليد يُسجَّل في سجل التدقيق: النوع والصفقة والمستخدم والوقت.
        </p>

        {choice ? (
          <Link
            href={options.find((o) => o.value === choice)!.href}
            className="bg-primary text-primary-foreground rounded-lg px-5 py-2.5 text-sm font-medium"
          >
            فتح المعاينة
          </Link>
        ) : (
          <span className="bg-surface-muted text-muted cursor-not-allowed rounded-lg px-5 py-2.5 text-sm font-medium">
            اختر النوع أولاً
          </span>
        )}
      </div>
    </Card>
  );
}
