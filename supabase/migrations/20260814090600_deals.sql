-- ═══════════════════════════════════════════════════════════════════════
-- 0007 — الصفقات ودفتر حركاتها
--
-- الصفقة هي الكيان المحوري لكل تعامل مع الموزع (§24.1)، والـ Ledger هو
-- مصدر الحقيقة لكل رصيد فيها (§24.2، §26). لا يوجد حقل رصيد مخزَّن.
--
-- المرجع: §18، §19، §24.1–24.3، §25، §26
-- ═══════════════════════════════════════════════════════════════════════

-- ── دورة حياة الصفقة (§24.3) ───────────────────────────────────────────
-- هذه الحالة مخزَّنة لأنها قرار إداري صريح، بخلاف حالتَي الوزن والمال
-- اللتين تُشتقان من الأرصدة.

create type public.deal_status as enum (
  'draft',          -- مجهّزة ولم تُسلَّم بعد
  'active',         -- تم التسليم والصفقة جارية
  'in_settlement',  -- قيد المصالحة النهائية
  'ready_to_close', -- المصالحة بلا فروقات — تنتظر اعتماد الإغلاق
  'closed',         -- مغلقة بلقطة نهائية
  'reopened',       -- أُعيد فتحها بصلاحية خاصة
  'cancelled'       -- ألغيت بحركة عكسية
);

-- ── حالتا الوزن والمال (§24.3) ─────────────────────────────────────────
-- منفصلتان عمداً: صفقة مدفوعة بالكامل مع وزن مفتوح ليست مغلقة، والعكس.

create type public.quantity_status as enum (
  'open',              -- لا توجد تسوية كمية بعد
  'partially_settled', -- جزء من الوزن سُوّي
  'fully_settled',     -- كل الوزن سُوّي
  'exception'          -- الوزن المسوّى يتجاوز المسلَّم — يحتاج تدخلاً
);

create type public.payment_status as enum (
  'unpaid',
  'partially_paid',
  'fully_paid',
  'credit_balance',    -- المدفوع يتجاوز القيمة المعدلة (§24.5)
  'exception'
);

-- ── الصفقات ────────────────────────────────────────────────────────────

create table public.deals (
  id             uuid        primary key default gen_random_uuid(),
  deal_no        text        not null unique,
  distributor_id uuid        not null references public.distributors (id) on delete restrict,
  status         public.deal_status not null default 'draft',
  delivery_date  date,
  due_date       date,
  notes          text        not null default '',
  opened_by      uuid        references auth.users (id) on delete set null,
  closed_at      timestamptz,
  closed_by      uuid        references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint deals_closed_consistency
    check ((status = 'closed') = (closed_at is not null))
);

comment on table public.deals is
  'رأس الصفقة ودورة حياتها. الأوزان والقيم والأرصدة كلها في deal_ledger '
  'وتُشتق عبر v_deal_* — لا حقل رصيد هنا (§26).';

create index deals_distributor_idx on public.deals (distributor_id, created_at desc);
create index deals_status_idx on public.deals (status);
create index deals_due_date_idx on public.deals (due_date) where status = 'active';

create trigger deals_set_updated_at
  before update on public.deals
  for each row execute function public.set_updated_at();

alter table public.deals enable row level security;

-- ── أسطر الصفقة ────────────────────────────────────────────────────────
-- اقتصاديات الجرام تُثبَّت هنا لحظة التسليم ولا تتغير بعدها، لأن كل
-- حساب لاحق (استرداد، بيع، مصالحة) يرجع إليها (§18.1).

create table public.deal_lines (
  id                    uuid          primary key default gen_random_uuid(),
  deal_id               uuid          not null references public.deals (id) on delete cascade,
  lot_id                uuid          not null references public.lots (id) on delete restrict,

  weight_g              weight_grams  not null,
  -- لقطة من تكلفة الدفعة وقت التسليم؛ لا تُقرأ من lots لاحقاً حتى لا
  -- يتغير تاريخ الصفقة إن عُدّلت الدفعة
  cost_per_g            rate_per_gram not null,
  deal_value_per_g      rate_per_gram not null,
  expected_profit_per_g rate_per_gram not null,

  created_at            timestamptz   not null default now(),

  constraint deal_lines_weight_positive check (weight_g > 0),
  constraint deal_lines_rates_not_negative
    check (cost_per_g >= 0 and deal_value_per_g >= 0),
  -- الربح المتوقع للجرام مشتق لا مستقل: قيمة الصفقة ناقص التكلفة (§18.1)
  constraint deal_lines_profit_is_derived
    check (expected_profit_per_g = deal_value_per_g - cost_per_g)
);

create index deal_lines_deal_idx on public.deal_lines (deal_id);
create index deal_lines_lot_idx on public.deal_lines (lot_id);

alter table public.deal_lines enable row level security;

/*
  قيد الدفعة الواحدة لكل صفقة (§24.1 — القرار المعتمد).

  مطبَّق كتريجر لا كقيد جدول لأنه يقرأ إعداداً قابلاً للتغيير: رفع القيد
  مستقبلاً يكون بتغيير app_settings لا بترحيل جديد.
*/
create or replace function public.enforce_deal_line_policy()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_multi_lot boolean;
  v_existing  int;
begin
  v_multi_lot := coalesce((public.get_setting('deal_multi_lot'))::boolean, false);

  if v_multi_lot then
    return new;
  end if;

  select count(*) into v_existing
  from public.deal_lines
  where deal_id = new.deal_id;

  if v_existing > 0 then
    raise exception
      'الصفقة تقبل دفعة واحدة فقط. أنشئ صفقة جديدة للكمية من دفعة أخرى.'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger deal_lines_enforce_policy
  before insert on public.deal_lines
  for each row execute function public.enforce_deal_line_policy();

-- ── دفتر حركات الصفقة (§24.2) ──────────────────────────────────────────

create type public.deal_entry_type as enum (
  'DEAL_OPEN',             -- إنشاء الصفقة وتثبيت الوزن والقيمة الأصلية
  'QTY_DELIVERED',         -- إضافة كمية للموزع من دفعة محددة
  'QTY_SOLD',              -- تصريف فعلي — هنا يتحول الربح إلى محقق
  'PAYMENT_RECEIVED',      -- تخفيض الرصيد المالي فقط
  'QTY_RETURNED',          -- إعادة كمية للمخزون وإلغاء قيمتها وربحها المتوقع
  'COMMERCIAL_ADJUSTMENT', -- خصم أو إضافة تجارية معتمدة
  'WEIGHT_ADJUSTMENT',     -- تسوية وزن بسبب موثق واعتماد
  'PAYMENT_REVERSAL',      -- عكس دفعة دون حذف الحركة الأصلية
  'CREDIT_TRANSFER',       -- نقل رصيد دائن من/إلى صفقة أخرى
  'DEAL_CLOSE'             -- إغلاق بعد المصالحة النهائية
);

create table public.deal_ledger (
  id                    bigint       generated always as identity primary key,
  deal_id               uuid         not null references public.deals (id) on delete restrict,
  deal_line_id          uuid         references public.deal_lines (id) on delete restrict,
  entry_type            public.deal_entry_type not null,

  /*
    الوزن في دلوين فقط:
      delivered — الداخل إلى عهدة الموزع
      settled   — الخارج منها ببيع أو استرداد أو تسوية

    الوزن المفتوح = مجموع الأول ناقص مجموع الثاني. نوع الحركة يفصّل
    أي نوع تسوية كانت، فلا حاجة لعمود لكل حالة.
  */
  delivered_weight_g    weight_grams not null default 0,
  settled_weight_g      weight_grams not null default 0,

  -- القيمة التجارية للصفقة: ما يلتزم الموزع بسداده
  commercial_value_delta money_amount not null default 0,
  -- رأس المال المرتبط بالوزن المفتوح: يدخل بالتسليم ويخرج بالبيع أو الاسترداد
  cost_delta            money_amount not null default 0,
  -- الربح المتوقع المرتبط بالوزن المفتوح
  expected_profit_delta money_amount not null default 0,
  -- الربح المحقق: يتراكم عند التصريف الفعلي وحده (القرار المعتمد §16.1)
  realized_profit_delta money_amount not null default 0,
  -- النقد المخصص لهذه الصفقة
  paid_delta            money_amount not null default 0,

  ref_type              text         not null default '',
  ref_id                text,
  reason                text         not null default '',
  notes                 text         not null default '',
  occurred_at           timestamptz  not null default now(),
  created_by            uuid         references auth.users (id) on delete set null,

  constraint deal_ledger_weights_not_negative
    check (delivered_weight_g >= 0 and settled_weight_g >= 0),

  /*
    معادلة §18.1: قيمة الصفقة = رأس المال + الربح المتوقع.

    تُفرض على حركات التسليم والاسترداد، وهي جوهر منطق §18.3: استرداد
    100ج بتكلفة 2,000 وربح متوقع 400 يخفض قيمة الصفقة 2,400 بالضبط.
    الحركات الأخرى (بيع، دفع، تسوية) لا تخضع لها.
  */
  constraint deal_ledger_value_equals_cost_plus_profit
    check (
      entry_type not in ('QTY_DELIVERED', 'QTY_RETURNED')
      or commercial_value_delta = cost_delta + expected_profit_delta
    )
);

comment on table public.deal_ledger is
  'دفتر حركات الصفقة — مصدر الحقيقة لكل رصيد. append-only: التصحيح '
  'بحركة عكسية لا بتعديل حركة سابقة (§24.2، §26، §30).';

create index deal_ledger_deal_idx on public.deal_ledger (deal_id, occurred_at, id);
create index deal_ledger_type_idx on public.deal_ledger (deal_id, entry_type);
create index deal_ledger_ref_idx on public.deal_ledger (ref_type, ref_id);

create trigger deal_ledger_immutable
  before update or delete on public.deal_ledger
  for each row execute function public.forbid_mutation();

alter table public.deal_ledger enable row level security;

-- ── سياسات الوصول ──────────────────────────────────────────────────────

create policy deals_select on public.deals
  for select to authenticated using (auth.uid() is not null);
create policy deal_lines_select on public.deal_lines
  for select to authenticated using (auth.uid() is not null);
create policy deal_ledger_select on public.deal_ledger
  for select to authenticated using (auth.uid() is not null);

/*
  لا سياسات كتابة على أي من الثلاثة.

  كل حركة تمس الصفقة تمس المخزون والأرصدة معاً، فلا يمكن أن تكون
  عملية جزئية. المسار الوحيد هو دوال RPC داخل معاملات ذرية (§30).
*/
