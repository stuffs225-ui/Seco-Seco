import { requireUser } from "@/lib/auth/dal";
import { isOpenAccessEnabled } from "@/lib/supabase/admin";

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
  const [user, openAccess] = await Promise.all([
    requireUser(),
    isOpenAccessEnabled(),
  ]);

  return (
    <div className="flex min-h-dvh flex-col">
      <AppNav email={user.email ?? ""} openAccess={openAccess} />
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6">
        {children}
      </main>
    </div>
  );
}
