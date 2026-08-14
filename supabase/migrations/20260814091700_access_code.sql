-- ═══════════════════════════════════════════════════════════════════════
-- 0018 — تدقيق تغيير رمز الدخول
--
-- رمز الدخول هو كلمة مرور حساب المالك في Supabase Auth، وتغييره يتم عبر
-- `auth.updateUser` التي لا تمر بقاعدتنا فلا تكتب في سجل التدقيق.
--
-- §11 يشترط أن تظهر كل حركة حساسة في السجل. تغيير مفتاح الدخول للنظام
-- المالي كله حركة حساسة، فنسجّلها صراحةً.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.log_access_code_changed()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول.' using errcode = 'insufficient_privilege';
  end if;

  /*
    لا يُسجَّل الرمز نفسه ولا أي جزء منه — لا القديم ولا الجديد.
    السجل يثبت أن التغيير حدث ومن نفّذه ومتى، وهذا ما يحتاجه التدقيق.
  */
  perform public.write_audit(
    'access_code.changed',
    'auth',
    auth.uid()::text,
    '{}'::jsonb
  );
end;
$$;

comment on function public.log_access_code_changed is
  'يقيّد تغيير رمز الدخول في سجل التدقيق دون تسجيل الرمز نفسه (§11).';

revoke all on function public.log_access_code_changed() from public, anon;
grant execute on function public.log_access_code_changed() to authenticated;
