"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { logout } from "@/app/login/actions";
import { cn } from "@/lib/utils";

/** أقسام النظام — تُبنى تباعاً حسب مراحل الخطة. */
const NAV_ITEMS = [
  { href: "/dashboard", label: "لوحة التحكم" },
  { href: "/inventory", label: "المخزون" },
  { href: "/distributors", label: "الموزعون" },
  { href: "/deals", label: "الصفقات" },
  { href: "/payments", label: "التحصيل" },
  { href: "/settings", label: "الإعدادات" },
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
