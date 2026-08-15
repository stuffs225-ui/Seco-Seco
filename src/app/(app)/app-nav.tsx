"use client";

import {
  Handshake,
  LayoutDashboard,
  Package,
  Settings,
  Users,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

/**
 * أقسام النظام.
 *
 * لا زر خروج: النظام مفتوح بلا دخول، والجلسة تُنشأ تلقائياً في الـ proxy.
 * زر خروج هنا يعيد الدخول فوراً فيبدو معطّلاً — وزر لا يعمل أسوأ من غيابه.
 */
const NAV_ITEMS: { href: string; label: string; icon: LucideIcon }[] = [
  { href: "/dashboard", label: "لوحة التحكم", icon: LayoutDashboard },
  { href: "/inventory", label: "المخزون", icon: Package },
  { href: "/distributors", label: "الموزعون", icon: Users },
  { href: "/deals", label: "الصفقات", icon: Handshake },
  { href: "/payments", label: "التحصيل", icon: Wallet },
  { href: "/settings", label: "الإعدادات", icon: Settings },
];

export function AppNav() {
  const pathname = usePathname();

  return (
    <header className="border-border bg-surface/90 no-print sticky top-0 z-40 border-b shadow-sm backdrop-blur-sm">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:gap-4 sm:px-6">
        <Link
          href="/dashboard"
          className="text-primary text-lg font-bold tracking-tight whitespace-nowrap"
        >
          سيكو سيكو
        </Link>

        {/*
          flex-wrap لا overflow-x-auto: تاب لا يتسع ينزل لسطر تالٍ ويبقى
          مرئياً، بدل أن يختفي خلف تمرير أفقي قد لا ينتبه له المستخدم.
        */}
        <nav className="flex flex-1 flex-wrap items-center gap-1">
          {NAV_ITEMS.map((item) => {
            const active =
              pathname === item.href || pathname.startsWith(`${item.href}/`);
            const Icon = item.icon;

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm whitespace-nowrap transition-colors",
                  active
                    ? "bg-primary/10 text-primary font-medium"
                    : "text-muted hover:bg-surface-muted hover:text-foreground",
                )}
              >
                <Icon className="size-4 shrink-0" aria-hidden="true" />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
