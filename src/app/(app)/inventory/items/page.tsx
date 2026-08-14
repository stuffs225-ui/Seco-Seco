import { Package } from "lucide-react";
import type { Metadata } from "next";

import {
  EmptyState,
  PageHeader,
  TableWrap,
  Th,
} from "@/components/domain/layout";
import { createClient } from "@/lib/supabase/server";

import { ItemRow } from "./item-row";

export const metadata: Metadata = { title: "الأصناف" };

type Item = {
  id: string;
  code: string;
  name: string;
  description: string;
  is_active: boolean;
};

export default async function ItemsPage() {
  const supabase = await createClient();

  const { data: items, error } = await supabase
    .from("items")
    .select("id, code, name, description, is_active")
    .order("name")
    .returns<Item[]>();

  const rows = items ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="الأصناف"
        description="التعديل والتعطيل — لا حذف، حتى لا تنكسر مشتريات قديمة"
        action={{ href: "/inventory/items/new", label: "إضافة صنف" }}
      />

      {error ? (
        <p className="text-negative text-sm">
          تعذّر تحميل الأصناف: {error.message}
        </p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا توجد أصناف بعد"
          description="أضف صنفاً لتتمكن من تسجيل شراء."
          action={{ href: "/inventory/items/new", label: "إضافة صنف" }}
          icon={<Package />}
        />
      ) : (
        <TableWrap>
          <thead className="bg-surface-muted text-muted">
            <tr>
              <Th>الكود</Th>
              <Th>الاسم</Th>
              <Th>الوصف</Th>
              <Th align="end">
                <span className="sr-only">إجراءات</span>
              </Th>
            </tr>
          </thead>
          <tbody className="divide-border divide-y">
            {rows.map((item) => (
              <ItemRow key={item.id} item={item} />
            ))}
          </tbody>
        </TableWrap>
      )}
    </div>
  );
}
