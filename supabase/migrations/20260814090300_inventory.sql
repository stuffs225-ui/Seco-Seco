-- ═══════════════════════════════════════════════════════════════════════
-- 0004 — الأصناف والمشتريات والدفعات والمخزون
--
-- المبدأ المحاسبي الأول (§2): كل عملية شراء تنشئ دفعة مستقلة حتى لو كان
-- الصنف نفسه، لأن تكلفة الجرام تختلف من دفعة إلى أخرى.
--
-- المرجع: §2، §4، §14، §16.7
-- ═══════════════════════════════════════════════════════════════════════

-- ── الأصناف ────────────────────────────────────────────────────────────

create table public.items (
  id          uuid        primary key default gen_random_uuid(),
  code        text        not null unique,
  name        text        not null,
  description text        not null default '',
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint items_code_not_blank check (btrim(code) <> ''),
  constraint items_name_not_blank check (btrim(name) <> '')
);

comment on table public.items is 'الأصناف — التعريف فقط. الكمية والتكلفة تخص الدفعة لا الصنف.';

create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

alter table public.items enable row level security;

-- ── الموردون ───────────────────────────────────────────────────────────

create table public.suppliers (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  phone      text        not null default '',
  notes      text        not null default '',
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_name_not_blank check (btrim(name) <> '')
);

create trigger suppliers_set_updated_at
  before update on public.suppliers
  for each row execute function public.set_updated_at();

alter table public.suppliers enable row level security;

-- ── المشتريات ──────────────────────────────────────────────────────────

create table public.purchases (
  id            uuid        primary key default gen_random_uuid(),
  supplier_id   uuid        references public.suppliers (id) on delete restrict,
  purchase_date date        not null,
  invoice_ref   text        not null default '',
  notes         text        not null default '',
  created_by    uuid        references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.purchases is
  'رأس عملية الشراء. الوزن والقيمة يخصان الدفعة (lot) المرتبطة بها.';

create index purchases_date_idx on public.purchases (purchase_date desc);
create index purchases_supplier_idx on public.purchases (supplier_id);

create trigger purchases_set_updated_at
  before update on public.purchases
  for each row execute function public.set_updated_at();

alter table public.purchases enable row level security;

-- ── مصاريف الشراء (§16.7) ──────────────────────────────────────────────
-- القرار المعتمد: مفتاح رسملة لكل مصروف. المصاريف المفعّلة تدخل في تكلفة
-- الدفعة وترفع تكلفة الجرام؛ الباقي مصروف تشغيلي يخصم من الربح لاحقاً.

create table public.purchase_expenses (
  id              uuid         primary key default gen_random_uuid(),
  purchase_id     uuid         not null references public.purchases (id) on delete cascade,
  expense_type    text         not null,
  amount          money_amount not null,
  include_in_cost boolean      not null default true,
  notes           text         not null default '',
  created_at      timestamptz  not null default now(),
  constraint purchase_expenses_amount_positive check (amount > 0),
  constraint purchase_expenses_type_not_blank check (btrim(expense_type) <> '')
);

comment on column public.purchase_expenses.include_in_cost is
  'هل يُرسمل هذا المصروف في تكلفة الدفعة؟ (§16.7 — القرار المعتمد: '
  'مفتاح لكل مصروف).';

create index purchase_expenses_purchase_idx
  on public.purchase_expenses (purchase_id);

alter table public.purchase_expenses enable row level security;

-- ── الدفعات (Lots) ─────────────────────────────────────────────────────

create table public.lots (
  id                   uuid         primary key default gen_random_uuid(),
  lot_no               text         not null unique,
  item_id              uuid         not null references public.items (id) on delete restrict,
  purchase_id          uuid         not null references public.purchases (id) on delete restrict,
  received_date        date         not null,

  purchased_weight_g   weight_grams not null,
  purchase_value       money_amount not null,
  -- مجموع المصاريف المرسملة لحظة الإنشاء. تُثبَّت هنا ولا تُشتق لاحقاً
  -- حتى لا تتغير تكلفة دفعة بيعت منها كميات بأثر رجعي.
  capitalized_expenses money_amount not null default 0,

  total_cost           money_amount generated always as
                         (purchase_value + capitalized_expenses) stored,
  cost_per_g           rate_per_gram generated always as
                         ((purchase_value + capitalized_expenses) / purchased_weight_g) stored,

  notes                text         not null default '',
  created_by           uuid         references auth.users (id) on delete set null,
  created_at           timestamptz  not null default now(),

  constraint lots_weight_positive check (purchased_weight_g > 0),
  constraint lots_value_not_negative check (purchase_value >= 0),
  constraint lots_expenses_not_negative check (capitalized_expenses >= 0)
);

comment on table public.lots is
  'الدفعة — وحدة التكلفة في النظام. كل شراء ينشئ دفعة مستقلة حتى لو '
  'تكرر الصنف، لأن تكلفة الجرام تختلف بينها (§2).';

comment on column public.lots.cost_per_g is
  'تكلفة الجرام محسوبة آلياً. مثال §14: 21,000 ÷ 1,200ج = 17.50. '
  'لا تُضرب في الوزن لاشتقاق تكلفة متبقية — الرصيد من الـ ledger (§26).';

create index lots_item_idx on public.lots (item_id);
create index lots_purchase_idx on public.lots (purchase_id);
create index lots_received_date_idx on public.lots (received_date desc);

alter table public.lots enable row level security;

-- ── دفتر حركات المخزون ─────────────────────────────────────────────────
-- مصدر الحقيقة للوزن المتاح في كل دفعة. الرصيد يُشتق بالجمع، ولا يُخزَّن
-- كحقل قابل للتعديل (§26).

create type public.inventory_entry_type as enum (
  'LOT_RECEIVED',   -- استلام دفعة جديدة — يزيد المتاح
  'DELIVERED',      -- تسليم كمية لموزع — يخفض المتاح وينقلها لعهدته
  'RETURNED',       -- استرداد كمية من موزع — تعود بنفس تكلفتها الأصلية
  'ADJUSTMENT'      -- تسوية معتمدة بسبب موثق
);

create table public.inventory_ledger (
  id             bigint       generated always as identity primary key,
  lot_id         uuid         not null references public.lots (id) on delete restrict,
  entry_type     public.inventory_entry_type not null,
  -- موجب يزيد المتاح في المخزن، سالب يخفضه
  weight_delta_g weight_grams not null,
  cost_delta     money_amount not null default 0,
  ref_type       text         not null default '',
  ref_id         text,
  notes          text         not null default '',
  occurred_at    timestamptz  not null default now(),
  created_by     uuid         references auth.users (id) on delete set null,
  constraint inventory_ledger_delta_not_zero check (weight_delta_g <> 0)
);

comment on table public.inventory_ledger is
  'دفتر حركات المخزون — مصدر الحقيقة للوزن المتاح. append-only.';

create index inventory_ledger_lot_idx
  on public.inventory_ledger (lot_id, occurred_at);
create index inventory_ledger_ref_idx
  on public.inventory_ledger (ref_type, ref_id);

create trigger inventory_ledger_immutable
  before update or delete on public.inventory_ledger
  for each row execute function public.forbid_mutation();

alter table public.inventory_ledger enable row level security;

-- ── رصيد المخزون المشتق ────────────────────────────────────────────────

create view public.v_lot_stock
with (security_invoker = true)
as
select
  l.id                            as lot_id,
  l.lot_no,
  l.item_id,
  i.code                          as item_code,
  i.name                          as item_name,
  l.received_date,
  l.purchased_weight_g,
  l.purchase_value,
  l.capitalized_expenses,
  l.total_cost,
  l.cost_per_g,
  -- الوزن المتاح في المخزن = مجموع حركات الدفعة
  coalesce(sum(le.weight_delta_g), 0)::weight_grams  as on_hand_weight_g,
  -- الوزن الخارج للموزعين حالياً = المشترى ناقص المتاح
  (l.purchased_weight_g - coalesce(sum(le.weight_delta_g), 0))::weight_grams
                                                     as out_weight_g,
  /*
    تكلفة المخزون المتاح — من مجموع حركات التكلفة، لا بالضرب.

    الضرب (وزن × تكلفة الجرام) يبدو أبسط لكنه ينحرف: دفعة 21,500 على
    1,200ج تكلفة جرامها 17.916667 (كسر غير منتهٍ)، وضربها في 1,200 يعطي
    21,500.0004 لا 21,500. الفرق يتراكم مع كل حركة.

    لذلك كل حركة تحمل cost_delta الخاصة بها، والتكلفة المتبقية = مجموعها.
    هذه هي القاعدة الحاكمة في §26، وتطبيقها هنا يجعل رقم المخزون مطابقاً
    تماماً لتكلفة الدفعة عندما لا يخرج منها شيء.
  */
  coalesce(sum(le.cost_delta), 0)::money_amount      as on_hand_cost
from public.lots l
join public.items i on i.id = l.item_id
left join public.inventory_ledger le on le.lot_id = l.id
group by l.id, i.code, i.name;

comment on view public.v_lot_stock is
  'رصيد كل دفعة مشتقاً من دفتر الحركات — لا يوجد حقل رصيد مخزَّن (§26).';

-- ── سياسات الوصول ──────────────────────────────────────────────────────

-- القراءة متاحة لكل مستخدم مسجَّل: هذه بيانات تشغيلية داخلية، والفصل
-- الحساس (التكلفة والربح) يقع عند حدود تقارير الموزعين لا هنا.
create policy items_select on public.items
  for select to authenticated using (auth.uid() is not null);
create policy suppliers_select on public.suppliers
  for select to authenticated using (auth.uid() is not null);
create policy purchases_select on public.purchases
  for select to authenticated using (auth.uid() is not null);
create policy purchase_expenses_select on public.purchase_expenses
  for select to authenticated using (auth.uid() is not null);
create policy lots_select on public.lots
  for select to authenticated using (auth.uid() is not null);
create policy inventory_ledger_select on public.inventory_ledger
  for select to authenticated using (auth.uid() is not null);

-- الأصناف والموردون: إدارة مباشرة لمن يملك الصلاحية (بيانات مرجعية،
-- لا أثر محاسبي لها بذاتها).
create policy items_write on public.items
  for all to authenticated
  using (public.has_permission('items.manage'))
  with check (public.has_permission('items.manage'));

create policy suppliers_write on public.suppliers
  for all to authenticated
  using (public.has_permission('suppliers.manage'))
  with check (public.has_permission('suppliers.manage'));

/*
  المشتريات والدفعات والمخزون: لا سياسات كتابة إطلاقاً.

  إنشاء دفعة يجب أن يكتب في lots و purchase_expenses و inventory_ledger
  معاً وإلا اختلّ الرصيد. لذلك المسار الوحيد هو دالة create_purchase_lot
  داخل معاملة واحدة (§30). غياب السياسة هنا ليس سهواً — هو القفل.
*/
