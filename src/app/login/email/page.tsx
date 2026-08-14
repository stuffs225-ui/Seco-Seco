import type { Metadata } from "next";
import Link from "next/link";

import { LoginForm } from "../login-form";

export const metadata: Metadata = { title: "الدخول بالبريد" };

/**
 * مسار احتياطي للدخول.
 *
 * يعمل حين لا يكون مفتاح service_role مضبوطاً — فيبقى النظام قابلاً
 * للوصول بدل أن يُقفل تماماً — وهو أيضاً المسار الذي ستستخدمه بقية
 * الأدوار عند تفعيلها، لأن رمز الدخول يفتح حساب المالك وحده.
 */
export default async function EmailLoginPage({
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
          <p className="text-muted mt-2 text-sm">الدخول ببريد وكلمة مرور</p>
        </div>

        <div className="border-border bg-surface rounded-xl border p-6 shadow-sm">
          <LoginForm next={next} />
        </div>

        <p className="mt-6 text-center text-xs">
          <Link
            href={next ? `/login?next=${encodeURIComponent(next)}` : "/login"}
            className="text-muted hover:text-foreground underline"
          >
            الدخول برمز
          </Link>
        </p>
      </div>
    </main>
  );
}
