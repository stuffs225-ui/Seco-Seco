import Link from "next/link";

import { cn } from "@/lib/utils";

/** ترويسة موحّدة لكل صفحة: العنوان والوصف وإجراء رئيسي اختياري. */
export function PageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: { href: string; label: string };
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 className="text-2xl font-bold">{title}</h1>
        {description ? (
          <p className="text-muted mt-1 text-sm">{description}</p>
        ) : null}
      </div>
      {action ? (
        <Link
          href={action.href}
          className="bg-primary text-primary-foreground no-print rounded-lg px-4 py-2 text-sm font-medium transition-opacity hover:opacity-90"
        >
          {action.label}
        </Link>
      ) : null}
    </div>
  );
}

/** بطاقة محتوى — الحاوية القياسية للجداول والنماذج والملخصات. */
export function Card({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "border-border bg-surface rounded-xl border shadow-sm",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** بطاقة مؤشر — رقم واحد بارز مع تسميته. */
export function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
}) {
  return (
    <Card className="p-4">
      <div className="text-muted text-xs">{label}</div>
      <div className="mt-1.5 text-xl font-semibold">{value}</div>
      {hint ? <div className="text-muted mt-1 text-xs">{hint}</div> : null}
    </Card>
  );
}

/** حالة القائمة الفارغة — تشرح ما ينقص بدل ترك مساحة بيضاء. */
export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: { href: string; label: string };
}) {
  return (
    <div className="border-border bg-surface rounded-xl border border-dashed p-10 text-center">
      <p className="font-medium">{title}</p>
      {description ? (
        <p className="text-muted mx-auto mt-1.5 max-w-md text-sm">
          {description}
        </p>
      ) : null}
      {action ? (
        <Link
          href={action.href}
          className="bg-primary text-primary-foreground mt-4 inline-block rounded-lg px-4 py-2 text-sm font-medium"
        >
          {action.label}
        </Link>
      ) : null}
    </div>
  );
}

/**
 * غلاف جدول قابل للتمرير أفقياً.
 *
 * الجداول المالية تحمل أعمدة كثيرة؛ التمرير داخل الغلاف يمنع الصفحة
 * كلها من التمرير الأفقي — وهو مزعج بوجه خاص في تخطيط RTL.
 */
export function TableWrap({ children }: { children: React.ReactNode }) {
  return (
    <Card className="overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">{children}</table>
      </div>
    </Card>
  );
}

export function Th({
  children,
  align = "start",
}: {
  children: React.ReactNode;
  align?: "start" | "end";
}) {
  return (
    <th
      className={cn(
        "px-4 py-2.5 font-medium whitespace-nowrap",
        align === "end" ? "text-end" : "text-start",
      )}
    >
      {children}
    </th>
  );
}

export function Td({
  children,
  align = "start",
  className,
}: {
  children: React.ReactNode;
  align?: "start" | "end";
  className?: string;
}) {
  return (
    <td
      className={cn(
        "px-4 py-3",
        align === "end" ? "text-end" : "text-start",
        className,
      )}
    >
      {children}
    </td>
  );
}
