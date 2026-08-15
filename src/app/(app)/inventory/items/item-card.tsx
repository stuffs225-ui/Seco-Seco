"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Card } from "@/components/domain/layout";
import { ToggleActiveButton } from "@/components/domain/toggle-active-button";
import { setItemActive } from "@/lib/actions/inventory";

import { ItemForm } from "./new/item-form";

type Item = {
  id: string;
  code: string;
  name: string;
  description: string;
  is_active: boolean;
};

/** نسخة بطاقة من ItemRow لعرض الجوال — نفس السلوك بالضبط. */
export function ItemCard({ item }: { item: Item }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <Card className="p-4">
        <ItemForm item={item} onSaved={() => setEditing(false)} />
        <button
          type="button"
          onClick={() => setEditing(false)}
          className="text-muted mt-2 text-xs underline-offset-2 hover:underline"
        >
          إلغاء التعديل
        </button>
      </Card>
    );
  }

  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-medium">
            {item.name}
            {!item.is_active ? (
              <span className="text-muted text-xs"> · معطَّل</span>
            ) : null}
          </div>
          <div className="num text-muted text-xs">{item.code}</div>
        </div>
      </div>

      {item.description ? (
        <p className="text-muted mt-2 text-sm">{item.description}</p>
      ) : null}

      <div className="mt-3 flex items-center justify-end gap-3">
        <button
          type="button"
          onClick={() => setEditing(true)}
          className="text-muted hover:text-foreground text-xs underline-offset-2 hover:underline"
        >
          تعديل
        </button>
        <ToggleActiveButton
          id={item.id}
          isActive={item.is_active}
          action={setItemActive}
          onDone={() => router.refresh()}
        />
      </div>
    </Card>
  );
}
