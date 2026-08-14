-- ═══════════════════════════════════════════════════════════════════════
-- 0012 — دوال التحصيل والتخصيص ومعالجة الرصيد الدائن
--
-- المرجع: §18.5، §24.4، §24.5، §27، §28، §30
-- ═══════════════════════════════════════════════════════════════════════

-- ── دالة داخلية: تخصيص مبلغ لصفقة ──────────────────────────────────────
-- تُستدعى من record_payment و allocate_payment، فلا يتكرر منطق الكتابة
-- في دفتر الصفقة في موضعين قد يفترقان.

create or replace function public.allocate_payment_internal(
  p_payment_id uuid,
  p_deal_id    uuid,
  p_amount     money_amount
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment       record;
  v_deal          record;
  v_allocation_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ التخصيص يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  select * into v_payment from public.payments where id = p_payment_id;
  if not found then
    raise exception 'الدفعة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  -- دفعة موزع لا تُخصَّص لصفقة موزع آخر
  if v_deal.distributor_id <> v_payment.distributor_id then
    raise exception 'لا يمكن تخصيص دفعة موزع لصفقة موزع آخر.'
      using errcode = 'check_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception
      'لا يمكن التخصيص لصفقة % — أعد فتحها أولاً.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- التريجر على الجدول يمنع تجاوز قيمة الدفعة (§24.4)
  insert into public.payment_allocations (payment_id, deal_id, amount, created_by)
  values (p_payment_id, p_deal_id, p_amount, auth.uid())
  returning id into v_allocation_id;

  /*
    الحركة في دفتر الصفقة.

    PAYMENT_RECEIVED يمس الرصيد المالي وحده: لا وزن ولا تكلفة ولا ربح.
    السداد لا يعني تصريفاً ولا يغيّر شيئاً في الكمية (§24.2، §24.9).
  */
  insert into public.deal_ledger (
    deal_id, entry_type, paid_delta, ref_type, ref_id, reason, occurred_at, created_by
  )
  values (
    p_deal_id, 'PAYMENT_RECEIVED', p_amount,
    'payment_allocation', v_allocation_id::text,
    'تحصيل مرجع ' || coalesce(nullif(v_payment.reference, ''), v_payment.payment_date::text),
    v_payment.payment_date::timestamptz, auth.uid()
  );

  return v_allocation_id;
end;
$$;

-- ── تسجيل دفعة (§24.4) ─────────────────────────────────────────────────

create or replace function public.record_payment(
  p_distributor_id  uuid,
  p_amount          money_amount,
  p_payment_date    date default current_date,
  p_method          public.payment_method default 'cash',
  p_reference       text default '',
  p_cash_account_id uuid default null,
  p_notes           text default '',
  -- سياسة التخصيص: specific أو oldest_first أو unallocated
  p_allocation_mode text default 'unallocated',
  -- للوضع specific: [{"deal_id":"…","amount":1000}]
  p_allocations     jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment_id  uuid;
  v_allocation  jsonb;
  v_remaining   money_amount;
  v_deal        record;
  v_deal_due    money_amount;
  v_take        money_amount;
begin
  perform public.assert_permission('payments.record');

  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ الدفعة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.distributors where id = p_distributor_id) then
    raise exception 'الموزع غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  insert into public.payments (
    distributor_id, payment_date, amount, method, reference,
    cash_account_id, notes, created_by
  )
  values (
    p_distributor_id, p_payment_date, p_amount, p_method,
    coalesce(p_reference, ''), p_cash_account_id, coalesce(p_notes, ''), auth.uid()
  )
  returning id into v_payment_id;

  -- النقد يدخل الصندوق بمجرد استلامه، بغض النظر عن تخصيصه لاحقاً
  if p_cash_account_id is not null then
    insert into public.cash_transactions (
      account_id, amount, occurred_at, ref_type, ref_id, notes, created_by
    )
    values (
      p_cash_account_id, p_amount, p_payment_date::timestamptz,
      'payment', v_payment_id::text, 'تحصيل من موزع', auth.uid()
    );
  end if;

  -- ── التخصيص (§24.4) ──────────────────────────────────────────────────

  if p_allocation_mode = 'specific' then
    perform public.assert_permission('payments.allocate');

    for v_allocation in
      select * from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    loop
      perform public.allocate_payment_internal(
        v_payment_id,
        (v_allocation ->> 'deal_id')::uuid,
        (v_allocation ->> 'amount')::money_amount
      );
    end loop;

  elsif p_allocation_mode = 'oldest_first' then
    perform public.assert_permission('payments.allocate');

    v_remaining := p_amount;

    /*
      التوزيع على أقدم الاستحقاقات.

      نقرأ الرصيد المتبقي من v_deal_money لا من حقل مخزَّن، ونتوقف عند
      نفاد المبلغ. ما يتبقى بلا تخصيص يبقى رصيداً غير مخصص ظاهراً في
      كشف الموزع — لا يُفرض على صفقة لم يخترها المستخدم.
    */
    for v_deal in
      select d.id, d.delivery_date
      from public.deals d
      join public.v_deal_money m on m.deal_id = d.id
      where d.distributor_id = p_distributor_id
        and d.status not in ('closed', 'cancelled')
        and m.remaining_balance > 0
      order by d.delivery_date nulls last, d.created_at
    loop
      exit when v_remaining <= 0;

      select remaining_balance into v_deal_due
      from public.v_deal_money where deal_id = v_deal.id;

      v_take := least(v_remaining, v_deal_due);

      if v_take > 0 then
        perform public.allocate_payment_internal(v_payment_id, v_deal.id, v_take);
        v_remaining := v_remaining - v_take;
      end if;
    end loop;
  end if;
  -- الوضع unallocated: الدفعة تُحفظ بلا تخصيص حتى يقرر المستخدم

  perform public.write_audit(
    'payment.recorded', 'payments', v_payment_id::text,
    jsonb_build_object(
      'distributor_id',  p_distributor_id,
      'amount',          p_amount,
      'method',          p_method,
      'allocation_mode', p_allocation_mode
    )
  );

  return v_payment_id;
end;
$$;

comment on function public.record_payment is
  'تسجيل تحصيل من موزع مع تخصيص اختياري: محدد أو على الأقدم أو بلا '
  'تخصيص يبقى رصيداً مفتوحاً (§24.4).';

-- ── تخصيص لاحق لدفعة قائمة ─────────────────────────────────────────────

create or replace function public.allocate_payment(
  p_payment_id uuid,
  p_deal_id    uuid,
  p_amount     money_amount
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_allocation_id uuid;
begin
  perform public.assert_permission('payments.allocate');

  v_allocation_id := public.allocate_payment_internal(
    p_payment_id, p_deal_id, p_amount);

  perform public.write_audit(
    'payment.allocated', 'payment_allocations', v_allocation_id::text,
    jsonb_build_object(
      'payment_id', p_payment_id,
      'deal_id',    p_deal_id,
      'amount',     p_amount
    )
  );

  return v_allocation_id;
end;
$$;

-- ── عكس تخصيص (§24.4) ──────────────────────────────────────────────────

create or replace function public.reverse_payment_allocation(
  p_allocation_id uuid,
  p_reason        text
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_allocation record;
  v_deal       record;
begin
  perform public.assert_permission('payments.reverse');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'عكس التخصيص يحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_allocation
  from public.payment_allocations
  where id = p_allocation_id
  for update;

  if not found then
    raise exception 'التخصيص غير موجود.' using errcode = 'foreign_key_violation';
  end if;

  if v_allocation.reversed_at is not null then
    raise exception 'التخصيص معكوس أصلاً.' using errcode = 'restrict_violation';
  end if;

  select * into v_deal from public.deals where id = v_allocation.deal_id;

  if v_deal.status = 'closed' then
    raise exception
      'الصفقة مغلقة. أعد فتحها بصلاحية مدير قبل عكس التخصيص.'
      using errcode = 'restrict_violation';
  end if;

  update public.payment_allocations
  set reversed_at = now(), reversed_by = auth.uid(), reversal_reason = p_reason
  where id = p_allocation_id;

  -- العكس حركة تُضاف؛ الحركة الأصلية تبقى في الدفتر كما هي (§24.2)
  insert into public.deal_ledger (
    deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
  )
  values (
    v_allocation.deal_id, 'PAYMENT_REVERSAL', -v_allocation.amount,
    'payment_allocation', p_allocation_id::text, p_reason, auth.uid()
  );

  perform public.write_audit(
    'payment.allocation_reversed', 'payment_allocations', p_allocation_id::text,
    jsonb_build_object(
      'deal_id', v_allocation.deal_id,
      'amount',  v_allocation.amount,
      'reason',  p_reason
    )
  );
end;
$$;

-- ── معالجة الرصيد الدائن (§24.5) ───────────────────────────────────────

create or replace function public.resolve_distributor_credit(
  p_deal_id        uuid,
  p_method         public.credit_resolution_method,
  p_amount         money_amount,
  p_reason         text,
  p_target_deal_id uuid default null,
  p_cash_account_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_deal        record;
  v_target      record;
  v_credit      money_amount;
  v_unresolved  money_amount;
  v_resolution_id uuid;
begin
  perform public.assert_permission('credits.resolve');

  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ المعالجة يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'معالجة الرصيد الدائن تحتاج سبباً موثقاً.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  select credit_amount, unresolved_amount into v_credit, v_unresolved
  from public.v_distributor_credits where deal_id = p_deal_id;

  if v_credit is null then
    raise exception 'لا يوجد رصيد دائن على هذه الصفقة.'
      using errcode = 'check_violation';
  end if;

  if p_amount > v_unresolved then
    raise exception
      'المبلغ % يتجاوز الرصيد الدائن غير المعالج وهو %.',
      p_amount, v_unresolved
      using errcode = 'check_violation';
  end if;

  insert into public.credit_resolutions (
    deal_id, target_deal_id, method, amount, reason, resolved_by
  )
  values (
    p_deal_id,
    case when p_method = 'transfer_to_deal' then p_target_deal_id end,
    p_method, p_amount, p_reason, auth.uid()
  )
  returning id into v_resolution_id;

  /*
    أثر كل طريقة معالجة.

    المشترك بينها جميعاً: المبلغ لا يُسجَّل إيراداً ولا ربحاً للشركة
    (§24.5). هو مال الموزع، إما يُرد أو يُنقل أو يبقى ديناً عليه.
  */
  if p_method = 'refund' then
    -- الرد يخفض ما هو محسوب مسدداً على الصفقة ويُخرج نقداً فعلياً
    insert into public.deal_ledger (
      deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
    )
    values (
      p_deal_id, 'CREDIT_TRANSFER', -p_amount,
      'credit_resolution', v_resolution_id::text,
      'رد رصيد دائن: ' || p_reason, auth.uid()
    );

    if p_cash_account_id is not null then
      insert into public.cash_transactions (
        account_id, amount, ref_type, ref_id, notes, created_by
      )
      values (
        p_cash_account_id, -p_amount,
        'credit_resolution', v_resolution_id::text,
        'رد رصيد دائن لموزع', auth.uid()
      );
    end if;

  elsif p_method = 'transfer_to_deal' then
    select * into v_target from public.deals where id = p_target_deal_id for update;

    if not found then
      raise exception 'الصفقة الهدف غير موجودة.'
        using errcode = 'foreign_key_violation';
    end if;

    if v_target.distributor_id <> v_deal.distributor_id then
      raise exception 'لا يُنقل الرصيد الدائن إلا لصفقة نفس الموزع.'
        using errcode = 'check_violation';
    end if;

    if v_target.status in ('closed', 'cancelled') then
      raise exception 'الصفقة الهدف % — لا يمكن النقل إليها.', v_target.status
        using errcode = 'restrict_violation';
    end if;

    -- النقل حركتان متقابلتان: لا نقد يدخل ولا يخرج
    insert into public.deal_ledger (
      deal_id, entry_type, paid_delta, ref_type, ref_id, reason, created_by
    )
    values
      (p_deal_id, 'CREDIT_TRANSFER', -p_amount,
       'credit_resolution', v_resolution_id::text,
       'نقل رصيد دائن إلى ' || v_target.deal_no, auth.uid()),
      (p_target_deal_id, 'CREDIT_TRANSFER', p_amount,
       'credit_resolution', v_resolution_id::text,
       'رصيد دائن منقول من ' || v_deal.deal_no, auth.uid());

  elsif p_method = 'authorized_adjustment' then
    -- تسوية تجارية معتمدة ترفع قيمة الصفقة فيستوعبها الرصيد الدائن
    insert into public.deal_ledger (
      deal_id, entry_type, commercial_value_delta, ref_type, ref_id, reason, created_by
    )
    values (
      p_deal_id, 'COMMERCIAL_ADJUSTMENT', p_amount,
      'credit_resolution', v_resolution_id::text,
      'تسوية معتمدة: ' || p_reason, auth.uid()
    );
  end if;
  -- keep_as_credit: لا حركة. الرصيد يبقى ظاهراً كالتزام على الشركة
  -- تجاه الموزع، وقد سُجِّل قرار إبقائه.

  perform public.write_audit(
    'credit.resolved', 'credit_resolutions', v_resolution_id::text,
    jsonb_build_object(
      'deal_id',        p_deal_id,
      'method',         p_method,
      'amount',         p_amount,
      'target_deal_id', p_target_deal_id,
      'reason',         p_reason
    )
  );

  return v_resolution_id;
end;
$$;

comment on function public.resolve_distributor_credit is
  'معالجة الرصيد الدائن للموزع: رد أو نقل أو إبقاء أو تسوية معتمدة. '
  'المبلغ لا يُسجَّل إيراداً ولا ربحاً في أي حالة (§24.5).';

-- ── الصلاحيات ──────────────────────────────────────────────────────────

revoke all on function public.allocate_payment_internal(uuid, uuid, money_amount)
  from public, anon, authenticated;

revoke all on function public.record_payment(
  uuid, money_amount, date, public.payment_method, text, uuid, text, text, jsonb
) from public, anon;
grant execute on function public.record_payment(
  uuid, money_amount, date, public.payment_method, text, uuid, text, text, jsonb
) to authenticated;

revoke all on function public.allocate_payment(uuid, uuid, money_amount)
  from public, anon;
grant execute on function public.allocate_payment(uuid, uuid, money_amount)
  to authenticated;

revoke all on function public.reverse_payment_allocation(uuid, text)
  from public, anon;
grant execute on function public.reverse_payment_allocation(uuid, text)
  to authenticated;

revoke all on function public.resolve_distributor_credit(
  uuid, public.credit_resolution_method, money_amount, text, uuid, uuid
) from public, anon;
grant execute on function public.resolve_distributor_credit(
  uuid, public.credit_resolution_method, money_amount, text, uuid, uuid
) to authenticated;
