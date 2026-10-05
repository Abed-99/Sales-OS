-- تصفير كامل للنظام: بيمسح كل الشركات وكل بياناتها (أصناف، زباين، فواتير، صناديق، قيود، موظفين...).
-- بيضل بس:
--   * حسابات الدخول (auth: الإيميلات وكلمات السر) وأسماء أصحابها (profiles)
--   * قائمة الصلاحيات الثابتة (permissions) — جزء من النظام نفسه
-- بعدها، أول ما تفوت بيطلب منك تعمل شركة جديدة، وبتنعمل لحالها الصفات والحسابات والصندوق والمستودع.
--
-- التشغيل: Supabase → SQL Editor → الصق الملف كلّو → Run.
-- خود نسخة احتياطية قبل (مشروح بـ docs/backup.md).

begin;

do $$
declare
  v_tables text;
begin
  select string_agg(format('public.%I', c.relname), ', ' order by c.relname)
  into v_tables
  from pg_class c
  where c.relnamespace = 'public'::regnamespace
    and c.relkind in ('r', 'p')
    and c.relname not in ('profiles', 'permissions');

  execute 'truncate table ' || v_tables || ' restart identity cascade';
end;
$$;

-- تأكيد: لازم كل الأرقام تطلع 0 إلا حسابات الدخول والصلاحيات.
select 'الشركات' as what, count(*) from public.companies
union all select 'الأصناف', count(*) from public.products
union all select 'الزباين', count(*) from public.traders
union all select 'فواتير البيع', count(*) from public.sales_invoices
union all select 'القيود', count(*) from public.journal_entries
union all select 'حسابات الدخول (باقية)', count(*) from auth.users
union all select 'الصلاحيات الثابتة (باقية)', count(*) from public.permissions;

commit;
