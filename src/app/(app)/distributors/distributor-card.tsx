"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Card } from "@/components/domain/layout";
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

/** نسخة بطاقة من DistributorRow لعرض الجوال — نفس السلوك بالضبط. */
export function DistributorCard({
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
      <Card className="p-4">
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
      </Card>
    );
  }

  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-medium">
            {distributor.name}
            {!distributor.is_active ? (
              <span className="text-muted text-xs"> · غير نشط</span>
            ) : null}
          </div>
          <div className="num text-muted text-xs">{distributor.code}</div>
        </div>
        <div className="num text-muted text-xs whitespace-nowrap">
          {distributor.phone || "—"}
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
        <div>
          <div className="text-muted text-xs">وزن العهدة</div>
          <div className="mt-0.5 font-medium">
            <Weight value={openWeight} />
          </div>
        </div>
        <div>
          <div className="text-muted text-xs">الذمة المستحقة</div>
          <div className="mt-0.5 font-medium">
            <Money value={balance} signed />
          </div>
        </div>
        <div>
          <div className="text-muted text-xs">حد الائتمان</div>
          <div className="mt-0.5">
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
          </div>
        </div>
      </div>

      <div className="mt-3 flex items-center justify-end gap-3">
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
    </Card>
  );
}
