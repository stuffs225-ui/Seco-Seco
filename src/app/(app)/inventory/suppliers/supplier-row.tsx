"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Td } from "@/components/domain/layout";
import { ToggleActiveButton } from "@/components/domain/toggle-active-button";
import { setSupplierActive } from "@/lib/actions/inventory";

import { SupplierForm } from "./supplier-form";

type Supplier = {
  id: string;
  name: string;
  phone: string;
  notes: string;
  is_active: boolean;
};

export function SupplierRow({ supplier }: { supplier: Supplier }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <tr>
        <td colSpan={4} className="px-4 py-4">
          <SupplierForm supplier={supplier} onSaved={() => setEditing(false)} />
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
      <Td>
        {supplier.name}
        {!supplier.is_active ? (
          <span className="text-muted text-xs"> · معطَّل</span>
        ) : null}
      </Td>
      <Td className="num text-muted">{supplier.phone || "—"}</Td>
      <Td className="text-muted">{supplier.notes || "—"}</Td>
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
            id={supplier.id}
            isActive={supplier.is_active}
            action={setSupplierActive}
            onDone={() => router.refresh()}
          />
        </div>
      </Td>
    </tr>
  );
}
