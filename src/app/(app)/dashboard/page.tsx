import type { Metadata } from "next";

export const metadata: Metadata = { title: "لوحة التحكم" };

/**
 * لوحة السيولة والمركز التشغيلي (البند 24.10).
 * تُبنى مؤشراتها في المرحلة M8 من `v_cash_position` و`v_dashboard_kpis` —
 * وهي نفس المصادر التي تقرأ منها التقارير، حتى لا تختلف الأرقام بين الشاشات.
 */
export default function DashboardPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">لوحة التحكم</h1>
        <p className="text-muted mt-1 text-sm">
          مؤشرات النشاط والسيولة والربحية
        </p>
      </div>

      <div className="border-border bg-surface rounded-xl border border-dashed p-8 text-center">
        <p className="text-muted text-sm">
          تُفعَّل مؤشرات اللوحة في المرحلة M8 بعد اكتمال الصفقات والتحصيل.
        </p>
      </div>
    </div>
  );
}
