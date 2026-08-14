-- ═══════════════════════════════════════════════════════════════════════
-- 0006 — الموزعون
--
-- المرجع: §4، §8، §24.11 (حدود العهدة والائتمان)
-- ═══════════════════════════════════════════════════════════════════════

create table public.distributors (
  id                 uuid         primary key default gen_random_uuid(),
  code               text         not null unique,
  name               text         not null,
  phone              text         not null default '',
  -- حدود العهدة: صفر يعني بلا حد. تُستخدم للتنبيه لا للمنع الصارم،
  -- لأن تجاوز الحد قرار عمل قد يوافق عليه المدير (§24.11)
  credit_limit_value money_amount not null default 0,
  credit_limit_weight weight_grams not null default 0,
  notes              text         not null default '',
  is_active          boolean      not null default true,
  created_at         timestamptz  not null default now(),
  updated_at         timestamptz  not null default now(),
  constraint distributors_code_not_blank check (btrim(code) <> ''),
  constraint distributors_name_not_blank check (btrim(name) <> ''),
  constraint distributors_limits_not_negative
    check (credit_limit_value >= 0 and credit_limit_weight >= 0)
);

comment on table public.distributors is
  'الموزعون. الأرصدة لا تُخزَّن هنا — تُشتق من الصفقات والدفعات (§26).';

create index distributors_active_idx on public.distributors (name) where is_active;

create trigger distributors_set_updated_at
  before update on public.distributors
  for each row execute function public.set_updated_at();

alter table public.distributors enable row level security;

create policy distributors_select on public.distributors
  for select to authenticated using (auth.uid() is not null);

create policy distributors_write on public.distributors
  for all to authenticated
  using (public.has_permission('distributors.manage'))
  with check (public.has_permission('distributors.manage'));
