-- ═══════════════════════════════════════════════════════════════════════
-- 0020 — توسيع إلغاء الصفقة + خيار استرداد لنفسي/للمخزون
--
-- ثلاثة طلبات مترابطة تعيد تشكيل دورة حياة الصفقة لمالك لا يتتبع كمية
-- التصريف يدوياً — يهمه التحصيل فقط (0019):
--
--   • إلغاء أي صفقة لم يُسجَّل عليها بيع حقيقي (QTY_SOLD) بعد، لا فقط
--     صفقة بسطر دفتر واحد. بيع حقيقي يعني بضاعة خرجت لعميل حقيقي —
--     التراجع عنه يحتاج مساراً مختلفاً (الاسترداد)، لا إلغاءً.
--   • عند الإلغاء: عكس كل تخصيصات الدفعات غير المعكوسة (تعود الدفعة
--     غير مخصصة، لا تُحذف) وإعادة الوزن المفتوح للمخزون دائماً.
--   • استرداد كمية: خيار جديد بين إعادتها للمخزون (الافتراضي، السلوك
--     القديم بالضبط) أو تسليمها للمالك مباشرة دون أن تعود قابلة للبيع.
--     أثر التكلفة والربح المتوقع على الصفقة مطابق تماماً في الحالتين.
--
-- المرجع: §18.3، §18.4، §24.3، §24.4، إضافة 0019
-- ═══════════════════════════════════════════════════════════════════════

-- ── record_deal_return: معامل الاسترداد الجديد ────────────────────────
--
-- توقيع الدالة يتغيّر (معامل سادس) فلا يستبدلها CREATE OR REPLACE —
-- يجب حذف النسخة القديمة أولاً لتفادي تحميل زائد يبقي السلوك القديم
-- حياً عند الاستدعاء بخمسة معاملات فقط.

drop function if exists public.record_deal_return(
  uuid, weight_grams, date, text, money_amount
);

alter table public.deal_returns
  add column restocked boolean not null default true;

comment on column public.deal_returns.restocked is
  'هل عادت الكمية المستردة قابلة للبيع في المخزون، أم سُلِّمت للمالك '
  'مباشرة دون أن تعود. التكلفة والربح المتوقع على الصفقة ينخفضان بنفس '
  'المعادلة في الحالتين — الفرق الوحيد أثر المخزون.';

create or replace function public.record_deal_return(
  p_deal_id          uuid,
  p_weight_g         weight_grams,
  p_return_date      date default current_date,
  p_reason           text default '',
  -- تُقرأ فقط حين تكون سياسة التقييم manual_value (V5.7)
  p_commercial_value money_amount default null,
  -- true (افتراضي): تعود الكمية للمخزون قابلة للبيع. false: تُسلَّم
  -- للمالك مباشرة — لا تدخل المخزون إطلاقاً.
  p_restock          boolean default true
)
returns uuid
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
  v_policy      text;
  v_cost        money_amount;
  v_profit      money_amount;
  v_reduction   money_amount;
  v_return_id   uuid;
begin
  perform public.assert_permission('deals.return');

  if p_weight_g is null or p_weight_g <= 0 then
    raise exception 'وزن الاسترداد يجب أن يكون أكبر من صفر.'
      using errcode = 'check_violation';
  end if;

  select * into v_deal from public.deals where id = p_deal_id for update;
  if not found then
    raise exception 'الصفقة غير موجودة.' using errcode = 'foreign_key_violation';
  end if;

  if v_deal.status in ('closed', 'cancelled') then
    raise exception
      'لا يمكن الاسترداد من صفقة % — أعد فتحها أولاً.', v_deal.status
      using errcode = 'restrict_violation';
  end if;

  -- الأرصدة المفتوحة من الدفتر
  select
    coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0),
    coalesce(sum(cost_delta), 0),
    coalesce(sum(expected_profit_delta), 0)
  into v_open_weight, v_open_cost, v_open_profit
  from public.deal_ledger
  where deal_id = p_deal_id;

  /*
    §18.4: لا يمكن استرداد وزن أكبر من الوزن غير المصرَّف والمتبقي فعلاً
    لدى الموزع. الوزن المفتوح هو بالضبط هذا المقدار — ما بيع لم يعد
    موجوداً ليُسترد.
  */
  if p_weight_g > v_open_weight then
    raise exception
      'وزن الاسترداد % ج يتجاوز الوزن غير المصرَّف لدى الموزع وهو % ج.',
      p_weight_g, v_open_weight
      using errcode = 'check_violation';
  end if;

  select * into v_line from public.deal_lines where deal_id = p_deal_id limit 1;

  /*
    §18.4: سعر رأس المال للكمية المستردة لا يُعاد احتسابه من سعر البيع؛
    يُستخدم cost_per_g للدفعة الأصلية المثبَّت على سطر الصفقة.

    عند استرداد كامل الوزن المفتوح ننقل الرصيد المفتوح كما هو بدل الضرب،
    فتصل التكلفة والربح المفتوحان إلى صفر تام.
  */
  if p_weight_g = v_open_weight then
    v_cost   := v_open_cost;
    v_profit := v_open_profit;
  else
    v_cost   := round(p_weight_g * v_line.cost_per_g, 4);
    v_profit := round(p_weight_g * v_line.expected_profit_per_g, 4);
  end if;

  -- ── التقييم التجاري تجاه الموزع (V5.7) ───────────────────────────────

  v_policy := public.get_setting_text('return_commercial_valuation');

  if v_policy = 'manual_value' then
    if p_commercial_value is null then
      raise exception
        'سياسة النظام تتطلب تحديد قيمة التسوية التجارية للكمية المستردة.'
        using errcode = 'check_violation';
    end if;
    if p_commercial_value < 0 then
      raise exception 'قيمة التسوية التجارية لا يمكن أن تكون سالبة.'
        using errcode = 'check_violation';
    end if;
    v_reduction := p_commercial_value;
    -- التكلفة الراجعة ثابتة دائماً؛ الفرق يقع كله على الربح المتوقع
    v_profit    := v_reduction - v_cost;
  else
    -- القرار المعتمد: بنفس سعر الجرام في الصفقة
    v_reduction := v_cost + v_profit;
  end if;

  -- ── التسجيل ──────────────────────────────────────────────────────────

  insert into public.deal_returns (
    deal_id, deal_line_id, lot_id, return_date, returned_weight_g,
    returned_cost, cancelled_expected_profit, deal_value_reduction,
    reason, created_by, restocked
  )
  values (
    p_deal_id, v_line.id, v_line.lot_id, p_return_date, p_weight_g,
    v_cost, v_profit, v_reduction,
    coalesce(p_reason, ''), auth.uid(), p_restock
  )
  returning id into v_return_id;

  /*
    الحركة في دفتر الصفقة.

    paid_delta صفر صراحةً: الاسترداد ليس سداداً (§18.3). realized_profit
    صفر أيضاً: الاسترداد يخفض الربح المتوقع ولا يمس الربح المحقق من
    كميات سبق بيعها (§18.4). أثر الصفقة هذا لا يتغير سواء عادت الكمية
    للمخزون أم لا — الفرق الوحيد أدناه في inventory_ledger.
  */
  insert into public.deal_ledger (
    deal_id, deal_line_id, entry_type,
    settled_weight_g, commercial_value_delta, cost_delta, expected_profit_delta,
    paid_delta, ref_type, ref_id, reason, occurred_at, created_by
  )
  values (
    p_deal_id, v_line.id, 'QTY_RETURNED',
    p_weight_g, -v_reduction, -v_cost, -v_profit,
    0, 'deal_return', v_return_id::text,
    coalesce(p_reason, ''), p_return_date::timestamptz, auth.uid()
  );

  -- §18.4: الكمية تعود إلى نفس الدفعة بتكلفتها الأصلية — فقط حين تُطلب
  -- إعادتها فعلاً للمخزون. استرداد "لنفسي" يُخرجها نهائياً دون أن تصير
  -- قابلة للبيع مجدداً.
  if p_restock then
    insert into public.inventory_ledger (
      lot_id, entry_type, weight_delta_g, cost_delta,
      ref_type, ref_id, notes, created_by
    )
    values (
      v_line.lot_id, 'RETURNED', p_weight_g, v_cost,
      'deal_return', v_return_id::text,
      'استرداد من الصفقة ' || v_deal.deal_no, auth.uid()
    );
  end if;

  perform public.write_audit(
    'deal.return_recorded', 'deals', p_deal_id::text,
    jsonb_build_object(
      'return_id',                 v_return_id,
      'weight_g',                  p_weight_g,
      'returned_cost',             v_cost,
      'cancelled_expected_profit', v_profit,
      'deal_value_reduction',      v_reduction,
      'valuation_policy',          v_policy,
      'restocked',                 p_restock
    )
  );

  return v_return_id;
end;
$$;

comment on function public.record_deal_return is
  'استرداد كمية — عكس جزئي لتسليم المخزون لا تحصيل نقدي (§18.3). '
  'التكلفة تعود بسعر الدفعة الأصلي والربح المتوقع ينخفض بحصته، وتعود '
  'الكمية فعلياً للمخزون فقط حين p_restock صحيح.';

revoke all on function public.record_deal_return(
  uuid, weight_grams, date, text, money_amount, boolean
) from public, anon;
grant execute on function public.record_deal_return(
  uuid, weight_grams, date, text, money_amount, boolean
) to authenticated;

-- ── cancel_deal: توسيع الحد ليشمل أي صفقة بلا بيع حقيقي ────────────────
--
-- الحد القديم رفض أي صفقة عليها أكثر من حركة تسليم واحدة — حتى لو
-- كانت الحركات الإضافية دفعات أو استردادات لا تمس بيعاً حقيقياً. بعد
-- إزالة تسجيل التصريف اليدوي من الواجهة (0020)، لن يظهر QTY_SOLD إلا
-- عند الإغلاق بضغطة واحدة، فأي صفقة لم تُغلَق بعد غالباً بلا بيع حقيقي
-- إطلاقاً — والحد الصحيح هو هذا بالضبط: بضاعة خرجت لعميل حقيقي فعلاً،
-- لا مجرد وجود دفعة أو استرداد سابق.

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
  v_has_sale    boolean;
  v_open_weight weight_grams;
  v_alloc       record;
  v_reversed    int := 0;
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

  select exists(
    select 1 from public.deal_ledger
    where deal_id = p_deal_id and entry_type = 'QTY_SOLD'
  ) into v_has_sale;

  if v_has_sale then
    raise exception
      'لا يمكن إلغاء صفقة سُجِّل عليها تصريف فعلي — استخدم الاسترداد أو التسوية بدل الإلغاء.'
      using errcode = 'check_violation';
  end if;

  -- عكس كل تخصيصات الدفعات غير المعكوسة: الدفعة الأصلية تبقى، تعود
  -- "غير مخصصة" ظاهرة في /payments — لا تُحذف ولا تختفي (§24.4)
  for v_alloc in
    select id from public.payment_allocations
    where deal_id = p_deal_id and reversed_at is null
  loop
    perform public.reverse_payment_allocation(
      v_alloc.id, 'إلغاء الصفقة: ' || p_reason
    );
    v_reversed := v_reversed + 1;
  end loop;

  select coalesce(sum(delivered_weight_g), 0) - coalesce(sum(settled_weight_g), 0)
    into v_open_weight
  from public.deal_ledger
  where deal_id = p_deal_id;

  -- الوزن المفتوح المتبقي يعود للمخزون كاملاً دائماً عند الإلغاء —
  -- الصفقة لم تحدث فعلياً، فلا معنى لخيار "لنفسي" هنا
  if v_open_weight > 0 then
    perform public.record_deal_return(
      p_deal_id, v_open_weight, current_date, p_reason, null, true
    );
  end if;

  update public.deals set status = 'cancelled' where id = p_deal_id;

  perform public.write_audit(
    'deal.cancelled', 'deals', p_deal_id::text,
    jsonb_build_object(
      'reason', p_reason,
      'weight_g', v_open_weight,
      'reversed_allocations', v_reversed
    )
  );

  return p_deal_id;
end;
$$;

comment on function public.cancel_deal is
  'إلغاء كامل لصفقة لم يُسجَّل عليها بيع حقيقي (QTY_SOLD) بعد. يعكس كل '
  'تخصيصات الدفعات غير المعكوسة ويعيد الوزن المفتوح للمخزون، ثم ينقل '
  'الحالة إلى cancelled (§24.3، §24.4).';

revoke all on function public.cancel_deal(uuid, text) from public, anon;
grant execute on function public.cancel_deal(uuid, text) to authenticated;
