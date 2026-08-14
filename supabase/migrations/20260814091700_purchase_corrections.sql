-- ═══════════════════════════════════════════════════════════════════════
-- 0018 — تصحيح دفعة شراء مسجَّلة بالخطأ
--
-- لا UPDATE مباشر على lots/purchases (§26 — الـ Ledger مصدر الحقيقة،
-- cost_per_g عمود مولَّد، ولا سياسة كتابة أصلاً). التصحيح هنا حركة عكسية
-- تُلغي الدفعة القديمة كاملة ثم تُنشئ دفعة جديدة بالقيم الصحيحة — نفس
-- النمط المستخدَم لإغلاق الصفقات (§21) وتوزيع الأرباح (§11).
--
-- مسموح فقط للدفعة التي لم يخرج منها أي وزن بعد (لا بيع، لا استرداد، لا
-- تسوية سابقة) — تصحيح دفعة استُهلك جزء منها يمس أرباحاً محقَّقة على
-- صفقات، والخطة تمنع صراحة تعديل فترات مقفلة بأثر رجعي (§17).
-- ═══════════════════════════════════════════════════════════════════════

-- ── استخراج منطق الإنشاء المشترك ───────────────────────────────────────
-- نفس جسم create_purchase_lot سابقاً، بلا أي تغيير في السلوك — فقط نُقل
-- إلى دالة داخلية يستدعيها create_purchase_lot و correct_purchase_lot
-- معاً، حتى لا تنحرف شيفرة مالية مكرَّرة في مكانين بمرور الوقت.
--
-- ليست security definer: تُستدعى من داخل جسم دالة security definer
-- بالفعل (create_purchase_lot أو correct_purchase_lot)، فتُنفَّذ بصلاحية
-- تلك الدالة المستدعية — لا حاجة لصلاحيات مستقلة، تماماً كنمط next_lot_no.

create or replace function public._create_purchase_lot_core(
  p_item_id         uuid,
  p_purchase_date   date,
  p_weight_g        weight_grams,
  p_purchase_value  money_amount,
  p_supplier_id     uuid,
  p_invoice_ref     text,
  p_notes           text,
  p_expenses        jsonb,
  p_audit_event     text,
  p_audit_extra     jsonb
)
returns uuid
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_purchase_id   uuid;
  v_lot_id        uuid;
  v_lot_no        text;
  v_capitalized   money_amount := 0;
  v_policy        text;
  v_expense       jsonb;
  v_include       boolean;
  v_amount        money_amount;
begin
  -- ── التحقق من المدخلات ───────────────────────────────────────────────
  -- القيود موجودة على الجداول أيضاً؛ الفحص هنا يعطي رسالة عربية مفهومة
  -- بدل نص قيد قاعدة بيانات.

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن الدفعة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_purchase_value is null or p_purchase_value < 0 then
    raise exception 'قيمة الشراء لا يمكن أن تكون سالبة.'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.items where id = p_item_id) then
    raise exception 'الصنف غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  -- ── رأس عملية الشراء ─────────────────────────────────────────────────

  insert into public.purchases
    (supplier_id, purchase_date, invoice_ref, notes, created_by)
  values
    (p_supplier_id, p_purchase_date, coalesce(p_invoice_ref, ''),
     coalesce(p_notes, ''), auth.uid())
  returning id into v_purchase_id;

  -- ── المصاريف ورسملتها (§16.7) ────────────────────────────────────────

  v_policy := public.get_setting_text('expense_capitalization');

  for v_expense in select * from jsonb_array_elements(coalesce(p_expenses, '[]'::jsonb))
  loop
    v_amount := (v_expense ->> 'amount')::money_amount;

    if v_amount is null or v_amount <= 0 then
      raise exception 'قيمة المصروف يجب أن تكون أكبر من صفر.'
        using errcode = 'check_violation';
    end if;

    v_include := case v_policy
      when 'always' then true
      when 'never'  then false
      else coalesce((v_expense ->> 'include_in_cost')::boolean, true)
    end;

    insert into public.purchase_expenses
      (purchase_id, expense_type, amount, include_in_cost, notes)
    values
      (v_purchase_id,
       coalesce(v_expense ->> 'expense_type', 'غير محدد'),
       v_amount,
       v_include,
       coalesce(v_expense ->> 'notes', ''));

    if v_include then
      v_capitalized := v_capitalized + v_amount;
    end if;
  end loop;

  -- ── الدفعة ───────────────────────────────────────────────────────────

  v_lot_no := public.next_lot_no(p_purchase_date);

  insert into public.lots (
    lot_no, item_id, purchase_id, received_date,
    purchased_weight_g, purchase_value, capitalized_expenses,
    notes, created_by
  )
  values (
    v_lot_no, p_item_id, v_purchase_id, p_purchase_date,
    p_weight_g, p_purchase_value, v_capitalized,
    coalesce(p_notes, ''), auth.uid()
  )
  returning id into v_lot_id;

  -- ── إدخال الكمية للمخزون ─────────────────────────────────────────────

  insert into public.inventory_ledger (
    lot_id, entry_type, weight_delta_g, cost_delta,
    ref_type, ref_id, notes, created_by
  )
  values (
    v_lot_id, 'LOT_RECEIVED', p_weight_g,
    p_purchase_value + v_capitalized,
    'purchase', v_purchase_id::text,
    'استلام دفعة ' || v_lot_no, auth.uid()
  );

  perform public.write_audit(
    p_audit_event,
    'lots',
    v_lot_id::text,
    coalesce(p_audit_extra, '{}'::jsonb) || jsonb_build_object(
      'lot_no',      v_lot_no,
      'item_id',     p_item_id,
      'weight_g',    p_weight_g,
      'value',       p_purchase_value,
      'capitalized', v_capitalized,
      'cost_per_g',  (select cost_per_g from public.lots where id = v_lot_id)
    )
  );

  return v_lot_id;
end;
$$;

revoke all on function public._create_purchase_lot_core(
  uuid, date, weight_grams, money_amount, uuid, text, text, jsonb, text, jsonb
) from public, anon, authenticated;

-- ── create_purchase_lot: نفس الواجهة والسلوك، الجسم مفوَّض للمشترك ─────

create or replace function public.create_purchase_lot(
  p_item_id         uuid,
  p_purchase_date   date,
  p_weight_g        weight_grams,
  p_purchase_value  money_amount,
  p_supplier_id     uuid    default null,
  p_invoice_ref     text    default '',
  p_notes           text    default '',
  p_expenses        jsonb   default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  perform public.assert_permission('purchases.manage');

  return public._create_purchase_lot_core(
    p_item_id, p_purchase_date, p_weight_g, p_purchase_value,
    p_supplier_id, p_invoice_ref, p_notes, p_expenses,
    'lot.created', '{}'::jsonb
  );
end;
$$;

comment on function public.create_purchase_lot is
  'المسار الوحيد لإنشاء دفعة شراء — معاملة ذرية واحدة (§4، §30).';

-- ── تصحيح دفعة غير مُستهلَكة ────────────────────────────────────────────

create or replace function public.correct_purchase_lot(
  p_old_lot_id      uuid,
  p_item_id         uuid,
  p_purchase_date   date,
  p_weight_g        weight_grams,
  p_purchase_value  money_amount,
  p_reason          text,
  p_supplier_id     uuid    default null,
  p_invoice_ref     text    default '',
  p_notes           text    default '',
  p_expenses        jsonb   default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_old_lot     public.lots;
  v_new_lot_id  uuid;
begin
  perform public.assert_permission('purchases.manage');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'سبب التصحيح إلزامي.' using errcode = 'check_violation';
  end if;

  select * into v_old_lot from public.lots where id = p_old_lot_id;

  if not found then
    raise exception 'الدفعة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  /*
    الحارس: لا تصحيح لدفعة خرج منها وزن بأي شكل — بيع أو استرداد أو
    تسوية أو تصحيح سابق. سلامة الحركة الوحيدة المسموحة (LOT_RECEIVED
    الأصلية) شرط ضروري، لا تفصيل.
  */
  if exists (
    select 1 from public.inventory_ledger
    where lot_id = p_old_lot_id and entry_type <> 'LOT_RECEIVED'
  ) or (
    select count(*) from public.inventory_ledger where lot_id = p_old_lot_id
  ) <> 1 then
    raise exception
      'لا يمكن تصحيح دفعة صُرِّف منها أو أُرجِع إليها شيء — سُحبت كمية أو سُجِّلت حركة عليها.'
      using errcode = 'check_violation';
  end if;

  -- حركة عكسية تُلغي الدفعة القديمة كاملة
  insert into public.inventory_ledger (
    lot_id, entry_type, weight_delta_g, cost_delta,
    ref_type, ref_id, notes, created_by
  )
  values (
    p_old_lot_id, 'ADJUSTMENT',
    -v_old_lot.purchased_weight_g, -v_old_lot.total_cost,
    'correction', p_old_lot_id::text,
    'تصحيح: إلغاء دفعة ' || v_old_lot.lot_no || ' — ' || p_reason,
    auth.uid()
  );

  v_new_lot_id := public._create_purchase_lot_core(
    p_item_id, p_purchase_date, p_weight_g, p_purchase_value,
    p_supplier_id, p_invoice_ref, p_notes, p_expenses,
    'lot.corrected',
    jsonb_build_object(
      'corrects_lot_id', p_old_lot_id,
      'corrects_lot_no', v_old_lot.lot_no,
      'reason',          p_reason
    )
  );

  return v_new_lot_id;
end;
$$;

comment on function public.correct_purchase_lot is
  'تصحيح دفعة لم يخرج منها وزن بعد: إلغاء كامل + إنشاء دفعة جديدة '
  'بالقيم الصحيحة، معاملة ذرية واحدة. لا تعديل مباشر — حركة عكسية (§26).';

revoke all on function public.correct_purchase_lot(
  uuid, uuid, date, weight_grams, money_amount, text, uuid, text, text, jsonb
) from public, anon;

grant execute on function public.correct_purchase_lot(
  uuid, uuid, date, weight_grams, money_amount, text, uuid, text, text, jsonb
) to authenticated;
