-- ═══════════════════════════════════════════════════════════════════════
-- 0014 — دوال التسوية والإغلاق
--
-- المرجع: §21، §24.2، §24.6، §27، §28
-- ═══════════════════════════════════════════════════════════════════════

-- ── تسوية وزن معتمدة (§24.2) ───────────────────────────────────────────
-- الطريق النظامي لتفسير وزن ناقص أو زائد لدى الموزع: هدر، فرق ميزان،
-- تلف. بدونه لا يمكن إغلاق صفقة بقي فيها وزن غير مبرَّر.

create or replace function public.record_weight_adjustment(
  p_deal_id  uuid,
  p_weight_g weight_grams,
  p_reason   text,
  p_date     date default current_date
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_line        record;
  v_open_weight weight_grams;
  v_open_cost   money_amount;
  v_open_profit money_amount;
  v_cost        money_amount;
  v_profit      money_amount;
  v_entry_id    bigint;
begin
  -- §28: تسوية وزن أو قيمة = Manager/Admin
  perform public.assert_permission('deals.adjust');

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن التسوية يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'تسوية الوزن تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception 'لا يمكن تسوية وزن صفقة %.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  select
    coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0),
    coalesce(sum(cost_delta), 0),
    coalesce(sum(expected_profit_delta), 0)
  into v_open_weight, v_open_cost, v_open_profit
  from public.deal_ledger
  where deal_id = p_deal_id;

  if p_weight_g > v_open_weight then
    raise exception
      'وزن التسوية % ج يتجاوز الوزن المفتوح وهو % ج.', p_weight_g, v_open_weight
      using errcode = 'check_violation';
  end if;

  select * into v_line from public.deal_lines where deal_id = p_deal_id limit 1;

  -- عند تسوية كامل المتبقي ننقل الرصيد كما هو فيصل إلى صفر تام
  if p_weight_g = v_open_weight then
    v_cost   := v_open_cost;
    v_profit := v_open_profit;
  else
    v_cost   := round(p_weight_g * v_line.cost_per_g, 4);
    v_profit := round(p_weight_g * v_line.expected_profit_per_g, 4);
  end if;

  /*
    التسوية تخرج الوزن من العهدة وتُسقط تكلفته وربحه المتوقع.

    لا تعود الكمية للمخزون — بخلاف الاسترداد — لأنها لم تعد موجودة.
    التكلفة المسقطة خسارة تظهر في الربح النهائي للصفقة.
    ولا تمس القيمة التجارية: ما يدين به الموزع قرار تجاري منفصل يُعالَج
    بتسوية تجارية إن لزم.
  */
  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    settled_weight_g, cost_delta, expected_profit_delta,
    ref_type, reason, occurred_at, created_by
  )
  values (
    p_deal_id, v_line.id, 'WEIGHT_ADJUSTMENT',
    p_weight_g, -v_cost, -v_profit,
    'weight_adjustment', p_reason, p_date::timestamptz, auth.uid()
  )
  returning id into v_entry_id;

  perform public.write_audit(
    'deal.weight_adjusted', 'deals', p_deal_id::text,
    jsonb_build_object('weight_g', p_weight_g, 'cost', v_cost, 'reason', p_reason)
  );

  return v_entry_id;
end;
$$;

-- ── تسوية تجارية معتمدة (§24.2) ────────────────────────────────────────

create or replace function public.record_commercial_adjustment(
  p_deal_id uuid,
  p_amount  money_amount,
  p_reason  text,
  p_date    date default current_date
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal     record;
  v_entry_id bigint;
begin
  perform public.assert_permission('deals.adjust');

  if p_amount is null or p_amount = 0 then
    raise exception 'مبلغ التسوية التجارية لا يمكن أن يكون صفراً.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'التسوية التجارية تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception 'لا يمكن تسوية صفقة %.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- موجب يزيد ما على الموزع، وسالب خصم تجاري معتمد يخفضه
  insert into public.deal_ledger (
    deal_id, entry_type, commercial_value_delta,
    ref_type, reason, occurred_at, created_by
  )
  values (
    p_deal_id, 'COMMERCIAL_ADJUSTMENT', p_amount,
    'commercial_adjustment', p_reason, p_date::timestamptz, auth.uid()
  )
  returning id into v_entry_id;

  perform public.write_audit(
    'deal.commercial_adjusted', 'deals', p_deal_id::text,
    jsonb_build_object('amount', p_amount, 'reason', p_reason)
  );

  return v_entry_id;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- إغلاق الصفقة (§21، §24.6)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.close_deal(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_recon       record;
  v_profit      record;
  v_version     int;
  v_snapshot_id uuid;
begin
  -- §28: إغلاق Deal = Authorized Manager
  perform public.assert_permission('deals.close');

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status = 'closed' then
    raise exception 'الصفقة مغلقة أصلاً.' using errcode = 'restrict_violation';
  end if;

  if v_deal.status = 'cancelled' then
    raise exception 'الصفقة ملغاة.' using errcode = 'restrict_violation';
  end if;

  select * into v_recon from public.v_deal_reconciliation where deal_id = p_deal_id;

  /*
    بوابة الإغلاق (§24.6).

    كل شرط برسالته الخاصة لأن «لا يمكن الإغلاق» وحدها لا تفيد المستخدم
    بشيء؛ عليه أن يعرف أي جرام أو ريال لم يُفسَّر بعد.
  */
  if not v_recon.weight_settled then
    raise exception
      'لا يمكن الإغلاق: ما زال لدى الموزع % ج غير مسوّاة. سجّل تصريفاً أو استرداداً أو تسوية وزن معتمدة.',
      v_recon.open_weight_g
      using errcode = 'restrict_violation';
  end if;

  if not v_recon.payment_settled then
    if v_recon.remaining_balance > 0 then
      raise exception
        'لا يمكن الإغلاق: ما زال على الموزع % غير مسدد. سجّل تحصيلاً أو تسوية تجارية معتمدة.',
        v_recon.remaining_balance
        using errcode = 'restrict_violation';
    else
      raise exception
        'لا يمكن الإغلاق: للموزع رصيد دائن % يحتاج معالجة أولاً.',
        -v_recon.remaining_balance
        using errcode = 'restrict_violation';
    end if;
  end if;

  if not v_recon.weight_explained or not v_recon.money_explained then
    raise exception
      'لا يمكن الإغلاق: توجد فروقات غير مفسرة — وزن % ومال %.',
      v_recon.unexplained_weight, v_recon.unexplained_money
      using errcode = 'restrict_violation';
  end if;

  -- ── اللقطة النهائية (§21) ────────────────────────────────────────────

  select * into v_profit from public.v_deal_profit where deal_id = p_deal_id;

  select coalesce(max(version), 0) + 1 into v_version
  from public.deal_closing_snapshots where deal_id = p_deal_id;

  insert into public.deal_closing_snapshots (
    deal_id, version, closed_by,
    original_weight_g, sold_weight_g, returned_weight_g, adjusted_weight_g,
    original_value, adjusted_value, total_paid,
    original_capital_cost, returned_capital_cost, cost_of_goods_sold,
    original_expected_profit, cancelled_expected_profit, realized_profit,
    details
  )
  values (
    p_deal_id, v_version, auth.uid(),
    v_recon.original_weight_g, v_recon.sold_weight_g,
    v_recon.returned_weight_g, v_recon.adjusted_weight_g,
    v_recon.original_value, v_recon.adjusted_value, v_recon.total_paid,
    v_profit.original_capital_cost, v_profit.returned_capital_cost,
    v_profit.cost_of_goods_sold,
    v_profit.original_expected_profit, v_profit.cancelled_expected_profit,
    v_profit.realized_profit,
    jsonb_build_object(
      'deal_no',            v_deal.deal_no,
      'distributor_id',     v_deal.distributor_id,
      'delivery_date',      v_deal.delivery_date,
      'due_date',           v_deal.due_date,
      'open_capital_cost',  v_profit.open_capital_cost,
      'closed_at',          now()
    )
  )
  returning id into v_snapshot_id;

  insert into public.deal_ledger (
    deal_id, entry_type, ref_type, ref_id, reason, created_by
  )
  values (
    p_deal_id, 'DEAL_CLOSE', 'closing_snapshot', v_snapshot_id::text,
    'إغلاق بعد مصالحة بلا فروقات', auth.uid()
  );

  update public.deals
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = p_deal_id;

  perform public.write_audit(
    'deal.closed', 'deals', p_deal_id::text,
    jsonb_build_object(
      'snapshot_id',     v_snapshot_id,
      'version',         v_version,
      'realized_profit', v_profit.realized_profit
    )
  );

  return v_snapshot_id;
end;
$$;

comment on function public.close_deal is
  'يغلق الصفقة بعد التحقق من المصالحة (§24.6) وينشئ لقطة نهائية ثابتة '
  '(§21). يرفض الإغلاق بوزن مفتوح أو رصيد مالي أو فروقات غير مفسرة.';

-- ── إعادة الفتح (§21، §28: Admin فقط) ──────────────────────────────────

create or replace function public.reopen_deal(
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
  v_snapshot_id uuid;
  v_reopen_id   uuid;
begin
  perform public.assert_permission('deals.reopen');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'إعادة فتح الصفقة تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status <> 'closed' then
    raise exception 'الصفقة ليست مغلقة.' using errcode = 'restrict_violation';
  end if;

  select id into v_snapshot_id
  from public.deal_closing_snapshots
  where deal_id = p_deal_id
  order by version desc limit 1;

  -- لقطة الإغلاق السابقة تبقى محفوظة (§21)؛ نسجل فقط أنه أُعيد الفتح
  insert into public.deal_reopenings (deal_id, snapshot_id, reason, reopened_by)
  values (p_deal_id, v_snapshot_id, p_reason, auth.uid())
  returning id into v_reopen_id;

  update public.deals
  set status = 'reopened', closed_at = null, closed_by = null
  where id = p_deal_id;

  perform public.write_audit(
    'deal.reopened', 'deals', p_deal_id::text,
    jsonb_build_object(
      'reason',               p_reason,
      'previous_snapshot_id', v_snapshot_id
    )
  );

  return v_reopen_id;
end;
$$;

comment on function public.reopen_deal is
  'إعادة فتح صفقة مغلقة بصلاحية خاصة مع سبب موثق. لقطة الإغلاق السابقة '
  'تبقى محفوظة ويُنشأ إغلاق بنسخة جديدة لاحقاً (§21).';

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.record_weight_adjustment(uuid, weight_grams, text, date)
  from public, anon;
grant execute on function public.record_weight_adjustment(uuid, weight_grams, text, date)
  to authenticated;

revoke all on function public.record_commercial_adjustment(uuid, money_amount, text, date)
  from public, anon;
grant execute on function public.record_commercial_adjustment(uuid, money_amount, text, date)
  to authenticated;

revoke all on function public.close_deal(uuid) from public, anon;
grant execute on function public.close_deal(uuid) to authenticated;

revoke all on function public.reopen_deal(uuid, text) from public, anon;
grant execute on function public.reopen_deal(uuid, text) to authenticated;
