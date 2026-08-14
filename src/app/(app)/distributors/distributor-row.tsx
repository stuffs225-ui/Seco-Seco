"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Td } from "@/components/domain/layout";
import { Money, Weight } from "@/components/domain/numeric";
import { ToggleActiveButton } from "@/components/domain/toggle-active-button";
import { setDistributorActive } from "@/lib/actions/deals";

import { DistributorForm } from "./new/distributor-form";

type Distributor = {
  id: string;
  code: string;
  name: string;
  phone: string;
  notes: string;
  credit_limit_value: string;
  is_active: boolean;
};

export function DistributorRow({
  distributor,
  openWeight,
  balance,
  overLimit,
}: {
  distributor: Distributor;
  openWeight: number;
  balance: number;
  overLimit: boolean;
}) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  const limit = Number(distributor.credit_limit_value);

  if (editing) {
    return (
      <tr>
        <td colSpan={6} className="px-4 py-4">
          <DistributorForm
            distributor={distributor}
            onSaved={() => setEditing(false)}
          />
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
      <Td className="num font-medium">{distributor.code}</Td>
      <Td>
        {distributor.name}
        {!distributor.is_active ? (
          <span className="text-muted text-xs"> · غير نشط</span>
        ) : null}
      </Td>
      <Td className="num text-muted">{distributor.phone || "—"}</Td>
      <Td align="end">
        <Weight value={openWeight} />
      </Td>
      <Td align="end" className="font-medium">
        <Money value={balance} signed />
      </Td>
      <Td align="end">
        {limit > 0 ? (
          <>
            <Money value={limit} className="text-muted" />
            {overLimit ? (
              <div className="text-negative text-xs">تجاوز الحد</div>
            ) : null}
          </>
        ) : (
          <span className="text-muted">بلا حد</span>
        )}
      </Td>
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
            id={distributor.id}
            isActive={distributor.is_active}
            action={setDistributorActive}
            onDone={() => router.refresh()}
          />
        </div>
      </Td>
    </tr>
  );
}
