"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { logout } from "@/app/login/actions";
import { cn } from "@/lib/utils";

/**
 * أقسام النظام.
 *
 * `ready: false` يعني أن القسم لم يُبنَ بعد فيظهر معطّلاً بدل أن يقود
 * إلى صفحة 404 — الحالة الصادقة أوضح للمستخدم من رابط مكسور.
 */
const NAV_ITEMS = [
  { href: "/dashboard", label: "لوحة التحكم", ready: true },
  { href: "/inventory", label: "المخزون", ready: true },
  { href: "/distributors", label: "الموزعون", ready: true },
  { href: "/deals", label: "الصفقات", ready: true },
  { href: "/payments", label: "التحصيل", ready: false },
  { href: "/settings", label: "الإعدادات", ready: true },
] as const;

export function AppNav({ email }: { email: string }) {
  const pathname = usePathname();

  return (
    <header className="border-border bg-surface no-print sticky top-0 z-40 border-b">
      <div className="mx-auto flex w-full max-w-7xl items-center gap-6 px-4 py-3 sm:px-6">
        <Link href="/dashboard" className="text-lg font-bold whitespace-nowrap">
          سيكو سيكو
        </Link>

        <nav className="flex flex-1 items-center gap-1 overflow-x-auto">
          {NAV_ITEMS.map((item) => {
            if (!item.ready) {
              return (
                <span
                  key={item.href}
                  aria-disabled="true"
                  title="قيد الإنشاء"
                  className="text-muted/50 cursor-not-allowed rounded-lg px-3 py-1.5 text-sm whitespace-nowrap"
                >
                  {item.label}
                </span>
              );
            }

            const active =
              pathname === item.href || pathname.startsWith(`${item.href}/`);

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap transition-colors",
                  active
                    ? "bg-surface-muted text-foreground font-medium"
                    : "text-muted hover:text-foreground",
                )}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-3">
          <span className="text-muted hidden text-xs sm:inline" dir="ltr">
            {email}
          </span>
          <form action={logout}>
            <button
              type="submit"
              className="text-muted hover:text-foreground text-sm"
            >
              خروج
            </button>
          </form>
        </div>
      </div>
    </header>
  );
}
