import { requireUser } from "@/lib/auth/dal";

import { AppNav } from "./app-nav";
import { BottomNav } from "./bottom-nav";

/**
 * تخطيط التطبيق المحمي. `requireUser` هنا هو الفحص المعتمد —
 * الـ proxy مجرد توجيه سريع، وRLS هو خط الدفاع الأخير.
 */
export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // الـ proxy ضمن وجود الجلسة قبل الوصول هنا؛ هذا الفحص هو المعتمد
  // على أي حال، ومن خلفه RLS كخط دفاع أخير.
  await requireUser();

  return (
    <div className="flex min-h-dvh flex-col">
      <AppNav />
      {/*
        pb-24: يحجز مساحة BottomNav الثابت على الجوال فلا يغطي آخر
        محتوى الصفحة؛ لا حاجة له على الكمبيوتر حيث BottomNav مخفي.
      */}
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 pb-24 sm:px-6 sm:pb-6">
        {children}
      </main>
      <BottomNav />
    </div>
  );
}
