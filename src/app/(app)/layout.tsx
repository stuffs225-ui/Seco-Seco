import { requireUser } from "@/lib/auth/dal";

import { AppNav } from "./app-nav";

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
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6">
        {children}
      </main>
    </div>
  );
}
