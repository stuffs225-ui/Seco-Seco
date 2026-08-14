"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Td } from "@/components/domain/layout";
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

export function ItemRow({ item }: { item: Item }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <tr>
        <td colSpan={4} className="px-4 py-4">
          <ItemForm item={item} onSaved={() => setEditing(false)} />
          <button
            type="button"
            onClick={() => setEditing(false)}
            className="text-muted mt-2 text-xs underline-offset-2 hover:underline"
          >
            إلغاء التعديل
          </button>
        </td>
      </tr>
    );
  }

  return (
    <tr className="hover:bg-surface-muted/50">
      <Td className="num font-medium">{item.code}</Td>
      <Td>
        {item.name}
        {!item.is_active ? (
          <span className="text-muted text-xs"> · معطَّل</span>
        ) : null}
      </Td>
      <Td className="text-muted">{item.description || "—"}</Td>
      <Td align="end">
        <div className="flex items-center justify-end gap-3">
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
      </Td>
    </tr>
  );
}
