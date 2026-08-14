import { requireUser } from "@/lib/auth/dal";

/**
 * تخطيط التقارير — نظيف ومهيّأ للطباعة.
 *
 * لا شريط تنقل ولا عناصر تطبيق: الصفحة كما ستخرج على الورق أو في ملف
 * PDF عند الطباعة من المتصفح. هذا هو مسار توليد PDF المعتمد لأن محرك
 * المتصفح وحده يشكّل العربية تشكيلاً صحيحاً.
 */
export default async function ReportsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireUser();

  return (
    <div className="bg-background min-h-dvh py-8 print:py-0">{children}</div>
  );
}
