-- ═══════════════════════════════════════════════════════════════════════
-- 0016 — صلاحيات قاعدة البيانات الصريحة
--
-- Supabase تمنح دور authenticated وصولاً واسعاً على schema public
-- افتراضياً، وسياسات RLS هي ما يصفّي الصفوف بعد ذلك. الاعتماد على ذلك
-- الافتراض ضمنياً يجعل الأمان غير مرئي في الريبو ومختلفاً بين البيئات.
--
-- هنا نثبّت المنح صراحةً: القراءة عبر RLS، ولا كتابة مباشرة على أي
-- جدول حركات — الكتابة كلها عبر دوال RPC (§30).
-- ═══════════════════════════════════════════════════════════════════════

grant usage on schema public to anon, authenticated;

-- ── القراءة: مسموحة على مستوى الجدول، ومصفّاة بـ RLS على مستوى الصف ──
-- كل جدول عليه RLS مفعّل، فالمنح هنا لا يكشف شيئاً بذاته: السياسات هي
-- التي تقرر أي صفوف يراها كل دور.

grant select on all tables in schema public to authenticated;

-- ── الكتابة: على الجداول المرجعية فقط ─────────────────────────────────
-- هذه بيانات تعريفية لا أثر محاسبي لها بذاتها، وسياساتها تشترط
-- الصلاحية المناسبة.

grant insert, update on public.items        to authenticated;
grant insert, update on public.suppliers    to authenticated;
grant insert, update on public.distributors to authenticated;
grant insert, update on public.cash_accounts to authenticated;
grant insert, update on public.profiles     to authenticated;
grant update         on public.app_settings to authenticated;

/*
  لا منح كتابة على: purchases, purchase_expenses, lots, inventory_ledger,
  deals, deal_lines, deal_ledger, deal_returns, payments,
  payment_allocations, credit_resolutions, cash_transactions,
  deal_closing_snapshots, deal_reopenings, audit_log, report_generation_log.

  هذه كلها تُكتب حصراً من دوال SECURITY DEFINER تنفّذ التحقق والمعاملة
  الذرية وسجل التدقيق. غياب المنح هنا هو القفل الفعلي — لا مجرد غياب
  سياسة RLS.
*/

-- ── المتسلسلات ─────────────────────────────────────────────────────────
-- تحتاجها الجداول المرجعية التي تقبل insert مباشرة.

grant usage on all sequences in schema public to authenticated;

-- ── لا وصول مجهول ──────────────────────────────────────────────────────
-- النظام كله خلف تسجيل الدخول؛ لا شيء يُقرأ بدون جلسة.

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;

-- ── المنح الافتراضية للكائنات المستقبلية ──────────────────────────────
-- حتى لا يعتمد ترحيل لاحق على منح ضمنية ينساها.

alter default privileges in schema public
  grant select on tables to authenticated;
