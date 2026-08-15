"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

import { NAV_ITEMS } from "./app-nav";

/**
 * شريط التنقل الرئيسي على الجوال — النظام لا يُستخدم إلا من الجوال.
 *
 * ثابت أسفل الشاشة بنمط تطبيقات الجوال القياسي بدل شريط علوي يُقرأ
 * سطراً بسطر. `env(safe-area-inset-bottom)` يحجز مساحة الحافة السفلية
 * على الهواتف ذات الحافة (iPhone وغيره) فلا يُقرأ آخر تبويب تحتها.
 */
export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="border-border bg-surface/95 no-print fixed inset-x-0 bottom-0 z-40 border-t shadow-[0_-1px_4px_rgba(0,0,0,0.04)] backdrop-blur-sm sm:hidden"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <div className="flex items-stretch">
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
                "flex min-h-14 flex-1 flex-col items-center justify-center gap-0.5 px-0.5 py-1.5 text-center text-[10px] leading-tight transition-colors",
                active
                  ? "text-primary font-medium"
                  : "text-muted hover:text-foreground",
              )}
            >
              <Icon
                className={cn("size-5 shrink-0", active && "text-primary")}
                aria-hidden="true"
              />
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
