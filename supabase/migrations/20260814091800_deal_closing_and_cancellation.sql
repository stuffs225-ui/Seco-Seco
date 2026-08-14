-- ═══════════════════════════════════════════════════════════════════════
-- 0019 — إغلاق بضغطة واحدة، وإلغاء صفقة لم يمسها شيء
--
-- كلاهما تنسيق فوق دوال مختبرة فعلاً — لا منطق مالي جديد.
-- ═══════════════════════════════════════════════════════════════════════

-- ── إغلاق يعتبر الباقي مصرَّفاً بالكامل ──────────────────────────────────
--
-- بعض المالكين لا يتتبعون كمية التصريف الفعلية — يهمهم التحصيل فقط،
-- وهو مستقل عن الوزن أصلاً (record_payment لا يمس الوزن إطلاقاً). لحظة
-- الإغلاق الوحيدة تشترط وزناً مفتوحاً صفراً؛ هذه الدالة تسوّي الباقي
-- كتصريف حقيقي (يُحقق الربح بشكل صحيح) بدل إجبار المستخدم على تسوية
-- معتمدة تُسقط التكلفة والربح كخسارة — خطأ لمن حصّل المبلغ فعلاً.

create or replace function public.close_deal_settling_remainder(
  p_deal_id uuid,
  p_notes   text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_open_weight weight_grams;
begin
  select coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0)
    into v_open_weight
  from public.deal_ledger
  where deal_id = p_deal_id;

  if v_open_weight > 0 then
    perform public.record_deal_sale(
      p_deal_id, v_open_weight, current_date,
      coalesce(nullif(btrim(p_notes), ''), 'إغلاق بضغطة واحدة — اعتبار الباقي مصرَّفاً بالكامل')
    );
  end if;

  return public.close_deal(p_deal_id);
end;
$$;

comment on function public.close_deal_settling_remainder is
  'تسجّل الوزن المفتوح كتصريف كامل ثم تغلق — لمن لا يتتبع كمية التصريف '
  'ويكتفي بالتحصيل. تفوّض بالكامل لـ record_deal_sale وclose_deal '
  'المختبرتين، فيبقى فحص الصلاحية والتسديد كما هو دون تكرار.';

revoke all on function public.close_deal_settling_remainder(uuid, text)
  from public, anon;
grant execute on function public.close_deal_settling_remainder(uuid, text)
  to authenticated;

-- ── إلغاء صفقة لم يمسها شيء بعد التسليم ──────────────────────────────────
--
-- نفس فلسفة correct_purchase_lot: صفقة أُنشئت بالخطأ (موزع غلط، وزن
-- غلط) ولم يُسجَّل عليها أي حركة غير التسليم الأول — قابلة للإلغاء
-- الكامل. صفقة عليها تصريف أو دفعة أو استرداد تمسّ أرباحاً أو نقداً
-- حقيقيين، فتُرفض وتُوجَّه للاسترداد بدلاً من الإلغاء.

create or replace function public.cancel_deal(
  p_deal_id uuid,
  p_reason  text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_entry_count int;
  v_open_weight weight_grams;
begin
  -- الإلغاء عكس تسليم فعلياً — نفس صلاحية الاسترداد (§28)
  perform public.assert_permission('deals.return');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'سبب الإلغاء إلزامي.' using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception 'الصفقة % بالفعل — لا يمكن إلغاؤها.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  select count(*) into v_entry_count
  from public.deal_ledger
  where deal_id = p_deal_id;

  if v_entry_count <> 1 then
    raise exception
      'لا يمكن إلغاء صفقة سُجِّلت عليها حركة غير التسليم الأول — استخدم الاسترداد أو التسوية بدل الإلغاء.'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(delivered_weight_g), 0) into v_open_weight
  from public.deal_ledger
  where deal_id = p_deal_id;

  -- يفوّض الحركة العكسية كاملة لدالة الاسترداد المختبرة — لا شيفرة كتابة جديدة
  perform public.record_deal_return(p_deal_id, v_open_weight, current_date, p_reason);

  update public.deals set status = 'cancelled' where id = p_deal_id;

  perform public.write_audit(
    'deal.cancelled', 'deals', p_deal_id::text,
    jsonb_build_object('reason', p_reason, 'weight_g', v_open_weight)
  );

  return p_deal_id;
end;
$$;

comment on function public.cancel_deal is
  'إلغاء كامل لصفقة لم يُسجَّل عليها غير التسليم الأول. تفوّض للاسترداد '
  'المختبر لعكس المخزون، ثم تنقل الحالة إلى cancelled (§24.3).';

revoke all on function public.cancel_deal(uuid, text) from public, anon;
grant execute on function public.cancel_deal(uuid, text) to authenticated;
