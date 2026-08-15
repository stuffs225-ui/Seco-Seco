"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Card } from "@/components/domain/layout";
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

/** نسخة بطاقة من SupplierRow لعرض الجوال — نفس السلوك بالضبط. */
export function SupplierCard({ supplier }: { supplier: Supplier }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <Card className="p-4">
        <SupplierForm supplier={supplier} onSaved={() => setEditing(false)} />
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
        <div className="font-medium">
          {supplier.name}
          {!supplier.is_active ? (
            <span className="text-muted text-xs"> · معطَّل</span>
          ) : null}
        </div>
        <div className="num text-muted text-xs whitespace-nowrap">
          {supplier.phone || "—"}
        </div>
      </div>

      {supplier.notes ? (
        <p className="text-muted mt-2 text-sm">{supplier.notes}</p>
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
          id={supplier.id}
          isActive={supplier.is_active}
          action={setSupplierActive}
          onDone={() => router.refresh()}
        />
      </div>
    </Card>
  );
}
