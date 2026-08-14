import type { Metadata } from "next";

import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "تسجيل الدخول" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;

  return (
    <main className="flex min-h-dvh items-center justify-center p-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-3xl font-bold tracking-tight">سيكو سيكو</h1>
          <p className="text-muted mt-2 text-sm">
            نظام إدارة المخزون والتوزيع والشراكة
          </p>
        </div>

        <div className="border-border bg-surface rounded-xl border p-6 shadow-sm">
          <LoginForm next={next} />
        </div>

        <p className="text-muted mt-6 text-center text-xs">
          الوصول بالدعوة فقط. راجع مدير النظام لإنشاء حساب.
        </p>
      </div>
    </main>
  );
}
