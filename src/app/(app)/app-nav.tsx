"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

/**
 * أقسام النظام.
 *
 * لا زر خروج: النظام مفتوح بلا دخول، والجلسة تُنشأ تلقائياً في الـ proxy.
 * زر خروج هنا يعيد الدخول فوراً فيبدو معطّلاً — وزر لا يعمل أسوأ من غيابه.
 */
const NAV_ITEMS = [
  { href: "/dashboard", label: "لوحة التحكم" },
  { href: "/inventory", label: "المخزون" },
  { href: "/distributors", label: "الموزعون" },
  { href: "/deals", label: "الصفقات" },
  { href: "/payments", label: "التحصيل" },
  { href: "/settings", label: "الإعدادات" },
] as const;

export function AppNav() {
  const pathname = usePathname();

  return (
    <header className="border-border bg-surface no-print sticky top-0 z-40 border-b">
      <div className="mx-auto flex w-full max-w-7xl items-center gap-4 px-4 py-3 sm:px-6">
        <Link href="/dashboard" className="text-lg font-bold whitespace-nowrap">
          سيكو سيكو
        </Link>

        <nav className="flex flex-1 items-center gap-1 overflow-x-auto">
          {NAV_ITEMS.map((item) => {
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
      </div>
    </header>
  );
}
