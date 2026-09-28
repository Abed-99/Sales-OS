-- الأساس الكامل لقاعدة البيانات.
-- هاد الملف منسوخ من supabase/schemas ومش لازم تعدّل عليه.
-- للتعديل: عدّل ملفات supabase/schemas وبعدين شغّل: npx supabase db diff -f اسم_التعديل

-- ======================================================================
-- الأساس
-- الشركات، المستخدمين، الصفات والصلاحيات، سجل النشاط
-- ======================================================================

set check_function_bodies = off;

-- كل التواريخ (current_date، تحويل الوقت لتاريخ) بتوقيت دمشق، مش UTC.
-- بدونها، أي عملية بين 12 و 3 الفجر بتنسجل بتاريخ مبارح.
alter database postgres set timezone to 'Asia/Damascus';

-- كل الجداول والدوال بتنعمل بصلاحيات مضبوطة من الأساس:
--   anon (زائر بدون تسجيل دخول): ما إله أي صلاحية.
--   authenticated (مستخدم مسجّل): قراءة وكتابة، والحماية الفعلية من RLS.
--   service_role (السيرفر): كل شي.
-- أي استثناء (جدول للقراءة بس، دالة داخلية) مكتوب بقسم "الصلاحيات" بآخر كل ملف.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges for role postgres in schema public grant all on tables to service_role;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
-- ملاحظة: حق "أي حدا يشغّل أي دالة" (PUBLIC) هو إعداد عام بـ Postgres، فلازم ينشال بدون "in schema".
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres in schema public grant execute on functions to authenticated, service_role;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid default auth.uid() not null references auth.users(id) on delete restrict,
  phone text,
  whatsapp text,
  logo_url text,
  default_currency text default 'USD'::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.permissions (
  code text primary key,
  module text not null,
  action text not null,
  label text not null,
  description text,
  sort_order integer default 0 not null
);

create table public.company_roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  is_owner boolean default false not null,
  is_protected boolean default false not null,
  active boolean default true not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);
create index company_roles_company_idx on public.company_roles using btree (company_id);
create unique index company_roles_name_unique on public.company_roles using btree (company_id, lower(name));
create unique index company_roles_one_owner on public.company_roles using btree (company_id) where (is_owner = true);

create table public.role_permissions (
  role_id uuid not null references public.company_roles(id) on delete cascade,
  permission_code text not null references public.permissions(code) on delete cascade,
  created_at timestamp with time zone default now() not null,
  constraint role_permissions_pkey primary key (role_id, permission_code)
);
create index role_permissions_role_idx on public.role_permissions using btree (role_id);

create table public.company_members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.company_roles(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint company_members_pkey primary key (company_id, user_id)
);
create index company_members_role_idx on public.company_members using btree (role_id);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamp with time zone default now() not null
);
create index audit_logs_company_created_idx on public.audit_logs using btree (company_id, created_at desc);

create table public.document_sequences (
  company_id uuid not null references public.companies(id) on delete cascade,
  document_type text not null,
  sequence_year integer not null,
  next_value bigint default 1 not null,
  constraint document_sequences_pkey primary key (company_id, document_type, sequence_year),
  constraint document_sequences_next_value_check check ((next_value > 0))
);


-- ----------------------------------------------------------------------
-- البيانات الثابتة
-- ----------------------------------------------------------------------

insert into public.permissions (code, module, action, label, description, sort_order) values
  ('dashboard.view', 'dashboard', 'view', 'عرض لوحة التحكم', null, 10),
  ('team.view', 'team', 'view', 'عرض الفريق', null, 20),
  ('team.manage_members', 'team', 'manage_members', 'إدارة الموظفين', null, 21),
  ('team.manage_roles', 'team', 'manage_roles', 'إدارة الصفات والصلاحيات', null, 22),
  ('traders.view', 'traders', 'view', 'عرض التجار', null, 30),
  ('traders.create', 'traders', 'create', 'إضافة تاجر', null, 31),
  ('traders.update', 'traders', 'update', 'تعديل تاجر', null, 32),
  ('traders.archive', 'traders', 'archive', 'تعطيل أو أرشفة تاجر', null, 33),
  ('traders.assign_rep', 'traders', 'assign_rep', 'تعيين مندوب للتاجر', null, 34),
  ('traders.view_balance', 'traders', 'view_balance', 'عرض حساب التاجر', null, 35),
  ('traders.manage_credit', 'traders', 'manage_credit', 'تحديد حد الدين ومهلة الدفع', null, 36),
  ('visits.view', 'visits', 'view', 'عرض الزيارات', null, 40),
  ('visits.create', 'visits', 'create', 'تسجيل زيارة', null, 41),
  ('visits.update', 'visits', 'update', 'تعديل زيارة', null, 42),
  ('suppliers.view', 'suppliers', 'view', 'عرض الموردين', null, 50),
  ('suppliers.create', 'suppliers', 'create', 'إضافة مورد', null, 51),
  ('suppliers.update', 'suppliers', 'update', 'تعديل مورد', null, 52),
  ('suppliers.archive', 'suppliers', 'archive', 'تعطيل أو أرشفة مورد', null, 53),
  ('suppliers.view_finance', 'suppliers', 'view_finance', 'عرض حساب المورد', null, 54),
  ('products.view', 'products', 'view', 'عرض الأصناف', null, 60),
  ('products.create', 'products', 'create', 'إضافة صنف', null, 61),
  ('products.update', 'products', 'update', 'تعديل صنف وأسعار الموردين', null, 62),
  ('products.archive', 'products', 'archive', 'تعطيل أو أرشفة صنف', null, 63),
  ('products.view_cost', 'products', 'view_cost', 'عرض تكلفة الشراء', null, 64),
  ('orders.view', 'orders', 'view', 'عرض الطلبيات', null, 70),
  ('orders.create', 'orders', 'create', 'إنشاء طلبية', null, 71),
  ('orders.update', 'orders', 'update', 'تعديل طلبية', null, 72),
  ('orders.cancel', 'orders', 'cancel', 'إلغاء طلبية', null, 73),
  ('orders.approve_discount', 'orders', 'approve_discount', 'الموافقة على الخصومات', null, 74),
  ('orders.override_credit_limit', 'orders', 'override_credit_limit', 'تجاوز حد ائتمان العميل', null, 75),
  ('deliveries.view', 'deliveries', 'view', 'عرض التوصيل', null, 80),
  ('deliveries.update', 'deliveries', 'update', 'تحديث حالة التوصيل', null, 81),
  ('purchases.view', 'purchases', 'view', 'عرض المشتريات', null, 90),
  ('purchases.create', 'purchases', 'create', 'تسجيل شراء', null, 91),
  ('purchases.update', 'purchases', 'update', 'تعديل شراء', null, 92),
  ('purchases.cancel', 'purchases', 'cancel', 'إلغاء شراء', null, 93),
  ('sales_invoices.view', 'sales_invoices', 'view', 'عرض فواتير البيع', null, 100),
  ('sales_invoices.create', 'sales_invoices', 'create', 'إنشاء فاتورة بيع', null, 101),
  ('sales_invoices.cancel', 'sales_invoices', 'cancel', 'إلغاء فاتورة بيع', null, 102),
  ('purchase_invoices.view', 'purchase_invoices', 'view', 'عرض فواتير الشراء', null, 110),
  ('purchase_invoices.create', 'purchase_invoices', 'create', 'إنشاء فاتورة شراء', null, 111),
  ('purchase_invoices.cancel', 'purchase_invoices', 'cancel', 'إلغاء فاتورة شراء', null, 112),
  ('payments.sales_view', 'payments', 'sales_view', 'عرض دفعات التجار', null, 120),
  ('payments.sales_create', 'payments', 'sales_create', 'قبض من تاجر', null, 121),
  ('payments.supplier_view', 'payments', 'supplier_view', 'عرض دفعات الموردين', null, 122),
  ('payments.supplier_create', 'payments', 'supplier_create', 'دفع لمورد', null, 123),
  ('payments.supplier_reverse', 'payments', 'supplier_reverse', 'عكس دفعة مورد', null, 124),
  ('payments.sales_reverse', 'payments', 'sales_reverse', 'عكس دفعة تاجر', null, 125),
  ('inventory.view', 'inventory', 'view', 'عرض المخزون', null, 130),
  ('inventory.adjust', 'inventory', 'adjust', 'تسوية المخزون', null, 131),
  ('inventory.returns', 'inventory', 'returns', 'إدارة المرتجعات', null, 132),
  ('finance.cashbox_view', 'finance', 'cashbox_view', 'عرض الصندوق والحسابات', null, 140),
  ('finance.cashbox_write', 'finance', 'cashbox_write', 'إدارة حركات الصندوق', null, 141),
  ('finance.expenses_view', 'finance', 'expenses_view', 'عرض المصاريف', null, 142),
  ('finance.expenses_write', 'finance', 'expenses_write', 'إضافة وتعديل المصاريف', null, 143),
  ('finance.expense_categories', 'finance', 'expense_categories', 'إدارة فئات المصاريف', null, 144),
  ('finance.accounts_view', 'finance', 'accounts_view', 'عرض الحسابات المالية', null, 145),
  ('finance.accounts_write', 'finance', 'accounts_write', 'إدارة الحسابات المالية', null, 146),
  ('finance.month_close', 'finance', 'month_close', 'إقفال الشهر', null, 147),
  ('finance.month_reopen', 'finance', 'month_reopen', 'إعادة فتح شهر مقفل', null, 148),
  ('finance.manual_journal', 'finance', 'manual_journal', 'إدخال قيد يومية يدوي', null, 149),
  ('finance.manual_journal_reverse', 'finance', 'manual_journal_reverse', 'عكس قيد يومية يدوي', null, 150),
  ('map.view', 'map', 'view', 'عرض الخريطة', null, 150),
  ('reports.view', 'reports', 'view', 'عرض التقارير', null, 160),
  ('reports.sales', 'reports', 'sales', 'تقارير المبيعات', null, 161),
  ('reports.profit', 'reports', 'profit', 'تقارير الأرباح', null, 162),
  ('reports.finance', 'reports', 'finance', 'التقارير المالية', null, 163),
  ('reports.team', 'reports', 'team', 'تقارير الموظفين والمندوبين', null, 164),
  ('settings.view', 'settings', 'view', 'عرض الإعدادات', null, 180),
  ('settings.manage_company', 'settings', 'manage_company', 'تعديل معلومات الشركة', null, 181),
  ('returns.reverse', 'returns', 'reverse', 'عكس مرتجع', 'عكس مرتجع بيع أو شراء مع المخزون والمحاسبة', 183),
  ('audit.view', 'audit', 'view', 'عرض سجل التعديلات', null, 190),
  ('payroll.view', 'payroll', 'view', 'عرض الرواتب', null, 200),
  ('payroll.manage_employees', 'payroll', 'manage_employees', 'إدارة الموظفين', null, 201),
  ('payroll.process', 'payroll', 'process', 'إعداد وترحيل الرواتب', null, 202),
  ('payroll.pay', 'payroll', 'pay', 'دفع الرواتب', null, 203),
  ('payroll.reports', 'payroll', 'reports', 'تقارير الرواتب', null, 204),
  ('assets.view', 'assets', 'view', 'عرض الأصول', null, 220),
  ('assets.manage', 'assets', 'manage', 'إدارة الأصول', null, 221),
  ('assets.depreciate', 'assets', 'depreciate', 'ترحيل الإهلاك', null, 222),
  ('partners.view', 'partners', 'view', 'عرض الشركاء', null, 230),
  ('partners.manage', 'partners', 'manage', 'إدارة الشركاء', null, 231),
  ('partners.transactions', 'partners', 'transactions', 'حركات الشركاء', null, 232),
  ('approvals.view', 'approvals', 'view', 'عرض الموافقات', null, 240),
  ('approvals.create', 'approvals', 'create', 'إنشاء طلب موافقة', null, 241),
  ('approvals.resolve', 'approvals', 'resolve', 'اعتماد أو رفض الموافقات', null, 242),
  ('returns.view', 'returns', 'view', 'عرض المرتجعات', null, 250),
  ('returns.create', 'returns', 'create', 'إنشاء مرتجع', null, 251)
on conflict (code) do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.assign_company_member_role(target_company uuid, target_user uuid, target_role uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_role_owner boolean;
begin

  if not public.has_permission(
    target_company,
    'team.manage_members'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    c.owner_user_id

  into
    v_owner

  from public.companies c

  where c.id =
        target_company;


  if v_owner is null then
    raise exception 'Company not found';
  end if;


  if target_user =
     v_owner
  then
    raise exception
      'Company owner role cannot be changed';
  end if;


  select
    r.is_owner

  into
    v_role_owner

  from public.company_roles r

  where r.id =
        target_role

    and r.company_id =
        target_company

    and r.active =
        true;


  if not found then
    raise exception 'Invalid team role';
  end if;


  if coalesce(
       v_role_owner,
       false
     )
  then
    raise exception
      'Owner role can only be assigned to the company owner';
  end if;


  insert into public.company_members(
    company_id,
    user_id,
    role_id
  )
  values(
    target_company,
    target_user,
    target_role
  )

  on conflict(
    company_id,
    user_id
  )
  do update
  set role_id =
      excluded.role_id;

end;
$function$;

create or replace function public.delete_company_role(target_company uuid, target_role uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_owner boolean;
  v_is_protected boolean;
begin

  if not public.is_company_owner(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;


  select
    r.is_owner,
    r.is_protected

  into
    v_is_owner,
    v_is_protected

  from public.company_roles r

  where r.id =
        target_role

    and r.company_id =
        target_company

  for update;


  if not found then
    raise exception 'Role not found';
  end if;


  if v_is_owner
     or v_is_protected
  then
    raise exception 'Protected role cannot be deleted';
  end if;


  if exists (
    select 1
    from public.company_members cm
    where cm.company_id =
          target_company
      and cm.role_id =
          target_role
  ) then
    raise exception 'Role is assigned to team members';
  end if;


  delete from public.company_roles
  where id =
        target_role
    and company_id =
        target_company;

end;
$function$;

create or replace function public.handle_company_access_setup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner_role uuid;
begin
  insert into public.company_roles(
    company_id,
    name,
    description,
    is_owner,
    is_protected,
    active,
    created_by
  )
  values
    (new.id,'المالك','كامل الصلاحيات والتحكم بالنظام',true,true,true,new.owner_user_id),
    (new.id,'مدير','إدارة العمليات اليومية',false,false,true,new.owner_user_id),
    (new.id,'مبيعات','المبيعات والتجار والزيارات والتوصيل',false,false,true,new.owner_user_id),
    (new.id,'محاسب','المشتريات والصندوق والحسابات والتقارير',false,false,true,new.owner_user_id),
    (new.id,'مشاهدة','عرض البيانات بدون تعديل',false,false,true,new.owner_user_id)
  on conflict do nothing;

  select id
  into v_owner_role
  from public.company_roles
  where company_id = new.id
    and is_owner = true
  limit 1;

  insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code
  from public.company_roles r
  cross join public.permissions p
  where r.company_id = new.id
    and r.is_owner = true
  on conflict do nothing;

  insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code
  from public.company_roles r
  join public.permissions p on p.code = any(array[
    'dashboard.view','team.view',
    'traders.view','traders.create','traders.update','traders.archive',
    'traders.assign_rep','traders.view_balance',
    'visits.view','visits.create','visits.update',
    'suppliers.view','suppliers.create','suppliers.update','suppliers.archive',
    'suppliers.view_finance',
    'products.view','products.create','products.update','products.archive','products.view_cost',
    'orders.view','orders.create','orders.update','orders.cancel','orders.approve_discount',
    'deliveries.view','deliveries.update',
    'purchases.view','purchases.create','purchases.update','purchases.cancel',
    'sales_invoices.view','sales_invoices.create','sales_invoices.cancel',
    'purchase_invoices.view','purchase_invoices.create','purchase_invoices.cancel',
    'payments.sales_view','payments.sales_create','payments.sales_reverse',
    'payments.supplier_view','payments.supplier_create','payments.supplier_reverse',
    'inventory.view','inventory.adjust','inventory.returns',
    'finance.cashbox_view','finance.cashbox_write',
    'finance.expenses_view','finance.expenses_write','finance.expense_categories',
    'finance.accounts_view','finance.accounts_write','finance.month_close',
    'map.view',
    'reports.view','reports.sales','reports.profit','reports.finance','reports.team',
    'settings.view','settings.manage_company',
    'audit.view',
    'traders.manage_credit','orders.override_credit_limit',
    'payroll.view','payroll.reports',
    'assets.view','partners.view',
    'returns.view','returns.create','returns.reverse',
    'approvals.view','approvals.resolve'
  ]::text[])
  where r.company_id = new.id
    and r.name = 'مدير'
    and r.is_owner = false
  on conflict do nothing;

  insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code
  from public.company_roles r
  join public.permissions p on p.code = any(array[
    'dashboard.view',
    'traders.view','traders.create','traders.update','traders.archive',
    'traders.assign_rep','traders.view_balance',
    'visits.view','visits.create','visits.update',
    'suppliers.view','products.view',
    'orders.view','orders.create','orders.update','orders.cancel',
    'deliveries.view','deliveries.update',
    'payments.sales_view','payments.sales_create',
    'inventory.view','map.view',
    'returns.view','returns.create',
    'settings.view'
  ]::text[])
  where r.company_id = new.id
    and r.name = 'مبيعات'
    and r.is_owner = false
  on conflict do nothing;

  insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code
  from public.company_roles r
  join public.permissions p on p.code = any(array[
    'dashboard.view',
    'traders.view','traders.view_balance',
    'suppliers.view','suppliers.view_finance',
    'products.view','products.view_cost',
    'orders.view',
    'purchases.view','purchases.create','purchases.update','purchases.cancel',
    'sales_invoices.view',
    'purchase_invoices.view','purchase_invoices.create','purchase_invoices.cancel',
    'payments.sales_view','payments.sales_create','payments.sales_reverse',
    'payments.supplier_view','payments.supplier_create','payments.supplier_reverse',
    'inventory.view',
    'finance.cashbox_view','finance.cashbox_write',
    'finance.expenses_view','finance.expenses_write','finance.expense_categories',
    'finance.accounts_view','finance.accounts_write','finance.month_close',
    'reports.view','reports.sales','reports.profit','reports.finance',
    'settings.view',
    'traders.manage_credit',
    'payroll.view','payroll.manage_employees','payroll.process','payroll.pay','payroll.reports',
    'assets.view','assets.manage','assets.depreciate',
    'partners.view','partners.manage','partners.transactions',
    'returns.view','returns.create','returns.reverse',
    'approvals.view','approvals.create','approvals.resolve'
  ]::text[])
  where r.company_id = new.id
    and r.name = 'محاسب'
    and r.is_owner = false
  on conflict do nothing;

  insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code
  from public.company_roles r
  join public.permissions p on p.code = any(array[
    'dashboard.view','traders.view','suppliers.view','products.view','orders.view','settings.view'
  ]::text[])
  where r.company_id = new.id
    and r.name = 'مشاهدة'
    and r.is_owner = false
  on conflict do nothing;

  insert into public.company_members(company_id,user_id,role_id)
  values(new.id,new.owner_user_id,v_owner_role)
  on conflict (company_id,user_id)
  do update set role_id = excluded.role_id;

  return new;
end;
$function$;

create or replace function public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (
    id,
    full_name
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do update
  set full_name =
    case
      when coalesce(public.profiles.full_name, '') = ''
        then excluded.full_name
      else public.profiles.full_name
    end;

  return new;
end;
$function$;

create or replace function public.has_any_permission(target_company uuid, target_permissions text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    public.is_company_owner(target_company)
    or exists(
      select 1
      from public.company_members cm
      join public.role_permissions rp on rp.role_id = cm.role_id
      where cm.company_id = target_company
        and cm.user_id = auth.uid()
        and rp.permission_code = any(target_permissions)
    );
$function$;

create or replace function public.has_permission(target_company uuid, target_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    public.is_company_owner(target_company)
    or exists(
      select 1
      from public.company_members cm
      join public.role_permissions rp on rp.role_id = cm.role_id
      where cm.company_id = target_company
        and cm.user_id = auth.uid()
        and rp.permission_code = target_permission
    );
$function$;

create or replace function public.is_company_member(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.company_members cm
    where cm.company_id = target_company
      and cm.user_id = auth.uid()
  );
$function$;

-- أسماء أعضاء الفريق (لعرض "مين طلب/مين وافق" بالصفحات). كل عضو بالشركة بيشوف أسماء زملاءه بس.
create or replace function public.get_company_member_names(target_company uuid)
 RETURNS TABLE(user_id uuid, name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    cm.user_id,
    coalesce(
      nullif(trim(p.full_name), ''),
      nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
      split_part(u.email, '@', 1)
    )
  from public.company_members cm
  join auth.users u on u.id = cm.user_id
  left join public.profiles p on p.id = cm.user_id
  where cm.company_id = target_company
    and public.is_company_member(target_company);
$function$;

create or replace function public.is_company_owner(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.companies c
    where c.id = target_company
      and c.owner_user_id = auth.uid()
  );
$function$;

create or replace function public.protect_company_default_currency()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
begin
  v_currency :=
    upper(
      trim(
        coalesce(
          new.default_currency,
          ''
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception
      'Invalid company base currency';
  end if;

  new.default_currency :=
    v_currency;

  if tg_op = 'UPDATE'
     and new.default_currency
         is distinct from
         old.default_currency
     and exists (
       select 1
       from public.journal_entries
       where company_id = old.id
       limit 1
     )
  then
    raise exception
      'Company base currency cannot change after accounting history exists';
  end if;

  return new;
end;
$function$;

create or replace function public.protect_owner_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_role_owner boolean;
  v_company uuid;
begin
  if tg_op = 'DELETE' then
    v_company := old.company_id;
  else
    v_company := new.company_id;
  end if;

  select owner_user_id
  into v_owner
  from public.companies
  where id = v_company;

  if tg_op = 'DELETE' and old.user_id = v_owner then
    raise exception 'Company owner membership cannot be deleted';
  end if;

  if tg_op in ('INSERT','UPDATE') then
    select is_owner
    into v_role_owner
    from public.company_roles
    where id = new.role_id
      and company_id = new.company_id;

    if coalesce(v_role_owner,false) and new.user_id <> v_owner then
      raise exception 'Owner role can only be assigned to the company owner';
    end if;

    if tg_op = 'UPDATE' and old.user_id = v_owner then
      if new.user_id <> old.user_id
         or new.company_id <> old.company_id
         or coalesce(v_role_owner,false) = false
      then
        raise exception 'Company owner membership is protected';
      end if;
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;

create or replace function public.protect_owner_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' and old.is_owner then
    raise exception 'Owner role cannot be deleted';
  end if;

  if tg_op = 'UPDATE' and old.is_owner then
    if new.company_id <> old.company_id
       or new.is_owner = false
       or new.is_protected = false
       or new.active = false
    then
      raise exception 'Owner role is protected';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;

create or replace function public.remove_company_member(target_company uuid, target_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
begin

  if not public.has_permission(
    target_company,
    'team.manage_members'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    c.owner_user_id

  into
    v_owner

  from public.companies c

  where c.id =
        target_company;


  if v_owner is null then
    raise exception 'Company not found';
  end if;


  if target_user =
     v_owner
  then
    raise exception
      'Company owner cannot be removed';
  end if;


  delete from public.company_members
  where company_id =
        target_company

    and user_id =
        target_user;


  if not found then
    raise exception 'Team member not found';
  end if;

end;
$function$;

create or replace function public.save_company_role(target_company uuid, target_role uuid, role_name text, role_description text, permission_codes text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role uuid;
  v_is_owner boolean;
  v_is_protected boolean;
begin

  if not public.is_company_owner(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;


  if nullif(
       trim(role_name),
       ''
     ) is null
  then
    raise exception 'Role name is required';
  end if;


  if exists (
    select 1

    from unnest(
      coalesce(
        permission_codes,
        array[]::text[]
      )
    ) requested(code)

    where not exists (
      select 1
      from public.permissions p
      where p.code =
            requested.code
    )
  ) then
    raise exception 'Invalid permission code';
  end if;


  if target_role is null then

    insert into public.company_roles(
      company_id,
      name,
      description,
      is_owner,
      is_protected,
      active,
      created_by
    )
    values(
      target_company,
      trim(role_name),
      nullif(
        trim(role_description),
        ''
      ),
      false,
      false,
      true,
      auth.uid()
    )

    returning id
    into v_role;

  else

    select
      r.is_owner,
      r.is_protected

    into
      v_is_owner,
      v_is_protected

    from public.company_roles r

    where r.id =
          target_role

      and r.company_id =
          target_company

    for update;


    if not found then
      raise exception 'Role not found';
    end if;


    if v_is_owner
       or v_is_protected
    then
      raise exception 'Protected role cannot be modified';
    end if;


    update public.company_roles
    set
      name =
        trim(role_name),

      description =
        nullif(
          trim(role_description),
          ''
        )

    where id =
          target_role

      and company_id =
          target_company

    returning id
    into v_role;

  end if;


  delete from public.role_permissions
  where role_id =
        v_role;


  insert into public.role_permissions(
    role_id,
    permission_code
  )

  select
    v_role,
    requested.code

  from (
    select distinct
      unnest(
        coalesce(
          permission_codes,
          array[]::text[]
        )
      ) as code
  ) requested

  join public.permissions p
    on p.code =
       requested.code;


  return v_role;
end;
$function$;

create or replace function public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

create or replace function public.write_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  payload jsonb;
  old_payload jsonb;
  new_payload jsonb;
  target_company uuid;
  target_id uuid;
begin
  if tg_op = 'DELETE' then
    payload := to_jsonb(old);
    old_payload := to_jsonb(old);
    new_payload := null;
  elsif tg_op = 'INSERT' then
    payload := to_jsonb(new);
    old_payload := null;
    new_payload := to_jsonb(new);
  else
    payload := to_jsonb(new);
    old_payload := to_jsonb(old);
    new_payload := to_jsonb(new);
  end if;

  target_company :=
    nullif(payload ->> 'company_id','')::uuid;

  target_id :=
    nullif(payload ->> 'id','')::uuid;

  if target_company is not null then
    insert into public.audit_logs(
      company_id,
      actor_user_id,
      action,
      entity_table,
      entity_id,
      old_data,
      new_data
    )
    values(
      target_company,
      auth.uid(),
      lower(tg_op),
      tg_table_name,
      target_id,
      old_payload,
      new_payload
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger companies_updated_at before update on public.companies for each row execute function public.set_updated_at();

create trigger on_company_access_setup after insert on public.companies for each row execute function public.handle_company_access_setup();

create trigger protect_company_default_currency_trigger before insert or update of default_currency on public.companies for each row execute function public.protect_company_default_currency();

create trigger audit_company_members after insert or delete or update on public.company_members for each row execute function public.write_audit_log();

create trigger protect_owner_membership_trigger before insert or delete or update on public.company_members for each row execute function public.protect_owner_membership();

create trigger audit_company_roles after insert or delete or update on public.company_roles for each row execute function public.write_audit_log();

create trigger company_roles_updated_at before update on public.company_roles for each row execute function public.set_updated_at();

create trigger protect_owner_role_trigger before delete or update on public.company_roles for each row execute function public.protect_owner_role();

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.permissions enable row level security;
alter table public.company_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.company_members enable row level security;
alter table public.audit_logs enable row level security;
alter table public.document_sequences enable row level security;
create policy audit_logs_read on public.audit_logs
  for select to authenticated
  using (public.has_permission(company_id, 'audit.view'::text));
create policy companies_create on public.companies
  for insert to authenticated
  with check ((owner_user_id = auth.uid()));
create policy companies_read on public.companies
  for select to authenticated
  using (((owner_user_id = auth.uid()) or public.is_company_member(id)));
create policy companies_update on public.companies
  for update to authenticated
  using (public.has_permission(id, 'settings.manage_company'::text))
  with check (public.has_permission(id, 'settings.manage_company'::text));
create policy company_members_create on public.company_members
  for insert to authenticated
  with check (public.has_permission(company_id, 'team.manage_members'::text));
create policy company_members_delete on public.company_members
  for delete to authenticated
  using (public.has_permission(company_id, 'team.manage_members'::text));
create policy company_members_read on public.company_members
  for select to authenticated
  using (((user_id = auth.uid()) or public.has_permission(company_id, 'team.view'::text)));
create policy company_members_update on public.company_members
  for update to authenticated
  using (public.has_permission(company_id, 'team.manage_members'::text))
  with check (public.has_permission(company_id, 'team.manage_members'::text));
create policy company_roles_owner_write on public.company_roles
  for all to authenticated
  using (public.is_company_owner(company_id))
  with check (public.is_company_owner(company_id));
create policy company_roles_read on public.company_roles
  for select to authenticated
  using (public.is_company_member(company_id));
create policy permissions_read on public.permissions
  for select to authenticated
  using (true);
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check ((id = auth.uid()));
create policy profiles_read on public.profiles
  for select to authenticated
  using ((id = auth.uid()));
create policy profiles_update on public.profiles
  for update to authenticated
  using ((id = auth.uid()))
  with check ((id = auth.uid()));
create policy role_permissions_owner_write on public.role_permissions
  for all to authenticated
  using ((exists ( select 1
   from public.company_roles r
  where ((r.id = role_permissions.role_id) and public.is_company_owner(r.company_id)))))
  with check ((exists ( select 1
   from public.company_roles r
  where ((r.id = role_permissions.role_id) and public.is_company_owner(r.company_id)))));
create policy role_permissions_read on public.role_permissions
  for select to authenticated
  using ((exists ( select 1
   from public.company_roles r
  where ((r.id = role_permissions.role_id) and public.is_company_member(r.company_id)))));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.audit_logs from authenticated;
revoke select, insert, update, delete on public.document_sequences from authenticated;

-- ======================================================================
-- الأصناف والزبائن والموردين
-- الفئات، الأصناف، الزبائن وزياراتهم، الموردين وأسعارهم
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint categories_company_id_name_key unique (company_id, name)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  brand text,
  unit text default 'قطعة'::text not null,
  sale_price numeric(14,2),
  minimum_sale_price numeric(14,2),
  image_url text,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint products_company_id_sku_key unique (company_id, sku),
  constraint products_minimum_sale_price_check check (((minimum_sale_price is null) or (minimum_sale_price >= (0)::numeric))),
  constraint products_sale_price_check check (((sale_price is null) or (sale_price >= (0)::numeric)))
);
create index dashboard_products_active_idx on public.products using btree (company_id, active);

create table public.traders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  area text,
  address text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  status text default 'new'::text not null,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  credit_limit numeric(14,2),
  payment_terms_days integer default 0 not null,
  whatsapp_marketing_opt_in boolean default false not null,
  whatsapp_opt_in_at timestamp with time zone,
  whatsapp_opt_out_at timestamp with time zone,
  constraint traders_check check ((((latitude is null) and (longitude is null)) or ((latitude is not null) and (longitude is not null)))),
  constraint traders_credit_limit_check check (((credit_limit is null) or (credit_limit >= (0)::numeric))),
  constraint traders_latitude_check check (((latitude is null) or ((latitude >= ('-90'::integer)::numeric) and (latitude <= (90)::numeric)))),
  constraint traders_longitude_check check (((longitude is null) or ((longitude >= ('-180'::integer)::numeric) and (longitude <= (180)::numeric)))),
  constraint traders_payment_terms_days_check check (((payment_terms_days >= 0) and (payment_terms_days <= 3650))),
  constraint traders_status_check check ((status = any (array['new'::text, 'contacted'::text, 'interested'::text, 'customer'::text, 'inactive'::text])))
);
create index dashboard_traders_customer_idx on public.traders using btree (company_id, status, created_at desc);
create unique index traders_company_phone_unique on public.traders using btree (company_id, phone) where (phone is not null);
create unique index traders_company_whatsapp_unique on public.traders using btree (company_id, whatsapp) where (whatsapp is not null);

create table public.trader_visits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete cascade,
  result text default 'زيارة'::text not null,
  notes text,
  contacted_at timestamp with time zone default now() not null,
  next_follow_up_at timestamp with time zone,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null
);
create index trader_visits_company_idx on public.trader_visits using btree (company_id);
create index trader_visits_trader_idx on public.trader_visits using btree (trader_id, contacted_at desc);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  address text,
  notes text,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  payment_terms_days integer default 0 not null,
  constraint suppliers_payment_terms_days_check check (((payment_terms_days >= 0) and (payment_terms_days <= 3650)))
);
create index dashboard_suppliers_active_idx on public.suppliers using btree (company_id, active);

create table public.supplier_prices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  purchase_price numeric(14,2) not null,
  available boolean default true not null,
  notes text,
  last_checked_at timestamp with time zone default now() not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint supplier_prices_supplier_id_product_id_key unique (supplier_id, product_id),
  constraint supplier_prices_purchase_price_check check ((purchase_price >= (0)::numeric))
);

create table public.supplier_price_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  purchase_price numeric(14,2) not null,
  available boolean default true not null,
  notes text,
  effective_at timestamp with time zone default now() not null,
  changed_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint supplier_price_history_purchase_price_check check ((purchase_price >= (0)::numeric))
);
create index supplier_price_history_company_idx on public.supplier_price_history using btree (company_id, effective_at desc);
create index supplier_price_history_lookup_idx on public.supplier_price_history using btree (company_id, product_id, supplier_id, effective_at desc);
create index supplier_price_history_product_idx on public.supplier_price_history using btree (product_id, effective_at desc);
create index supplier_price_history_supplier_idx on public.supplier_price_history using btree (supplier_id, effective_at desc);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.archive_trader(target_company uuid, target_trader uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'traders.archive'
  ) then
    raise exception 'Not allowed';
  end if;

  update public.traders
  set status = 'inactive'
  where id = target_trader
    and company_id = target_company;

  if not found then
    raise exception 'Trader not found';
  end if;
end;
$function$;

create or replace function public.capture_supplier_price_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if
    tg_op = 'INSERT'
    or old.purchase_price is distinct from new.purchase_price
    or old.available is distinct from new.available
    or old.notes is distinct from new.notes
  then
    insert into public.supplier_price_history (
      company_id,
      supplier_id,
      product_id,
      purchase_price,
      available,
      notes,
      effective_at,
      changed_by
    )
    values (
      new.company_id,
      new.supplier_id,
      new.product_id,
      new.purchase_price,
      new.available,
      new.notes,
      coalesce(new.last_checked_at, now()),
      auth.uid()
    );
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_product_active_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    if new.active = false
       and not public.has_permission(
         new.company_id,
         'products.archive'
       )
    then
      raise exception 'Not allowed';
    end if;

    return new;
  end if;

  if new.active
     is distinct from old.active
     and not public.has_permission(
       new.company_id,
       'products.archive'
     )
  then
    raise exception 'Not allowed';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_product_category_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.category_id is not null
     and not exists (
       select 1
       from public.categories c
       where c.id = new.category_id
         and c.company_id = new.company_id
     )
  then
    raise exception 'Category does not belong to this company';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_supplier_active_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    if new.active = false
       and not public.has_permission(
         new.company_id,
         'suppliers.archive'
       )
    then
      raise exception 'Not allowed';
    end if;

    return new;
  end if;

  if new.active is distinct from old.active
     and not public.has_permission(
       new.company_id,
       'suppliers.archive'
     )
  then
    raise exception 'Not allowed';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_supplier_price_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if not exists (
    select 1
    from public.suppliers s
    where s.id = new.supplier_id
      and s.company_id = new.company_id
  ) then
    raise exception 'Supplier does not belong to this company';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception 'Product does not belong to this company';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_trader_credit_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  -- حد الدين ومهلة الدفع ما بيغيّرهن إلا اللي عنده صلاحية "تحديد حد الدين" (مش المندوب).
  -- بدونها، مندوب عنده صلاحية "تعديل زبون" كان يقدر يرفع حد الدين من برا الشاشة.
  if auth.uid() is null then
    return new;
  end if;

  if (
    tg_op = 'INSERT'
    and (new.credit_limit is not null or new.payment_terms_days <> 0)
  ) or (
    tg_op = 'UPDATE'
    and (
      new.credit_limit is distinct from old.credit_limit
      or new.payment_terms_days is distinct from old.payment_terms_days
    )
  ) then
    if not public.has_permission(new.company_id, 'traders.manage_credit') then
      raise exception 'Not allowed to change credit terms';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_trader_archive_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_requires_archive boolean := false;
begin
  if new.status = 'inactive' then
    if tg_op = 'INSERT' then
      v_requires_archive := true;
    elsif old.status is distinct from 'inactive' then
      v_requires_archive := true;
    end if;
  end if;

  if v_requires_archive
     and not public.has_permission(
       new.company_id,
       'traders.archive'
     )
  then
    raise exception 'Not allowed';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_trader_visit_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if not exists (
    select 1
    from public.traders t
    where t.id = new.trader_id
      and t.company_id = new.company_id
  ) then
    raise exception 'Trader does not belong to this company';
  end if;

  return new;
end;
$function$;

create or replace function public.get_map_traders(target_company uuid)
 RETURNS TABLE(id uuid, name text, area text, address text, phone text, whatsapp text, latitude numeric, longitude numeric, status text, balance_due numeric, overdue boolean, pending_orders integer, pending_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  v_today date := (now() at time zone 'Asia/Damascus')::date;
  v_can_see_balance boolean;
  v_can_see_deliveries boolean;
begin
  if not public.has_permission(target_company, 'map.view') then
    raise exception 'Not allowed';
  end if;

  -- الديون والتوصيلات بتطلع بس لمين عنده صلاحية يشوفها.
  v_can_see_balance := public.has_any_permission(
    target_company,
    array['traders.view_balance', 'payments.sales_view', 'reports.sales', 'reports.finance']::text[]
  );
  v_can_see_deliveries := public.has_any_permission(
    target_company,
    array['deliveries.view', 'deliveries.update']::text[]
  );

  return query
  with debts as (
    -- الرصيد بعملة الشركة.
    select
      si.trader_id,
      sum(public.finance_to_base(target_company, si.currency, si.balance_due, v_today)) as balance,
      bool_or(coalesce(si.due_date, si.invoice_date) < v_today) as is_overdue
    from public.sales_invoices si
    where si.company_id = target_company
      and si.status = 'posted'
      and si.balance_due > 0
    group by si.trader_id
  ),
  pending as (
    -- طلبيات جاهزة للتوصيل أو طالعة مع السواق.
    select
      so.trader_id,
      count(*)::integer as orders,
      sum(so.total) as orders_total
    from public.sales_orders so
    where so.company_id = target_company
      and so.status in ('ready', 'out_for_delivery')
    group by so.trader_id
  )
  select
    t.id,
    t.name,
    t.area,
    t.address,
    t.phone,
    t.whatsapp,
    t.latitude,
    t.longitude,
    t.status,
    case when v_can_see_balance then round(coalesce(d.balance, 0), 2) end,
    case when v_can_see_balance then coalesce(d.is_overdue, false) end,
    case when v_can_see_deliveries then coalesce(p.orders, 0) end,
    case when v_can_see_deliveries then round(coalesce(p.orders_total, 0), 2) end
  from public.traders t
  left join debts d on d.trader_id = t.id
  left join pending p on p.trader_id = t.id
  where t.company_id = target_company
    and t.status <> 'inactive'
  order by t.area nulls last, t.name;
end;
$function$;

create or replace function public.prevent_duplicate_trader_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if exists (
    select 1
    from public.traders t
    where t.company_id = new.company_id
      and t.id <> new.id
      and (
        (new.phone is not null and (t.phone = new.phone or t.whatsapp = new.phone))
        or
        (new.whatsapp is not null and (t.phone = new.whatsapp or t.whatsapp = new.whatsapp))
      )
  ) then
    raise exception 'رقم الهاتف أو واتساب مستخدم عند تاجر آخر';
  end if;

  return new;
end;
$function$;

create or replace function public.save_product_with_supplier_prices(target_company uuid, target_product uuid, product_name text, product_sku text, product_brand text, target_category uuid, product_unit text, product_sale_price numeric, product_minimum_sale_price numeric, product_image_url text, product_active boolean, supplier_prices_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_product uuid;
  v_item jsonb;
  v_supplier uuid;
  v_price numeric;
  v_available boolean;
  v_notes text;
begin
  if nullif(trim(product_name), '') is null then
    raise exception 'Product name is required';
  end if;

  if product_sale_price is not null and product_sale_price < 0 then
    raise exception 'Invalid sale price';
  end if;

  if product_minimum_sale_price is not null
     and product_minimum_sale_price < 0 then
    raise exception 'Invalid minimum sale price';
  end if;

  if target_category is not null
     and not exists (
       select 1
       from public.categories c
       where c.id = target_category
         and c.company_id = target_company
     ) then
    raise exception 'Invalid category';
  end if;

  if target_product is null then

    if not public.has_permission(target_company, 'products.create') then
      raise exception 'Not allowed';
    end if;

    insert into public.products(
      company_id,
      category_id,
      sku,
      name,
      brand,
      unit,
      sale_price,
      minimum_sale_price,
      image_url,
      active
    )
    values(
      target_company,
      target_category,
      nullif(trim(product_sku), ''),
      trim(product_name),
      nullif(trim(product_brand), ''),
      coalesce(nullif(trim(product_unit), ''), 'قطعة'),
      product_sale_price,
      product_minimum_sale_price,
      nullif(trim(product_image_url), ''),
      product_active
    )
    returning id into v_product;

  else

    if not public.has_permission(target_company, 'products.update') then
      raise exception 'Not allowed';
    end if;

    update public.products
    set
      category_id = target_category,
      sku = nullif(trim(product_sku), ''),
      name = trim(product_name),
      brand = nullif(trim(product_brand), ''),
      unit = coalesce(nullif(trim(product_unit), ''), 'قطعة'),
      sale_price = product_sale_price,
      minimum_sale_price = product_minimum_sale_price,
      image_url = nullif(trim(product_image_url), ''),
      active = product_active,
      updated_at = now()
    where id = target_product
      and company_id = target_company
    returning id into v_product;

    if v_product is null then
      raise exception 'Product not found';
    end if;

  end if;

  for v_item in
    select value
    from jsonb_array_elements(
      coalesce(supplier_prices_payload, '[]'::jsonb)
    )
  loop

    v_supplier := (v_item ->> 'supplier_id')::uuid;
    v_price := (v_item ->> 'purchase_price')::numeric;
    v_available := coalesce(
      (v_item ->> 'available')::boolean,
      true
    );
    v_notes := nullif(trim(v_item ->> 'notes'), '');

    if v_price is null or v_price < 0 then
      raise exception 'Invalid supplier price';
    end if;

    if not exists (
      select 1
      from public.suppliers s
      where s.id = v_supplier
        and s.company_id = target_company
    ) then
      raise exception 'Invalid supplier';
    end if;

    insert into public.supplier_prices(
      company_id,
      supplier_id,
      product_id,
      purchase_price,
      available,
      notes,
      last_checked_at
    )
    values(
      target_company,
      v_supplier,
      v_product,
      v_price,
      v_available,
      v_notes,
      now()
    )
    on conflict (supplier_id, product_id)
    do update set
      purchase_price = excluded.purchase_price,
      available = excluded.available,
      notes = excluded.notes,
      last_checked_at = now(),
      updated_at = now();

  end loop;

  -- أسعار الموردين غير الموجودة في الحمولة الحالية تصبح غير متاحة.
  -- نحافظ على السجل التاريخي بدل الحذف.
  update public.supplier_prices sp
  set
    available = false,
    last_checked_at = now(),
    updated_at = now()
  where sp.company_id = target_company
    and sp.product_id = v_product
    and sp.available = true
    and not exists (
      select 1
      from jsonb_array_elements(
        coalesce(supplier_prices_payload, '[]'::jsonb)
      ) as x(item)
      where (x.item ->> 'supplier_id')::uuid = sp.supplier_id
    );

  return v_product;
end;
$function$;

create or replace function public.set_product_active(target_company uuid, target_product uuid, target_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(target_company, 'products.archive') then
    raise exception 'Not allowed';
  end if;

  -- ما منأرشف صنف موجود بطلبية لسا ما خلصت، مشان ما تعلق الطلبية.
  if target_active = false and exists (
    select 1
    from public.sales_order_items soi
    join public.sales_orders so on so.id = soi.order_id
    where soi.product_id = target_product
      and so.company_id = target_company
      and so.status in ('draft', 'new', 'to_purchase', 'purchasing', 'ready', 'out_for_delivery')
  ) then
    raise exception 'Product has open orders';
  end if;

  update public.products
  set
    active = target_active,
    updated_at = now()
  where id = target_product
    and company_id = target_company;

  if not found then
    raise exception 'Product not found';
  end if;
end;
$function$;

create or replace function public.set_trader_whatsapp_consent_timestamps()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    if new.whatsapp_marketing_opt_in then
      new.whatsapp_opt_in_at := now();
      new.whatsapp_opt_out_at := null;
    else
      new.whatsapp_opt_in_at := null;
      new.whatsapp_opt_out_at := null;
    end if;

    return new;
  end if;

  -- Prevent ordinary customer edits from rewriting consent history.
  new.whatsapp_opt_in_at := old.whatsapp_opt_in_at;
  new.whatsapp_opt_out_at := old.whatsapp_opt_out_at;

  if new.whatsapp_marketing_opt_in
     is distinct from old.whatsapp_marketing_opt_in
  then
    if new.whatsapp_marketing_opt_in then
      new.whatsapp_opt_in_at := now();
    else
      new.whatsapp_opt_out_at := now();
    end if;
  end if;

  return new;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger categories_updated_at before update on public.categories for each row execute function public.set_updated_at();

create trigger audit_products after insert or delete or update on public.products for each row execute function public.write_audit_log();

create trigger products_active_permission_guard before insert or update of active on public.products for each row execute function public.enforce_product_active_permission();

create trigger products_category_company_guard before insert or update of company_id, category_id on public.products for each row execute function public.enforce_product_category_company();

create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();

create trigger supplier_prices_company_guard before insert or update of company_id, supplier_id, product_id on public.supplier_prices for each row execute function public.enforce_supplier_price_company();

create trigger supplier_prices_history_trigger after insert or update on public.supplier_prices for each row execute function public.capture_supplier_price_history();

create trigger supplier_prices_updated_at before update on public.supplier_prices for each row execute function public.set_updated_at();

create trigger audit_suppliers after insert or delete or update on public.suppliers for each row execute function public.write_audit_log();

create trigger suppliers_active_permission_guard before insert or update of active on public.suppliers for each row execute function public.enforce_supplier_active_permission();

create trigger suppliers_updated_at before update on public.suppliers for each row execute function public.set_updated_at();

create trigger trader_visits_company_guard before insert or update of company_id, trader_id on public.trader_visits for each row execute function public.enforce_trader_visit_company();

create trigger audit_traders after insert or delete or update on public.traders for each row execute function public.write_audit_log();

create trigger traders_archive_permission_guard before insert or update on public.traders for each row execute function public.enforce_trader_archive_permission();
create trigger traders_credit_permission_guard before insert or update of credit_limit, payment_terms_days on public.traders for each row execute function public.enforce_trader_credit_permission();

create trigger traders_prevent_duplicate_contact before insert or update of phone, whatsapp on public.traders for each row execute function public.prevent_duplicate_trader_contact();

create trigger traders_updated_at before update on public.traders for each row execute function public.set_updated_at();

create trigger traders_whatsapp_consent_timestamps before insert or update of whatsapp_marketing_opt_in, whatsapp_opt_in_at, whatsapp_opt_out_at on public.traders for each row execute function public.set_trader_whatsapp_consent_timestamps();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.traders enable row level security;
alter table public.trader_visits enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_prices enable row level security;
alter table public.supplier_price_history enable row level security;
create policy categories_create on public.categories
  for insert to authenticated
  with check (public.has_permission(company_id, 'products.create'::text));
create policy categories_delete on public.categories
  for delete to authenticated
  using (public.has_permission(company_id, 'products.archive'::text));
create policy categories_read on public.categories
  for select to authenticated
  using (public.has_any_permission(company_id, array['products.view'::text, 'orders.view'::text, 'purchases.view'::text]));
create policy categories_update on public.categories
  for update to authenticated
  using (public.has_permission(company_id, 'products.update'::text))
  with check (public.has_permission(company_id, 'products.update'::text));
create policy products_create on public.products
  for insert to authenticated
  with check (public.has_permission(company_id, 'products.create'::text));
create policy products_read on public.products
  for select to authenticated
  using (public.has_any_permission(company_id, array['products.view'::text, 'orders.view'::text, 'orders.create'::text, 'purchases.view'::text, 'inventory.view'::text, 'reports.sales'::text, 'reports.profit'::text]));
create policy products_update on public.products
  for update to authenticated
  using (public.has_permission(company_id, 'products.update'::text))
  with check (public.has_permission(company_id, 'products.update'::text));
create policy supplier_price_history_select on public.supplier_price_history
  for select to authenticated
  using (public.has_any_permission(company_id, array['products.view_cost'::text, 'purchases.view'::text, 'suppliers.view_finance'::text]));
create policy supplier_prices_create on public.supplier_prices
  for insert to authenticated
  with check (public.has_permission(company_id, 'products.update'::text));
create policy supplier_prices_read on public.supplier_prices
  for select to authenticated
  using (public.has_any_permission(company_id, array['products.view_cost'::text, 'products.update'::text, 'purchases.view'::text, 'purchases.create'::text, 'purchases.update'::text, 'purchase_invoices.view'::text, 'purchase_invoices.create'::text, 'suppliers.view_finance'::text, 'reports.profit'::text, 'reports.finance'::text]));
create policy supplier_prices_update on public.supplier_prices
  for update to authenticated
  using (public.has_permission(company_id, 'products.update'::text))
  with check (public.has_permission(company_id, 'products.update'::text));
create policy suppliers_create on public.suppliers
  for insert to authenticated
  with check (public.has_permission(company_id, 'suppliers.create'::text));
create policy suppliers_read on public.suppliers
  for select to authenticated
  using (public.has_any_permission(company_id, array['suppliers.view'::text, 'purchases.view'::text, 'products.view'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy suppliers_update on public.suppliers
  for update to authenticated
  using (public.has_permission(company_id, 'suppliers.update'::text))
  with check (public.has_permission(company_id, 'suppliers.update'::text));
create policy trader_visits_create on public.trader_visits
  for insert to authenticated
  with check (public.has_permission(company_id, 'visits.create'::text));
create policy trader_visits_delete on public.trader_visits
  for delete to authenticated
  using (public.has_permission(company_id, 'visits.update'::text));
create policy trader_visits_read on public.trader_visits
  for select to authenticated
  using (public.has_any_permission(company_id, array['visits.view'::text, 'reports.team'::text]));
create policy trader_visits_update on public.trader_visits
  for update to authenticated
  using (public.has_permission(company_id, 'visits.update'::text))
  with check (public.has_permission(company_id, 'visits.update'::text));
create policy traders_create on public.traders
  for insert to authenticated
  with check (public.has_permission(company_id, 'traders.create'::text));
create policy traders_read on public.traders
  for select to authenticated
  using (public.has_any_permission(company_id, array['traders.view'::text, 'orders.view'::text, 'orders.create'::text, 'map.view'::text, 'reports.sales'::text, 'reports.profit'::text, 'reports.team'::text]));
create policy traders_update on public.traders
  for update to authenticated
  using (public.has_permission(company_id, 'traders.update'::text))
  with check (public.has_permission(company_id, 'traders.update'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke execute on function public.enforce_product_active_permission() from authenticated;
revoke execute on function public.enforce_product_category_company() from authenticated;

-- ======================================================================
-- المحاسبة
-- دليل الحسابات، الفترات المالية، أسعار الصرف، القيود اليومية
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  parent_id uuid references public.finance_accounts(id) on delete restrict,
  code text not null,
  name text not null,
  account_type text not null,
  account_group text,
  normal_balance text not null,
  system_key text,
  allow_posting boolean default true not null,
  is_system boolean default false not null,
  active boolean default true not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint finance_accounts_company_id_code_key unique (company_id, code),
  constraint finance_accounts_account_type_check check ((account_type = any (array['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text]))),
  constraint finance_accounts_normal_balance_check check ((normal_balance = any (array['debit'::text, 'credit'::text])))
);
create index finance_accounts_company_idx on public.finance_accounts using btree (company_id, account_type, active, code);
create unique index finance_accounts_system_key_unique on public.finance_accounts using btree (company_id, system_key) where (system_key is not null);

create table public.finance_periods (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text default 'open'::text not null,
  closed_at timestamp with time zone,
  closed_by uuid references auth.users(id) on delete set null,
  reopened_at timestamp with time zone,
  reopened_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint finance_periods_company_id_period_start_key unique (company_id, period_start),
  constraint finance_periods_check check ((period_end >= period_start)),
  constraint finance_periods_status_check check ((status = any (array['open'::text, 'closed'::text])))
);

create table public.finance_exchange_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  currency text not null,
  rate_date date not null,
  rate_to_base numeric(24,10) not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint finance_exchange_rates_company_id_currency_rate_date_key unique (company_id, currency, rate_date),
  constraint finance_exchange_rates_currency_check check ((upper(trim(both from currency)) ~ '^[A-Z]{3}$'::text)),
  constraint finance_exchange_rates_rate_to_base_check check ((rate_to_base > (0)::numeric))
);
create index finance_exchange_rates_lookup_idx on public.finance_exchange_rates using btree (company_id, currency, rate_date desc);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entry_number text not null,
  entry_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  description text not null,
  status text default 'posted'::text not null,
  currency text default 'USD'::text not null,
  exchange_rate_to_base numeric(20,8) default 1 not null,
  source_type text,
  source_id uuid,
  reversed_from_id uuid references public.journal_entries(id) on delete restrict,
  posted_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint journal_entries_company_id_entry_number_key unique (company_id, entry_number),
  constraint journal_entries_exchange_rate_to_base_check check ((exchange_rate_to_base > (0)::numeric)),
  constraint journal_entries_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index journal_entries_company_date_idx on public.journal_entries using btree (company_id, entry_date desc, created_at desc);
create unique index journal_entries_reversal_unique on public.journal_entries using btree (reversed_from_id) where (reversed_from_id is not null);
create index journal_entries_source_idx on public.journal_entries using btree (company_id, source_type, source_id);
create unique index journal_entries_source_unique on public.journal_entries using btree (company_id, source_type, source_id) where ((source_id is not null) and (reversed_from_id is null));

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid not null references public.finance_accounts(id) on delete restrict,
  debit numeric(18,2) default 0 not null,
  credit numeric(18,2) default 0 not null,
  base_debit numeric(18,2) default 0 not null,
  base_credit numeric(18,2) default 0 not null,
  party_type text,
  party_id uuid,
  memo text,
  created_at timestamp with time zone default now() not null,
  constraint journal_lines_base_credit_check check ((base_credit >= (0)::numeric)),
  constraint journal_lines_base_debit_check check ((base_debit >= (0)::numeric)),
  constraint journal_lines_check check ((((debit > (0)::numeric) and (credit = (0)::numeric)) or ((credit > (0)::numeric) and (debit = (0)::numeric)))),
  constraint journal_lines_credit_check check ((credit >= (0)::numeric)),
  constraint journal_lines_debit_check check ((debit >= (0)::numeric)),
  constraint journal_lines_party_type_check check (((party_type is null) or (party_type = any (array['trader'::text, 'supplier'::text, 'employee'::text, 'partner'::text, 'other'::text]))))
);
create index journal_lines_account_idx on public.journal_lines using btree (company_id, account_id);
create index journal_lines_entry_idx on public.journal_lines using btree (journal_entry_id);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.assert_finance_period_open(target_company uuid, target_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (
    select 1
    from public.finance_periods fp
    where fp.company_id =
          target_company
      and fp.status =
          'closed'
      and target_date
          between
          fp.period_start
          and
          fp.period_end
  ) then
    raise exception
      'Financial period is closed';
  end if;
end;
$function$;

create or replace function public.balance_journal_base_rounding(target_entry uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_diff numeric(18,2);
  v_line uuid;
begin
  select
    round(
      coalesce(
        sum(base_debit),
        0
      ),
      2
    ),
    round(
      coalesce(
        sum(base_credit),
        0
      ),
      2
    )
  into
    v_debit,
    v_credit
  from public.journal_lines
  where journal_entry_id =
        target_entry;

  v_diff :=
    round(
      v_debit -
      v_credit,
      2
    );

  if abs(v_diff) <= 0.009 then
    return;
  end if;

  if v_diff > 0 then

    select id
    into v_line
    from public.journal_lines
    where journal_entry_id =
          target_entry
      and credit > 0
    order by
      base_credit desc,
      id
    limit 1
    for update;

    if v_line is null then
      raise exception
        'Cannot balance journal base rounding';
    end if;

    update public.journal_lines
    set base_credit =
        round(
          base_credit +
          v_diff,
          2
        )
    where id = v_line;

  else

    select id
    into v_line
    from public.journal_lines
    where journal_entry_id =
          target_entry
      and debit > 0
    order by
      base_debit desc,
      id
    limit 1
    for update;

    if v_line is null then
      raise exception
        'Cannot balance journal base rounding';
    end if;

    update public.journal_lines
    set base_debit =
        round(
          base_debit +
          abs(v_diff),
          2
        )
    where id = v_line;

  end if;

  select
    round(
      coalesce(
        sum(base_debit),
        0
      ),
      2
    ),
    round(
      coalesce(
        sum(base_credit),
        0
      ),
      2
    )
  into
    v_debit,
    v_credit
  from public.journal_lines
  where journal_entry_id =
        target_entry;

  if v_debit <> v_credit then
    raise exception
      'Journal base currency is not balanced';
  end if;
end;
$function$;

create or replace function public.close_finance_month(target_company uuid, target_year integer, target_month integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
  v_end date;
begin
  if not public.has_permission(
    target_company,
    'finance.month_close'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_month < 1
     or target_month > 12
  then
    raise exception 'Invalid month';
  end if;

  v_start :=
    make_date(
      target_year,
      target_month,
      1
    );

  v_end :=
    (
      v_start +
      interval '1 month' -
      interval '1 day'
    )::date;

  insert into public.finance_periods(
    company_id,
    period_start,
    period_end,
    status,
    closed_at,
    closed_by
  )
  values(
    target_company,
    v_start,
    v_end,
    'closed',
    now(),
    auth.uid()
  )
  on conflict(
    company_id,
    period_start
  )
  do update set
    period_end =
      excluded.period_end,

    status =
      'closed',

    closed_at =
      now(),

    closed_by =
      auth.uid(),

    reopened_at =
      null,

    reopened_by =
      null;
end;
$function$;

create or replace function public.company_default_chart_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.ensure_default_chart_of_accounts(
      new.id
    );

  return new;
end;
$function$;

create or replace function public.ensure_default_chart_of_accounts(target_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  -- Main groups
  insert into public.finance_accounts(
    company_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    allow_posting,
    is_system
  )
  values
  (
    target_company,
    '1000',
    'الأصول',
    'asset',
    'assets',
    'debit',
    false,
    true
  ),
  (
    target_company,
    '2000',
    'الالتزامات',
    'liability',
    'liabilities',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '3000',
    'حقوق الملكية',
    'equity',
    'equity',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '4000',
    'الإيرادات',
    'revenue',
    'revenue',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '5000',
    'تكلفة المبيعات',
    'expense',
    'cost_of_sales',
    'debit',
    false,
    true
  ),
  (
    target_company,
    '6000',
    'المصاريف',
    'expense',
    'expenses',
    'debit',
    false,
    true
  )
  on conflict(
    company_id,
    code
  )
  do nothing;


  -- Assets
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1100',
    'الصندوق والبنوك',
    'asset',
    'cash_bank',
    'debit',
    null,
    false,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1110',
    'الصندوق الرئيسي',
    'asset',
    'cash_bank',
    'debit',
    'cash_default',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1100'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1200',
    'ذمم العملاء',
    'asset',
    'receivables',
    'debit',
    'accounts_receivable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1300',
    'المخزون',
    'asset',
    'inventory',
    'debit',
    'inventory',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1400',
    'سلف وقروض الموظفين',
    'asset',
    'employee_receivables',
    'debit',
    'employee_advances',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1500',
    'الأصول الثابتة',
    'asset',
    'fixed_assets',
    'debit',
    'fixed_assets',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1590',
    'مجمع إهلاك الأصول',
    'asset',
    'fixed_assets',
    'credit',
    'accumulated_depreciation',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  -- Liabilities
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2100',
    'ذمم الموردين',
    'liability',
    'payables',
    'credit',
    'accounts_payable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2200',
    'رواتب وأجور مستحقة',
    'liability',
    'payroll',
    'credit',
    'payroll_payable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2300',
    'اقتطاعات وضرائب رواتب مستحقة',
    'liability',
    'payroll',
    'credit',
    'payroll_withholdings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  -- Equity
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3100',
    'رأس المال',
    'equity',
    'capital',
    'credit',
    'capital',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3200',
    'مسحوبات وجاري الشركاء',
    'equity',
    'partner_drawings',
    'debit',
    'partner_drawings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3300',
    'الأرباح المحتجزة',
    'equity',
    'retained_earnings',
    'credit',
    'retained_earnings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  -- Revenue
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '4100',
    'إيرادات المبيعات',
    'revenue',
    'sales',
    'credit',
    'sales_revenue',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '4000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '4200',
    'مردودات ومسموحات المبيعات',
    'revenue',
    'sales_returns',
    'debit',
    'sales_returns',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '4000'
  on conflict(company_id,code)
  do nothing;


  -- Cost of sales
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '5100',
    'تكلفة البضاعة المباعة',
    'expense',
    'cost_of_sales',
    'debit',
    'cogs',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '5000'
  on conflict(company_id,code)
  do nothing;


  -- Expenses
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6100',
    'الرواتب والأجور',
    'expense',
    'payroll',
    'debit',
    'salary_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6110',
    'بدلات ومكافآت الموظفين',
    'expense',
    'payroll',
    'debit',
    'payroll_benefits_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6120',
    'مساهمات صاحب العمل',
    'expense',
    'payroll',
    'debit',
    'employer_contribution_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6200',
    'مصاريف تشغيلية عامة',
    'expense',
    'operating_expense',
    'debit',
    'operating_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6300',
    'مصروف الإهلاك',
    'expense',
    'depreciation',
    'debit',
    'depreciation_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6400',
    'فروقات وتسويات المخزون',
    'expense',
    'inventory_adjustments',
    'debit',
    'inventory_adjustment_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;

  -- حسابات بتطلبها القيود التلقائية. بدونها بيفشل القبض والدفع وفواتير البيع والشراء.
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    v.code,
    v.name,
    v.account_type,
    v.system_key,
    v.normal_balance,
    v.system_key,
    true,
    true
  from (
    values
      ('1600', '1000', 'دفعات مقدمة للموردين', 'asset', 'debit', 'supplier_advances'),
      ('2400', '2000', 'قروض الشركاء', 'liability', 'credit', 'partner_loans'),
      ('2500', '2000', 'دفعات مقدمة من العملاء', 'liability', 'credit', 'customer_advances'),
      ('2600', '2000', 'بضاعة مستلمة بانتظار الفاتورة', 'liability', 'credit', 'inventory_clearing'),
      ('3400', '3000', 'أرباح موزعة مستحقة', 'equity', 'debit', 'profit_distributions'),
      ('3500', '3000', 'أرصدة افتتاحية', 'equity', 'credit', 'opening_balance_equity'),
      ('4300', '4000', 'خصومات المبيعات', 'revenue', 'debit', 'sales_discounts'),
      ('5200', '5000', 'فروقات أسعار الشراء', 'expense', 'debit', 'purchase_variance')
  ) as v(code, parent_code, name, account_type, normal_balance, system_key)
  join public.finance_accounts p
    on p.company_id = target_company
   and p.code = v.parent_code
  on conflict do nothing;

end;
$function$;

create or replace function public.finance_rate_to_base(target_company uuid, target_currency text, target_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base text;
  v_currency text;
  v_rate numeric(24,10);
  v_effective_date date;
begin
  select upper(trim(default_currency))
  into v_base
  from public.companies
  where id = target_company;

  if v_base is null then
    raise exception 'Company not found';
  end if;

  v_currency :=
    upper(
      trim(
        coalesce(
          target_currency,
          v_base
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid currency';
  end if;

  if v_currency = v_base then
    return 1;
  end if;

  v_effective_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone 'Asia/Damascus'
      )::date
    );

  select rate_to_base
  into v_rate
  from public.finance_exchange_rates
  where company_id = target_company
    and upper(currency) = v_currency
    and rate_date <= v_effective_date
  order by rate_date desc
  limit 1;

  if v_rate is null then
    raise exception
      'Missing exchange rate for % on %',
      v_currency,
      v_effective_date;
  end if;

  return v_rate;
end;
$function$;

create or replace function public.finance_to_base(target_company uuid, target_currency text, target_amount numeric, target_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- تحويل مبلغ لعملة الشركة للتقارير: آخر سعر لحد التاريخ، وإذا ما في، أقدم سعر مسجّل.
  -- ما بترمي خطأ متل finance_rate_to_base، فالتقرير ما بيوقف إذا ناقص سعر.
  select target_amount * coalesce(
    case
      when upper(target_currency) = (
        select upper(c.default_currency) from public.companies c where c.id = target_company
      ) then 1::numeric
    end,
    (
      select r.rate_to_base
      from public.finance_exchange_rates r
      where r.company_id = target_company
        and upper(r.currency) = upper(target_currency)
        and r.rate_date <= coalesce(target_date, current_date)
      order by r.rate_date desc
      limit 1
    ),
    (
      select r.rate_to_base
      from public.finance_exchange_rates r
      where r.company_id = target_company
        and upper(r.currency) = upper(target_currency)
      order by r.rate_date
      limit 1
    )
  )
$function$;
create or replace function public.finance_system_account(target_company uuid, target_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  select id
  into v_id
  from public.finance_accounts
  where company_id = target_company
    and system_key = target_key
    and active = true
    and allow_posting = true
  limit 1;

  if v_id is null then
    raise exception
      'Missing system account: %',
      target_key;
  end if;

  return v_id;
end;
$function$;

create or replace function public.next_journal_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'journal_entry',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id =
        target_company
    and document_type =
        'journal_entry'
    and sequence_year =
        v_year
  for update;

  update public.document_sequences
  set next_value =
      next_value + 1
  where company_id =
        target_company
    and document_type =
        'journal_entry'
    and sequence_year =
        v_year;

  return
    'JE-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.payment_currency_quote(target_company uuid, target_invoice_currency text, target_payment_currency text, target_invoice_amount numeric, target_payment_date date)
 RETURNS TABLE(invoice_currency text, payment_currency text, invoice_amount numeric, payment_amount numeric, payment_rate_to_base numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base text;
  v_invoice_currency text;
  v_payment_currency text;
  v_rate numeric(24,10);
begin
  if not public.has_any_permission(
    target_company,
    array[
      'payments.sales_view',
      'payments.sales_create',
      'payments.supplier_view',
      'payments.supplier_create',
      'finance.accounts_view'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if target_invoice_amount is null
     or target_invoice_amount <= 0
  then
    raise exception
      'Invalid amount';
  end if;

  select upper(default_currency)
  into v_base
  from public.companies
  where id =
        target_company;

  if v_base is null then
    raise exception
      'Company not found';
  end if;

  v_invoice_currency :=
    upper(
      trim(
        target_invoice_currency
      )
    );

  v_payment_currency :=
    upper(
      trim(
        target_payment_currency
      )
    );

  if v_invoice_currency =
     v_payment_currency
  then
    return query
    select
      v_invoice_currency,
      v_payment_currency,
      round(
        target_invoice_amount,
        2
      ),
      round(
        target_invoice_amount,
        2
      ),
      1::numeric;

    return;
  end if;

  -- Current professional rule:
  -- cross-currency settlement is allowed when the debt
  -- itself is in the company's base currency.
  if v_invoice_currency <>
     v_base
  then
    raise exception
      'Cross-currency settlement currently requires invoice currency to be company base currency';
  end if;

  v_rate :=
    public.finance_rate_to_base(
      target_company,
      v_payment_currency,
      coalesce(
        target_payment_date,
        current_date
      )
    );

  return query
  select
    v_invoice_currency,
    v_payment_currency,
    round(
      target_invoice_amount,
      2
    ),
    round(
      target_invoice_amount /
      v_rate,
      2
    ),
    v_rate;
end;
$function$;

create or replace function public.post_manual_journal_entry(target_company uuid, target_date date, target_description text, target_currency text, target_exchange_rate numeric, lines_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_entry uuid;
  v_number text;

  v_base_currency text;
  v_currency text;
  v_rate numeric(20,8);
  v_business_date date;

  v_line jsonb;
  v_account uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);

  v_total_debit numeric(18,2) := 0;
  v_total_credit numeric(18,2) := 0;

  v_base_debit numeric(18,2);
  v_base_credit numeric(18,2);

  v_party_type text;
  v_party_id uuid;
  v_memo text;
begin
  if not public.has_permission(
    target_company,
    'finance.manual_journal'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_description),
       ''
     ) is null
  then
    raise exception
      'Description is required';
  end if;

  if lines_payload is null
     or jsonb_typeof(
          lines_payload
        ) <> 'array'
     or jsonb_array_length(
          lines_payload
        ) < 2
  then
    raise exception
      'Journal needs at least two lines';
  end if;

  v_business_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone
        'Asia/Damascus'
      )::date
    );

  perform
    public.assert_finance_period_open(
      target_company,
      v_business_date
    );

  select
    upper(default_currency)
  into
    v_base_currency
  from public.companies
  where id =
        target_company;

  if v_base_currency is null then
    raise exception
      'Company not found';
  end if;

  v_currency :=
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        v_base_currency
      )
    );

  if v_currency =
     v_base_currency
  then
    v_rate := 1;
  else
    -- Never trust a browser-supplied accounting FX rate.
    -- Use the approved company rate snapshot for this date.
    v_rate :=
      public.finance_rate_to_base(
        target_company,
        v_currency,
        v_business_date
      );
  end if;

  -- Validate and total first.
  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    begin
      v_account :=
        (
          v_line->>'account_id'
        )::uuid;

      v_debit :=
        coalesce(
          nullif(
            v_line->>'debit',
            ''
          )::numeric,
          0
        );

      v_credit :=
        coalesce(
          nullif(
            v_line->>'credit',
            ''
          )::numeric,
          0
        );
    exception
      when others then
        raise exception
          'Invalid journal line';
    end;

    if not exists (
      select 1
      from public.finance_accounts a
      where a.id =
            v_account
        and a.company_id =
            target_company
        and a.active = true
        and a.allow_posting = true
    ) then
      raise exception
        'Invalid posting account';
    end if;

    if v_debit < 0
       or v_credit < 0
       or (
         v_debit = 0
         and v_credit = 0
       )
       or (
         v_debit > 0
         and v_credit > 0
       )
    then
      raise exception
        'Invalid debit or credit';
    end if;

    v_total_debit :=
      v_total_debit +
      v_debit;

    v_total_credit :=
      v_total_credit +
      v_credit;
  end loop;

  if round(
       v_total_debit,
       2
     ) <>
     round(
       v_total_credit,
       2
     )
  then
    raise exception
      'Journal entry is not balanced';
  end if;

  v_number :=
    public.next_journal_number(
      target_company,
      v_business_date
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    posted_at
  )
  values(
    target_company,
    v_number,
    v_business_date,
    trim(
      target_description
    ),
    'posted',
    v_currency,
    v_rate,
    'manual',
    now()
  )
  returning id
  into v_entry;

  -- Manual entries use their own id as immutable source identity.
  -- This lets the generic reversal engine reverse them safely.
  update public.journal_entries
  set source_id =
      v_entry
  where id =
        v_entry;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    v_account :=
      (
        v_line->>'account_id'
      )::uuid;

    v_debit :=
      coalesce(
        nullif(
          v_line->>'debit',
          ''
        )::numeric,
        0
      );

    v_credit :=
      coalesce(
        nullif(
          v_line->>'credit',
          ''
        )::numeric,
        0
      );

    v_base_debit :=
      round(
        v_debit *
        v_rate,
        2
      );

    v_base_credit :=
      round(
        v_credit *
        v_rate,
        2
      );

    v_party_type :=
      nullif(
        trim(
          v_line->>'party_type'
        ),
        ''
      );

    v_party_id :=
      nullif(
        v_line->>'party_id',
        ''
      )::uuid;

    v_memo :=
      nullif(
        trim(
          v_line->>'memo'
        ),
        ''
      );

    insert into public.journal_lines(
      company_id,
      journal_entry_id,
      account_id,
      debit,
      credit,
      base_debit,
      base_credit,
      party_type,
      party_id,
      memo
    )
    values(
      target_company,
      v_entry,
      v_account,
      v_debit,
      v_credit,
      v_base_debit,
      v_base_credit,
      v_party_type,
      v_party_id,
      v_memo
    );
  end loop;

  perform
    public.balance_journal_base_rounding(
      v_entry
    );

  return v_entry;
end;
$function$;

create or replace function public.post_system_journal(target_company uuid, target_date date, target_description text, target_currency text, target_rate numeric, target_source_type text, target_source_id uuid, lines_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_existing uuid;
  v_entry uuid;
  v_number text;
  v_currency text;
  v_base_currency text;
  v_rate numeric(24,10);
  v_business_date date;

  v_line jsonb;
  v_account uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);

  v_total_debit numeric(18,2) := 0;
  v_total_credit numeric(18,2) := 0;

  v_party_type text;
  v_party_id uuid;
  v_memo text;
begin
  if target_source_id is not null then
    select id
    into v_existing
    from public.journal_entries
    where company_id =
          target_company
      and source_type =
          target_source_type
      and source_id =
          target_source_id
      and reversed_from_id
          is null
    limit 1;

    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  if lines_payload is null
     or jsonb_typeof(
          lines_payload
        ) <> 'array'
     or jsonb_array_length(
          lines_payload
        ) < 2
  then
    raise exception
      'Automatic journal requires at least two lines';
  end if;

  v_business_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone
        'Asia/Damascus'
      )::date
    );

  perform
    public.assert_finance_period_open(
      target_company,
      v_business_date
    );

  select
    upper(default_currency),
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        default_currency
      )
    )
  into
    v_base_currency,
    v_currency
  from public.companies
  where id =
        target_company;

  if v_currency is null
     or v_base_currency is null
  then
    raise exception
      'Company not found';
  end if;

  if v_currency =
     v_base_currency
  then
    v_rate := 1;
  else

    if target_rate is not null
       and target_rate <= 0
    then
      raise exception
        'Invalid exchange rate';
    end if;

    v_rate :=
      coalesce(
        target_rate,
        public.finance_rate_to_base(
          target_company,
          v_currency,
          v_business_date
        )
      );

  end if;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    begin
      v_account :=
        (
          v_line->>'account_id'
        )::uuid;

      v_debit :=
        coalesce(
          nullif(
            v_line->>'debit',
            ''
          )::numeric,
          0
        );

      v_credit :=
        coalesce(
          nullif(
            v_line->>'credit',
            ''
          )::numeric,
          0
        );
    exception
      when others then
        raise exception
          'Invalid automatic journal line';
    end;

    if not exists(
      select 1
      from public.finance_accounts
      where id = v_account
        and company_id =
            target_company
        and active = true
        and allow_posting = true
    ) then
      raise exception
        'Invalid automatic journal account';
    end if;

    if (
      v_debit <= 0
      and v_credit <= 0
    )
    or (
      v_debit > 0
      and v_credit > 0
    )
    then
      raise exception
        'Invalid automatic debit or credit';
    end if;

    v_total_debit :=
      v_total_debit +
      v_debit;

    v_total_credit :=
      v_total_credit +
      v_credit;
  end loop;

  if round(
       v_total_debit,
       2
     ) <>
     round(
       v_total_credit,
       2
     )
  then
    raise exception
      'Automatic journal is not balanced: debit %, credit %',
      v_total_debit,
      v_total_credit;
  end if;

  v_number :=
    public.next_journal_number(
      target_company,
      v_business_date
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    source_id,
    posted_at
  )
  values(
    target_company,
    v_number,
    v_business_date,
    target_description,
    'posted',
    upper(v_currency),
    v_rate,
    target_source_type,
    target_source_id,
    now()
  )
  returning id
  into v_entry;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    v_account :=
      (
        v_line->>'account_id'
      )::uuid;

    v_debit :=
      coalesce(
        nullif(
          v_line->>'debit',
          ''
        )::numeric,
        0
      );

    v_credit :=
      coalesce(
        nullif(
          v_line->>'credit',
          ''
        )::numeric,
        0
      );

    v_party_type :=
      nullif(
        trim(
          v_line->>'party_type'
        ),
        ''
      );

    v_party_id :=
      nullif(
        v_line->>'party_id',
        ''
      )::uuid;

    v_memo :=
      nullif(
        trim(
          v_line->>'memo'
        ),
        ''
      );

    insert into public.journal_lines(
      company_id,
      journal_entry_id,
      account_id,
      debit,
      credit,
      base_debit,
      base_credit,
      party_type,
      party_id,
      memo
    )
    values(
      target_company,
      v_entry,
      v_account,
      round(v_debit,2),
      round(v_credit,2),

      round(
        v_debit *
        v_rate,
        2
      ),

      round(
        v_credit *
        v_rate,
        2
      ),

      v_party_type,
      v_party_id,
      v_memo
    );
  end loop;

  perform
    public.balance_journal_base_rounding(
      v_entry
    );

  return v_entry;
end;
$function$;

create or replace function public.reopen_finance_month(target_company uuid, target_year integer, target_month integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
begin
  if not public.has_permission(
    target_company,
    'finance.month_reopen'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_month < 1
     or target_month > 12
  then
    raise exception 'Invalid month';
  end if;

  v_start :=
    make_date(
      target_year,
      target_month,
      1
    );

  update public.finance_periods
  set
    status = 'open',
    reopened_at = now(),
    reopened_by = auth.uid()
  where company_id =
        target_company
    and period_start =
        v_start
    and status = 'closed';

  if not found then
    raise exception 'Closed financial period not found';
  end if;
end;
$function$;

create or replace function public.reverse_manual_journal_entry(target_company uuid, target_entry uuid, target_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_source_type text;
  v_source_id uuid;
  v_status text;
  v_reversed_from uuid;

  v_reversal uuid;
  v_business_date date;
begin

  if not public.has_permission(
    target_company,
    'finance.manual_journal_reverse'
  ) then
    raise exception
      'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason is required';
  end if;


  select
    source_type,
    source_id,
    status,
    reversed_from_id

  into
    v_source_type,
    v_source_id,
    v_status,
    v_reversed_from

  from public.journal_entries

  where id =
        target_entry

    and company_id =
        target_company

  for update;


  if not found then
    raise exception
      'Journal entry not found';
  end if;


  if v_source_type <>
     'manual'
     or v_reversed_from
        is not null
  then
    raise exception
      'Only original manual journals can be reversed';
  end if;


  -- Compatibility guard for manual entries created before
  -- source_id became the entry's own id.
  if v_source_id is null then

    update public.journal_entries
    set source_id =
        id

    where id =
          target_entry

      and company_id =
          target_company;

  elsif v_source_id <>
        target_entry
  then

    raise exception
      'Invalid manual journal source identity';

  end if;


  -- Idempotent retry: return the existing reversal.
  select id
  into v_reversal

  from public.journal_entries

  where reversed_from_id =
        target_entry

  limit 1;


  if v_reversal is not null then
    return v_reversal;
  end if;


  v_business_date :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;


  -- reverse_system_journal itself verifies that the reversal
  -- date is inside an open financial period.
  v_reversal :=
    public.reverse_system_journal(
      target_company,
      'manual',
      target_entry,
      v_business_date,
      'عكس قيد يدوي: ' ||
      trim(target_reason)
    );


  if v_reversal is null then
    raise exception
      'Manual journal reversal failed';
  end if;


  return v_reversal;
end;
$function$;

create or replace function public.reverse_system_journal(target_company uuid, target_source_type text, target_source_id uuid, target_date date, target_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_original public.journal_entries%rowtype;
  v_reversal uuid;
  v_number text;
begin
  select *
  into v_original
  from public.journal_entries
  where company_id =
        target_company
    and source_type =
        target_source_type
    and source_id =
        target_source_id
    and reversed_from_id
        is null
  limit 1
  for update;

  if v_original.id is null then
    return null;
  end if;

  select id
  into v_reversal
  from public.journal_entries
  where reversed_from_id =
        v_original.id
  limit 1;

  if v_reversal is not null then
    return v_reversal;
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_number :=
    public.next_journal_number(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    source_id,
    reversed_from_id,
    posted_at
  )
  values(
    target_company,
    v_number,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      nullif(
        trim(target_description),
        ''
      ),
      'عكس ' ||
      v_original.description
    ),
    'posted',
    v_original.currency,
    v_original.exchange_rate_to_base,
    'reversal',
    v_original.id,
    v_original.id,
    now()
  )
  returning id
  into v_reversal;

  insert into public.journal_lines(
    company_id,
    journal_entry_id,
    account_id,
    debit,
    credit,
    base_debit,
    base_credit,
    party_type,
    party_id,
    memo
  )
  select
    company_id,
    v_reversal,
    account_id,
    credit,
    debit,
    base_credit,
    base_debit,
    party_type,
    party_id,
    coalesce(
      memo,
      'عكس القيد'
    )
  from public.journal_lines
  where journal_entry_id =
        v_original.id;

  update public.journal_entries
  set status = 'reversed'
  where id =
        v_original.id;

  return v_reversal;
end;
$function$;

create or replace function public.save_finance_account(target_company uuid, target_account uuid, target_parent uuid, target_code text, target_name text, target_type text, target_group text, target_normal_balance text, target_allow_posting boolean, target_active boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;

  v_is_system boolean;
  v_old_type text;
  v_old_group text;
  v_old_normal_balance text;
  v_old_allow_posting boolean;

  v_target_group text;
begin

  if not public.has_permission(
    target_company,
    'finance.accounts_write'
  ) then
    raise exception
      'Not allowed';
  end if;


  if nullif(
       trim(target_code),
       ''
     ) is null
  then
    raise exception
      'Account code is required';
  end if;


  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Account name is required';
  end if;


  if target_type not in (
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense'
  ) then
    raise exception
      'Invalid account type';
  end if;


  if target_normal_balance not in (
    'debit',
    'credit'
  ) then
    raise exception
      'Invalid normal balance';
  end if;


  v_target_group :=
    nullif(
      trim(target_group),
      ''
    );


  -- Parent must belong to this company.
  if target_parent is not null
     and not exists (
       select 1
       from public.finance_accounts
       where id =
             target_parent
         and company_id =
             target_company
     )
  then
    raise exception
      'Invalid parent account';
  end if;


  if target_account is null then

    insert into public.finance_accounts(
      company_id,
      parent_id,
      code,
      name,
      account_type,
      account_group,
      normal_balance,
      allow_posting,
      is_system,
      active
    )
    values(
      target_company,
      target_parent,
      trim(target_code),
      trim(target_name),
      target_type,
      v_target_group,
      target_normal_balance,
      coalesce(
        target_allow_posting,
        true
      ),
      false,
      coalesce(
        target_active,
        true
      )
    )
    returning id
    into v_id;


  else

    -- Lock the account while validating structural changes.
    select
      is_system,
      account_type,
      account_group,
      normal_balance,
      allow_posting
    into
      v_is_system,
      v_old_type,
      v_old_group,
      v_old_normal_balance,
      v_old_allow_posting
    from public.finance_accounts
    where id =
          target_account
      and company_id =
          target_company
    for update;


    if not found then
      raise exception
        'Account not found';
    end if;


    if v_is_system then
      raise exception
        'System account cannot be structurally modified';
    end if;


    if target_parent =
       target_account
    then
      raise exception
        'Account cannot be its own parent';
    end if;


    -- Prevent A -> B -> C -> A style cycles.
    if target_parent is not null
       and exists (
         with recursive descendants(id)
         as (
           select
             a.id
           from public.finance_accounts a
           where a.company_id =
                 target_company
             and a.parent_id =
                 target_account

           union

           select
             a.id
           from public.finance_accounts a

           join descendants d
             on a.parent_id =
                d.id

           where a.company_id =
                 target_company
         )

         select 1
         from descendants
         where id =
               target_parent
       )
    then
      raise exception
        'Account hierarchy cycle is not allowed';
    end if;


    -- Once accounting history exists, classification must remain
    -- immutable. Changing it would rewrite historical reports.
    if exists (
         select 1
         from public.journal_lines jl
         where jl.company_id =
               target_company
           and jl.account_id =
               target_account
       )
       and (
         target_type
           is distinct from
           v_old_type

         or v_target_group
           is distinct from
           v_old_group

         or target_normal_balance
           is distinct from
           v_old_normal_balance

         or coalesce(
              target_allow_posting,
              true
            )
            is distinct from
            v_old_allow_posting
       )
    then
      raise exception
        'Posted account classification cannot be changed';
    end if;


    update public.finance_accounts
    set
      parent_id =
        target_parent,

      code =
        trim(target_code),

      name =
        trim(target_name),

      account_type =
        target_type,

      account_group =
        v_target_group,

      normal_balance =
        target_normal_balance,

      allow_posting =
        coalesce(
          target_allow_posting,
          true
        ),

      active =
        coalesce(
          target_active,
          true
        )

    where id =
          target_account

      and company_id =
          target_company

    returning id
    into v_id;

  end if;


  return v_id;
end;
$function$;

create or replace function public.save_finance_exchange_rate(target_company uuid, target_currency text, target_date date, target_rate numeric, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_base_currency text;
  v_currency text;
  v_business_date date;
  v_rate_date date;
begin
  if not public.has_permission(
    target_company,
    'finance.accounts_write'
  ) then
    raise exception 'Not allowed';
  end if;

  select upper(trim(default_currency))
  into v_base_currency
  from public.companies
  where id = target_company;

  if v_base_currency is null then
    raise exception 'Company not found';
  end if;

  v_currency :=
    upper(
      trim(
        coalesce(
          target_currency,
          ''
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid currency';
  end if;

  if v_currency = v_base_currency then
    raise exception 'Base currency does not need exchange rate';
  end if;

  if target_rate is null
     or target_rate <= 0
  then
    raise exception 'Invalid exchange rate';
  end if;

  v_business_date :=
    (
      now()
      at time zone 'Asia/Damascus'
    )::date;

  v_rate_date :=
    coalesce(
      target_date,
      v_business_date
    );

  if v_rate_date > v_business_date then
    raise exception 'Future exchange rate date is not allowed';
  end if;

  insert into public.finance_exchange_rates(
    company_id,
    currency,
    rate_date,
    rate_to_base,
    notes
  )
  values(
    target_company,
    v_currency,
    v_rate_date,
    target_rate,
    nullif(
      trim(target_notes),
      ''
    )
  )
  on conflict(
    company_id,
    currency,
    rate_date
  )
  do update set
    rate_to_base =
      excluded.rate_to_base,

    notes =
      excluded.notes

  returning id
  into v_id;

  return v_id;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.finance_general_ledger with (security_invoker=true) as
 select je.company_id,
    je.id as journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.status,
    je.currency,
    je.exchange_rate_to_base,
    je.source_type,
    je.source_id,
    jl.id as journal_line_id,
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.account_type,
    a.account_group,
    jl.debit,
    jl.credit,
    jl.base_debit,
    jl.base_credit,
    jl.party_type,
    jl.party_id,
    jl.memo,
    je.created_at
   from public.journal_entries je
     join public.journal_lines jl on jl.journal_entry_id = je.id
     join public.finance_accounts a on a.id = jl.account_id;

create view public.finance_trial_balance with (security_invoker=true) as
 select a.company_id,
    a.id as account_id,
    a.code,
    a.name,
    a.account_type,
    a.account_group,
    a.normal_balance,
    coalesce(sum(jl.base_debit), 0::numeric)::numeric(18,2) as debit,
    coalesce(sum(jl.base_credit), 0::numeric)::numeric(18,2) as credit,
    (coalesce(sum(jl.base_debit), 0::numeric) - coalesce(sum(jl.base_credit), 0::numeric))::numeric(18,2) as balance
   from public.finance_accounts a
     left join public.journal_lines jl on jl.account_id = a.id
     left join public.journal_entries je on je.id = jl.journal_entry_id
  where a.allow_posting = true
  group by a.company_id, a.id, a.code, a.name, a.account_type, a.account_group, a.normal_balance;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger company_default_chart after insert on public.companies for each row execute function public.company_default_chart_trigger();

create trigger audit_finance_accounts after insert or delete or update on public.finance_accounts for each row execute function public.write_audit_log();

create trigger finance_accounts_updated_at before update on public.finance_accounts for each row execute function public.set_updated_at();

create trigger audit_finance_exchange_rates after insert or delete or update on public.finance_exchange_rates for each row execute function public.write_audit_log();

create trigger finance_exchange_rates_updated_at before update on public.finance_exchange_rates for each row execute function public.set_updated_at();

create trigger audit_journal_entries after insert or update on public.journal_entries for each row execute function public.write_audit_log();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.finance_accounts enable row level security;
alter table public.finance_periods enable row level security;
alter table public.finance_exchange_rates enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
create policy finance_accounts_read on public.finance_accounts
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy finance_exchange_rates_read on public.finance_exchange_rates
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy finance_periods_read on public.finance_periods
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.accounts_view'::text, 'reports.finance'::text, 'finance.month_close'::text, 'finance.month_reopen'::text]));
create policy journal_entries_read on public.journal_entries
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy journal_lines_read on public.journal_lines
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.finance_accounts from authenticated;
revoke insert, update, delete on public.finance_periods from authenticated;
revoke insert, update, delete on public.finance_exchange_rates from authenticated;
revoke insert, update, delete on public.journal_entries from authenticated;
revoke insert, update, delete on public.journal_lines from authenticated;
revoke execute on function public.assert_finance_period_open(uuid,date) from authenticated;
revoke execute on function public.balance_journal_base_rounding(uuid) from authenticated;
revoke execute on function public.ensure_default_chart_of_accounts(uuid) from authenticated;
revoke execute on function public.finance_rate_to_base(uuid,text,date) from authenticated;
revoke execute on function public.finance_system_account(uuid,text) from authenticated;
revoke execute on function public.finance_to_base(uuid,text,numeric,date) from authenticated;
revoke execute on function public.next_journal_number(uuid,date) from authenticated;
revoke execute on function public.post_system_journal(uuid,date,text,text,numeric,text,uuid,jsonb) from authenticated;
revoke execute on function public.reverse_system_journal(uuid,text,uuid,date,text) from authenticated;

-- ======================================================================
-- الصناديق
-- الصناديق، المصاريف، حركات المصاري
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.cashboxes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text default 'الصندوق الرئيسي'::text not null,
  currency text default 'USD'::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create unique index cashboxes_company_name_unique on public.cashboxes using btree (company_id, name);

create table public.cashbox_gl_accounts (
  cashbox_id uuid primary key references public.cashboxes(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  account_id uuid not null references public.finance_accounts(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint cashbox_gl_accounts_account_id_key unique (account_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid references public.cashboxes(id) on delete set null,
  category text not null,
  amount numeric(14,2) not null,
  notes text,
  occurred_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint expenses_amount_check check ((amount > (0)::numeric))
);
create index expenses_company_idx on public.expenses using btree (company_id, occurred_at desc);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  direction text not null,
  type text not null,
  amount numeric(14,2) not null,
  order_id uuid,
  trader_id uuid references public.traders(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  expense_id uuid references public.expenses(id) on delete set null,
  supplier_payment_id uuid,
  customer_payment_id uuid,
  notes text,
  occurred_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  employee_id uuid,
  payroll_payment_id uuid,
  partner_transaction_id uuid,
  constraint cash_transactions_amount_check check ((amount > (0)::numeric)),
  constraint cash_transactions_direction_check check ((direction = any (array['in'::text, 'out'::text]))),
  constraint cash_transactions_type_check check ((type = any (array['sale_receipt'::text, 'supplier_payment'::text, 'expense'::text, 'partner_deposit'::text, 'partner_withdrawal'::text, 'adjustment_in'::text, 'adjustment_out'::text, 'customer_payment_reversal'::text, 'supplier_payment_reversal'::text, 'payroll_payment'::text, 'employee_advance'::text, 'employee_loan'::text, 'partner_distribution'::text, 'asset_purchase'::text])))
);
create index cash_transactions_company_idx on public.cash_transactions using btree (company_id, occurred_at desc);
create index cash_transactions_customer_payment_idx on public.cash_transactions using btree (customer_payment_id) where (customer_payment_id is not null);
create unique index cash_transactions_customer_payment_type_unique on public.cash_transactions using btree (customer_payment_id, type) where ((customer_payment_id is not null) and (type = any (array['sale_receipt'::text, 'adjustment_out'::text])));
create unique index cash_transactions_partner_transaction_unique on public.cash_transactions using btree (partner_transaction_id) where (partner_transaction_id is not null);
create unique index cash_transactions_payroll_payment_unique on public.cash_transactions using btree (payroll_payment_id, type) where ((payroll_payment_id is not null) and (type = 'payroll_payment'::text));
create index cash_transactions_supplier_payment_idx on public.cash_transactions using btree (supplier_payment_id) where (supplier_payment_id is not null);
create unique index cash_transactions_supplier_payment_type_unique on public.cash_transactions using btree (supplier_payment_id, type) where ((supplier_payment_id is not null) and (type = any (array['supplier_payment'::text, 'adjustment_in'::text])));
create index cash_transactions_trader_idx on public.cash_transactions using btree (trader_id, occurred_at desc) where (trader_id is not null);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.cashbox_gl_account_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.ensure_cashbox_gl_account(
      new.id
    );

  return new;
end;
$function$;

create or replace function public.enforce_cashbox_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.cashbox_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.cashboxes c
    where c.id = new.cashbox_id
      and c.company_id = new.company_id
  ) then
    raise exception 'Cashbox belongs to another company or does not exist';
  end if;

  return new;
end;
$function$;

create or replace function public.ensure_cashbox_gl_account(target_cashbox uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_name text;
  v_account uuid;
  v_parent uuid;
  v_currency text;
  v_code text;
begin
  if exists (
    select 1
    from public.cashbox_gl_accounts
    where cashbox_id =
          target_cashbox
  ) then
    return;
  end if;

  select
    company_id,
    name,
    upper(currency)
  into
    v_company,
    v_name,
    v_currency
  from public.cashboxes
  where id =
        target_cashbox;

  if v_company is null then
    return;
  end if;

  perform
    public.ensure_default_chart_of_accounts(
      v_company
    );

  select a.id
  into v_account
  from public.finance_accounts a
  where a.company_id =
        v_company

    and a.system_key =
        'cash_default'

    and not exists (
      select 1
      from public.cashbox_gl_accounts m
      where m.account_id =
            a.id
    )
  limit 1;

  if v_account is null then

    select id
    into v_parent
    from public.finance_accounts
    where company_id =
          v_company
      and code = '1100'
    limit 1;

    -- رقم مرتب تحت "الصندوق والبنوك": 1120، 1130، ...
    perform pg_advisory_xact_lock(hashtext('cashbox_code:' || v_company::text));

    select coalesce(max(code::integer), 1110) + 10
    into v_code
    from public.finance_accounts
    where company_id = v_company
      and code ~ '^11[1-9][0-9]$';

    if v_code::integer > 1199 then
      select coalesce(max(code::integer), 1100) + 1
      into v_code
      from public.finance_accounts
      where company_id = v_company
        and code ~ '^11[0-9][0-9]$';
    end if;

    insert into public.finance_accounts(
      company_id,
      parent_id,
      code,
      name,
      account_type,
      account_group,
      normal_balance,
      allow_posting,
      is_system
    )
    values(
      v_company,
      v_parent,
      v_code,
      coalesce(v_name, 'صندوق') || ' (' || coalesce(v_currency, '') || ')',
      'asset',
      'cash_bank',
      'debit',
      true,
      true
    )
    returning id
    into v_account;

  end if;

  insert into public.cashbox_gl_accounts(
    cashbox_id,
    company_id,
    account_id
  )
  values(
    target_cashbox,
    v_company,
    v_account
  )
  on conflict(cashbox_id)
  do nothing;
end;
$function$;

create or replace function public.finance_cashbox_account(target_company uuid, target_cashbox uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_account uuid;
begin
  if not exists(
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid cashbox';
  end if;

  perform
    public.ensure_cashbox_gl_account(
      target_cashbox
    );

  select account_id
  into v_account
  from public.cashbox_gl_accounts
  where cashbox_id =
        target_cashbox
    and company_id =
        target_company;

  if v_account is null then
    raise exception
      'Cashbox GL account not found';
  end if;

  return v_account;
end;
$function$;

create or replace function public.get_cashbox_balances(target_company uuid)
 RETURNS TABLE(id uuid, name text, currency text, active boolean, balance numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- رصيد كل صندوق لحاله (الملخص فوق بيجمع حسب العملة).
  select
    cb.id,
    cb.name,
    upper(cb.currency),
    cb.active,
    coalesce(
      (
        select sum(case when ct.direction = 'in' then ct.amount else -ct.amount end)
        from public.cash_transactions ct
        where ct.cashbox_id = cb.id
      ),
      0
    )
  from public.cashboxes cb
  where cb.company_id = target_company
    and public.has_any_permission(
      target_company,
      array['finance.cashbox_view', 'finance.cashbox_write', 'finance.expenses_view', 'finance.expenses_write']
    )
  order by cb.active desc, cb.created_at
$function$;

create or replace function public.get_cashbox_summary(target_company uuid, target_date date)
 RETURNS TABLE(currency text, balance numeric, today_in numeric, today_out numeric, month_expense numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'finance.cashbox_view',
      'finance.cashbox_write',
      'finance.expenses_view',
      'finance.expenses_write'
    ]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with currency_list as (
    select distinct upper(cb.currency) as currency
    from public.cashboxes cb
    where cb.company_id = target_company

    union

    select upper(coalesce(c.default_currency,'USD'))
    from public.companies c
    where c.id = target_company
  ),
  transaction_totals as (
    select
      upper(cb.currency) as currency,
      coalesce(
        sum(
          case
            when ct.direction = 'in' then ct.amount
            else -ct.amount
          end
        ),
        0
      ) as balance,
      coalesce(
        sum(
          case
            when ct.direction = 'in'
             and (ct.occurred_at at time zone 'Asia/Damascus')::date = target_date
              then ct.amount
            else 0
          end
        ),
        0
      ) as today_in,
      coalesce(
        sum(
          case
            when ct.direction = 'out'
             and (ct.occurred_at at time zone 'Asia/Damascus')::date = target_date
              then ct.amount
            else 0
          end
        ),
        0
      ) as today_out
    from public.cash_transactions ct
    join public.cashboxes cb
      on cb.id = ct.cashbox_id
     and cb.company_id = target_company
    where ct.company_id = target_company
    group by upper(cb.currency)
  ),
  expense_totals as (
    select
      upper(cb.currency) as currency,
      coalesce(sum(e.amount),0) as month_expense
    from public.expenses e
    join public.cashboxes cb
      on cb.id = e.cashbox_id
     and cb.company_id = target_company
    where e.company_id = target_company
      and (e.occurred_at at time zone 'Asia/Damascus')::date >=
          date_trunc('month',target_date::timestamp)::date
      and (e.occurred_at at time zone 'Asia/Damascus')::date <
          (
            date_trunc('month',target_date::timestamp)
            + interval '1 month'
          )::date
    group by upper(cb.currency)
  )
  select
    cl.currency,
    coalesce(tt.balance,0)::numeric,
    coalesce(tt.today_in,0)::numeric,
    coalesce(tt.today_out,0)::numeric,
    coalesce(et.month_expense,0)::numeric
  from currency_list cl
  left join transaction_totals tt
    on tt.currency = cl.currency
  left join expense_totals et
    on et.currency = cl.currency
  order by cl.currency;
end;
$function$;

create or replace function public.handle_company_default_cashbox()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.cashboxes(company_id,name,currency)
  values(new.id,'الصندوق الرئيسي',coalesce(new.default_currency,'USD'))
  on conflict do nothing;
  return new;
end;
$function$;

create or replace function public.protect_cashbox_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.currency := upper(trim(coalesce(new.currency,'')));

  if new.currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid cashbox currency';
  end if;

  if tg_op = 'UPDATE'
     and old.active = true
     and new.active = false
     and coalesce((
       select sum(case when ct.direction = 'in' then ct.amount else -ct.amount end)
       from public.cash_transactions ct
       where ct.cashbox_id = old.id
     ), 0) <> 0
  then
    -- ما منوقّف صندوق فيه مصاري، مشان رصيده ما يختفي من الشاشات.
    raise exception 'Cashbox still has a balance';
  end if;

  if tg_op = 'UPDATE' then
    if new.company_id is distinct from old.company_id then
      raise exception 'Cashbox company cannot be changed';
    end if;

    if new.currency is distinct from old.currency
       and (
         exists (
           select 1
           from public.cash_transactions ct
           where ct.cashbox_id = old.id
         )
         or exists (
           select 1
           from public.expenses e
           where e.cashbox_id = old.id
         )
       )
    then
      raise exception 'Cashbox currency cannot change after financial activity';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.record_cash_movement(target_company uuid, target_cashbox uuid, movement_type text, movement_amount numeric, movement_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cashbox uuid;
  v_id uuid;
  v_direction text;
  v_now timestamptz := now();
begin
  if not public.has_permission(
    target_company,
    'finance.cashbox_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_cashbox is null then
    raise exception 'Cashbox required';
  end if;

  if movement_amount is null or movement_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if movement_type not in (
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out'
  ) then
    raise exception 'Invalid movement';
  end if;

  v_direction :=
    case
      when movement_type in (
        'partner_deposit',
        'adjustment_in'
      ) then 'in'
      else 'out'
    end;

  select id
  into v_cashbox
  from public.cashboxes
  where id = target_cashbox
    and company_id = target_company
    and active = true
  for update;

  if v_cashbox is null then
    raise exception 'Invalid or inactive cashbox';
  end if;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    v_direction,
    movement_type,
    round(movement_amount,2),
    nullif(trim(coalesce(movement_notes,'')),''),
    v_now
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.record_expense(target_company uuid, target_cashbox uuid, expense_category text, expense_amount numeric, expense_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cashbox uuid;
  v_expense uuid;
  v_now timestamptz := now();
begin
  if not public.has_permission(
    target_company,
    'finance.expenses_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_cashbox is null then
    raise exception 'Cashbox required';
  end if;

  if expense_amount is null or expense_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if nullif(trim(coalesce(expense_category,'')),'') is null then
    raise exception 'Category required';
  end if;

  select id
  into v_cashbox
  from public.cashboxes
  where id = target_cashbox
    and company_id = target_company
    and active = true
  for update;

  if v_cashbox is null then
    raise exception 'Invalid or inactive cashbox';
  end if;

  insert into public.expenses(
    company_id,
    cashbox_id,
    category,
    amount,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    trim(expense_category),
    round(expense_amount,2),
    nullif(trim(coalesce(expense_notes,'')),''),
    v_now
  )
  returning id into v_expense;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    expense_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'expense',
    round(expense_amount,2),
    v_expense,
    nullif(trim(coalesce(expense_notes,'')),''),
    v_now
  );

  return v_expense;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_cash_transactions after insert or delete or update on public.cash_transactions for each row execute function public.write_audit_log();

create trigger cash_transactions_cashbox_company_guard before insert or update of company_id, cashbox_id on public.cash_transactions for each row execute function public.enforce_cashbox_company();

create trigger cashbox_gl_account_after_insert after insert on public.cashboxes for each row execute function public.cashbox_gl_account_trigger();

create trigger protect_cashbox_identity_trigger before insert or update on public.cashboxes for each row execute function public.protect_cashbox_identity();

create trigger on_company_default_cashbox after insert on public.companies for each row execute function public.handle_company_default_cashbox();

create trigger audit_expenses after insert or delete or update on public.expenses for each row execute function public.write_audit_log();

create trigger expenses_cashbox_company_guard before insert or update of company_id, cashbox_id on public.expenses for each row execute function public.enforce_cashbox_company();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.cashboxes enable row level security;
alter table public.cashbox_gl_accounts enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_transactions enable row level security;
create policy cash_transactions_read on public.cash_transactions
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.cashbox_view'::text, 'finance.accounts_view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'payments.supplier_view'::text, 'payments.supplier_create'::text, 'reports.finance'::text]));
create policy cashbox_gl_accounts_read on public.cashbox_gl_accounts
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.cashbox_view'::text) or public.has_permission(company_id, 'finance.accounts_view'::text)));
create policy cashboxes_read on public.cashboxes
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.cashbox_view'::text, 'finance.accounts_view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'payments.supplier_view'::text, 'payments.supplier_create'::text, 'reports.finance'::text]));
create policy cashboxes_write on public.cashboxes
  for all to authenticated
  using (public.has_permission(company_id, 'finance.cashbox_write'::text))
  with check (public.has_permission(company_id, 'finance.cashbox_write'::text));
create policy expenses_read on public.expenses
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.expenses_view'::text, 'reports.finance'::text, 'reports.profit'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.cashbox_gl_accounts from authenticated;
revoke insert, update, delete on public.expenses from authenticated;
revoke insert, update, delete on public.cash_transactions from authenticated;
revoke execute on function public.ensure_cashbox_gl_account(uuid) from authenticated;
revoke execute on function public.finance_cashbox_account(uuid,uuid) from authenticated;

-- ======================================================================
-- المخزون
-- المستودعات، الأرصدة، الحركات، التحويلات، الجرد
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text,
  name text not null,
  address text,
  is_default boolean default false not null,
  active boolean default true not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint warehouses_company_id_name_key unique (company_id, name)
);
create index warehouses_company_idx on public.warehouses using btree (company_id, active, name);
create unique index warehouses_one_default_per_company on public.warehouses using btree (company_id) where ((is_default = true) and (active = true));

create table public.inventory_stock (
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  on_hand numeric(18,3) default 0 not null,
  average_cost numeric(18,4) default 0 not null,
  updated_at timestamp with time zone default now() not null,
  constraint inventory_stock_pkey primary key (warehouse_id, product_id),
  constraint inventory_stock_average_cost_check check ((average_cost >= (0)::numeric)),
  constraint inventory_stock_on_hand_check check ((on_hand >= (0)::numeric))
);
create index inventory_stock_company_product_idx on public.inventory_stock using btree (company_id, product_id);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null,
  quantity numeric(18,3) not null,
  unit_cost numeric(18,4),
  source_table text,
  source_id uuid,
  source_line_id uuid,
  reference_number text,
  notes text,
  occurred_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint inventory_movements_movement_type_check check ((movement_type = any (array['opening'::text, 'purchase_receipt'::text, 'sales_delivery'::text, 'sales_return'::text, 'purchase_return'::text, 'adjustment_in'::text, 'adjustment_out'::text, 'transfer_in'::text, 'transfer_out'::text]))),
  constraint inventory_movements_quantity_check check ((quantity <> (0)::numeric)),
  constraint inventory_movements_unit_cost_check check (((unit_cost is null) or (unit_cost >= (0)::numeric)))
);
create index inventory_movements_company_date_idx on public.inventory_movements using btree (company_id, occurred_at desc);
create unique index inventory_movements_source_unique on public.inventory_movements using btree (source_table, source_line_id, movement_type) where ((source_table is not null) and (source_line_id is not null));
create index inventory_movements_stock_idx on public.inventory_movements using btree (warehouse_id, product_id, occurred_at desc);

create table public.inventory_transfers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  transfer_number text not null,
  source_warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  destination_warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  status text default 'posted'::text not null,
  transfer_date date default current_date not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  constraint inventory_transfers_company_id_transfer_number_key unique (company_id, transfer_number),
  constraint inventory_transfers_check check ((source_warehouse_id <> destination_warehouse_id)),
  constraint inventory_transfers_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index inventory_transfers_company_date_idx on public.inventory_transfers using btree (company_id, transfer_date desc, created_at desc);
create index inventory_transfers_company_status_idx on public.inventory_transfers using btree (company_id, status, transfer_date desc);

create table public.inventory_transfer_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  transfer_id uuid not null references public.inventory_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  unit_cost numeric(18,4) not null,
  created_at timestamp with time zone default now() not null,
  constraint inventory_transfer_items_transfer_id_product_id_key unique (transfer_id, product_id),
  constraint inventory_transfer_items_quantity_check check ((quantity > (0)::numeric)),
  constraint inventory_transfer_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index inventory_transfer_items_transfer_idx on public.inventory_transfer_items using btree (transfer_id);

create table public.inventory_counts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  count_number text not null,
  count_date date default current_date not null,
  status text default 'posted'::text not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  constraint inventory_counts_company_id_count_number_key unique (company_id, count_number),
  constraint inventory_counts_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index inventory_counts_company_date_idx on public.inventory_counts using btree (company_id, count_date desc, created_at desc);
create index inventory_counts_company_status_idx on public.inventory_counts using btree (company_id, status, count_date desc);

create table public.inventory_count_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  count_id uuid not null references public.inventory_counts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  system_quantity numeric(18,3) not null,
  counted_quantity numeric(18,3) not null,
  difference_quantity numeric(18,3) not null,
  unit_cost numeric(18,4) not null,
  created_at timestamp with time zone default now() not null,
  constraint inventory_count_items_count_id_product_id_key unique (count_id, product_id),
  constraint inventory_count_items_counted_quantity_check check ((counted_quantity >= (0)::numeric)),
  constraint inventory_count_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index inventory_count_items_count_idx on public.inventory_count_items using btree (count_id);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.can_view_inventory_cost(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    public.has_any_permission(
      target_company,
      array[
        'products.view_cost',
        'suppliers.view_finance',
        'reports.finance',
        'reports.profit'
      ]::text[]
    );
$function$;

create or replace function public.create_default_warehouse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.warehouses(
    company_id,
    code,
    name,
    is_default,
    active
  )
  values(
    new.id,
    'MAIN',
    'المستودع الرئيسي',
    true,
    true
  )
  on conflict do nothing;

  return new;
end;
$function$;

create or replace function public.create_warehouse(target_company uuid, target_name text, target_code text DEFAULT NULL::text, target_address text DEFAULT NULL::text, target_is_default boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_default boolean;
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(trim(target_name),'') is null then
    raise exception 'Warehouse name is required';
  end if;

  v_default :=
    coalesce(
      target_is_default,
      false
    );

  if not exists (
    select 1
    from public.warehouses
    where company_id =
          target_company
      and active = true
  ) then
    v_default := true;
  end if;

  if v_default then
    update public.warehouses
    set is_default = false
    where company_id =
          target_company;
  end if;

  insert into public.warehouses(
    company_id,
    code,
    name,
    address,
    is_default,
    active
  )
  values(
    target_company,
    nullif(trim(target_code),''),
    trim(target_name),
    nullif(trim(target_address),''),
    v_default,
    true
  )
  returning id
  into v_id;

  return v_id;
end;
$function$;

create or replace function public.get_inventory_stats(target_company uuid)
 RETURNS TABLE(reserved_lines bigint, out_of_stock bigint, stock_value numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- أرقام أعلى صفحة المخزون محسوبة جوّا القاعدة، مش بتحميل كل الأسطر
  -- (الـ API بيرجّع 1000 سطر كحد أقصى، فالمجموع كان يطلع ناقص بالشركات الكبيرة).
  -- العرض inventory_summary بيطبّق صلاحية المخزون وبيخفي الكلفة عن اللي ما إلهم.
  select
    count(*) filter (where s.reserved > 0),
    count(*) filter (where s.available <= 0),
    case
      when public.can_view_inventory_cost(target_company)
        then coalesce(sum(s.stock_value), 0)
    end
  from public.inventory_summary s
  where s.company_id = target_company
$function$;
create or replace function public.get_inventory_valuation(target_company uuid)
 RETURNS TABLE(warehouse_id uuid, warehouse_name text, product_id uuid, product_name text, sku text, on_hand numeric, reserved numeric, available numeric, average_cost numeric, stock_value numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'reports.profit',
      'products.view_cost',
      'suppliers.view_finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    w.id,
    w.name,

    p.id,
    p.name,
    p.sku,

    round(
      s.on_hand,
      3
    ),

    round(
      coalesce(
        (
          select
            sum(r.quantity)
          from public.inventory_reservations r
          where r.company_id =
                target_company

            and r.warehouse_id =
                s.warehouse_id

            and r.product_id =
                s.product_id

            and r.status =
                'active'
        ),
        0
      ),
      3
    ),

    round(
      greatest(
        s.on_hand -
        coalesce(
          (
            select
              sum(r.quantity)
            from public.inventory_reservations r
            where r.company_id =
                  target_company

              and r.warehouse_id =
                  s.warehouse_id

              and r.product_id =
                  s.product_id

              and r.status =
                  'active'
          ),
          0
        ),
        0
      ),
      3
    ),

    round(
      s.average_cost,
      4
    ),

    round(
      s.on_hand *
      s.average_cost,
      2
    )

  from public.inventory_stock s

  join public.warehouses w
    on w.id =
       s.warehouse_id

  join public.products p
    on p.id =
       s.product_id

  where s.company_id =
        target_company

  order by
    w.name,
    p.name;
end;
$function$;

create or replace function public.next_inventory_count_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'stock_count',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'stock_count'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'stock_count'
    and sequence_year = v_year;

  return
    'CNT-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.next_inventory_transfer_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'warehouse_transfer',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'warehouse_transfer'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'warehouse_transfer'
    and sequence_year = v_year;

  return
    'TR-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.post_inventory_count(target_company uuid, target_warehouse uuid, target_count_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count uuid;
  v_number text;

  v_item jsonb;

  v_product uuid;
  v_counted numeric(18,3);
  v_supplied_cost numeric(18,4);

  v_system numeric(18,3);
  v_reserved numeric(18,3);
  v_average_cost numeric(18,4);
  v_cost numeric(18,4);
  v_reference_cost numeric(18,4);
  v_can_set_cost boolean;

  v_difference numeric(18,3);

  v_line uuid;
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.warehouses
    where id =
          target_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid warehouse';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception
      'Stock count needs at least one item';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate count product';
  end if;

  v_number :=
    public.next_inventory_count_number(
      target_company,
      coalesce(
        target_count_date,
        current_date
      )
    );

  insert into public.inventory_counts(
    company_id,
    warehouse_id,
    count_number,
    count_date,
    status,
    notes
  )
  values(
    target_company,
    target_warehouse,
    v_number,
    coalesce(
      target_count_date,
      current_date
    ),
    'posted',
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_count;

  for v_item in
    select value
    from jsonb_array_elements(items_payload)
  loop
    begin
      v_product :=
        (v_item->>'product_id')::uuid;

      v_counted :=
        (v_item->>'counted_quantity')::numeric;

      v_supplied_cost :=
        nullif(
          v_item->>'unit_cost',
          ''
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid stock count item';
    end;

    if v_counted is null
       or v_counted < 0
    then
      raise exception
        'Counted quantity cannot be negative';
    end if;

    if not exists (
      select 1
      from public.products
      where id =
            v_product
        and company_id =
            target_company
        and active = true
    ) then
      raise exception
        'Invalid product';
    end if;

    insert into public.inventory_stock(
      company_id,
      warehouse_id,
      product_id,
      on_hand,
      average_cost
    )
    values(
      target_company,
      target_warehouse,
      v_product,
      0,
      0
    )
    on conflict(
      warehouse_id,
      product_id
    )
    do nothing;

    select
      on_hand,
      average_cost
    into
      v_system,
      v_average_cost
    from public.inventory_stock
    where warehouse_id =
          target_warehouse
      and product_id =
          v_product
    for update;

    select
      coalesce(
        sum(quantity),
        0
      )
    into v_reserved
    from public.inventory_reservations
    where company_id =
          target_company
      and warehouse_id =
          target_warehouse
      and product_id =
          v_product
      and status =
          'active';

    if v_counted <
       v_reserved
    then
      raise exception
        'Counted quantity is below reserved stock';
    end if;

    v_difference :=
      round(
        v_counted -
        v_system,
        3
      );

    if v_supplied_cost is not null
       and v_supplied_cost < 0
    then
      raise exception
        'Invalid unit cost';
    end if;

    v_can_set_cost :=
      public.has_any_permission(
        target_company,
        array[
          'products.view_cost',
          'suppliers.view_finance',
          'reports.finance',
          'reports.profit'
        ]::text[]
      );

    -- Existing inventory always keeps its server-side
    -- weighted average. A browser cannot revalue it.
    if coalesce(
         v_system,
         0
       ) > 0
       or coalesce(
         v_average_cost,
         0
       ) > 0
    then

      v_cost :=
        coalesce(
          v_average_cost,
          0
        );

    elsif coalesce(
            v_supplied_cost,
            0
          ) > 0
    then

      if not v_can_set_cost then
        raise exception
          'Not allowed to set inventory cost';
      end if;

      v_cost :=
        round(
          v_supplied_cost,
          4
        );

    else

      select
        sp.purchase_price

      into
        v_reference_cost

      from public.supplier_prices sp

      where sp.company_id =
            target_company

        and sp.product_id =
            v_product

        and sp.available =
            true

      order by
        sp.last_checked_at desc,
        sp.updated_at desc

      limit 1;

      v_cost :=
        round(
          coalesce(
            v_reference_cost,
            0
          ),
          4
        );

    end if;

    if v_difference > 0
       and v_cost <= 0
       and v_system <= 0
    then
      raise exception
        'Unit cost is required for new positive stock';
    end if;

    insert into public.inventory_count_items(
      company_id,
      count_id,
      product_id,
      system_quantity,
      counted_quantity,
      difference_quantity,
      unit_cost
    )
    values(
      target_company,
      v_count,
      v_product,
      v_system,
      v_counted,
      v_difference,
      v_cost
    )
    returning id
    into v_line;

    if v_difference > 0 then
      perform
        public.post_inventory_movement(
          target_company,
          target_warehouse,
          v_product,
          'adjustment_in',
          v_difference,
          v_cost,
          'inventory_counts',
          v_count,
          v_line,
          v_number,
          target_notes,
          now()
        );

      perform
        public.reserve_pending_orders_for_product(
          target_company,
          target_warehouse,
          v_product
        );

    elsif v_difference < 0 then
      perform
        public.post_inventory_movement(
          target_company,
          target_warehouse,
          v_product,
          'adjustment_out',
          v_difference,
          v_average_cost,
          'inventory_counts',
          v_count,
          v_line,
          v_number,
          target_notes,
          now()
        );
    end if;
  end loop;

  return v_count;
end;
$function$;

create or replace function public.post_inventory_movement(target_company uuid, target_warehouse uuid, target_product uuid, target_type text, target_quantity numeric, target_unit_cost numeric DEFAULT NULL::numeric, target_source_table text DEFAULT NULL::text, target_source_id uuid DEFAULT NULL::uuid, target_source_line_id uuid DEFAULT NULL::uuid, target_reference text DEFAULT NULL::text, target_notes text DEFAULT NULL::text, target_occurred_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_stock public.inventory_stock%rowtype;
  v_new_on_hand numeric(18,3);
  v_new_average numeric(18,4);
  v_new_value numeric(24,4);
  v_movement uuid;
  v_existing uuid;
begin
  if not exists (
    select 1
    from public.warehouses w
    where w.id = target_warehouse
      and w.company_id = target_company
      and w.active = true
  ) then
    raise exception 'Invalid warehouse';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = target_product
      and p.company_id = target_company
  ) then
    raise exception 'Invalid product';
  end if;

  if target_quantity is null
     or target_quantity = 0
  then
    raise exception 'Movement quantity cannot be zero';
  end if;

  if target_source_table is not null
     and target_source_line_id is not null
  then
    select id
    into v_existing
    from public.inventory_movements
    where source_table =
          target_source_table
      and source_line_id =
          target_source_line_id
      and movement_type =
          target_type
    limit 1;

    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  insert into public.inventory_stock(
    company_id,
    warehouse_id,
    product_id,
    on_hand,
    average_cost
  )
  values(
    target_company,
    target_warehouse,
    target_product,
    0,
    0
  )
  on conflict(
    warehouse_id,
    product_id
  )
  do nothing;

  select *
  into v_stock
  from public.inventory_stock
  where warehouse_id =
        target_warehouse
    and product_id =
        target_product
  for update;

  v_new_on_hand :=
    round(
      v_stock.on_hand +
      target_quantity,
      3
    );

  if v_new_on_hand < 0 then
    raise exception
      'Insufficient stock';
  end if;

  v_new_average :=
    v_stock.average_cost;

  if target_unit_cost is not null then

    v_new_value :=
      round(
        (
          v_stock.on_hand *
          v_stock.average_cost
        ) +
        (
          target_quantity *
          target_unit_cost
        ),
        4
      );

    if v_new_on_hand = 0 then

      v_new_average := 0;

    elsif v_new_value < -0.01 then

      raise exception
        'Inventory value would become negative';

    else

      v_new_average :=
        round(
          greatest(
            v_new_value,
            0
          ) /
          v_new_on_hand,
          4
        );

    end if;

  elsif v_new_on_hand = 0 then

    v_new_average := 0;

  end if;

  update public.inventory_stock
  set
    on_hand =
      v_new_on_hand,

    average_cost =
      v_new_average,

    updated_at =
      now()

  where warehouse_id =
        target_warehouse

    and product_id =
        target_product;

  insert into public.inventory_movements(
    company_id,
    warehouse_id,
    product_id,
    movement_type,
    quantity,
    unit_cost,
    source_table,
    source_id,
    source_line_id,
    reference_number,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_warehouse,
    target_product,
    target_type,
    target_quantity,
    target_unit_cost,
    target_source_table,
    target_source_id,
    target_source_line_id,
    target_reference,
    target_notes,
    coalesce(
      target_occurred_at,
      now()
    )
  )
  returning id
  into v_movement;

  return v_movement;
end;
$function$;

create or replace function public.post_inventory_transfer(target_company uuid, target_source_warehouse uuid, target_destination_warehouse uuid, target_transfer_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_transfer uuid;
  v_number text;

  v_item jsonb;

  v_product uuid;
  v_quantity numeric(18,3);

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_average_cost numeric(18,4);

  v_line uuid;
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_source_warehouse =
     target_destination_warehouse
  then
    raise exception
      'Source and destination warehouses must be different';
  end if;

  if not exists (
    select 1
    from public.warehouses
    where id =
          target_source_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid source warehouse';
  end if;

  if not exists (
    select 1
    from public.warehouses
    where id =
          target_destination_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid destination warehouse';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception
      'Transfer needs at least one item';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate transfer product';
  end if;

  v_number :=
    public.next_inventory_transfer_number(
      target_company,
      coalesce(
        target_transfer_date,
        current_date
      )
    );

  insert into public.inventory_transfers(
    company_id,
    transfer_number,
    source_warehouse_id,
    destination_warehouse_id,
    status,
    transfer_date,
    notes
  )
  values(
    target_company,
    v_number,
    target_source_warehouse,
    target_destination_warehouse,
    'posted',
    coalesce(
      target_transfer_date,
      current_date
    ),
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_transfer;

  for v_item in
    select value
    from jsonb_array_elements(items_payload)
  loop
    begin
      v_product :=
        (v_item->>'product_id')::uuid;

      v_quantity :=
        (v_item->>'quantity')::numeric;
    exception
      when others then
        raise exception
          'Invalid transfer item';
    end;

    if v_quantity is null
       or v_quantity <= 0
    then
      raise exception
        'Invalid transfer quantity';
    end if;

    select
      s.on_hand,
      s.average_cost
    into
      v_on_hand,
      v_average_cost
    from public.inventory_stock s
    where s.company_id =
          target_company
      and s.warehouse_id =
          target_source_warehouse
      and s.product_id =
          v_product
    for update;

    if v_on_hand is null then
      raise exception
        'Product has no stock in source warehouse';
    end if;

    select
      coalesce(
        sum(ir.quantity),
        0
      )
    into v_reserved
    from public.inventory_reservations ir
    where ir.company_id =
          target_company
      and ir.warehouse_id =
          target_source_warehouse
      and ir.product_id =
          v_product
      and ir.status =
          'active';

    if v_quantity >
       (
         v_on_hand -
         v_reserved
       )
    then
      raise exception
        'Transfer exceeds available stock';
    end if;

    insert into public.inventory_transfer_items(
      company_id,
      transfer_id,
      product_id,
      quantity,
      unit_cost
    )
    values(
      target_company,
      v_transfer,
      v_product,
      v_quantity,
      coalesce(
        v_average_cost,
        0
      )
    )
    returning id
    into v_line;

    perform
      public.post_inventory_movement(
        target_company,
        target_source_warehouse,
        v_product,
        'transfer_out',
        -v_quantity,
        coalesce(
          v_average_cost,
          0
        ),
        'inventory_transfers',
        v_transfer,
        v_line,
        v_number,
        target_notes,
        now()
      );

    perform
      public.post_inventory_movement(
        target_company,
        target_destination_warehouse,
        v_product,
        'transfer_in',
        v_quantity,
        coalesce(
          v_average_cost,
          0
        ),
        'inventory_transfers',
        v_transfer,
        v_line,
        v_number,
        target_notes,
        now()
      );

    perform
      public.reserve_pending_orders_for_product(
        target_company,
        target_destination_warehouse,
        v_product
      );
  end loop;

  return v_transfer;
end;
$function$;

create or replace function public.product_reference_cost(target_company uuid, target_product uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with stock_cost as (
    select
      case
        when coalesce(sum(s.on_hand),0) > 0 then
          sum(s.on_hand * s.average_cost) / nullif(sum(s.on_hand),0)
        else null
      end as cost
    from public.inventory_stock s
    where s.company_id = target_company
      and s.product_id = target_product
      and s.on_hand > 0
  ), supplier_cost as (
    select min(sp.purchase_price) as cost
    from public.supplier_prices sp
    where sp.company_id = target_company
      and sp.product_id = target_product
      and sp.available = true
  )
  select coalesce(
    (select cost from stock_cost),
    (select cost from supplier_cost),
    0
  );
$function$;

create or replace function public.reverse_inventory_count(target_company uuid, target_count uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_warehouse uuid;
  v_number text;

  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;

  select
    status,
    warehouse_id,
    count_number

  into
    v_status,
    v_warehouse,
    v_number

  from public.inventory_counts

  where id =
        target_count

    and company_id =
        target_company

  for update;

  if v_status is null then
    raise exception
      'Inventory count not found';
  end if;

  if v_status = 'reversed' then
    return;
  end if;


  -- ----------------------------------------------------------
  -- Positive original adjustment must still be available
  -- before it can be removed.
  -- ----------------------------------------------------------

  for v_item in
    select
      id,
      product_id,
      difference_quantity,
      unit_cost

    from public.inventory_count_items

    where count_id =
          target_count

      and difference_quantity >
          0

  loop

    select
      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                target_company

            and r.warehouse_id =
                v_warehouse

            and r.product_id =
                v_item.product_id

            and r.status =
                'active'
        ),
        0
      )

    into
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          v_warehouse

      and s.product_id =
          v_item.product_id;

    if
      coalesce(
        v_on_hand,
        0
      ) -
      coalesce(
        v_reserved,
        0
      )
      <
      v_item.difference_quantity
    then
      raise exception
        'Cannot reverse stock count: adjusted stock was already reserved or used';
    end if;

  end loop;


  -- ----------------------------------------------------------
  -- Reverse each original difference.
  -- ----------------------------------------------------------

  for v_item in
    select
      id,
      product_id,
      difference_quantity,
      unit_cost

    from public.inventory_count_items

    where count_id =
          target_count

      and difference_quantity <>
          0

  loop

    if v_item.difference_quantity > 0 then

      perform
        public.post_inventory_movement(
          target_company,
          v_warehouse,
          v_item.product_id,
          'adjustment_out',
          -v_item.difference_quantity,
          v_item.unit_cost,
          'inventory_count_reversals',
          target_count,
          v_item.id,
          v_number || '-REV',
          trim(target_reason),
          now()
        );

    else

      perform
        public.post_inventory_movement(
          target_company,
          v_warehouse,
          v_item.product_id,
          'adjustment_in',
          abs(
            v_item.difference_quantity
          ),
          v_item.unit_cost,
          'inventory_count_reversals',
          target_count,
          v_item.id,
          v_number || '-REV',
          trim(target_reason),
          now()
        );

      perform
        public.reserve_pending_orders_for_product(
          target_company,
          v_warehouse,
          v_item.product_id
        );

    end if;

  end loop;


  update public.inventory_counts
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason)

  where id =
        target_count;
end;
$function$;

create or replace function public.reverse_inventory_transfer(target_company uuid, target_transfer uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_source uuid;
  v_destination uuid;

  v_number text;

  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;

  select
    status,
    source_warehouse_id,
    destination_warehouse_id,
    transfer_number

  into
    v_status,
    v_source,
    v_destination,
    v_number

  from public.inventory_transfers

  where id =
        target_transfer

    and company_id =
        target_company

  for update;

  if v_status is null then
    raise exception
      'Inventory transfer not found';
  end if;

  if v_status = 'reversed' then
    return;
  end if;


  -- Destination must still have available stock.
  for v_item in
    select
      id,
      product_id,
      quantity,
      unit_cost

    from public.inventory_transfer_items

    where transfer_id =
          target_transfer

  loop

    select
      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                target_company

            and r.warehouse_id =
                v_destination

            and r.product_id =
                v_item.product_id

            and r.status =
                'active'
        ),
        0
      )

    into
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          v_destination

      and s.product_id =
          v_item.product_id;

    if
      coalesce(
        v_on_hand,
        0
      ) -
      coalesce(
        v_reserved,
        0
      )
      <
      v_item.quantity
    then
      raise exception
        'Cannot reverse transfer: destination stock is already reserved or used';
    end if;

  end loop;


  for v_item in
    select
      id,
      product_id,
      quantity,
      unit_cost

    from public.inventory_transfer_items

    where transfer_id =
          target_transfer

  loop

    -- Remove from original destination.
    perform
      public.post_inventory_movement(
        target_company,
        v_destination,
        v_item.product_id,
        'transfer_out',
        -v_item.quantity,
        v_item.unit_cost,
        'inventory_transfer_reversals',
        target_transfer,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

    -- Put back into original source.
    perform
      public.post_inventory_movement(
        target_company,
        v_source,
        v_item.product_id,
        'transfer_in',
        v_item.quantity,
        v_item.unit_cost,
        'inventory_transfer_reversals',
        target_transfer,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

    perform
      public.reserve_pending_orders_for_product(
        target_company,
        v_source,
        v_item.product_id
      );

  end loop;


  update public.inventory_transfers
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason)

  where id =
        target_transfer;
end;
$function$;

create or replace function public.set_default_warehouse(target_company uuid, target_warehouse uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.warehouses
    where id =
          target_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception 'Invalid warehouse';
  end if;

  update public.warehouses
  set is_default = false
  where company_id =
        target_company;

  update public.warehouses
  set is_default = true
  where id =
        target_warehouse
    and company_id =
        target_company;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.inventory_movement_history as
 select id,
    company_id,
    warehouse_id,
    product_id,
    movement_type,
    quantity,
        case
            when public.can_view_inventory_cost(company_id) then unit_cost
            else null::numeric
        end as unit_cost,
    source_table,
    source_id,
    source_line_id,
    reference_number,
    notes,
    occurred_at,
    created_at
   from public.inventory_movements m
  where public.has_any_permission(company_id, array['inventory.view'::text, 'inventory.adjust'::text, 'reports.finance'::text, 'reports.profit'::text]);


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger company_default_warehouse after insert on public.companies for each row execute function public.create_default_warehouse();

create trigger audit_inventory_count_items after insert or delete or update on public.inventory_count_items for each row execute function public.write_audit_log();

create trigger audit_inventory_counts after insert or delete or update on public.inventory_counts for each row execute function public.write_audit_log();

create trigger audit_inventory_movements after insert on public.inventory_movements for each row execute function public.write_audit_log();

create trigger audit_inventory_transfer_items after insert or delete or update on public.inventory_transfer_items for each row execute function public.write_audit_log();

create trigger audit_inventory_transfers after insert or delete or update on public.inventory_transfers for each row execute function public.write_audit_log();

create trigger audit_warehouses after insert or delete or update on public.warehouses for each row execute function public.write_audit_log();

create trigger warehouses_updated_at before update on public.warehouses for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.warehouses enable row level security;
alter table public.inventory_stock enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.inventory_transfers enable row level security;
alter table public.inventory_transfer_items enable row level security;
alter table public.inventory_counts enable row level security;
alter table public.inventory_count_items enable row level security;
create policy inventory_count_items_read on public.inventory_count_items
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy inventory_counts_read on public.inventory_counts
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy inventory_movements_read on public.inventory_movements
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy inventory_stock_read on public.inventory_stock
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy inventory_transfer_items_read on public.inventory_transfer_items
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy inventory_transfers_read on public.inventory_transfers
  for select to authenticated
  using (public.has_permission(company_id, 'inventory.view'::text));
create policy warehouses_read on public.warehouses
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'inventory.adjust'::text, 'purchases.view'::text, 'deliveries.view'::text, 'reports.view'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke select, insert, update, delete on public.inventory_stock from authenticated;
revoke select, insert, update, delete on public.inventory_movements from authenticated;
revoke insert, update, delete on public.inventory_transfers from authenticated;
revoke select, insert, update, delete on public.inventory_transfer_items from authenticated;
grant select (id, company_id, transfer_id, product_id, quantity) on public.inventory_transfer_items to authenticated;
revoke insert, update, delete on public.inventory_counts from authenticated;
revoke select, insert, update, delete on public.inventory_count_items from authenticated;
grant select (id, company_id, count_id, product_id, system_quantity, counted_quantity, difference_quantity) on public.inventory_count_items to authenticated;
revoke execute on function public.next_inventory_count_number(uuid,date) from authenticated;
revoke execute on function public.next_inventory_transfer_number(uuid,date) from authenticated;
revoke execute on function public.post_inventory_movement(uuid,uuid,uuid,text,numeric,numeric,text,uuid,uuid,text,text,timestamp with time zone) from authenticated;
revoke execute on function public.product_reference_cost(uuid,uuid) from authenticated;

-- ======================================================================
-- المبيعات
-- عروض الأسعار، الطلبيات، الحجز، التوصيل، فواتير البيع، قبض الزبائن
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  status text default 'new'::text not null,
  payment_status text default 'unpaid'::text not null,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  notes text,
  ordered_at timestamp with time zone default now() not null,
  delivered_at timestamp with time zone,
  paid_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  order_number text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_orders_company_order_number_key unique (company_id, order_number),
  constraint sales_orders_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text, 'credit'::text]))),
  constraint sales_orders_status_check check ((status = any (array['draft'::text, 'new'::text, 'to_purchase'::text, 'purchasing'::text, 'ready'::text, 'out_for_delivery'::text, 'delivered'::text, 'cancelled'::text])))
);
create index dashboard_sales_orders_delivered_idx on public.sales_orders using btree (company_id, delivered_at) where (status = 'delivered'::text);
create index dashboard_sales_orders_status_idx on public.sales_orders using btree (company_id, status);
create index sales_orders_company_idx on public.sales_orders using btree (company_id, created_at desc);
create index sales_orders_trader_idx on public.sales_orders using btree (trader_id, created_at desc);

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null,
  sale_unit_price numeric(14,2) not null,
  line_total numeric(14,2) default 0 not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_order_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_order_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_order_items_sale_unit_price_check check ((sale_unit_price >= (0)::numeric))
);
create index sales_order_items_order_idx on public.sales_order_items using btree (order_id);

create table public.sales_quotes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  quote_number text not null,
  quote_date date default current_date not null,
  valid_until date,
  status text default 'draft'::text not null,
  currency text not null,
  subtotal numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  accepted_at timestamp with time zone,
  converted_order_id uuid references public.sales_orders(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_quotes_company_id_quote_number_key unique (company_id, quote_number),
  constraint sales_quotes_status_check check ((status = any (array['draft'::text, 'sent'::text, 'accepted'::text, 'rejected'::text, 'cancelled'::text, 'converted'::text]))),
  constraint sales_quotes_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_quotes_total_check check ((total >= (0)::numeric))
);
create index sales_quotes_company_status_idx on public.sales_quotes using btree (company_id, status, quote_date desc);
create index sales_quotes_trader_idx on public.sales_quotes using btree (trader_id, quote_date desc);

create table public.sales_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.sales_quotes(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  sale_unit_price numeric(18,2) not null,
  line_total numeric(18,2) default 0 not null,
  minimum_sale_price_snapshot numeric(18,2),
  reference_cost_snapshot numeric(18,4),
  created_at timestamp with time zone default now() not null,
  constraint sales_quote_items_quote_id_product_id_key unique (quote_id, product_id),
  constraint sales_quote_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_quote_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_quote_items_sale_unit_price_check check ((sale_unit_price >= (0)::numeric))
);

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete cascade,
  quantity numeric(18,3) not null,
  status text default 'active'::text not null,
  created_at timestamp with time zone default now() not null,
  released_at timestamp with time zone,
  constraint inventory_reservations_warehouse_id_sales_order_item_id_key unique (warehouse_id, sales_order_item_id),
  constraint inventory_reservations_quantity_check check ((quantity > (0)::numeric)),
  constraint inventory_reservations_status_check check ((status = any (array['active'::text, 'released'::text, 'fulfilled'::text, 'cancelled'::text])))
);
create index inventory_reservations_product_idx on public.inventory_reservations using btree (company_id, product_id, status);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  status text default 'pending'::text not null,
  delivered_at timestamp with time zone,
  failed_at timestamp with time zone,
  failed_by uuid references auth.users(id) on delete set null,
  failure_reason text,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  delivery_number text,
  started_at timestamp with time zone,
  created_by uuid references auth.users(id) on delete set null,
  constraint deliveries_status_check check ((status = any (array['pending'::text, 'out_for_delivery'::text, 'delivered'::text, 'failed'::text])))
);
create unique index deliveries_number_unique on public.deliveries using btree (company_id, delivery_number) where (delivery_number is not null);
create index deliveries_order_idx on public.deliveries using btree (order_id, created_at desc);
create index deliveries_order_status_idx on public.deliveries using btree (company_id, order_id, status, created_at desc);

create table public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null,
  unit text,
  created_at timestamp with time zone default now() not null,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  constraint delivery_items_quantity_check check ((quantity > (0)::numeric))
);
create index delivery_items_delivery_idx on public.delivery_items using btree (delivery_id);
create unique index delivery_items_delivery_order_wh_unique on public.delivery_items using btree (delivery_id, sales_order_item_id, warehouse_id);
create index delivery_items_order_item_idx on public.delivery_items using btree (sales_order_item_id);

create table public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  order_id uuid not null references public.sales_orders(id) on delete restrict,
  invoice_number text not null,
  status text default 'posted'::text not null,
  payment_status text default 'unpaid'::text not null,
  currency text default 'USD'::text not null,
  invoice_date date default current_date not null,
  due_date date,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  paid_total numeric(14,2) default 0 not null,
  balance_due numeric(14,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone default now() not null,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_invoices_company_id_invoice_number_key unique (company_id, invoice_number),
  constraint sales_invoices_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint sales_invoices_check check (((due_date is null) or (due_date >= invoice_date))),
  constraint sales_invoices_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint sales_invoices_paid_total_check check ((paid_total >= (0)::numeric)),
  constraint sales_invoices_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text]))),
  constraint sales_invoices_status_check check ((status = any (array['posted'::text, 'cancelled'::text]))),
  constraint sales_invoices_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_invoices_total_check check ((total >= (0)::numeric))
);
create index dashboard_sales_invoices_posted_idx on public.sales_invoices using btree (company_id, posted_at) where (status = 'posted'::text);
create index sales_invoices_company_date_idx on public.sales_invoices using btree (company_id, invoice_date desc, created_at desc);
create index sales_invoices_due_idx on public.sales_invoices using btree (company_id, due_date) where ((status = 'posted'::text) and (payment_status <> 'paid'::text));
create index sales_invoices_order_idx on public.sales_invoices using btree (order_id, created_at desc);
create index sales_invoices_trader_date_idx on public.sales_invoices using btree (trader_id, invoice_date desc, created_at desc);

create table public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  sales_order_item_id uuid references public.sales_order_items(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  description text not null,
  unit text,
  quantity numeric(14,3) not null,
  unit_price numeric(14,2) not null,
  line_total numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_invoice_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_invoice_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_invoice_items_unit_price_check check ((unit_price >= (0)::numeric))
);
create index sales_invoice_items_invoice_idx on public.sales_invoice_items using btree (invoice_id);
create index sales_invoice_items_order_item_idx on public.sales_invoice_items using btree (sales_order_item_id) where (sales_order_item_id is not null);
create index sales_invoice_items_product_idx on public.sales_invoice_items using btree (company_id, product_id);

create table public.sales_invoice_delivery_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  delivery_id uuid not null references public.deliveries(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint sales_invoice_delivery_links_delivery_id_key unique (delivery_id)
);
create index sales_invoice_delivery_invoice_idx on public.sales_invoice_delivery_links using btree (sales_invoice_id);

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  payment_number text not null,
  status text default 'posted'::text not null,
  payment_date date default current_date not null,
  amount numeric(14,2) not null,
  allocated_total numeric(14,2) default 0 not null,
  unallocated_total numeric(14,2) default 0 not null,
  payment_method text default 'cash'::text not null,
  reference_number text,
  notes text,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  payment_currency text,
  exchange_rate_to_base numeric(24,10),
  base_amount numeric(20,4),
  constraint customer_payments_company_id_payment_number_key unique (company_id, payment_number),
  constraint customer_payments_amount_check check ((amount > (0)::numeric)),
  constraint customer_payments_check check (((allocated_total >= (0)::numeric) and (allocated_total <= amount))),
  constraint customer_payments_check1 check (((unallocated_total >= (0)::numeric) and (unallocated_total <= amount))),
  constraint customer_payments_check2 check (((allocated_total + unallocated_total) = amount)),
  constraint customer_payments_payment_method_check check ((payment_method = any (array['cash'::text, 'bank'::text, 'card'::text, 'check'::text, 'other'::text]))),
  constraint customer_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index customer_payments_company_date_idx on public.customer_payments using btree (company_id, payment_date desc, created_at desc);
create index customer_payments_currency_idx on public.customer_payments using btree (company_id, payment_currency, payment_date desc);
create index customer_payments_trader_date_idx on public.customer_payments using btree (trader_id, payment_date desc, created_at desc);

create table public.customer_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete restrict,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  payment_amount numeric(20,2),
  payment_currency text,
  invoice_currency text,
  payment_rate_to_base numeric(24,10),
  constraint customer_payment_allocations_payment_id_sales_invoice_id_key unique (payment_id, sales_invoice_id),
  constraint customer_payment_allocations_amount_check check ((amount > (0)::numeric))
);
create index customer_payment_allocations_invoice_idx on public.customer_payment_allocations using btree (sales_invoice_id);
create index customer_payment_allocations_payment_idx on public.customer_payment_allocations using btree (payment_id);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_customer_payment_fk foreign key (customer_payment_id) references public.customer_payments(id) on delete set null;
alter table public.cash_transactions
  add constraint cash_transactions_order_id_fkey foreign key (order_id) references public.sales_orders(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.apply_customer_credit_to_invoice(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_trader uuid;
  v_company uuid;
  v_balance numeric(20,2);
  v_invoice_currency text;

  v_payment record;
  v_apply numeric(20,2);
begin
  select
    trader_id,
    company_id,
    balance_due,
    upper(currency)

  into
    v_trader,
    v_company,
    v_balance,
    v_invoice_currency

  from public.sales_invoices

  where id =
        target_invoice
    and status =
        'posted';

  if v_trader is null
     or coalesce(
          v_balance,
          0
        ) <= 0
  then
    return;
  end if;


  for v_payment in

    select
      p.id,
      p.unallocated_total,
      upper(
        coalesce(
          p.payment_currency,
          cb.currency
        )
      ) as payment_currency

    from public.customer_payments p

    join public.cashboxes cb
      on cb.id =
         p.cashbox_id

    where p.company_id =
          v_company
      and p.trader_id =
          v_trader
      and p.status =
          'posted'
      and p.unallocated_total >
          0
      and upper(
            coalesce(
              p.payment_currency,
              cb.currency
            )
          ) =
          v_invoice_currency

    order by
      p.payment_date,
      p.created_at

  loop

    select balance_due
    into v_balance
    from public.sales_invoices
    where id =
          target_invoice
    for update;

    exit when
      coalesce(
        v_balance,
        0
      ) <= 0;

    v_apply :=
      least(
        v_balance,
        v_payment.unallocated_total
      );

    if v_apply > 0 then

      insert into public.customer_payment_allocations(
        company_id,
        payment_id,
        sales_invoice_id,
        amount,
        payment_amount,
        payment_currency,
        invoice_currency,
        payment_rate_to_base
      )
      values(
        v_company,
        v_payment.id,
        target_invoice,
        round(
          v_apply,
          2
        ),
        round(
          v_apply,
          2
        ),
        v_payment.payment_currency,
        v_invoice_currency,
        -- نفس سعر قيد القبض الأصلي (سعر يوم الدفعة)، مش 1، وإلا الليرة بتنحسب دولار.
        null
      )
      on conflict(
        payment_id,
        sales_invoice_id
      )
      do nothing;

    end if;

  end loop;
end;
$function$;

create or replace function public.apply_customer_payment_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_days integer := 0;
begin
  select
    coalesce(
      t.payment_terms_days,
      0
    )
  into v_days
  from public.traders t
  where t.id = new.trader_id
    and t.company_id =
        new.company_id;

  if new.due_date is null
     or new.due_date =
        new.invoice_date
  then
    new.due_date :=
      new.invoice_date +
      v_days;
  end if;

  return new;
end;
$function$;

create or replace function public.can_access_order(target_order uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.sales_orders o
    where o.id = target_order
      and public.has_any_permission(
        o.company_id,
        array[
          'orders.view',
          'deliveries.view',
          'payments.sales_view',
          'reports.sales',
          'reports.profit',
          'reports.finance'
        ]::text[]
      )
  );
$function$;

create or replace function public.cancel_sales_invoice(target_company uuid, target_invoice uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_order uuid;
  v_number text;
  v_line record;
begin
  if not public.has_permission(
    target_company,
    'sales_invoices.cancel'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    status,
    order_id,
    invoice_number
  into
    v_status,
    v_order,
    v_number
  from public.sales_invoices
  where id = target_invoice
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Sales invoice not found';
  end if;

  if v_status =
     'cancelled'
  then
    return;
  end if;

  if exists(
    select 1
    from public.customer_payment_allocations a

    join public.customer_payments p
      on p.id =
         a.payment_id

    where a.sales_invoice_id =
          target_invoice

      and p.status =
          'posted'

      and a.amount > 0
  ) then
    raise exception
      'Reverse allocated customer payments before cancelling invoice';
  end if;

  update public.sales_invoices
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),

    cancellation_reason =
      coalesce(
        nullif(
          trim(target_reason),
          ''
        ),
        'Cancelled'
      )

  where id =
        target_invoice;

  -- إلغاء البيعة معناه ما صارت: البضاعة المسلّمة بترجع لمستودعها بنفس كلفة خروجها،
  -- والقيد التلقائي بيعكس كلفة البضاعة المباعة. (الفاتورة اللي عليها مرتجع ما بتنلغى أصلًا.)
  for v_line in
    select
      di.id,
      di.warehouse_id,
      di.product_id,
      di.quantity,
      m.unit_cost
    from public.sales_invoice_delivery_links l
    join public.delivery_items di
      on di.delivery_id = l.delivery_id
    left join public.inventory_movements m
      on m.source_table = 'deliveries'
     and m.source_line_id = di.id
     and m.movement_type = 'sales_delivery'
    where l.sales_invoice_id = target_invoice
  loop
    perform public.post_inventory_movement(
      target_company,
      v_line.warehouse_id,
      v_line.product_id,
      'sales_return',
      v_line.quantity,
      v_line.unit_cost,
      'sales_invoice_cancellations',
      target_invoice,
      v_line.id,
      v_number,
      'إلغاء فاتورة ' || v_number,
      now()
    );
  end loop;

  perform
    public.recalc_sales_order_payment(
      v_order
    );
end;
$function$;

create or replace function public.cancel_sales_order(target_company uuid, target_order uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_res record;
begin
  if not public.has_permission(
    target_company,
    'orders.cancel'
  ) then
    raise exception 'Not allowed';
  end if;

  select so.status
  into v_status
  from public.sales_orders so
  where so.id = target_order
    and so.company_id = target_company
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception 'Cancellation reason required';
  end if;

  if v_status in (
    'out_for_delivery',
    'delivered'
  ) then
    raise exception
      'Order cannot be cancelled at this stage';
  end if;

  if exists (
    select 1
    from public.sales_invoices si
    where si.company_id = target_company
      and si.order_id = target_order
      and si.status <> 'cancelled'
  ) then
    raise exception
      'Cancel sales invoice first';
  end if;

  update public.sales_orders
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    cancellation_reason =
      trim(target_reason)
  where id = target_order
    and company_id = target_company;

  for v_res in
    select
      ir.id,
      ir.warehouse_id,
      ir.product_id
    from public.inventory_reservations ir

    join public.sales_order_items soi
      on soi.id =
         ir.sales_order_item_id

    where soi.order_id =
          target_order

      and ir.status =
          'active'

    for update
  loop
    update public.inventory_reservations
    set
      status = 'cancelled',
      released_at = now()
    where id = v_res.id;

    perform
      public.reserve_pending_orders_for_product(
        target_company,
        v_res.warehouse_id,
        v_res.product_id
      );
  end loop;
end;
$function$;

create or replace function public.complete_order_delivery(target_company uuid, target_order uuid, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order_status text;
  v_delivery uuid;
  v_invoice uuid;

  v_trader uuid;
  v_currency text;

  v_order_subtotal numeric(14,2);
  v_order_discount numeric(14,2);

  v_subtotal numeric(14,2);
  v_discount numeric(14,2);
  v_previous_discount numeric(14,2);
  v_total numeric(14,2);

  v_invoice_number text;
  v_now timestamptz;

  v_fully_delivered boolean;

  v_line record;
  v_reservation uuid;
  v_reservation_qty numeric(18,3);
  v_average_cost numeric(18,4);
begin
  if not public.has_permission(
    target_company,
    'deliveries.update'
  ) then
    raise exception 'Not allowed';
  end if;

  select status
  into v_order_status
  from public.sales_orders
  where id =
        target_order
    and company_id =
        target_company
  for update;

  if v_order_status is null then
    raise exception
      'Order not found';
  end if;

  if v_order_status in (
       'ready',
       'delivered'
     )
     and not exists (
       select 1
       from public.deliveries d
       where d.company_id =
             target_company
         and d.order_id =
             target_order
         and d.status =
             'out_for_delivery'
     )
  then

    select
      l.sales_invoice_id

    into
      v_invoice

    from public.sales_invoice_delivery_links l

    join public.deliveries d
      on d.id =
         l.delivery_id

    where d.company_id =
          target_company

      and d.order_id =
          target_order

      and d.status =
          'delivered'

    order by
      d.delivered_at desc
      nulls last,
      d.created_at desc

    limit 1;

    if v_invoice is not null then
      return v_invoice;
    end if;

  end if;

  if v_order_status <>
     'out_for_delivery'
  then
    raise exception
      'Order is not currently out for delivery';
  end if;

  select d.id
  into v_delivery
  from public.deliveries d
  where d.company_id =
        target_company
    and d.order_id =
        target_order
    and d.status =
        'out_for_delivery'
  order by
    d.created_at desc
  limit 1
  for update;

  if v_delivery is null then
    raise exception
      'Active delivery not found';
  end if;

  select l.sales_invoice_id
  into v_invoice
  from public.sales_invoice_delivery_links l
  where l.delivery_id =
        v_delivery;

  if v_invoice is not null then
    return v_invoice;
  end if;

  v_now := now();

  -- Physically issue every delivery line.
  for v_line in
    select
      di.id,
      di.sales_order_item_id,
      di.product_id,
      di.warehouse_id,
      di.quantity
    from public.delivery_items di
    where di.delivery_id =
          v_delivery
    order by di.created_at
  loop
    select
      ir.id,
      ir.quantity
    into
      v_reservation,
      v_reservation_qty
    from public.inventory_reservations ir
    where ir.sales_order_item_id =
          v_line.sales_order_item_id
      and ir.warehouse_id =
          v_line.warehouse_id
      and ir.status =
          'active'
    for update;

    if v_reservation is null
       or v_reservation_qty <
          v_line.quantity
    then
      raise exception
        'Reserved stock is missing for delivery';
    end if;

    select
      coalesce(
        s.average_cost,
        0
      )
    into v_average_cost
    from public.inventory_stock s
    where s.warehouse_id =
          v_line.warehouse_id
      and s.product_id =
          v_line.product_id;

    if v_average_cost is null then
      raise exception
        'Inventory balance not found';
    end if;

    perform
      public.post_inventory_movement(
        target_company,
        v_line.warehouse_id,
        v_line.product_id,
        'sales_delivery',
        -v_line.quantity,
        v_average_cost,
        'deliveries',
        v_delivery,
        v_line.id,
        null,
        target_notes,
        v_now
      );

    if v_reservation_qty >
       v_line.quantity
    then
      update public.inventory_reservations
      set quantity =
          quantity -
          v_line.quantity
      where id =
            v_reservation;
    else
      update public.inventory_reservations
      set
        status =
          'fulfilled',
        released_at =
          v_now
      where id =
            v_reservation;
    end if;
  end loop;

  update public.deliveries
  set
    status =
      'delivered',

    delivered_at =
      coalesce(
        delivered_at,
        v_now
      ),

    notes =
      coalesce(
        nullif(
          trim(target_notes),
          ''
        ),
        notes
      ),

    updated_at =
      v_now

  where id =
        v_delivery;

  select
    o.trader_id,
    o.subtotal,
    o.discount_total,
    coalesce(
      c.default_currency,
      'USD'
    )
  into
    v_trader,
    v_order_subtotal,
    v_order_discount,
    v_currency

  from public.sales_orders o

  join public.companies c
    on c.id =
       o.company_id

  where o.id =
        target_order

    and o.company_id =
        target_company;

  select
    coalesce(
      sum(
        di.quantity *
        soi.sale_unit_price
      ),
      0
    )
  into v_subtotal

  from public.delivery_items di

  join public.sales_order_items soi
    on soi.id =
       di.sales_order_item_id

  where di.delivery_id =
        v_delivery;

  select
    not exists (
      select 1

      from public.sales_order_items soi

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'delivered'
      ) delivered on true

      where soi.order_id =
            target_order

        and delivered.qty <
            soi.quantity
    )
  into v_fully_delivered;

  select
    coalesce(
      sum(si.discount_total),
      0
    )
  into v_previous_discount
  from public.sales_invoices si
  where si.company_id =
        target_company

    and si.order_id =
        target_order

    and si.status =
        'posted';

  if coalesce(
       v_order_discount,
       0
     ) <= 0
  then
    v_discount := 0;

  elsif v_fully_delivered then
    v_discount :=
      greatest(
        v_order_discount -
        v_previous_discount,
        0
      );

  elsif coalesce(
          v_order_subtotal,
          0
        ) > 0
  then
    v_discount :=
      round(
        v_order_discount *
        (
          v_subtotal /
          v_order_subtotal
        ),
        2
      );

  else
    v_discount := 0;
  end if;

  v_discount :=
    least(
      v_discount,
      v_subtotal,
      greatest(
        coalesce(
          v_order_discount,
          0
        ) -
        coalesce(
          v_previous_discount,
          0
        ),
        0
      )
    );

  v_total :=
    round(
      greatest(
        v_subtotal -
        v_discount,
        0
      ),
      2
    );

  v_invoice_number :=
    public.next_sales_invoice_number(
      target_company,
      v_now::date
    );

  insert into public.sales_invoices(
    company_id,
    trader_id,
    order_id,
    invoice_number,
    status,
    payment_status,
    currency,
    invoice_date,
    due_date,
    subtotal,
    discount_total,
    total,
    paid_total,
    balance_due,
    notes,
    posted_at
  )
  values(
    target_company,
    v_trader,
    target_order,
    v_invoice_number,
    'posted',

    case
      when v_total = 0
        then 'paid'
      else 'unpaid'
    end,

    v_currency,
    v_now::date,
    v_now::date,
    round(
      v_subtotal,
      2
    ),
    round(
      v_discount,
      2
    ),
    v_total,
    0,
    v_total,
    nullif(
      trim(target_notes),
      ''
    ),
    v_now
  )
  returning id
  into v_invoice;

  insert into public.sales_invoice_items(
    company_id,
    invoice_id,
    product_id,
    description,
    unit,
    quantity,
    unit_price,
    line_total
  )
  select
    target_company,
    v_invoice,
    soi.product_id,
    p.name,
    p.unit,

    sum(
      di.quantity
    ),

    soi.sale_unit_price,

    round(
      sum(
        di.quantity
      ) *
      soi.sale_unit_price,
      2
    )

  from public.delivery_items di

  join public.sales_order_items soi
    on soi.id =
       di.sales_order_item_id

  join public.products p
    on p.id =
       soi.product_id

  where di.delivery_id =
        v_delivery

  group by
    soi.id,
    soi.product_id,
    p.name,
    p.unit,
    soi.sale_unit_price;

  insert into public.sales_invoice_delivery_links(
    company_id,
    sales_invoice_id,
    delivery_id
  )
  values(
    target_company,
    v_invoice,
    v_delivery
  );

  perform
    public.apply_customer_credit_to_invoice(
      v_invoice
    );

  perform
    public.recalc_sales_invoice_payment(
      v_invoice
    );

  if v_fully_delivered then
    update public.sales_orders
    set
      status =
        'delivered',

      delivered_at =
        coalesce(
          delivered_at,
          v_now
        )

    where id =
          target_order

      and company_id =
          target_company;
  else
    update public.sales_orders
    set
      status = 'new',
      delivered_at = null

    where id =
          target_order

      and company_id =
          target_company;

    perform
      public.refresh_sales_order_inventory_status(
        target_order
      );
  end if;

  return v_invoice;
end;
$function$;

create or replace function public.convert_sales_quote_to_order(target_company uuid, target_quote uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_quote public.sales_quotes%rowtype;
  v_items jsonb;
begin
  if not public.has_permission(target_company,'orders.create') then
    raise exception 'Not allowed';
  end if;

  select * into v_quote
  from public.sales_quotes
  where id=target_quote and company_id=target_company
  for update;

  if not found then raise exception 'Quote not found'; end if;
  if v_quote.converted_order_id is not null or v_quote.status='converted' then
    return jsonb_build_object('status','created','order_id',v_quote.converted_order_id,'approval_id',null);
  end if;
  if v_quote.status <> 'accepted' then raise exception 'Quote must be accepted first'; end if;
  if v_quote.valid_until is not null and v_quote.valid_until < (now() at time zone 'Asia/Damascus')::date then
    raise exception 'Quote has expired';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'product_id',i.product_id,
      'quantity',i.quantity,
      'sale_unit_price',i.sale_unit_price
    ) order by i.created_at
  ) into v_items
  from public.sales_quote_items i
  where i.quote_id=target_quote;

  return public.create_sales_order_v2(
    target_company,
    v_quote.trader_id,
    v_quote.notes,
    v_items,
    target_quote
  );
end;
$function$;

create or replace function public.create_order_delivery(target_company uuid, target_order uuid, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_delivery uuid;
  v_number text;

  v_item jsonb;
  v_order_item uuid;
  v_product uuid;

  v_quantity numeric(18,3);
  v_order_quantity numeric(18,3);
  v_delivered numeric(18,3);
  v_reserved numeric(18,3);

  v_remaining numeric(18,3);
  v_take numeric(18,3);

  v_res record;
begin
  if not public.has_permission(
    target_company,
    'deliveries.update'
  ) then
    raise exception 'Not allowed';
  end if;

  select status
  into v_status
  from public.sales_orders
  where id =
        target_order
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Order not found';
  end if;

  if v_status <> 'ready' then
    raise exception
      'Order is not ready for delivery';
  end if;

  if exists (
    select 1
    from public.deliveries
    where company_id =
          target_company
      and order_id =
          target_order
      and status =
          'out_for_delivery'
  ) then
    raise exception
      'Order already has an active delivery';
  end if;

  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Delivery must contain items';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      items_payload
    ) x
    group by
      x->>'sales_order_item_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate delivery item';
  end if;

  v_number :=
    public.next_delivery_number(
      target_company,
      current_date
    );

  insert into public.deliveries(
    company_id,
    order_id,
    delivery_number,
    status,
    started_at,
    created_by
  )
  values(
    target_company,
    target_order,
    v_number,
    'out_for_delivery',
    now(),
    auth.uid()
  )
  returning id
  into v_delivery;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_order_item :=
        (
          v_item->>'sales_order_item_id'
        )::uuid;

      v_quantity :=
        (
          v_item->>'quantity'
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid delivery item';
    end;

    if v_quantity is null
       or v_quantity <= 0
    then
      raise exception
        'Invalid delivery quantity';
    end if;

    select
      soi.product_id,
      soi.quantity
    into
      v_product,
      v_order_quantity
    from public.sales_order_items soi

    join public.sales_orders so
      on so.id =
         soi.order_id

    where soi.id =
          v_order_item
      and soi.order_id =
          target_order
      and so.company_id =
          target_company;

    if v_product is null then
      raise exception
        'Sales order item not found';
    end if;

    select
      coalesce(
        sum(di.quantity),
        0
      )
    into v_delivered
    from public.delivery_items di

    join public.deliveries d
      on d.id =
         di.delivery_id

    where di.sales_order_item_id =
          v_order_item

      and d.status =
          'delivered';

    if
      round(
        v_delivered +
        v_quantity,
        3
      ) >
      round(
        v_order_quantity,
        3
      )
    then
      raise exception
        'Delivery exceeds remaining order quantity';
    end if;

    select
      coalesce(
        sum(ir.quantity),
        0
      )
    into v_reserved
    from public.inventory_reservations ir

    where ir.sales_order_item_id =
          v_order_item

      and ir.status =
          'active';

    if
      round(
        v_quantity,
        3
      ) >
      round(
        v_reserved,
        3
      )
    then
      raise exception
        'Delivery quantity is not fully reserved';
    end if;

    v_remaining :=
      v_quantity;

    for v_res in
      select
        ir.id,
        ir.warehouse_id,
        ir.quantity
      from public.inventory_reservations ir

      join public.warehouses w
        on w.id =
           ir.warehouse_id

      where ir.sales_order_item_id =
            v_order_item

        and ir.status =
            'active'

      order by
        w.is_default desc,
        ir.created_at

      for update of ir
    loop
      exit when
        v_remaining <= 0;

      v_take :=
        least(
          v_remaining,
          v_res.quantity
        );

      insert into public.delivery_items(
        company_id,
        delivery_id,
        sales_order_item_id,
        product_id,
        warehouse_id,
        quantity,
        unit
      )
      select
        target_company,
        v_delivery,
        v_order_item,
        v_product,
        v_res.warehouse_id,
        v_take,
        p.unit
      from public.products p
      where p.id =
            v_product;

      v_remaining :=
        v_remaining -
        v_take;
    end loop;

    if v_remaining > 0.0001 then
      raise exception
        'Could not allocate reserved stock';
    end if;
  end loop;

  update public.sales_orders
  set status =
      'out_for_delivery'
  where id =
        target_order
    and company_id =
        target_company;

  return v_delivery;
end;
$function$;

create or replace function public.create_sales_order(target_company uuid, target_trader uuid, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order uuid;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(14,3);
  v_price numeric(14,2);
  v_min_price numeric(14,2);
  v_total numeric(14,2) := 0;
begin
  if not public.has_permission(
    target_company,
    'orders.create'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_trader is null
     or not exists (
       select 1
       from public.traders t
       where t.id = target_trader
         and t.company_id =
             target_company
         and t.status <>
             'inactive'
     )
  then
    raise exception 'Invalid trader';
  end if;

  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Order must contain items';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      items_payload
    ) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate products are not allowed';
  end if;

  insert into public.sales_orders(
    company_id,
    trader_id,
    status,
    payment_status,
    notes
  )
  values(
    target_company,
    target_trader,
    'new',
    'unpaid',
    nullif(
      btrim(target_notes),
      ''
    )
  )
  returning id
  into v_order;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_product :=
        (v_item->>'product_id')::uuid;

      v_quantity :=
        (v_item->>'quantity')::numeric;

      v_price :=
        (v_item->>'sale_unit_price')::numeric;
    exception
      when others then
        raise exception
          'Invalid order item';
    end;

    if v_quantity is null
       or v_quantity <= 0
    then
      raise exception
        'Quantity must be greater than zero';
    end if;

    if v_price is null
       or v_price < 0
    then
      raise exception
        'Sale price cannot be negative';
    end if;

    select p.minimum_sale_price
    into v_min_price
    from public.products p
    where p.id =
          v_product
      and p.company_id =
          target_company
      and p.active = true;

    if not found then
      raise exception
        'Invalid or inactive product';
    end if;

    if v_min_price is not null
       and v_price < v_min_price
       and not public.has_permission(
         target_company,
         'orders.approve_discount'
       )
    then
      raise exception
        'Sale price is below allowed minimum';
    end if;

    insert into public.sales_order_items(
      order_id,
      product_id,
      quantity,
      sale_unit_price,
      line_total
    )
    values(
      v_order,
      v_product,
      v_quantity,
      v_price,
      round(
        v_quantity *
        v_price,
        2
      )
    );

    v_total :=
      v_total +
      round(
        v_quantity *
        v_price,
        2
      );
  end loop;

  update public.sales_orders
  set
    subtotal = v_total,
    total = v_total
  where id = v_order
    and company_id =
        target_company;

  perform
    public.reserve_sales_order(
      target_company,
      v_order
    );

  return v_order;
end;
$function$;

create or replace function public.create_sales_order_v2(target_company uuid, target_trader uuid, target_notes text, items_payload jsonb, target_source_quote uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
  v_minimum numeric(18,2);
  v_cost numeric(18,4);
  v_threshold numeric(18,4);

  v_requires_approval boolean := false;

  v_details jsonb :=
    '[]'::jsonb;

  v_approval uuid;
  v_order uuid;
begin
  if not public.has_permission(
    target_company,
    'orders.create'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_trader is null
     or not exists (
       select 1
       from public.traders t
       where t.id =
             target_trader
         and t.company_id =
             target_company
         and t.status <>
             'inactive'
     )
  then
    raise exception
      'Invalid trader';
  end if;

  if target_source_quote is not null then
    perform
      public.validate_sales_quote_conversion_source(
        target_company,
        target_source_quote,
        target_trader,
        items_payload
      );
  end if;
  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Order must contain items';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      items_payload
    ) x
    group by
      x->>'product_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate products are not allowed';
  end if;

  if target_source_quote is not null
     and not exists (
       select 1
       from public.sales_quotes q
       where q.id =
             target_source_quote
         and q.company_id =
             target_company
         and q.trader_id =
             target_trader
         and q.status =
             'accepted'
         and q.converted_order_id
             is null
         and (
           q.valid_until is null
           or
           q.valid_until >=
             current_date
         )
     )
  then
    raise exception
      'Invalid or unavailable source quote';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_product :=
        (v_item->>'product_id')::uuid;

      v_quantity :=
        (v_item->>'quantity')::numeric;

      v_price :=
        (v_item->>'sale_unit_price')::numeric;

    exception
      when others then
        raise exception
          'Invalid order item';
    end;

    if v_quantity is null
       or v_quantity <= 0
    then
      raise exception
        'Quantity must be greater than zero';
    end if;

    if v_price is null
       or v_price < 0
    then
      raise exception
        'Sale price cannot be negative';
    end if;

    select
      p.minimum_sale_price
    into
      v_minimum
    from public.products p
    where p.id =
          v_product
      and p.company_id =
          target_company
      and p.active = true;

    if not found then
      raise exception
        'Invalid or inactive product';
    end if;

    v_cost :=
      public.product_reference_cost(
        target_company,
        v_product
      );

    v_threshold :=
      greatest(
        coalesce(
          v_minimum,
          0
        ),
        coalesce(
          v_cost,
          0
        )
      );

    if v_price <
       v_threshold
    then
      v_requires_approval :=
        true;

      v_details :=
        v_details ||
        jsonb_build_array(
          jsonb_build_object(
            'product_id',
            v_product,

            'sale_price',
            v_price,

            'minimum_sale_price',
            v_minimum,

            'reference_cost',
            v_cost,

            'required_minimum',
            v_threshold
          )
        );
    end if;
  end loop;

  if v_requires_approval
     and not public.has_permission(
       target_company,
       'orders.approve_discount'
     )
  then

    if target_source_quote is not null then
      select ar.id
      into v_approval
      from public.approval_requests ar
      where ar.company_id =
            target_company
        and ar.request_type =
            'below_cost_order'
        and ar.reference_type =
            'sales_quote'
        and ar.reference_id =
            target_source_quote
        and ar.status =
            'pending'
      order by
        ar.requested_at desc
      limit 1;
    end if;

    if v_approval is null then
      insert into public.approval_requests(
        company_id,
        request_type,
        reference_type,
        reference_id,
        title,
        description,
        payload
      )
      values(
        target_company,

        'below_cost_order',

        case
          when target_source_quote
               is null
            then 'sales_order_request'
          else 'sales_quote'
        end,

        target_source_quote,

        'موافقة بيع تحت التكلفة أو الحد الأدنى',

        'الطلب يحتوي على صنف بسعر أقل من التكلفة المرجعية أو الحد الأدنى المسموح.',

        jsonb_build_object(
          'trader_id',
          target_trader,

          'notes',
          target_notes,

          'items',
          items_payload,

          'source_quote_id',
          target_source_quote,

          'price_guard_details',
          v_details
        )
      )
      returning id
      into v_approval;
    end if;

    return
      jsonb_build_object(
        'status',
        'pending_approval',

        'order_id',
        null,

        'approval_id',
        v_approval
      );
  end if;

  v_order :=
    public.create_sales_order(
      target_company,
      target_trader,
      target_notes,
      items_payload
    );

  if target_source_quote is not null then
    update public.sales_quotes
    set
      status =
        'converted',

      converted_order_id =
        v_order

    where id =
          target_source_quote

      and company_id =
          target_company

      and status =
          'accepted'

      and converted_order_id
          is null;
  end if;

  return
    jsonb_build_object(
      'status',
      'created',

      'order_id',
      v_order,

      'approval_id',
      null
    );
end;
$function$;

create or replace function public.create_sales_quote(target_company uuid, target_trader uuid, target_valid_until date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_quote uuid;
  v_number text;
  v_currency text;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
  v_minimum numeric(18,2);
  v_cost numeric(18,4);
  v_total numeric(18,2) := 0;
begin
  if not public.has_permission(target_company,'orders.create') then
    raise exception 'Not allowed';
  end if;

  if not exists(
    select 1 from public.traders
    where id = target_trader
      and company_id = target_company
      and status <> 'inactive'
  ) then
    raise exception 'Invalid trader';
  end if;

  if target_valid_until is not null and target_valid_until < (now() at time zone 'Asia/Damascus')::date then
    raise exception 'Quote validity date cannot be in the past';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0 then
    raise exception 'Quote must contain items';
  end if;

  if exists(
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception 'Duplicate products are not allowed';
  end if;

  select coalesce(default_currency,'USD')
  into v_currency
  from public.companies
  where id = target_company;

  v_number := public.next_sales_quote_number(target_company,(now() at time zone 'Asia/Damascus')::date);

  insert into public.sales_quotes(
    company_id,trader_id,quote_number,quote_date,valid_until,status,currency,notes
  ) values(
    target_company,target_trader,v_number,(now() at time zone 'Asia/Damascus')::date,target_valid_until,'draft',v_currency,
    nullif(btrim(target_notes),'')
  ) returning id into v_quote;

  for v_item in select value from jsonb_array_elements(items_payload)
  loop
    begin
      v_product := (v_item->>'product_id')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'sale_unit_price')::numeric;
    exception when others then
      raise exception 'Invalid quote item';
    end;

    if v_quantity <= 0 or v_price < 0 then
      raise exception 'Invalid quote item values';
    end if;

    select minimum_sale_price
    into v_minimum
    from public.products
    where id = v_product
      and company_id = target_company
      and active = true;

    if not found then
      raise exception 'Invalid or inactive product';
    end if;

    v_cost := public.product_reference_cost(target_company,v_product);

    insert into public.sales_quote_items(
      quote_id,product_id,quantity,sale_unit_price,line_total,
      minimum_sale_price_snapshot,reference_cost_snapshot
    ) values(
      v_quote,v_product,v_quantity,v_price,round(v_quantity*v_price,2),
      v_minimum,v_cost
    );

    v_total := v_total + round(v_quantity*v_price,2);
  end loop;

  update public.sales_quotes
  set subtotal = v_total,
      total = v_total
  where id = v_quote;

  return v_quote;
end;
$function$;

create or replace function public.customer_payment_allocation_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  if tg_op = 'DELETE' then

    perform
      public.refresh_customer_payment_totals(
        old.payment_id
      );

    perform
      public.recalc_sales_invoice_payment(
        old.sales_invoice_id
      );

    return old;
  end if;


  if tg_op = 'UPDATE' then

    if old.payment_id
       is distinct from
       new.payment_id
    then

      perform
        public.refresh_customer_payment_totals(
          old.payment_id
        );

    end if;


    if old.sales_invoice_id
       is distinct from
       new.sales_invoice_id
    then

      perform
        public.recalc_sales_invoice_payment(
          old.sales_invoice_id
        );

    end if;

  end if;


  perform
    public.refresh_customer_payment_totals(
      new.payment_id
    );


  perform
    public.recalc_sales_invoice_payment(
      new.sales_invoice_id
    );


  return new;

end;
$function$;

create or replace function public.customer_payment_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invoice uuid;
begin

  if old.status is distinct from new.status
  then

    for v_invoice in
      select distinct sales_invoice_id
      from public.customer_payment_allocations
      where payment_id = new.id

    loop

      perform
        public.recalc_sales_invoice_payment(
          v_invoice
        );

    end loop;

  end if;


  return new;

end;
$function$;

create or replace function public.enforce_sales_order_credit_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_limit numeric(14,2);
  v_receivables numeric(14,2);
  v_other_orders numeric(14,2);
  v_invoiced_for_order numeric(14,2);
  v_this_order numeric(14,2);
  v_exposure numeric(14,2);
begin
  if new.status = 'cancelled' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.trader_id = old.trader_id
       and coalesce(new.total,0) <=
           coalesce(old.total,0)
    then
      return new;
    end if;
  end if;

  select t.credit_limit
  into v_limit
  from public.traders t
  where t.id = new.trader_id
    and t.company_id = new.company_id;

  if v_limit is null then
    return new;
  end if;

  if public.has_permission(
    new.company_id,
    'orders.override_credit_limit'
  ) then
    return new;
  end if;

  select
    coalesce(
      sum(si.balance_due),
      0
    )
  into v_receivables
  from public.sales_invoices si
  where si.company_id = new.company_id
    and si.trader_id = new.trader_id
    and si.status = 'posted'
    and si.balance_due > 0;

  select
    coalesce(
      sum(
        greatest(
          so.total -
          coalesce(
            (
              select sum(si.total)
              from public.sales_invoices si
              where si.company_id =
                    new.company_id
                and si.order_id =
                    so.id
                and si.status =
                    'posted'
            ),
            0
          ),
          0
        )
      ),
      0
    )
  into v_other_orders
  from public.sales_orders so
  where so.company_id = new.company_id
    and so.trader_id = new.trader_id
    and so.status <> 'cancelled'
    and so.id <> new.id;

  select
    coalesce(
      sum(si.total),
      0
    )
  into v_invoiced_for_order
  from public.sales_invoices si
  where si.company_id =
        new.company_id
    and si.order_id =
        new.id
    and si.status =
        'posted';

  v_this_order :=
    greatest(
      coalesce(new.total,0) -
      v_invoiced_for_order,
      0
    );

  v_exposure :=
    round(
      v_receivables +
      v_other_orders +
      v_this_order,
      2
    );

  if v_exposure >
     v_limit + 0.01
  then
    raise exception
      'تم تجاوز حد ائتمان العميل. الحد: %، الانكشاف بعد الطلب: %',
      round(v_limit,2),
      round(v_exposure,2);
  end if;

  return new;
end;
$function$;

create or replace function public.fail_order_delivery(target_company uuid, target_order uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order_status text;
  v_delivery uuid;
begin
  if not public.has_permission(
    target_company,
    'deliveries.update'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Failure reason required';
  end if;

  select
    so.status

  into
    v_order_status

  from public.sales_orders so

  where so.id =
        target_order

    and so.company_id =
        target_company

  for update;

  if v_order_status is null then
    raise exception
      'Order not found';
  end if;

  select
    d.id

  into
    v_delivery

  from public.deliveries d

  where d.company_id =
        target_company

    and d.order_id =
        target_order

    and d.status =
        'out_for_delivery'

  order by
    d.created_at desc

  limit 1

  for update;

  if v_delivery is null then

    if exists (
      select 1

      from public.deliveries d

      where d.company_id =
            target_company

        and d.order_id =
            target_order

        and d.status =
            'failed'

        and d.failure_reason =
            trim(target_reason)
    ) then
      return;
    end if;

    raise exception
      'Active delivery not found';
  end if;

  if exists (
    select 1

    from public.sales_invoice_delivery_links l

    where l.delivery_id =
          v_delivery
  ) then
    raise exception
      'Delivered or invoiced delivery cannot be failed';
  end if;

  update public.deliveries
  set
    status =
      'failed',

    failed_at =
      now(),

    failed_by =
      auth.uid(),

    failure_reason =
      trim(target_reason),

    notes =
      coalesce(
        notes,
        nullif(
          trim(target_reason),
          ''
        )
      ),

    updated_at =
      now()

  where id =
        v_delivery;

  update public.sales_orders
  set
    status =
      'new',

    delivered_at =
      null,

    updated_at =
      now()

  where id =
        target_order

    and company_id =
        target_company;

  perform
    public.refresh_sales_order_inventory_status(
      target_order
    );
end;
$function$;

create or replace function public.get_deliveries_summary(target_company uuid)
 RETURNS TABLE(ready_count bigint, road_count bigint, road_units numeric, remaining_units numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'deliveries.view',
      'deliveries.update'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    (
      select count(*)::bigint
      from public.sales_orders so
      where so.company_id =
            target_company
        and so.status =
            'ready'
    ),

    (
      select count(*)::bigint
      from public.sales_orders so
      where so.company_id =
            target_company
        and so.status =
            'out_for_delivery'
    ),

    (
      select round(
        coalesce(
          sum(di.quantity),
          0
        ),
        3
      )
      from public.delivery_items di
      join public.deliveries d
        on d.id =
           di.delivery_id
      where d.company_id =
            target_company
        and d.status =
            'out_for_delivery'
    ),

    (
      select round(
        coalesce(
          sum(
            greatest(
              soi.quantity -
              coalesce(
                delivered.qty,
                0
              ) -
              coalesce(
                active.qty,
                0
              ),
              0
            )
          ),
          0
        ),
        3
      )

      from public.sales_order_items soi

      join public.sales_orders so
        on so.id =
           soi.order_id

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'delivered'
      ) delivered
        on true

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'out_for_delivery'
      ) active
        on true

      where so.company_id =
            target_company

        and so.status in (
          'ready',
          'out_for_delivery'
        )
    );
end;
$function$;

create or replace function public.get_delivery_queue(target_company uuid, target_search text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'deliveries.view',
      'deliveries.update'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_status :=
    case
      when target_status in (
        'ready',
        'out_for_delivery'
      )
      then target_status
      else null
    end;

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint

  into
    v_total

  from public.sales_orders so

  join public.traders t
    on t.id =
       so.trader_id

  where so.company_id =
        target_company

    and so.status in (
      'ready',
      'out_for_delivery'
    )

    and (
      v_status is null
      or so.status =
         v_status
    )

    and (
      v_search is null

      or t.name ilike
         '%' || v_search || '%'

      or coalesce(
           t.phone,
           ''
         ) ilike
         '%' || v_search || '%'

      or coalesce(
           t.whatsapp,
           ''
         ) ilike
         '%' || v_search || '%'

      or coalesce(
           t.area,
           ''
         ) ilike
         '%' || v_search || '%'

      or so.id::text ilike
         '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date,
          sort_created
      ),
      '[]'::jsonb
    )

  into
    v_rows

  from (
    select
      coalesce(
        so.ordered_at,
        so.created_at
      ) as sort_date,

      so.created_at as sort_created,

      jsonb_build_object(
        'id',
          so.id,

        'order_number',
          so.order_number,

        'status',
          so.status,

        'payment_status',
          so.payment_status,

        'total',
          so.total,

        'created_at',
          so.created_at,

        'ordered_at',
          so.ordered_at,

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name,

            'area',
              t.area,

            'address',
              t.address,

            'phone',
              t.phone,

            'whatsapp',
              t.whatsapp,

            'latitude',
              t.latitude,

            'longitude',
              t.longitude
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_orders so

    join public.traders t
      on t.id =
         so.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              soi.id,

            'product_id',
              soi.product_id,

            'quantity',
              soi.quantity,

            'sale_unit_price',
              soi.sale_unit_price,

            'product_name',
              p.name,

            'sku',
              p.sku,

            'unit',
              p.unit,

            'delivered_quantity',
              coalesce(
                delivered.qty,
                0
              ),

            'active_quantity',
              coalesce(
                active.qty,
                0
              ),

            'remaining_quantity',
              greatest(
                soi.quantity -
                coalesce(
                  delivered.qty,
                  0
                ) -
                coalesce(
                  active.qty,
                  0
                ),
                0
              )
          )
          order by
            soi.created_at
        ) as payload

      from public.sales_order_items soi

      join public.products p
        on p.id =
           soi.product_id

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'delivered'
      ) delivered
        on true

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'out_for_delivery'
      ) active
        on true

      where soi.order_id =
            so.id
    ) items
      on true

    where so.company_id =
          target_company

      and so.status in (
        'ready',
        'out_for_delivery'
      )

      and (
        v_status is null
        or so.status =
           v_status
      )

      and (
        v_search is null

        or t.name ilike
           '%' || v_search || '%'

        or coalesce(
             t.phone,
             ''
           ) ilike
           '%' || v_search || '%'

        or coalesce(
             t.whatsapp,
             ''
           ) ilike
           '%' || v_search || '%'

        or coalesce(
             t.area,
             ''
           ) ilike
           '%' || v_search || '%'

        or so.id::text ilike
           '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
      )

    order by
      coalesce(
        so.ordered_at,
        so.created_at
      ),
      so.created_at

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_orders_summary(target_company uuid)
 RETURNS TABLE(total_count bigint, active_count bigint, new_count bigint, ready_delivery_count bigint, total_active_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'orders.view'
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    count(*)::bigint,

    count(*) filter (
      where so.status <>
            'cancelled'
    )::bigint,

    count(*) filter (
      where so.status =
            'new'
    )::bigint,

    count(*) filter (
      where so.status in (
        'ready',
        'out_for_delivery'
      )
    )::bigint,

    round(
      coalesce(
        sum(so.total)
        filter (
          where so.status <>
                'cancelled'
        ),
        0
      ),
      2
    )

  from public.sales_orders so
  where so.company_id =
        target_company;
end;
$function$;

create or replace function public.sales_quote_matches(target_quote uuid, target_search text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- البحث بعروض الأسعار بكل شي: رقم العرض، الزبون (اسم، منطقة، هاتف)، الملاحظات،
  -- المبلغ، أو اسم/كود/ماركة صنف موجود بالعرض.
  select exists (
    select 1
    from public.sales_quotes q
    join public.traders t on t.id = q.trader_id
    where q.id = target_quote
      and (
        q.quote_number ilike '%' || target_search || '%'
        or t.name ilike '%' || target_search || '%'
        or coalesce(t.area, '') ilike '%' || target_search || '%'
        or coalesce(t.phone, '') ilike '%' || target_search || '%'
        or coalesce(t.whatsapp, '') ilike '%' || target_search || '%'
        or coalesce(q.notes, '') ilike '%' || target_search || '%'
        or q.total = case
          when replace(target_search, ',', '') ~ '^[0-9]+([.][0-9]+)?$'
            then replace(target_search, ',', '')::numeric
        end
        or exists (
          select 1
          from public.sales_quote_items qi
          join public.products p on p.id = qi.product_id
          where qi.quote_id = q.id
            and (
              p.name ilike '%' || target_search || '%'
              or coalesce(p.sku, '') ilike '%' || target_search || '%'
              or coalesce(p.brand, '') ilike '%' || target_search || '%'
            )
        )
      )
  )
$function$;

create or replace function public.get_quotes_queue(target_company uuid, target_search text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_today date;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_permission(
    target_company,
    'orders.view'
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_status :=
    case
      when target_status in (
        'draft',
        'sent',
        'accepted',
        'rejected',
        'cancelled',
        'converted',
        'expired'
      )
      then target_status
      else null
    end;

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  select
    count(*)::bigint

  into
    v_total

  from public.sales_quotes q

  join public.traders t
    on t.id =
       q.trader_id

  where q.company_id =
        target_company

    and (
      v_status is null

      or (
        v_status =
        'expired'

        and q.status in (
          'draft',
          'sent',
          'accepted'
        )

        and q.valid_until
            is not null

        and q.valid_until <
            v_today
      )

      or (
        v_status <>
        'expired'

        and q.status =
            v_status
      )
    )

    and (
        v_search is null
        or public.sales_quote_matches(q.id, v_search)
      );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_quote_date desc,
          sort_created_at desc
      ),
      '[]'::jsonb
    )

  into
    v_rows

  from (
    select
      q.quote_date
        as sort_quote_date,

      q.created_at
        as sort_created_at,

      jsonb_build_object(
        'id',
          q.id,

        'trader_id',
          q.trader_id,

        'quote_number',
          q.quote_number,

        'quote_date',
          q.quote_date,

        'valid_until',
          q.valid_until,

        'status',
          q.status,

        'currency',
          q.currency,

        'subtotal',
          q.subtotal,

        'total',
          q.total,

        'notes',
          q.notes,

        'accepted_at',
          q.accepted_at,

        'converted_order_id',
          q.converted_order_id,

        'created_at',
          q.created_at,

        'expired',
          (
            q.status in (
              'draft',
              'sent',
              'accepted'
            )
            and q.valid_until
                is not null
            and q.valid_until <
                v_today
          ),

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name,

            'area',
              t.area
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_quotes q

    join public.traders t
      on t.id =
         q.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              i.id,

            'product_id',
              i.product_id,

            'quantity',
              i.quantity,

            'sale_unit_price',
              i.sale_unit_price,

            'line_total',
              i.line_total,

            'product_name',
              p.name,

            'sku',
              p.sku,

            'unit',
              p.unit
          )
          order by
            i.created_at
        ) as payload

      from public.sales_quote_items i

      join public.products p
        on p.id =
           i.product_id

      where i.quote_id =
            q.id
    ) items
      on true

    where q.company_id =
          target_company

      and (
        v_status is null

        or (
          v_status =
          'expired'

          and q.status in (
            'draft',
            'sent',
            'accepted'
          )

          and q.valid_until
              is not null

          and q.valid_until <
              v_today
        )

        or (
          v_status <>
          'expired'

          and q.status =
              v_status
        )
      )

      and (
        v_search is null
        or public.sales_quote_matches(q.id, v_search)
      )

    order by
      q.quote_date desc,
      q.created_at desc

    limit v_limit
    offset v_offset
  ) q_rows;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_quotes_summary(target_company uuid)
 RETURNS TABLE(all_count bigint, open_count bigint, accepted_count bigint, converted_count bigint, expired_open_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date;
begin
  if not public.has_permission(
    target_company,
    'orders.view'
  ) then
    raise exception 'Not allowed';
  end if;

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  return query
  select
    count(*)::bigint,

    count(*) filter (
      where q.status in (
        'draft',
        'sent'
      )
    )::bigint,

    count(*) filter (
      where q.status =
            'accepted'
    )::bigint,

    count(*) filter (
      where q.status =
            'converted'
    )::bigint,

    count(*) filter (
      where q.status in (
        'draft',
        'sent',
        'accepted'
      )
        and q.valid_until
            is not null
        and q.valid_until <
            v_today
    )::bigint

  from public.sales_quotes q

  where q.company_id =
        target_company;
end;
$function$;

create or replace function public.get_trader_sales_summary(target_company uuid, target_trader uuid)
 RETURNS TABLE(invoice_count bigint, total_invoiced numeric, outstanding numeric, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'sales_invoices.view',
      'payments.sales_view',
      'payments.sales_create',
      'traders.view_balance',
      'reports.sales',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.traders t
    where t.id = target_trader
      and t.company_id = target_company
  ) then
    raise exception 'Trader not found';
  end if;

  select upper(
    coalesce(c.default_currency,'USD')
  )
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  return query
  select
    count(si.id)::bigint,

    round(
      coalesce(sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),0),
      2
    )::numeric,

    round(
      coalesce(sum((si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),0),
      2
    )::numeric,

    v_currency
  from public.sales_invoices si
  where si.company_id = target_company
    and si.trader_id = target_trader
    and si.status = 'posted';
end;
$function$;

create or replace function public.next_customer_payment_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin

  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );


  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'customer_payment',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;


  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'customer_payment'
    and sequence_year = v_year
  for update;


  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'customer_payment'
    and sequence_year = v_year;


  return
    'CP-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text,6,'0');

end;
$function$;

create or replace function public.next_delivery_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'delivery_note',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'delivery_note'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'delivery_note'
    and sequence_year = v_year;

  return
    'DN-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text,6,'0');
end;
$function$;

create or replace function public.next_sales_invoice_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin

  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );


  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'sales_invoice',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;


  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'sales_invoice'
    and sequence_year = v_year
  for update;


  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'sales_invoice'
    and sequence_year = v_year;


  return
    'SI-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text,6,'0');

end;
$function$;

create or replace function public.next_sales_order_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer := extract(year from coalesce(target_date, current_date))::integer;
  v_value integer;
begin
  insert into public.document_sequences(company_id, document_type, sequence_year, next_value)
  values(target_company, 'sales_order', v_year, 1)
  on conflict(company_id, document_type, sequence_year) do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'sales_order'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'sales_order'
    and sequence_year = v_year;

  return 'SO-' || v_year::text || '-' || lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.assign_sales_order_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- كل طلبية بتاخد رقم مقروء (SO-2026-000001) بدل ما تنعرض بجزء من الـ UUID.
  if new.order_number is null then
    new.order_number := public.next_sales_order_number(
      new.company_id,
      (coalesce(new.ordered_at, now()) at time zone 'Asia/Damascus')::date
    );
  end if;
  return new;
end;
$function$;

create or replace function public.next_sales_quote_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer := extract(year from coalesce(target_date,current_date))::integer;
  v_value integer;
begin
  insert into public.document_sequences(company_id,document_type,sequence_year,next_value)
  values(target_company,'sales_quote',v_year,1)
  on conflict(company_id,document_type,sequence_year) do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'sales_quote'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'sales_quote'
    and sequence_year = v_year;

  return 'Q-' || v_year::text || '-' || lpad(v_value::text,6,'0');
end;
$function$;

create or replace function public.recalc_sales_invoice_payment(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total numeric(18,2);
  v_paid numeric(18,2);
  v_returns numeric(18,2);
  v_balance numeric(18,2);
  v_order uuid;
begin
  select
    total,
    order_id
  into
    v_total,
    v_order
  from public.sales_invoices
  where id =
        target_invoice;

  if v_total is null then
    return;
  end if;

  select
    coalesce(
      sum(a.amount),
      0
    )
  into v_paid
  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id =
       a.payment_id

  where a.sales_invoice_id =
        target_invoice

    and p.status =
        'posted';

  select
    coalesce(
      sum(sr.total),
      0
    )
  into v_returns
  from public.sales_returns sr
  where sr.sales_invoice_id =
        target_invoice
    and sr.status =
        'posted';

  v_balance :=
    greatest(
      round(
        v_total -
        v_paid -
        v_returns,
        2
      ),
      0
    );

  update public.sales_invoices
  set
    paid_total =
      round(
        v_paid,
        2
      ),

    balance_due =
      v_balance,

    payment_status =
      case
        when v_balance <= 0.009
          then 'paid'

        when (
          v_paid +
          v_returns
        ) > 0
          then 'partial'

        else 'unpaid'
      end

  where id =
        target_invoice;

  if v_order is not null then
    perform
      public.recalc_sales_order_payment(
        v_order
      );
  end if;
end;
$function$;

create or replace function public.recalc_sales_order(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_subtotal numeric(14,2);
  v_discount numeric(14,2);
begin
  select coalesce(sum(quantity * sale_unit_price),0)
  into v_subtotal
  from public.sales_order_items
  where order_id = target_order;

  select coalesce(discount_total,0)
  into v_discount
  from public.sales_orders
  where id = target_order;

  update public.sales_orders
  set
    subtotal = round(v_subtotal,2),
    total = round(greatest(v_subtotal - v_discount,0),2),
    updated_at = now()
  where id = target_order;
end;
$function$;

create or replace function public.recalc_sales_order_payment(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order_total numeric(18,2);
  v_paid numeric(18,2);
  v_returns numeric(18,2);
  v_settled numeric(18,2);
begin
  select total
  into v_order_total
  from public.sales_orders
  where id = target_order;

  if v_order_total is null then
    return;
  end if;

  select
    coalesce(
      sum(a.amount),
      0
    )
  into v_paid
  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id =
       a.payment_id

  join public.sales_invoices si
    on si.id =
       a.sales_invoice_id

  where si.order_id =
        target_order

    and si.status =
        'posted'

    and p.status =
        'posted';

  select
    coalesce(
      sum(sr.total),
      0
    )
  into v_returns
  from public.sales_returns sr

  join public.sales_invoices si
    on si.id =
       sr.sales_invoice_id

  where si.order_id =
        target_order

    and si.status =
        'posted'

    and sr.status =
        'posted';

  v_settled :=
    round(
      v_paid +
      v_returns,
      2
    );

  update public.sales_orders
  set
    payment_status =
      case
        when v_settled >=
             v_order_total - 0.009
          then 'paid'

        when v_settled > 0
          then 'partial'

        else 'unpaid'
      end,

    paid_at =
      case
        when v_settled >=
             v_order_total - 0.009
          then coalesce(
            paid_at,
            now()
          )

        else null
      end

  where id =
        target_order;
end;
$function$;

create or replace function public.record_customer_payment(target_company uuid, target_trader uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text, allocations_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;

  v_method text;

  v_base_currency text;
  v_payment_currency text;
  v_payment_rate numeric(24,10);
  v_base_amount numeric(20,4);

  v_allocation jsonb;

  v_invoice uuid;
  v_alloc_amount numeric(20,2);
  v_payment_alloc_amount numeric(20,2);

  v_balance numeric(20,2);
  v_invoice_status text;
  v_invoice_trader uuid;
  v_invoice_currency text;
  v_order uuid;

  v_allocated_payment_sum numeric(20,2) := 0;

  v_allocation_count integer := 0;
  v_single_order uuid := null;
begin
  if not public.has_permission(
    target_company,
    'payments.sales_create'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid payment amount';
  end if;

  if not exists(
    select 1
    from public.traders
    where id =
          target_trader
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid trader';
  end if;

  v_method :=
    coalesce(
      nullif(
        trim(target_method),
        ''
      ),
      'cash'
    );

  if v_method not in (
    'cash',
    'bank',
    'card',
    'check',
    'other'
  ) then
    raise exception
      'Invalid payment method';
  end if;

  target_payment_date :=
    coalesce(
      target_payment_date,
      current_date
    );

  if target_cashbox is not null then

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.id =
          target_cashbox
      and cb.company_id =
          target_company
      and cb.active = true;

  else

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.company_id =
          target_company
      and cb.active = true

    order by
      case
        when upper(cb.currency) =
             upper(c.default_currency)
          then 0
        else 1
      end,
      cb.created_at

    limit 1;

  end if;

  if v_cashbox is null then
    raise exception
      'No valid active cashbox';
  end if;

  v_payment_rate :=
    public.finance_rate_to_base(
      target_company,
      v_payment_currency,
      target_payment_date
    );

  v_base_amount :=
    round(
      target_amount *
      v_payment_rate,
      4
    );

  if jsonb_typeof(
       coalesce(
         allocations_payload,
         '[]'::jsonb
       )
     ) <> 'array'
  then
    raise exception
      'Invalid allocations payload';
  end if;

  v_number :=
    public.next_customer_payment_number(
      target_company,
      target_payment_date
    );

  insert into public.customer_payments(
    company_id,
    trader_id,
    cashbox_id,
    payment_number,
    status,
    payment_date,
    amount,
    allocated_total,
    unallocated_total,
    payment_method,
    reference_number,
    notes,
    payment_currency,
    exchange_rate_to_base,
    base_amount
  )
  values(
    target_company,
    target_trader,
    v_cashbox,
    v_number,
    'posted',
    target_payment_date,
    round(
      target_amount,
      2
    ),
    0,
    round(
      target_amount,
      2
    ),
    v_method,
    nullif(
      trim(target_reference),
      ''
    ),
    nullif(
      trim(target_notes),
      ''
    ),
    v_payment_currency,
    v_payment_rate,
    v_base_amount
  )
  returning id
  into v_payment;


  for v_allocation in

    select value
    from jsonb_array_elements(
      coalesce(
        allocations_payload,
        '[]'::jsonb
      )
    )

  loop

    begin
      v_invoice :=
        nullif(
          v_allocation ->
          'sales_invoice_id' #>> '{}',
          ''
        )::uuid;

      v_alloc_amount :=
        nullif(
          v_allocation ->
          'amount' #>> '{}',
          ''
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid payment allocation';
    end;

    if v_invoice is null
       or v_alloc_amount is null
       or v_alloc_amount <= 0
    then
      raise exception
        'Invalid payment allocation';
    end if;

    select
      balance_due,
      status,
      trader_id,
      upper(currency),
      order_id

    into
      v_balance,
      v_invoice_status,
      v_invoice_trader,
      v_invoice_currency,
      v_order

    from public.sales_invoices

    where id =
          v_invoice
      and company_id =
          target_company

    for update;

    if v_balance is null then
      raise exception
        'Sales invoice not found';
    end if;

    if v_invoice_status <>
       'posted'
    then
      raise exception
        'Cannot pay cancelled or unposted invoice';
    end if;

    if v_invoice_trader <>
       target_trader
    then
      raise exception
        'Invoice belongs to another trader';
    end if;

    if round(
         v_alloc_amount,
         2
       ) >
       round(
         v_balance,
         2
       )
    then
      raise exception
        'Allocation exceeds invoice balance';
    end if;


    if v_invoice_currency =
       v_payment_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount,
          2
        );

    elsif v_invoice_currency =
          v_base_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount /
          v_payment_rate,
          2
        );

    else

      raise exception
        'Cross-currency settlement currently requires invoice currency to be company base currency';

    end if;


    v_allocated_payment_sum :=
      round(
        v_allocated_payment_sum +
        v_payment_alloc_amount,
        2
      );

    if v_allocated_payment_sum >
       round(
         target_amount,
         2
       ) + 0.01
    then
      raise exception
        'Allocations exceed payment amount after currency conversion';
    end if;


    insert into public.customer_payment_allocations(
      company_id,
      payment_id,
      sales_invoice_id,
      amount,
      payment_amount,
      payment_currency,
      invoice_currency,
      payment_rate_to_base
    )
    values(
      target_company,
      v_payment,
      v_invoice,
      round(
        v_alloc_amount,
        2
      ),
      v_payment_alloc_amount,
      v_payment_currency,
      v_invoice_currency,
      v_payment_rate
    );


    v_allocation_count :=
      v_allocation_count + 1;

    if v_allocation_count = 1 then
      v_single_order :=
        v_order;

    elsif v_single_order is distinct from
          v_order
    then
      v_single_order :=
        null;
    end if;

  end loop;


  perform
    public.refresh_customer_payment_totals(
      v_payment
    );


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    order_id,
    trader_id,
    customer_payment_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    'in',
    'sale_receipt',
    round(
      target_amount,
      2
    ),
    v_single_order,
    target_trader,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'قبض عميل ' ||
      v_number
    ),
    target_payment_date::timestamptz
  );

  return v_payment;
end;
$function$;

create or replace function public.refresh_customer_payment_totals(target_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_amount numeric(20,2);
  v_allocated numeric(20,2);
begin
  select amount
  into v_amount
  from public.customer_payments
  where id =
        target_payment
  for update;

  if v_amount is null then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          coalesce(
            payment_amount,
            amount
          )
        ),
        0
      ),
      2
    )
  into v_allocated
  from public.customer_payment_allocations
  where payment_id =
        target_payment;

  if v_allocated >
     round(
       v_amount,
       2
     ) + 0.01
  then
    raise exception
      'Payment allocations exceed cash payment amount';
  end if;

  update public.customer_payments
  set
    allocated_total =
      round(
        v_allocated,
        2
      ),

    unallocated_total =
      greatest(
        round(
          v_amount -
          v_allocated,
          2
        ),
        0
      )

  where id =
        target_payment;
end;
$function$;

create or replace function public.refresh_sales_order_inventory_status(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_total integer;
  v_covered integer;
  v_has_purchase boolean;
begin
  select status
  into v_status
  from public.sales_orders
  where id = target_order;

  if v_status is null
     or v_status in (
       'cancelled',
       'delivered'
     )
  then
    return;
  end if;

  if v_status = 'out_for_delivery'
     and exists (
       select 1
       from public.deliveries d
       where d.order_id =
             target_order
         and d.status =
             'out_for_delivery'
     )
  then
    return;
  end if;

  select
    count(*),
    count(*) filter (
      where
        coalesce(delivered.qty,0) +
        coalesce(reserved.qty,0)
        >= soi.quantity
    )
  into
    v_total,
    v_covered
  from public.sales_order_items soi

  left join lateral (
    select
      coalesce(
        sum(di.quantity),
        0
      ) as qty
    from public.delivery_items di
    join public.deliveries d
      on d.id = di.delivery_id
    where di.sales_order_item_id =
          soi.id
      and d.status =
          'delivered'
  ) delivered on true

  left join lateral (
    select
      coalesce(
        sum(ir.quantity),
        0
      ) as qty
    from public.inventory_reservations ir
    where ir.sales_order_item_id =
          soi.id
      and ir.status =
          'active'
  ) reserved on true

  where soi.order_id =
        target_order;

  if v_total > 0
     and v_covered = v_total
  then
    update public.sales_orders
    set status = 'ready'
    where id = target_order
      and status not in (
        'cancelled',
        'delivered',
        'out_for_delivery'
      );

    return;
  end if;

  select exists (
    select 1
    from public.sales_order_items soi

    join public.purchase_invoice_item_sources src
      on src.sales_order_item_id =
         soi.id

    join public.purchase_invoice_items pii
      on pii.id =
         src.purchase_invoice_item_id

    join public.purchase_invoices pi
      on pi.id =
         pii.invoice_id

    where soi.order_id =
          target_order

      and pi.status <>
          'cancelled'
  )
  into v_has_purchase;

  update public.sales_orders
  set status =
    case
      when v_has_purchase
        then 'purchasing'
      else 'to_purchase'
    end
  where id = target_order
    and status not in (
      'cancelled',
      'delivered',
      'out_for_delivery'
    );
end;
$function$;

create or replace function public.reserve_pending_orders_for_product(target_company uuid, target_warehouse uuid, target_product uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_on_hand numeric(18,3);
  v_warehouse_reserved numeric(18,3);
  v_available numeric(18,3);

  v_row record;
  v_delivered numeric(18,3);
  v_reserved numeric(18,3);
  v_need numeric(18,3);
  v_take numeric(18,3);
begin
  select s.on_hand
  into v_on_hand
  from public.inventory_stock s
  where s.company_id =
        target_company
    and s.warehouse_id =
        target_warehouse
    and s.product_id =
        target_product
  for update;

  if v_on_hand is null then
    return;
  end if;

  select
    coalesce(
      sum(ir.quantity),
      0
    )
  into v_warehouse_reserved
  from public.inventory_reservations ir
  where ir.company_id =
        target_company
    and ir.warehouse_id =
        target_warehouse
    and ir.product_id =
        target_product
    and ir.status =
        'active';

  v_available :=
    greatest(
      v_on_hand -
      v_warehouse_reserved,
      0
    );

  if v_available <= 0 then
    return;
  end if;

  for v_row in
    select
      soi.id as order_item_id,
      soi.quantity,
      so.id as order_id
    from public.sales_order_items soi

    join public.sales_orders so
      on so.id = soi.order_id

    where so.company_id =
          target_company

      and soi.product_id =
          target_product

      and so.status in (
        'new',
        'to_purchase',
        'purchasing',
        'ready'
      )

    order by
      so.ordered_at,
      so.created_at,
      soi.created_at
  loop
    exit when v_available <= 0;

    select
      coalesce(
        sum(di.quantity),
        0
      )
    into v_delivered
    from public.delivery_items di

    join public.deliveries d
      on d.id =
         di.delivery_id

    where di.sales_order_item_id =
          v_row.order_item_id

      and d.status =
          'delivered';

    select
      coalesce(
        sum(ir.quantity),
        0
      )
    into v_reserved
    from public.inventory_reservations ir
    where ir.sales_order_item_id =
          v_row.order_item_id
      and ir.status =
          'active';

    v_need :=
      greatest(
        v_row.quantity -
        v_delivered -
        v_reserved,
        0
      );

    if v_need <= 0 then
      continue;
    end if;

    v_take :=
      least(
        v_need,
        v_available
      );

    insert into public.inventory_reservations(
      company_id,
      warehouse_id,
      product_id,
      sales_order_item_id,
      quantity,
      status
    )
    values(
      target_company,
      target_warehouse,
      target_product,
      v_row.order_item_id,
      v_take,
      'active'
    )
    on conflict(
      warehouse_id,
      sales_order_item_id
    )
    do update set
      quantity =
        case
          when public.inventory_reservations.status =
               'active'
          then
            public.inventory_reservations.quantity +
            excluded.quantity
          else
            excluded.quantity
        end,

      status = 'active',
      released_at = null;

    v_available :=
      v_available -
      v_take;
  end loop;

  for v_row in
    select distinct
      so.id as order_id
    from public.sales_orders so
    join public.sales_order_items soi
      on soi.order_id = so.id
    where so.company_id =
          target_company
      and soi.product_id =
          target_product
      and so.status in (
        'new',
        'to_purchase',
        'purchasing',
        'ready'
      )
  loop
    perform
      public.refresh_sales_order_inventory_status(
        v_row.order_id
      );
  end loop;
end;
$function$;

create or replace function public.reserve_sales_order(target_company uuid, target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_product record;
  v_warehouse record;
begin
  for v_product in
    select distinct
      soi.product_id
    from public.sales_order_items soi
    where soi.order_id =
          target_order
  loop
    for v_warehouse in
      select
        w.id
      from public.warehouses w
      where w.company_id =
            target_company
        and w.active = true
      order by
        w.is_default desc,
        w.created_at
    loop
      perform
        public.reserve_pending_orders_for_product(
          target_company,
          v_warehouse.id,
          v_product.product_id
        );
    end loop;
  end loop;

  perform
    public.refresh_sales_order_inventory_status(
      target_order
    );
end;
$function$;

create or replace function public.reverse_customer_payment(target_company uuid, target_payment uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_cashbox uuid;
  v_amount numeric(14,2);
  v_trader uuid;
  v_number text;
begin

  if not public.has_permission(
    target_company,
    'payments.sales_reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    status,
    cashbox_id,
    amount,
    trader_id,
    payment_number

  into
    v_status,
    v_cashbox,
    v_amount,
    v_trader,
    v_number

  from public.customer_payments

  where id = target_payment
    and company_id = target_company

  for update;


  if v_status is null then
    raise exception
      'Customer payment not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if nullif(
    trim(target_reason),
    ''
  ) is null
  then
    raise exception
      'Reversal reason required';
  end if;


  update public.customer_payments
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason)

  where id = target_payment;


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    trader_id,
    customer_payment_id,
    notes
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'customer_payment_reversal',
    v_amount,
    v_trader,
    target_payment,
    'عكس دفعة تاجر ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$function$;

create or replace function public.sales_order_items_recalc_after_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    perform public.recalc_sales_order(old.order_id);
    return old;
  end if;

  perform public.recalc_sales_order(new.order_id);
  return new;
end;
$function$;

create or replace function public.set_sales_order_item_line_total()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.line_total := round(new.quantity * new.sale_unit_price, 2);
  return new;
end;
$function$;

create or replace function public.set_sales_quote_status(target_company uuid, target_quote uuid, target_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current text;
  v_valid_until date;
begin
  if not public.has_permission(
    target_company,
    'orders.update'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_status not in (
    'sent',
    'accepted',
    'rejected',
    'cancelled'
  ) then
    raise exception 'Invalid quote status';
  end if;

  select
    status,
    valid_until
  into
    v_current,
    v_valid_until
  from public.sales_quotes
  where id = target_quote
    and company_id = target_company
  for update;

  if not found then
    raise exception 'Quote not found';
  end if;

  if v_current = 'draft' then

    if target_status not in (
      'sent',
      'cancelled'
    ) then
      raise exception
        'Invalid quote status transition';
    end if;

  elsif v_current = 'sent' then

    if target_status not in (
      'accepted',
      'rejected',
      'cancelled'
    ) then
      raise exception
        'Invalid quote status transition';
    end if;

  elsif v_current = 'accepted' then

    if target_status <> 'cancelled' then
      raise exception
        'Invalid quote status transition';
    end if;

  else
    raise exception
      'Quote status cannot be changed';
  end if;

  if target_status = 'accepted'
     and v_valid_until is not null
     and v_valid_until <
         (
           now()
           at time zone
           'Asia/Damascus'
         )::date
  then
    raise exception
      'Quote has expired';
  end if;

  update public.sales_quotes
  set
    status =
      target_status,

    accepted_at =
      case
        when target_status =
             'accepted'
          then now()
        else accepted_at
      end

  where id =
        target_quote

    and company_id =
        target_company;
end;
$function$;

create or replace function public.validate_sales_quote_conversion_source(target_company uuid, target_quote uuid, target_trader uuid, items_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_trader uuid;
  v_valid_until date;
  v_converted uuid;
  v_expected jsonb;
  v_actual jsonb;
begin
  select
    q.status,
    q.trader_id,
    q.valid_until,
    q.converted_order_id
  into
    v_status,
    v_trader,
    v_valid_until,
    v_converted
  from public.sales_quotes q
  where q.id = target_quote
    and q.company_id = target_company
  for update;

  if not found then
    raise exception 'Quote not found';
  end if;

  if v_converted is not null
     or v_status = 'converted'
  then
    raise exception 'Quote already converted';
  end if;

  if v_status <> 'accepted' then
    raise exception
      'Quote must be accepted first';
  end if;

  if v_valid_until is not null
     and v_valid_until <
         (
           now()
           at time zone
           'Asia/Damascus'
         )::date
  then
    raise exception 'Quote has expired';
  end if;

  if v_trader <> target_trader then
    raise exception
      'Quote trader mismatch';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception
      'Invalid quote order payload';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'product_id',
          i.product_id,

        'quantity',
          i.quantity,

        'sale_unit_price',
          i.sale_unit_price
      )
      order by
        i.product_id::text
    )
  into
    v_expected
  from public.sales_quote_items i
  where i.quote_id =
        target_quote;

  begin
    select
      jsonb_agg(
        jsonb_build_object(
          'product_id',
            (x->>'product_id')::uuid,

          'quantity',
            (x->>'quantity')::numeric,

          'sale_unit_price',
            (x->>'sale_unit_price')::numeric
        )
        order by
          (x->>'product_id')
      )
    into
      v_actual
    from jsonb_array_elements(
      items_payload
    ) x;

  exception
    when others then
      raise exception
        'Invalid quote order payload';
  end;

  if v_expected is null
     or v_actual is null
     or v_expected <> v_actual
  then
    raise exception
      'Order payload does not match quote';
  end if;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.inventory_summary as
 select s.company_id,
    s.warehouse_id,
    w.name as warehouse_name,
    s.product_id,
    p.sku,
    p.name as product_name,
    p.unit,
    round(s.on_hand, 3) as on_hand,
    round(coalesce(( select sum(r.quantity) as sum
           from public.inventory_reservations r
          where r.company_id = s.company_id and r.warehouse_id = s.warehouse_id and r.product_id = s.product_id and r.status = 'active'::text), 0::numeric), 3) as reserved,
    round(greatest(s.on_hand - coalesce(( select sum(r.quantity) as sum
           from public.inventory_reservations r
          where r.company_id = s.company_id and r.warehouse_id = s.warehouse_id and r.product_id = s.product_id and r.status = 'active'::text), 0::numeric), 0::numeric), 3) as available,
        case
            when public.can_view_inventory_cost(s.company_id) then round(s.average_cost, 4)
            else null::numeric
        end as average_cost,
        case
            when public.can_view_inventory_cost(s.company_id) then round(s.on_hand * s.average_cost, 2)
            else null::numeric
        end as stock_value,
    s.updated_at
   from public.inventory_stock s
     join public.warehouses w on w.id = s.warehouse_id
     join public.products p on p.id = s.product_id
  where public.has_any_permission(s.company_id, array['inventory.view'::text, 'inventory.adjust'::text, 'inventory.returns'::text, 'purchases.view'::text, 'purchase_invoices.view'::text, 'reports.finance'::text, 'reports.profit'::text]);


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger sales_orders_assign_number before insert on public.sales_orders for each row execute function public.assign_sales_order_number();
create trigger audit_customer_payment_allocations after insert or delete or update on public.customer_payment_allocations for each row execute function public.write_audit_log();

create trigger customer_payment_allocation_changed_trigger after insert or delete or update on public.customer_payment_allocations for each row execute function public.customer_payment_allocation_changed();

create trigger audit_customer_payments after insert or delete or update on public.customer_payments for each row execute function public.write_audit_log();

create trigger customer_payment_status_changed_trigger after update of status on public.customer_payments for each row execute function public.customer_payment_status_changed();

create trigger customer_payments_updated_at before update on public.customer_payments for each row execute function public.set_updated_at();

create trigger audit_deliveries after insert or delete or update on public.deliveries for each row execute function public.write_audit_log();

create trigger deliveries_updated_at before update on public.deliveries for each row execute function public.set_updated_at();

create trigger audit_inventory_reservations after insert or delete or update on public.inventory_reservations for each row execute function public.write_audit_log();

create trigger audit_sales_invoice_items after insert or delete or update on public.sales_invoice_items for each row execute function public.write_audit_log();

create trigger audit_sales_invoices after insert or delete or update on public.sales_invoices for each row execute function public.write_audit_log();

create trigger sales_invoice_payment_terms before insert on public.sales_invoices for each row execute function public.apply_customer_payment_terms();

create trigger sales_invoices_updated_at before update on public.sales_invoices for each row execute function public.set_updated_at();

create trigger sales_order_items_line_total_before before insert or update of quantity, sale_unit_price on public.sales_order_items for each row execute function public.set_sales_order_item_line_total();

create trigger sales_order_items_recalc_after after insert or delete or update on public.sales_order_items for each row execute function public.sales_order_items_recalc_after_trigger();

create trigger audit_sales_orders after insert or delete or update on public.sales_orders for each row execute function public.write_audit_log();

create trigger sales_orders_credit_limit_guard before insert or update of trader_id, total on public.sales_orders for each row execute function public.enforce_sales_order_credit_limit();

create trigger sales_orders_updated_at before update on public.sales_orders for each row execute function public.set_updated_at();

create trigger audit_sales_quotes after insert or delete or update on public.sales_quotes for each row execute function public.write_audit_log();

create trigger sales_quotes_updated_at before update on public.sales_quotes for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.sales_quotes enable row level security;
alter table public.sales_quote_items enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_items enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;
alter table public.sales_invoice_delivery_links enable row level security;
alter table public.customer_payments enable row level security;
alter table public.customer_payment_allocations enable row level security;
create policy customer_payment_allocations_read on public.customer_payment_allocations
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'reports.finance'::text]));
create policy customer_payments_read on public.customer_payments
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'finance.cashbox_view'::text, 'finance.accounts_view'::text, 'reports.finance'::text]));
create policy deliveries_read on public.deliveries
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'deliveries.update'::text]));
create policy delivery_items_read on public.delivery_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'deliveries.update'::text, 'orders.view'::text, 'sales_invoices.view'::text]));
create policy inventory_reservations_read on public.inventory_reservations
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'orders.view'::text, 'deliveries.view'::text]));
create policy sales_invoice_delivery_links_read on public.sales_invoice_delivery_links
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'orders.view'::text, 'sales_invoices.view'::text, 'payments.sales_view'::text]));
create policy sales_invoice_items_read on public.sales_invoice_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['sales_invoices.view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'traders.view_balance'::text, 'reports.sales'::text, 'reports.profit'::text]));
create policy sales_invoices_read on public.sales_invoices
  for select to authenticated
  using (public.has_any_permission(company_id, array['sales_invoices.view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'traders.view_balance'::text, 'reports.sales'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy sales_order_items_read on public.sales_order_items
  for select to authenticated
  using (public.can_access_order(order_id));
create policy sales_orders_create on public.sales_orders
  for insert to authenticated
  with check (public.has_permission(company_id, 'orders.create'::text));
create policy sales_orders_read on public.sales_orders
  for select to authenticated
  using (public.has_any_permission(company_id, array['orders.view'::text, 'deliveries.view'::text, 'payments.sales_view'::text, 'reports.sales'::text, 'reports.profit'::text, 'reports.finance'::text]));
create policy sales_orders_update on public.sales_orders
  for update to authenticated
  using (public.has_permission(company_id, 'orders.update'::text))
  with check (public.has_permission(company_id, 'orders.update'::text));
create policy sales_quote_items_read on public.sales_quote_items
  for select to authenticated
  using ((exists ( select 1
   from public.sales_quotes q
  where ((q.id = sales_quote_items.quote_id) and public.has_permission(q.company_id, 'orders.view'::text)))));
create policy sales_quotes_read on public.sales_quotes
  for select to authenticated
  using (public.has_permission(company_id, 'orders.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.sales_quotes from authenticated;
revoke select, insert, update, delete on public.sales_quote_items from authenticated;
grant select (id, quote_id, product_id, quantity, sale_unit_price, line_total, minimum_sale_price_snapshot, created_at) on public.sales_quote_items to authenticated;
revoke insert, update, delete on public.inventory_reservations from authenticated;
revoke insert, update, delete on public.deliveries from authenticated;
revoke insert, update, delete on public.delivery_items from authenticated;
revoke insert, update, delete on public.sales_invoices from authenticated;
revoke insert, update, delete on public.sales_invoice_items from authenticated;
revoke insert, update, delete on public.sales_invoice_delivery_links from authenticated;
revoke insert, update, delete on public.customer_payments from authenticated;
revoke insert, update, delete on public.customer_payment_allocations from authenticated;
revoke execute on function public.apply_customer_credit_to_invoice(uuid) from authenticated;
revoke execute on function public.next_customer_payment_number(uuid,date) from authenticated;
revoke execute on function public.next_delivery_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_invoice_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_quote_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_order_number(uuid,date) from authenticated;
revoke execute on function public.assign_sales_order_number() from authenticated;
revoke execute on function public.recalc_sales_invoice_payment(uuid) from authenticated;
revoke execute on function public.recalc_sales_order(uuid) from authenticated;
revoke execute on function public.recalc_sales_order_payment(uuid) from authenticated;
revoke execute on function public.refresh_customer_payment_totals(uuid) from authenticated;
revoke execute on function public.refresh_sales_order_inventory_status(uuid) from authenticated;
revoke execute on function public.reserve_pending_orders_for_product(uuid,uuid,uuid) from authenticated;
revoke execute on function public.reserve_sales_order(uuid,uuid) from authenticated;
revoke execute on function public.sales_quote_matches(uuid,text) from authenticated;
revoke execute on function public.validate_sales_quote_conversion_source(uuid,uuid,uuid,jsonb) from authenticated;

-- ======================================================================
-- المشتريات
-- فواتير الشراء، استلام البضاعة، الدفع للموردين
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  invoice_number text not null,
  supplier_invoice_number text,
  status text default 'posted'::text not null,
  payment_status text default 'unpaid'::text not null,
  currency text default 'USD'::text not null,
  invoice_date date default current_date not null,
  due_date date,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  tax_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  paid_total numeric(14,2) default 0 not null,
  balance_due numeric(14,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint purchase_invoices_company_id_invoice_number_key unique (company_id, invoice_number),
  constraint purchase_invoices_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint purchase_invoices_check check (((due_date is null) or (due_date >= invoice_date))),
  constraint purchase_invoices_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint purchase_invoices_paid_total_check check ((paid_total >= (0)::numeric)),
  constraint purchase_invoices_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text]))),
  constraint purchase_invoices_status_check check ((status = any (array['draft'::text, 'posted'::text, 'cancelled'::text]))),
  constraint purchase_invoices_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint purchase_invoices_tax_total_check check ((tax_total >= (0)::numeric)),
  constraint purchase_invoices_total_check check ((total >= (0)::numeric))
);
create index purchase_invoices_company_date_idx on public.purchase_invoices using btree (company_id, invoice_date desc, created_at desc);
create index purchase_invoices_due_idx on public.purchase_invoices using btree (company_id, due_date) where ((status = 'posted'::text) and (payment_status <> 'paid'::text));
create index purchase_invoices_supplier_idx on public.purchase_invoices using btree (supplier_id, invoice_date desc);
create unique index purchase_invoices_supplier_number_unique on public.purchase_invoices using btree (company_id, supplier_id, supplier_invoice_number) where ((supplier_invoice_number is not null) and (status <> 'cancelled'::text));

create table public.purchase_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.purchase_invoices(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  description text,
  quantity numeric(14,3) not null,
  unit_cost numeric(14,2) not null,
  discount_amount numeric(14,2) default 0 not null,
  tax_amount numeric(14,2) default 0 not null,
  line_total numeric(14,2) not null,
  notes text,
  created_at timestamp with time zone default now() not null,
  constraint purchase_invoice_items_discount_amount_check check ((discount_amount >= (0)::numeric)),
  constraint purchase_invoice_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint purchase_invoice_items_quantity_check check ((quantity > (0)::numeric)),
  constraint purchase_invoice_items_tax_amount_check check ((tax_amount >= (0)::numeric)),
  constraint purchase_invoice_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index purchase_invoice_items_invoice_idx on public.purchase_invoice_items using btree (invoice_id);
create index purchase_invoice_items_product_idx on public.purchase_invoice_items using btree (company_id, product_id);

create table public.purchase_invoice_item_sources (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete cascade,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  quantity numeric(14,3) not null,
  created_at timestamp with time zone default now() not null,
  constraint purchase_invoice_item_sources_purchase_invoice_item_id_sale_key unique (purchase_invoice_item_id, sales_order_item_id),
  constraint purchase_invoice_item_sources_quantity_check check ((quantity > (0)::numeric))
);
create index purchase_invoice_sources_order_item_idx on public.purchase_invoice_item_sources using btree (sales_order_item_id);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_invoice_id uuid references public.purchase_invoices(id) on delete restrict,
  receipt_number text not null,
  status text default 'posted'::text not null,
  receipt_date date default current_date not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  constraint goods_receipts_company_id_receipt_number_key unique (company_id, receipt_number),
  constraint goods_receipts_status_check check ((status = any (array['posted'::text, 'cancelled'::text])))
);
create index goods_receipts_company_date_idx on public.goods_receipts using btree (company_id, receipt_date desc, created_at desc);
create index goods_receipts_company_status_idx on public.goods_receipts using btree (company_id, status, receipt_date desc);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  goods_receipt_id uuid not null references public.goods_receipts(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  unit_cost numeric(18,4) not null,
  created_at timestamp with time zone default now() not null,
  constraint goods_receipt_items_quantity_check check ((quantity > (0)::numeric)),
  constraint goods_receipt_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index goods_receipt_items_purchase_item_idx on public.goods_receipt_items using btree (purchase_invoice_item_id);
create index goods_receipt_items_receipt_idx on public.goods_receipt_items using btree (goods_receipt_id);

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  payment_number text not null,
  status text default 'posted'::text not null,
  payment_date date default current_date not null,
  amount numeric(14,2) not null,
  allocated_total numeric(14,2) default 0 not null,
  unallocated_total numeric(14,2) default 0 not null,
  payment_method text default 'cash'::text not null,
  reference_number text,
  notes text,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  payment_currency text,
  exchange_rate_to_base numeric(24,10),
  base_amount numeric(20,4),
  constraint supplier_payments_company_id_payment_number_key unique (company_id, payment_number),
  constraint supplier_payments_amount_check check ((amount > (0)::numeric)),
  constraint supplier_payments_check check (((allocated_total >= (0)::numeric) and (allocated_total <= amount))),
  constraint supplier_payments_check1 check (((unallocated_total >= (0)::numeric) and (unallocated_total <= amount))),
  constraint supplier_payments_check2 check (((allocated_total + unallocated_total) = amount)),
  constraint supplier_payments_payment_method_check check ((payment_method = any (array['cash'::text, 'bank'::text, 'card'::text, 'check'::text, 'other'::text]))),
  constraint supplier_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index supplier_payments_company_date_idx on public.supplier_payments using btree (company_id, payment_date desc, created_at desc);
create index supplier_payments_currency_idx on public.supplier_payments using btree (company_id, payment_currency, payment_date desc);
create index supplier_payments_supplier_date_idx on public.supplier_payments using btree (supplier_id, payment_date desc, created_at desc);

create table public.supplier_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.supplier_payments(id) on delete restrict,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  payment_amount numeric(20,2),
  payment_currency text,
  invoice_currency text,
  payment_rate_to_base numeric(24,10),
  constraint supplier_payment_allocations_payment_id_purchase_invoice_id_key unique (payment_id, purchase_invoice_id),
  constraint supplier_payment_allocations_amount_check check ((amount > (0)::numeric))
);
create index supplier_payment_allocations_invoice_idx on public.supplier_payment_allocations using btree (purchase_invoice_id);
create index supplier_payment_allocations_payment_idx on public.supplier_payment_allocations using btree (payment_id);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_supplier_payment_fk foreign key (supplier_payment_id) references public.supplier_payments(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.apply_supplier_payment_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_days integer := 0;
begin
  select
    coalesce(
      s.payment_terms_days,
      0
    )
  into v_days
  from public.suppliers s
  where s.id = new.supplier_id
    and s.company_id =
        new.company_id;

  if new.due_date is null
     or new.due_date =
        new.invoice_date
  then
    new.due_date :=
      new.invoice_date +
      v_days;
  end if;

  return new;
end;
$function$;

create or replace function public.cancel_purchase_invoice(target_company uuid, target_invoice uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_order uuid;
begin
  if not public.has_permission(
    target_company,
    'purchase_invoices.cancel'
  ) then
    raise exception 'Not allowed';
  end if;

  select status
  into v_status

  from public.purchase_invoices

  where id =
        target_invoice

    and company_id =
        target_company

  for update;

  if v_status is null then
    raise exception
      'Purchase invoice not found';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Cancellation reason required';
  end if;


  -- Supplier allocations must be reversed first.
  if exists(
    select 1

    from public.supplier_payment_allocations a

    join public.supplier_payments p
      on p.id =
         a.payment_id

    where a.purchase_invoice_id =
          target_invoice

      and p.status =
          'posted'

      and a.amount >
          0
  ) then
    raise exception
      'Reverse allocated supplier payments before cancelling invoice';
  end if;


  -- Goods received must be physically reversed first.
  if exists(
    select 1

    from public.goods_receipts gr

    where gr.company_id =
          target_company

      and gr.purchase_invoice_id =
          target_invoice

      and gr.status =
          'posted'
  ) then
    raise exception
      'Reverse posted goods receipts before cancelling purchase invoice';
  end if;


  -- Do not allow cancellation over an active purchase return.
  if exists(
    select 1

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.purchase_invoice_id =
          target_invoice

      and pr.status =
          'posted'
  ) then
    raise exception
      'Purchase invoice has posted returns and cannot be cancelled';
  end if;


  update public.purchase_invoices
  set
    status =
      'cancelled',

    cancelled_at =
      now(),

    cancelled_by =
      auth.uid(),

    cancellation_reason =
      trim(target_reason)

  where id =
        target_invoice;


  -- Refresh all linked sales-order procurement states.
  for v_order in
    select distinct
      soi.order_id

    from public.purchase_invoice_item_sources src

    join public.purchase_invoice_items pii
      on pii.id =
         src.purchase_invoice_item_id

    join public.sales_order_items soi
      on soi.id =
         src.sales_order_item_id

    where pii.invoice_id =
          target_invoice

  loop

    perform
      public.refresh_sales_order_purchase_status(
        v_order
      );

  end loop;
end;
$function$;

create or replace function public.create_purchase_invoice(target_company uuid, target_supplier uuid, target_supplier_invoice_number text, target_invoice_date date, target_due_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invoice uuid;
  v_invoice_number text;
  v_currency text;

  v_item jsonb;
  v_item_id uuid;
  v_product uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(14,2);
  v_discount numeric(14,2);
  v_tax numeric(14,2);
  v_line_total numeric(14,2);

  v_allocation jsonb;
  v_order_item uuid;
  v_alloc_quantity numeric(14,3);
  v_required_quantity numeric(14,3);
  v_existing_allocated numeric(14,3);
  v_this_item_allocated numeric(14,3);
  v_order uuid;

  v_subtotal numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_tax_total numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
begin
  if not public.has_permission(
    target_company,
    'purchase_invoices.create'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers
    where id = target_supplier
      and company_id = target_company
      and active = true
  ) then
    raise exception 'Invalid or archived supplier';
  end if;

  if target_invoice_date is null then
    target_invoice_date := current_date;
  end if;

  if target_due_date is not null
     and target_due_date < target_invoice_date
  then
    raise exception 'Due date cannot be before invoice date';
  end if;

  if jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception 'Purchase invoice needs at least one item';
  end if;

  select default_currency
  into v_currency
  from public.companies
  where id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  v_invoice_number :=
    public.next_purchase_invoice_number(
      target_company,
      target_invoice_date
    );

  insert into public.purchase_invoices(
    company_id,
    supplier_id,
    invoice_number,
    supplier_invoice_number,
    status,
    payment_status,
    currency,
    invoice_date,
    due_date,
    notes,
    posted_at,
    posted_by
  )
  values(
    target_company,
    target_supplier,
    v_invoice_number,
    nullif(trim(target_supplier_invoice_number),''),
    'posted',
    'unpaid',
    v_currency,
    target_invoice_date,
    target_due_date,
    nullif(trim(target_notes),''),
    now(),
    auth.uid()
  )
  returning id into v_invoice;

  for v_item in
    select value
    from jsonb_array_elements(items_payload)
  loop
    v_product := (v_item ->> 'product_id')::uuid;
    v_quantity := (v_item ->> 'quantity')::numeric;
    v_unit_cost := (v_item ->> 'unit_cost')::numeric;

    v_discount :=
      coalesce(
        nullif(v_item ->> 'discount_amount','')::numeric,
        0
      );

    v_tax :=
      coalesce(
        nullif(v_item ->> 'tax_amount','')::numeric,
        0
      );

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Invalid purchase quantity';
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'Invalid purchase cost';
    end if;

    if v_discount < 0 or v_tax < 0 then
      raise exception 'Invalid discount or tax';
    end if;

    if v_discount >
       round(
         v_quantity * v_unit_cost,
         2
       )
    then
      raise exception
        'Discount exceeds purchase line subtotal';
    end if;

    if not exists (
      select 1
      from public.products
      where id = v_product
        and company_id = target_company
        and active = true
    ) then
      raise exception 'Invalid or archived product';
    end if;

    v_line_total :=
      round(
        greatest(
          (v_quantity * v_unit_cost)
          - v_discount
          + v_tax,
          0
        ),
        2
      );

    insert into public.purchase_invoice_items(
      company_id,
      invoice_id,
      product_id,
      description,
      quantity,
      unit_cost,
      discount_amount,
      tax_amount,
      line_total,
      notes
    )
    values(
      target_company,
      v_invoice,
      v_product,
      nullif(trim(v_item ->> 'description'),''),
      v_quantity,
      v_unit_cost,
      v_discount,
      v_tax,
      v_line_total,
      nullif(trim(v_item ->> 'notes'),'')
    )
    returning id into v_item_id;

    v_this_item_allocated := 0;

    if jsonb_typeof(
      coalesce(v_item -> 'allocations','[]'::jsonb)
    ) = 'array'
    then
      for v_allocation in
        select value
        from jsonb_array_elements(
          coalesce(v_item -> 'allocations','[]'::jsonb)
        )
      loop
        v_order_item :=
          nullif(
            v_allocation ->> 'sales_order_item_id',
            ''
          )::uuid;

        v_alloc_quantity :=
          nullif(
            v_allocation ->> 'quantity',
            ''
          )::numeric;

        if v_order_item is null
           or v_alloc_quantity is null
           or v_alloc_quantity <= 0
        then
          raise exception 'Invalid allocated quantity';
        end if;

        select
          soi.quantity,
          so.id
        into
          v_required_quantity,
          v_order
        from public.sales_order_items soi
        join public.sales_orders so
          on so.id = soi.order_id
        where soi.id = v_order_item
          and soi.product_id = v_product
          and so.company_id = target_company
          and so.status <> 'cancelled';

        if v_required_quantity is null then
          raise exception 'Invalid sales order allocation';
        end if;

        select coalesce(sum(src.quantity),0)
        into v_existing_allocated
        from public.purchase_invoice_item_sources src
        join public.purchase_invoice_items pii
          on pii.id = src.purchase_invoice_item_id
        join public.purchase_invoices pi
          on pi.id = pii.invoice_id
        where src.sales_order_item_id = v_order_item
          and pi.status <> 'cancelled';

        if v_existing_allocated + v_alloc_quantity > v_required_quantity then
          raise exception 'Purchase allocation exceeds ordered quantity';
        end if;

        v_this_item_allocated :=
          v_this_item_allocated + v_alloc_quantity;

        if v_this_item_allocated > v_quantity then
          raise exception 'Allocations exceed purchase invoice item quantity';
        end if;

        insert into public.purchase_invoice_item_sources(
          company_id,
          purchase_invoice_item_id,
          sales_order_item_id,
          quantity
        )
        values(
          target_company,
          v_item_id,
          v_order_item,
          v_alloc_quantity
        );

        perform public.refresh_sales_order_purchase_status(v_order);
      end loop;
    end if;

    insert into public.supplier_prices(
      company_id,
      supplier_id,
      product_id,
      purchase_price,
      available,
      notes,
      last_checked_at
    )
    values(
      target_company,
      target_supplier,
      v_product,
      v_unit_cost,
      true,
      'من فاتورة شراء ' || v_invoice_number,
      now()
    )
    on conflict (supplier_id, product_id)
    do update set
      purchase_price = excluded.purchase_price,
      available = true,
      notes = excluded.notes,
      last_checked_at = now(),
      updated_at = now();

    v_subtotal := v_subtotal + (v_quantity * v_unit_cost);
    v_discount_total := v_discount_total + v_discount;
    v_tax_total := v_tax_total + v_tax;
    v_total := v_total + v_line_total;
  end loop;

  update public.purchase_invoices
  set
    subtotal = round(v_subtotal,2),
    discount_total = round(v_discount_total,2),
    tax_total = round(v_tax_total,2),
    total = round(v_total,2),
    paid_total = 0,
    balance_due = round(v_total,2),
    payment_status =
      case
        when v_total = 0 then 'paid'
        else 'unpaid'
      end
  where id = v_invoice;

  return v_invoice;
end;
$function$;

create or replace function public.get_purchase_needs(target_company uuid)
 RETURNS TABLE(sales_order_item_id uuid, order_id uuid, trader_name text, product_id uuid, product_name text, sku text, required_quantity numeric, allocated_quantity numeric, remaining_quantity numeric, ordered_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'purchases.view'
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    soi.id,
    so.id,
    t.name,
    p.id,
    p.name,
    p.sku,

    greatest(
      soi.quantity -
      coalesce(delivered.qty,0) -
      coalesce(reserved.qty,0),
      0
    ) as required_quantity,

    least(
      coalesce(purchased.qty,0),
      greatest(
        soi.quantity -
        coalesce(delivered.qty,0) -
        coalesce(reserved.qty,0),
        0
      )
    ) as allocated_quantity,

    greatest(
      soi.quantity -
      coalesce(delivered.qty,0) -
      coalesce(reserved.qty,0) -
      coalesce(purchased.qty,0),
      0
    ) as remaining_quantity,

    so.ordered_at

  from public.sales_order_items soi

  join public.sales_orders so
    on so.id = soi.order_id

  join public.traders t
    on t.id = so.trader_id

  join public.products p
    on p.id = soi.product_id

  left join lateral (
    select
      coalesce(
        sum(di.quantity),
        0
      ) as qty
    from public.delivery_items di

    join public.deliveries d
      on d.id =
         di.delivery_id

    where di.sales_order_item_id =
          soi.id

      and d.status =
          'delivered'
  ) delivered on true

  left join lateral (
    select
      coalesce(
        sum(ir.quantity),
        0
      ) as qty
    from public.inventory_reservations ir

    where ir.sales_order_item_id =
          soi.id

      and ir.status =
          'active'
  ) reserved on true

  left join lateral (
    select
      coalesce(
        sum(src.quantity),
        0
      ) as qty

    from public.purchase_invoice_item_sources src

    join public.purchase_invoice_items pii
      on pii.id =
         src.purchase_invoice_item_id

    join public.purchase_invoices pi
      on pi.id =
         pii.invoice_id

    where src.sales_order_item_id =
          soi.id

      and pi.status <>
          'cancelled'
  ) purchased on true

  where so.company_id =
        target_company

    and so.status in (
      'new',
      'to_purchase',
      'purchasing',
      'ready'
    )

    and greatest(
      soi.quantity -
      coalesce(delivered.qty,0) -
      coalesce(reserved.qty,0) -
      coalesce(purchased.qty,0),
      0
    ) > 0

  order by
    so.ordered_at,
    p.name;
end;
$function$;

create or replace function public.get_purchases_summary(target_company uuid)
 RETURNS TABLE(invoice_count bigint, outstanding_total numeric, supplier_credit_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'purchases.view'
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    (
      select
        count(*)::bigint

      from public.purchase_invoices pi

      where pi.company_id =
            target_company
        and pi.status =
            'posted'
    ),

    (
      select
        round(
          coalesce(
            sum(
              (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            ),
            0
          ),
          2
        )

      from public.purchase_invoices pi

      where pi.company_id =
            target_company
        and pi.status =
            'posted'
    ),

    (
      select
        round(
          coalesce(
            sum(
              case
                when sp.amount > 0
                then
                  coalesce(
                    sp.base_amount,
                    sp.amount *
                    coalesce(
                      sp.exchange_rate_to_base,
                      1
                    )
                  ) *
                  (
                    sp.unallocated_total /
                    sp.amount
                  )
                else 0
              end
            ),
            0
          ),
          2
        )

      from public.supplier_payments sp

      where sp.company_id =
            target_company
        and sp.status =
            'posted'
    );
end;
$function$;

create or replace function public.get_receivable_purchase_items(target_company uuid)
 RETURNS TABLE(invoice_id uuid, supplier_id uuid, invoice_number text, supplier_invoice_number text, currency text, invoice_date date, invoice_total numeric, supplier_name text, item_id uuid, product_id uuid, description text, invoiced_quantity numeric, received_quantity numeric, remaining_quantity numeric, product_name text, sku text, unit text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'inventory.adjust',
      'purchases.update'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    pi.id,
    pi.supplier_id,
    pi.invoice_number,
    pi.supplier_invoice_number,
    pi.currency,
    pi.invoice_date,
    pi.total,
    s.name,
    pii.id,
    pii.product_id,
    pii.description,
    round(
      pii.quantity,
      3
    ),
    round(
      coalesce(
        received.qty,
        0
      ),
      3
    ),
    round(
      greatest(
        pii.quantity -
        coalesce(
          received.qty,
          0
        ),
        0
      ),
      3
    ),
    p.name,
    p.sku,
    p.unit

  from public.purchase_invoices pi

  join public.suppliers s
    on s.id =
       pi.supplier_id

  join public.purchase_invoice_items pii
    on pii.invoice_id =
       pi.id

  join public.products p
    on p.id =
       pii.product_id

  left join lateral (
    select
      coalesce(
        sum(gri.quantity),
        0
      ) as qty

    from public.goods_receipt_items gri

    join public.goods_receipts gr
      on gr.id =
         gri.goods_receipt_id

    where gri.purchase_invoice_item_id =
          pii.id

      and gr.status =
          'posted'
  ) received
    on true

  where pi.company_id =
        target_company

    and pi.status =
        'posted'

    and pii.quantity -
        coalesce(
          received.qty,
          0
        ) > 0

  order by
    pi.invoice_date,
    pi.created_at,
    pi.invoice_number,
    p.name;
end;
$function$;

create or replace function public.get_supplier_financial_summary(target_company uuid, target_supplier uuid)
 RETURNS TABLE(total_purchases numeric, total_payments numeric, invoice_balance numeric, advance_credit numeric, net_balance numeric, invoice_count bigint, payment_count bigint, available_products bigint, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;

  v_total_purchases numeric := 0;
  v_total_payments numeric := 0;
  v_invoice_balance numeric := 0;
  v_advance_credit numeric := 0;

  v_invoice_count bigint := 0;
  v_payment_count bigint := 0;
  v_available_products bigint := 0;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'suppliers.view_finance',
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers s
    where s.id = target_supplier
      and s.company_id = target_company
  ) then
    raise exception 'Supplier not found';
  end if;

  select upper(c.default_currency)
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  with invoice_values as (
    select
      pi.total,
      pi.balance_due,

      case
        when upper(pi.currency) = v_currency
          then 1::numeric
        else public.finance_rate_to_base(
          target_company,
          pi.currency,
          pi.invoice_date
        )
      end as rate_to_base

    from public.purchase_invoices pi

    where pi.company_id = target_company
      and pi.supplier_id = target_supplier
      and pi.status = 'posted'
  )
  select
    round(
      coalesce(
        sum(
          iv.total *
          iv.rate_to_base
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          iv.balance_due *
          iv.rate_to_base
        ),
        0
      ),
      2
    ),

    count(*)::bigint

  into
    v_total_purchases,
    v_invoice_balance,
    v_invoice_count

  from invoice_values iv;

  select
    round(
      coalesce(
        sum(
          coalesce(
            sp.base_amount,
            sp.amount *
            coalesce(
              sp.exchange_rate_to_base,
              1
            )
          )
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          sp.unallocated_total *
          coalesce(
            sp.exchange_rate_to_base,
            1
          )
        ),
        0
      ),
      2
    ),

    count(*)::bigint

  into
    v_total_payments,
    v_advance_credit,
    v_payment_count

  from public.supplier_payments sp

  where sp.company_id = target_company
    and sp.supplier_id = target_supplier
    and sp.status = 'posted';

  select count(*)::bigint
  into v_available_products
  from public.supplier_prices sp
  where sp.company_id = target_company
    and sp.supplier_id = target_supplier
    and sp.available = true;

  return query
  select
    v_total_purchases,

    v_total_payments,

    v_invoice_balance,

    v_advance_credit,

    round(
      v_invoice_balance -
      v_advance_credit,
      2
    ),

    v_invoice_count,

    v_payment_count,

    v_available_products,

    v_currency;
end;
$function$;

create or replace function public.get_supplier_ledger(target_company uuid, target_supplier uuid, target_limit integer DEFAULT 100)
 RETURNS TABLE(source_id uuid, event_date date, event_created_at timestamp with time zone, row_type text, reference text, description text, debit numeric, credit numeric, balance numeric, total_count bigint, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_limit integer;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'suppliers.view_finance',
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers s
    where s.id = target_supplier
      and s.company_id = target_company
  ) then
    raise exception 'Supplier not found';
  end if;

  select upper(c.default_currency)
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  v_limit :=
    least(
      greatest(
        coalesce(target_limit,100),
        1
      ),
      200
    );

  return query

  with movements as (

    select
      pi.id as source_id,

      pi.invoice_date as event_date,

      pi.created_at as event_created_at,

      'invoice'::text as row_type,

      pi.invoice_number::text as reference,

      case
        when nullif(
          trim(
            coalesce(
              pi.supplier_invoice_number,
              ''
            )
          ),
          ''
        ) is not null
        then
          'فاتورة مورد ' ||
          pi.supplier_invoice_number

        else
          'فاتورة شراء'
      end::text as description,

      round(
        pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date),
        2
      )::numeric as debit,

      0::numeric as credit

    from public.purchase_invoices pi

    where pi.company_id = target_company
      and pi.supplier_id = target_supplier
      and pi.status = 'posted'


    union all


    select
      sp.id as source_id,

      sp.payment_date as event_date,

      sp.created_at as event_created_at,

      'payment'::text as row_type,

      sp.payment_number::text as reference,

      case
        when nullif(
          trim(
            coalesce(
              sp.reference_number,
              ''
            )
          ),
          ''
        ) is not null
        then
          'دفعة - ' ||
          sp.reference_number

        else
          'دفعة للمورد'
      end::text as description,

      0::numeric as debit,

      round(
        coalesce(
          sp.base_amount,
          sp.amount *
          coalesce(
            sp.exchange_rate_to_base,
            1
          )
        ),
        2
      )::numeric as credit

    from public.supplier_payments sp

    where sp.company_id = target_company
      and sp.supplier_id = target_supplier
      and sp.status = 'posted'

    union all

    -- المرتجع للمورد بينقّص اللي علينا إله، متل الدفعة.
    select
      pr.id as source_id,
      pr.return_date as event_date,
      pr.created_at as event_created_at,
      'return'::text as row_type,
      pr.return_number::text as reference,
      'مرتجع للمورد'::text as description,
      0::numeric as debit,
      round(
        pr.total * public.finance_rate_to_base(target_company, pr.currency, pr.return_date),
        2
      )::numeric as credit
    from public.purchase_returns pr
    where pr.company_id = target_company
      and pr.supplier_id = target_supplier
      and pr.status = 'posted'
  ),

  running as (
    select
      m.*,

      round(
        sum(
          m.debit -
          m.credit
        ) over (
          order by
            m.event_date,
            m.event_created_at,
            m.row_type,
            m.source_id
          rows between
            unbounded preceding
            and current row
        ),
        2
      )::numeric as running_balance,

      count(*) over()::bigint
        as full_count

    from movements m
  )

  select
    r.source_id,

    r.event_date,

    r.event_created_at,

    r.row_type,

    r.reference,

    r.description,

    r.debit,

    r.credit,

    r.running_balance,

    r.full_count,

    v_currency

  from running r

  order by
    r.event_date desc,
    r.event_created_at desc,
    r.row_type desc,
    r.source_id desc

  limit v_limit;
end;
$function$;

create or replace function public.next_goods_receipt_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'goods_receipt',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'goods_receipt'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value =
      next_value + 1
  where company_id = target_company
    and document_type = 'goods_receipt'
    and sequence_year = v_year;

  return
    'GRN-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.next_purchase_invoice_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year := extract(year from coalesce(target_date, current_date));

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'purchase_invoice',
    v_year,
    1
  )
  on conflict (
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'purchase_invoice'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'purchase_invoice'
    and sequence_year = v_year;

  return
    'PI-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.next_supplier_payment_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin

  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'supplier_payment',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;


  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'supplier_payment'
    and sequence_year = v_year
  for update;


  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'supplier_payment'
    and sequence_year = v_year;


  return
    'SP-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.recalc_purchase_invoice_payment(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total numeric(18,2);
  v_paid numeric(18,2);
  v_returns numeric(18,2);
  v_balance numeric(18,2);
begin
  select total
  into v_total
  from public.purchase_invoices
  where id =
        target_invoice;

  if v_total is null then
    return;
  end if;

  select
    coalesce(
      sum(a.amount),
      0
    )
  into v_paid
  from public.supplier_payment_allocations a

  join public.supplier_payments p
    on p.id =
       a.payment_id

  where a.purchase_invoice_id =
        target_invoice

    and p.status =
        'posted';

  select
    coalesce(
      sum(pr.total),
      0
    )
  into v_returns
  from public.purchase_returns pr
  where pr.purchase_invoice_id =
        target_invoice
    and pr.status =
        'posted';

  v_balance :=
    greatest(
      round(
        v_total -
        v_paid -
        v_returns,
        2
      ),
      0
    );

  update public.purchase_invoices
  set
    paid_total =
      round(
        v_paid,
        2
      ),

    balance_due =
      v_balance,

    payment_status =
      case
        when v_balance <= 0.009
          then 'paid'

        when (
          v_paid +
          v_returns
        ) > 0
          then 'partial'

        else 'unpaid'
      end

  where id =
        target_invoice;
end;
$function$;

create or replace function public.receive_purchase_invoice(target_company uuid, target_invoice uuid, target_warehouse uuid, target_receipt_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_supplier uuid;
  v_invoice_status text;

  v_receipt uuid;
  v_receipt_number text;

  v_item jsonb;

  v_purchase_item uuid;
  v_product uuid;

  v_requested numeric(18,3);
  v_invoiced numeric(18,3);
  v_received numeric(18,3);

  v_unit_cost numeric(18,4);

  v_receipt_item uuid;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'inventory.adjust',
      'purchases.update'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select
    supplier_id,
    status
  into
    v_supplier,
    v_invoice_status
  from public.purchase_invoices
  where id =
        target_invoice
    and company_id =
        target_company
  for update;

  if v_supplier is null then
    raise exception
      'Purchase invoice not found';
  end if;

  if v_invoice_status <>
     'posted'
  then
    raise exception
      'Purchase invoice is not posted';
  end if;

  if not exists (
    select 1
    from public.warehouses
    where id =
          target_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid warehouse';
  end if;

  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Receipt needs at least one item';
  end if;

  v_receipt_number :=
    public.next_goods_receipt_number(
      target_company,
      coalesce(
        target_receipt_date,
        current_date
      )
    );

  insert into public.goods_receipts(
    company_id,
    warehouse_id,
    supplier_id,
    purchase_invoice_id,
    receipt_number,
    status,
    receipt_date,
    notes
  )
  values(
    target_company,
    target_warehouse,
    v_supplier,
    target_invoice,
    v_receipt_number,
    'posted',
    coalesce(
      target_receipt_date,
      current_date
    ),
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_receipt;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_purchase_item :=
        (
          v_item->>'purchase_invoice_item_id'
        )::uuid;

      v_requested :=
        (
          v_item->>'quantity'
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid receipt item';
    end;

    if v_requested is null
       or v_requested <= 0
    then
      raise exception
        'Invalid receipt quantity';
    end if;

    select
      product_id,
      quantity,
      unit_cost
    into
      v_product,
      v_invoiced,
      v_unit_cost
    from public.purchase_invoice_items
    where id =
          v_purchase_item
      and invoice_id =
          target_invoice
      and company_id =
          target_company;

    if v_product is null then
      raise exception
        'Purchase invoice item not found';
    end if;

    select
      coalesce(
        sum(gri.quantity),
        0
      )
    into v_received
    from public.goods_receipt_items gri

    join public.goods_receipts gr
      on gr.id =
         gri.goods_receipt_id

    where gri.purchase_invoice_item_id =
          v_purchase_item

      and gr.status =
          'posted';

    if
      round(
        v_received +
        v_requested,
        3
      ) >
      round(
        v_invoiced,
        3
      )
    then
      raise exception
        'Receipt exceeds purchased quantity';
    end if;

    insert into public.goods_receipt_items(
      company_id,
      goods_receipt_id,
      purchase_invoice_item_id,
      product_id,
      quantity,
      unit_cost
    )
    values(
      target_company,
      v_receipt,
      v_purchase_item,
      v_product,
      v_requested,
      v_unit_cost
    )
    returning id
    into v_receipt_item;

    perform
      public.post_inventory_movement(
        target_company,
        target_warehouse,
        v_product,
        'purchase_receipt',
        v_requested,
        v_unit_cost,
        'goods_receipts',
        v_receipt,
        v_receipt_item,
        v_receipt_number,
        target_notes,
        now()
      );

    perform
      public.reserve_pending_orders_for_product(
        target_company,
        target_warehouse,
        v_product
      );
  end loop;

  return v_receipt;
end;
$function$;

create or replace function public.record_supplier_payment(target_company uuid, target_supplier uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text, allocations_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;

  v_method text;

  v_base_currency text;
  v_payment_currency text;
  v_payment_rate numeric(24,10);
  v_base_amount numeric(20,4);

  v_allocation jsonb;

  v_invoice uuid;
  v_alloc_amount numeric(20,2);
  v_payment_alloc_amount numeric(20,2);

  v_balance numeric(20,2);
  v_invoice_status text;
  v_invoice_supplier uuid;
  v_invoice_currency text;

  v_allocated_payment_sum numeric(20,2) := 0;
begin
  if not public.has_permission(
    target_company,
    'payments.supplier_create'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid payment amount';
  end if;

  if not exists(
    select 1
    from public.suppliers
    where id =
          target_supplier
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid supplier';
  end if;

  v_method :=
    coalesce(
      nullif(
        trim(target_method),
        ''
      ),
      'cash'
    );

  if v_method not in (
    'cash',
    'bank',
    'card',
    'check',
    'other'
  ) then
    raise exception
      'Invalid payment method';
  end if;

  target_payment_date :=
    coalesce(
      target_payment_date,
      current_date
    );

  if target_cashbox is not null then

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.id =
          target_cashbox
      and cb.company_id =
          target_company
      and cb.active = true;

  else

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.company_id =
          target_company
      and cb.active = true

    order by
      case
        when upper(cb.currency) =
             upper(c.default_currency)
          then 0
        else 1
      end,
      cb.created_at

    limit 1;

  end if;

  if v_cashbox is null then
    raise exception
      'No valid active cashbox';
  end if;

  v_payment_rate :=
    public.finance_rate_to_base(
      target_company,
      v_payment_currency,
      target_payment_date
    );

  v_base_amount :=
    round(
      target_amount *
      v_payment_rate,
      4
    );

  if jsonb_typeof(
       coalesce(
         allocations_payload,
         '[]'::jsonb
       )
     ) <> 'array'
  then
    raise exception
      'Invalid allocations payload';
  end if;

  v_number :=
    public.next_supplier_payment_number(
      target_company,
      target_payment_date
    );

  insert into public.supplier_payments(
    company_id,
    supplier_id,
    cashbox_id,
    payment_number,
    status,
    payment_date,
    amount,
    allocated_total,
    unallocated_total,
    payment_method,
    reference_number,
    notes,
    payment_currency,
    exchange_rate_to_base,
    base_amount
  )
  values(
    target_company,
    target_supplier,
    v_cashbox,
    v_number,
    'posted',
    target_payment_date,
    round(
      target_amount,
      2
    ),
    0,
    round(
      target_amount,
      2
    ),
    v_method,
    nullif(
      trim(target_reference),
      ''
    ),
    nullif(
      trim(target_notes),
      ''
    ),
    v_payment_currency,
    v_payment_rate,
    v_base_amount
  )
  returning id
  into v_payment;


  for v_allocation in

    select value
    from jsonb_array_elements(
      coalesce(
        allocations_payload,
        '[]'::jsonb
      )
    )

  loop

    begin
      v_invoice :=
        nullif(
          v_allocation ->
          'purchase_invoice_id' #>> '{}',
          ''
        )::uuid;

      v_alloc_amount :=
        nullif(
          v_allocation ->
          'amount' #>> '{}',
          ''
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid payment allocation';
    end;

    if v_invoice is null
       or v_alloc_amount is null
       or v_alloc_amount <= 0
    then
      raise exception
        'Invalid payment allocation';
    end if;

    select
      balance_due,
      status,
      supplier_id,
      upper(currency)

    into
      v_balance,
      v_invoice_status,
      v_invoice_supplier,
      v_invoice_currency

    from public.purchase_invoices

    where id =
          v_invoice
      and company_id =
          target_company

    for update;

    if v_balance is null then
      raise exception
        'Purchase invoice not found';
    end if;

    if v_invoice_status <>
       'posted'
    then
      raise exception
        'Cannot pay cancelled or unposted invoice';
    end if;

    if v_invoice_supplier <>
       target_supplier
    then
      raise exception
        'Invoice belongs to another supplier';
    end if;

    if round(
         v_alloc_amount,
         2
       ) >
       round(
         v_balance,
         2
       )
    then
      raise exception
        'Allocation exceeds invoice balance';
    end if;


    if v_invoice_currency =
       v_payment_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount,
          2
        );

    elsif v_invoice_currency =
          v_base_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount /
          v_payment_rate,
          2
        );

    else

      raise exception
        'Cross-currency settlement currently requires invoice currency to be company base currency';

    end if;


    v_allocated_payment_sum :=
      round(
        v_allocated_payment_sum +
        v_payment_alloc_amount,
        2
      );

    if v_allocated_payment_sum >
       round(
         target_amount,
         2
       ) + 0.01
    then
      raise exception
        'Allocations exceed payment amount after currency conversion';
    end if;


    insert into public.supplier_payment_allocations(
      company_id,
      payment_id,
      purchase_invoice_id,
      amount,
      payment_amount,
      payment_currency,
      invoice_currency,
      payment_rate_to_base
    )
    values(
      target_company,
      v_payment,
      v_invoice,
      round(
        v_alloc_amount,
        2
      ),
      v_payment_alloc_amount,
      v_payment_currency,
      v_invoice_currency,
      v_payment_rate
    );

  end loop;


  perform
    public.refresh_supplier_payment_totals(
      v_payment
    );


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    supplier_id,
    supplier_payment_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'supplier_payment',
    round(
      target_amount,
      2
    ),
    target_supplier,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'دفعة مورد ' ||
      v_number
    ),
    target_payment_date::timestamptz
  );

  return v_payment;
end;
$function$;

create or replace function public.refresh_sales_order_purchase_status(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.refresh_sales_order_inventory_status(
      target_order
    );
end;
$function$;

create or replace function public.refresh_supplier_payment_totals(target_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_amount numeric(20,2);
  v_allocated numeric(20,2);
begin
  select amount
  into v_amount
  from public.supplier_payments
  where id =
        target_payment
  for update;

  if v_amount is null then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          coalesce(
            payment_amount,
            amount
          )
        ),
        0
      ),
      2
    )
  into v_allocated
  from public.supplier_payment_allocations
  where payment_id =
        target_payment;

  if v_allocated >
     round(
       v_amount,
       2
     ) + 0.01
  then
    raise exception
      'Payment allocations exceed cash payment amount';
  end if;

  update public.supplier_payments
  set
    allocated_total =
      round(
        v_allocated,
        2
      ),

    unallocated_total =
      greatest(
        round(
          v_amount -
          v_allocated,
          2
        ),
        0
      )

  where id =
        target_payment;
end;
$function$;

create or replace function public.reverse_goods_receipt(target_company uuid, target_receipt uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_warehouse uuid;
  v_invoice uuid;
  v_number text;

  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);

  v_order uuid;
begin
  if not public.has_permission(
    target_company,
    'inventory.adjust'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;

  select
    status,
    warehouse_id,
    purchase_invoice_id,
    receipt_number

  into
    v_status,
    v_warehouse,
    v_invoice,
    v_number

  from public.goods_receipts

  where id =
        target_receipt

    and company_id =
        target_company

  for update;

  if v_status is null then
    raise exception
      'Goods receipt not found';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;


  -- ----------------------------------------------------------
  -- Validate every item before changing anything.
  -- Reserved/sold/transferred stock prevents reversal.
  -- ----------------------------------------------------------

  for v_item in
    select
      id,
      product_id,
      quantity,
      unit_cost

    from public.goods_receipt_items

    where goods_receipt_id =
          target_receipt

    order by created_at,
             id

  loop

    select
      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                target_company

            and r.warehouse_id =
                v_warehouse

            and r.product_id =
                v_item.product_id

            and r.status =
                'active'
        ),
        0
      )

    into
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          v_warehouse

      and s.product_id =
          v_item.product_id;

    if
      coalesce(
        v_on_hand,
        0
      ) -
      coalesce(
        v_reserved,
        0
      )
      <
      v_item.quantity
    then
      raise exception
        'Cannot reverse receipt: some received stock was already reserved, transferred or delivered';
    end if;

  end loop;


  -- ----------------------------------------------------------
  -- Post opposite inventory movements.
  -- ----------------------------------------------------------

  for v_item in
    select
      id,
      product_id,
      quantity,
      unit_cost

    from public.goods_receipt_items

    where goods_receipt_id =
          target_receipt

    order by created_at,
             id

  loop

    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'purchase_return',
        -v_item.quantity,
        v_item.unit_cost,
        'goods_receipt_reversals',
        target_receipt,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

  end loop;


  update public.goods_receipts
  set
    status =
      'cancelled',

    cancelled_at =
      now(),

    cancelled_by =
      auth.uid(),

    cancellation_reason =
      trim(target_reason)

  where id =
        target_receipt;


  -- ----------------------------------------------------------
  -- Receipt no longer counts toward purchased/received qty.
  -- Refresh linked sales order procurement status.
  -- ----------------------------------------------------------

  if v_invoice is not null then

    for v_order in
      select distinct
        soi.order_id

      from public.purchase_invoice_item_sources src

      join public.purchase_invoice_items pii
        on pii.id =
           src.purchase_invoice_item_id

      join public.sales_order_items soi
        on soi.id =
           src.sales_order_item_id

      where pii.invoice_id =
            v_invoice

    loop

      perform
        public.refresh_sales_order_purchase_status(
          v_order
        );

    end loop;

  end if;
end;
$function$;

create or replace function public.reverse_supplier_payment(target_company uuid, target_payment uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_cashbox uuid;
  v_amount numeric(14,2);
  v_supplier uuid;
  v_number text;
begin

  if not public.has_permission(
    target_company,
    'payments.supplier_reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    status,
    cashbox_id,
    amount,
    supplier_id,
    payment_number

  into
    v_status,
    v_cashbox,
    v_amount,
    v_supplier,
    v_number

  from public.supplier_payments

  where id = target_payment
    and company_id = target_company

  for update;


  if v_status is null then
    raise exception 'Supplier payment not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if nullif(trim(target_reason),'') is null
  then
    raise exception 'Reversal reason required';
  end if;


  update public.supplier_payments
  set
    status = 'reversed',
    reversed_at = now(),
    reversed_by = auth.uid(),
    reversal_reason =
      trim(target_reason)

  where id = target_payment;


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    supplier_id,
    supplier_payment_id,
    notes
  )
  values(
    target_company,
    v_cashbox,
    'in',
    'supplier_payment_reversal',
    v_amount,
    v_supplier,
    target_payment,
    'عكس دفعة مورد ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$function$;

create or replace function public.supplier_payment_allocation_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  if tg_op = 'DELETE' then

    perform
      public.refresh_supplier_payment_totals(
        old.payment_id
      );

    perform
      public.recalc_purchase_invoice_payment(
        old.purchase_invoice_id
      );

    return old;

  end if;


  if tg_op = 'UPDATE' then

    if old.payment_id is distinct from
       new.payment_id
    then
      perform
        public.refresh_supplier_payment_totals(
          old.payment_id
        );
    end if;

    if old.purchase_invoice_id
       is distinct from
       new.purchase_invoice_id
    then
      perform
        public.recalc_purchase_invoice_payment(
          old.purchase_invoice_id
        );
    end if;

  end if;


  perform
    public.refresh_supplier_payment_totals(
      new.payment_id
    );

  perform
    public.recalc_purchase_invoice_payment(
      new.purchase_invoice_id
    );

  return new;
end;
$function$;

create or replace function public.supplier_payment_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invoice uuid;
begin

  if old.status is distinct from new.status
  then

    for v_invoice in
      select distinct purchase_invoice_id
      from public.supplier_payment_allocations
      where payment_id = new.id
    loop

      perform
        public.recalc_purchase_invoice_payment(
          v_invoice
        );

    end loop;

  end if;

  return new;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_goods_receipt_items after insert or delete or update on public.goods_receipt_items for each row execute function public.write_audit_log();

create trigger audit_goods_receipts after insert or delete or update on public.goods_receipts for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_sources after insert or delete or update on public.purchase_invoice_item_sources for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_items after insert or delete or update on public.purchase_invoice_items for each row execute function public.write_audit_log();

create trigger audit_purchase_invoices after insert or delete or update on public.purchase_invoices for each row execute function public.write_audit_log();

create trigger purchase_invoice_payment_terms before insert on public.purchase_invoices for each row execute function public.apply_supplier_payment_terms();

create trigger purchase_invoices_updated_at before update on public.purchase_invoices for each row execute function public.set_updated_at();

create trigger audit_supplier_payment_allocations after insert or delete or update on public.supplier_payment_allocations for each row execute function public.write_audit_log();

create trigger supplier_payment_allocation_changed_trigger after insert or delete or update on public.supplier_payment_allocations for each row execute function public.supplier_payment_allocation_changed();

create trigger audit_supplier_payments after insert or delete or update on public.supplier_payments for each row execute function public.write_audit_log();

create trigger supplier_payment_status_changed_trigger after update of status on public.supplier_payments for each row execute function public.supplier_payment_status_changed();

create trigger supplier_payments_updated_at before update on public.supplier_payments for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_items enable row level security;
alter table public.purchase_invoice_item_sources enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
create policy goods_receipt_items_read on public.goods_receipt_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'purchases.view'::text, 'purchase_invoices.view'::text]));
create policy goods_receipts_read on public.goods_receipts
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'purchases.view'::text, 'purchase_invoices.view'::text]));
create policy purchase_invoice_sources_read on public.purchase_invoice_item_sources
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy purchase_invoice_items_read on public.purchase_invoice_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy purchase_invoices_read on public.purchase_invoices
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy supplier_payment_allocations_read on public.supplier_payment_allocations
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text]));
create policy supplier_payments_read on public.supplier_payments
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.supplier_view'::text, 'suppliers.view_finance'::text, 'finance.cashbox_view'::text, 'finance.accounts_view'::text, 'reports.finance'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.purchase_invoices from authenticated;
revoke insert, update, delete on public.purchase_invoice_items from authenticated;
revoke insert, update, delete on public.purchase_invoice_item_sources from authenticated;
revoke insert, update, delete on public.goods_receipts from authenticated;
revoke select, insert, update, delete on public.goods_receipt_items from authenticated;
grant select (id, company_id, goods_receipt_id, purchase_invoice_item_id, product_id, quantity, created_at) on public.goods_receipt_items to authenticated;
revoke insert, update, delete on public.supplier_payments from authenticated;
revoke insert, update, delete on public.supplier_payment_allocations from authenticated;
revoke execute on function public.next_goods_receipt_number(uuid,date) from authenticated;
revoke execute on function public.next_purchase_invoice_number(uuid,date) from authenticated;
revoke execute on function public.next_supplier_payment_number(uuid,date) from authenticated;
revoke execute on function public.recalc_purchase_invoice_payment(uuid) from authenticated;
revoke execute on function public.refresh_sales_order_purchase_status(uuid) from authenticated;
revoke execute on function public.refresh_supplier_payment_totals(uuid) from authenticated;

-- ======================================================================
-- المرتجعات والموافقات
-- مرتجعات البيع والشراء، طلبات الموافقة
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  return_number text not null,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  trader_id uuid not null references public.traders(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  return_date date default current_date not null,
  status text default 'posted'::text not null,
  currency text not null,
  subtotal numeric(18,2) default 0 not null,
  discount_total numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  reversal_journal_entry_id uuid references public.journal_entries(id) on delete set null,
  constraint sales_returns_company_id_return_number_key unique (company_id, return_number),
  constraint sales_returns_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint sales_returns_status_check check ((status = any (array['posted'::text, 'cancelled'::text, 'reversed'::text]))),
  constraint sales_returns_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_returns_total_check check ((total >= (0)::numeric))
);
create index sales_returns_company_status_idx on public.sales_returns using btree (company_id, status, return_date desc);
create index sales_returns_invoice_idx on public.sales_returns using btree (sales_invoice_id, return_date desc);

create table public.sales_return_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  sales_invoice_item_id uuid not null references public.sales_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  description text not null,
  unit text,
  quantity numeric(14,3) not null,
  unit_price numeric(18,2) not null,
  line_total numeric(18,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_return_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_return_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_return_items_unit_price_check check ((unit_price >= (0)::numeric))
);
create index sales_return_items_invoice_item_idx on public.sales_return_items using btree (sales_invoice_item_id);
create index sales_return_items_return_idx on public.sales_return_items using btree (sales_return_id);

create table public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  return_number text not null,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  return_date date default current_date not null,
  status text default 'posted'::text not null,
  currency text not null,
  inventory_cost_total numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  reversal_journal_entry_id uuid references public.journal_entries(id) on delete set null,
  constraint purchase_returns_company_id_return_number_key unique (company_id, return_number),
  constraint purchase_returns_inventory_cost_total_check check ((inventory_cost_total >= (0)::numeric)),
  constraint purchase_returns_status_check check ((status = any (array['posted'::text, 'cancelled'::text, 'reversed'::text]))),
  constraint purchase_returns_total_check check ((total >= (0)::numeric))
);
create index purchase_returns_company_status_idx on public.purchase_returns using btree (company_id, status, return_date desc);
create index purchase_returns_invoice_idx on public.purchase_returns using btree (purchase_invoice_id, return_date desc);

create table public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  description text,
  quantity numeric(14,3) not null,
  unit_cost numeric(18,2) not null,
  inventory_cost numeric(18,2) not null,
  line_total numeric(18,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint purchase_return_items_inventory_cost_check check ((inventory_cost >= (0)::numeric)),
  constraint purchase_return_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint purchase_return_items_quantity_check check ((quantity > (0)::numeric)),
  constraint purchase_return_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index purchase_return_items_invoice_item_idx on public.purchase_return_items using btree (purchase_invoice_item_id);
create index purchase_return_items_return_idx on public.purchase_return_items using btree (purchase_return_id);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  request_type text not null,
  reference_type text,
  reference_id uuid,
  title text not null,
  description text,
  payload jsonb default '{}'::jsonb not null,
  status text default 'pending'::text not null,
  requested_by uuid default auth.uid() references auth.users(id) on delete set null,
  requested_at timestamp with time zone default now() not null,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamp with time zone,
  resolution_notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint approval_requests_status_check check ((status = any (array['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);
create index approval_requests_company_status_idx on public.approval_requests using btree (company_id, status, requested_at desc);
create index approval_requests_reference_idx on public.approval_requests using btree (company_id, reference_type, reference_id);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

-- لما الزبون يرجّع بضاعة من فاتورة كان دافعها، جزء من دفعته بيتحرّر وبيصير رصيد إلو
-- (بينخصم تلقائي من فاتورته الجاية). كل تحرير إلو قيد خاص، لحتى إذا انعكست الدفعة ينعكس معها.
create table public.customer_payment_releases (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete restrict,
  allocation_id uuid references public.customer_payment_allocations(id) on delete set null,
  sales_return_id uuid not null references public.sales_returns(id) on delete restrict,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_amount numeric(20,2) not null check (payment_amount > 0),
  payment_currency text not null,
  created_at timestamp with time zone default now() not null
);
create index customer_payment_releases_payment_idx on public.customer_payment_releases using btree (payment_id);
create index customer_payment_releases_return_idx on public.customer_payment_releases using btree (sales_return_id);
revoke insert, update, delete on public.customer_payment_releases from authenticated;
alter table public.customer_payment_releases enable row level security;
create policy customer_payment_releases_read on public.customer_payment_releases
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'reports.finance'::text]));

create or replace function public.block_invoice_cancel_with_posted_return()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  if old.status = 'posted'
     and new.status = 'cancelled'
  then

    if tg_table_name =
       'sales_invoices'
    then

      if exists(
        select 1
        from public.sales_returns sr
        where sr.company_id =
              new.company_id
          and sr.sales_invoice_id =
              new.id
          and sr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted sales returns before cancelling sales invoice';
      end if;


    elsif tg_table_name =
          'purchase_invoices'
    then

      if exists(
        select 1
        from public.purchase_returns pr
        where pr.company_id =
              new.company_id
          and pr.purchase_invoice_id =
              new.id
          and pr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted purchase returns before cancelling purchase invoice';
      end if;

    end if;

  end if;

  return new;
end;
$function$;

create or replace function public.can_view_returns(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    public.has_any_permission(
      target_company,
      array[
        'returns.view',
        'returns.create',
        'inventory.returns',
        'returns.reverse'
      ]::text[]
    );
$function$;

create or replace function public.create_purchase_return(target_company uuid, target_invoice uuid, target_warehouse uuid, target_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_return uuid;
  v_number text;

  v_supplier uuid;
  v_currency text;
  v_invoice_total numeric(18,2);

  v_item jsonb;
  v_invoice_item uuid;
  v_product uuid;
  v_description text;

  v_invoice_qty numeric(14,3);
  v_unit_cost numeric(18,2);
  v_original_line_total numeric(18,2);

  v_qty numeric(14,3);
  v_returned numeric(14,3);

  v_line_total numeric(18,2);
  v_inventory_cost numeric(18,2);

  v_total numeric(18,2) := 0;
  v_cost_total numeric(18,2) := 0;

  v_prior_returns numeric(18,2);
  v_paid numeric(18,2);
  v_open_ap numeric(18,2);

  v_ap_part numeric(18,2);
  v_advance_part numeric(18,2);
  v_variance numeric(18,2);

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_stock_cost numeric(18,4);

  v_return_item uuid;

  v_ap uuid;
  v_supplier_advance uuid;
  v_clearing uuid;
  v_variance_account uuid;

  v_lines jsonb := '[]'::jsonb;
  v_entry uuid;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Return requires items';
  end if;

  select
    supplier_id,
    currency,
    total
  into
    v_supplier,
    v_currency,
    v_invoice_total
  from public.purchase_invoices
  where id =
        target_invoice

    and company_id =
        target_company

    and status =
        'posted'
  for update;

  if v_supplier is null then
    raise exception
      'Posted purchase invoice not found';
  end if;

  if not exists(
    select 1
    from public.warehouses
    where id =
          target_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid warehouse';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_date,
        current_date
      )
    );

  v_number :=
    public.next_purchase_return_number(
      target_company,
      coalesce(
        target_date,
        current_date
      )
    );

  insert into public.purchase_returns(
    company_id,
    return_number,
    purchase_invoice_id,
    supplier_id,
    warehouse_id,
    return_date,
    status,
    currency,
    notes
  )
  values(
    target_company,
    v_number,
    target_invoice,
    v_supplier,
    target_warehouse,
    coalesce(
      target_date,
      current_date
    ),
    'posted',
    v_currency,
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_return;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_invoice_item :=
        (
          v_item->>'purchase_invoice_item_id'
        )::uuid;

      v_qty :=
        (
          v_item->>'quantity'
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid purchase return item';
    end;

    if v_qty is null
       or v_qty <= 0
    then
      raise exception
        'Return quantity must be greater than zero';
    end if;

    select
      product_id,
      description,
      quantity,
      unit_cost,
      line_total
    into
      v_product,
      v_description,
      v_invoice_qty,
      v_unit_cost,
      v_original_line_total
    from public.purchase_invoice_items
    where id =
          v_invoice_item

      and invoice_id =
          target_invoice

      and company_id =
          target_company;

    if v_product is null then
      raise exception
        'Invalid purchase invoice item';
    end if;

    select
      coalesce(
        sum(pri.quantity),
        0
      )
    into v_returned
    from public.purchase_return_items pri

    join public.purchase_returns pr
      on pr.id =
         pri.purchase_return_id

    where pri.purchase_invoice_item_id =
          v_invoice_item

      and pr.status =
          'posted';

    if round(
         v_returned +
         v_qty,
         3
       ) >
       round(
         v_invoice_qty,
         3
       )
    then
      raise exception
        'Returned quantity exceeds invoiced quantity';
    end if;

    select
      coalesce(
        s.average_cost,
        0
      ),

      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)
          from public.inventory_reservations r
          where r.company_id =
                target_company
            and r.warehouse_id =
                target_warehouse
            and r.product_id =
                v_product
            and r.status =
                'active'
        ),
        0
      )

    -- الكلفة لازم تنقرا مع الكمية: البضاعة بترجع للمورد بمتوسط كلفتها بالمستودع.
    into
      v_stock_cost,
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          target_warehouse

      and s.product_id =
          v_product;

    if coalesce(
         v_on_hand,
         0
       ) -
       coalesce(
         v_reserved,
         0
       ) <
       v_qty
    then
      raise exception
        'Not enough available stock for purchase return';
    end if;

    v_inventory_cost :=
      round(
        v_stock_cost *
        v_qty,
        2
      );

    v_line_total :=
      case
        when v_invoice_qty > 0
          then round(
            (
              v_original_line_total /
              v_invoice_qty
            ) *
            v_qty,
            2
          )

        else v_inventory_cost
      end;

    insert into public.purchase_return_items(
      company_id,
      purchase_return_id,
      purchase_invoice_item_id,
      product_id,
      description,
      quantity,
      unit_cost,
      inventory_cost,
      line_total
    )
    values(
      target_company,
      v_return,
      v_invoice_item,
      v_product,
      v_description,
      v_qty,
      v_unit_cost,
      v_inventory_cost,
      v_line_total
    )
    returning id
    into v_return_item;

    perform
      public.post_inventory_movement(
        target_company,
        target_warehouse,
        v_product,
        'purchase_return',
        -v_qty,
        v_stock_cost,
        'purchase_returns',
        v_return,
        v_return_item,
        v_number,
        target_notes,
        coalesce(
          target_date,
          current_date
        )::timestamptz
      );

    v_total :=
      v_total +
      v_line_total;

    v_cost_total :=
      v_cost_total +
      v_inventory_cost;
  end loop;

  select
    coalesce(
      sum(total),
      0
    )
  into v_prior_returns
  from public.purchase_returns
  where purchase_invoice_id =
        target_invoice

    and status =
        'posted'

    and id <>
        v_return;

  select
    coalesce(
      sum(a.amount),
      0
    )
  into v_paid
  from public.supplier_payment_allocations a

  join public.supplier_payments p
    on p.id =
       a.payment_id

  where a.purchase_invoice_id =
        target_invoice

    and p.status =
        'posted';

  v_open_ap :=
    greatest(
      round(
        v_invoice_total -
        v_paid -
        v_prior_returns,
        2
      ),
      0
    );

  v_ap_part :=
    least(
      v_total,
      v_open_ap
    );

  v_advance_part :=
    greatest(
      v_total -
      v_ap_part,
      0
    );

  v_ap :=
    public.finance_system_account(
      target_company,
      'accounts_payable'
    );

  v_supplier_advance :=
    public.finance_system_account(
      target_company,
      'supplier_advances'
    );

  v_clearing :=
    public.finance_system_account(
      target_company,
      'inventory_clearing'
    );

  v_variance_account :=
    public.finance_system_account(
      target_company,
      'purchase_variance'
    );

  if v_ap_part > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          v_ap_part,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'تخفيض ذمة المورد'
        )
      );
  end if;

  if v_advance_part > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_supplier_advance,
          'debit',
          v_advance_part,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'رصيد مستحق من المورد'
        )
      );
  end if;

  if v_cost_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          0,
          'credit',
          v_cost_total,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'مرتجع مخزون للمورد'
        )
      );
  end if;

  v_variance :=
    round(
      v_total -
      v_cost_total,
      2
    );

  if v_variance > 0 then

    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          0,
          'credit',
          v_variance,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'عكس فروقات شراء'
        )
      );

  elsif v_variance < 0 then

    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          abs(v_variance),
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'تسوية مرتجع شراء'
        )
      );

  end if;

  v_entry :=
    public.post_system_journal(
      target_company,
      coalesce(
        target_date,
        current_date
      ),
      'مرتجع مشتريات ' ||
      v_number,
      v_currency,
      null,
      'purchase_return',
      v_return,
      v_lines
    );

  update public.purchase_returns
  set
    inventory_cost_total =
      round(
        v_cost_total,
        2
      ),

    total =
      round(
        v_total,
        2
      ),

    journal_entry_id =
      v_entry

  where id =
        v_return;

  perform
    public.recalc_purchase_invoice_payment(
      target_invoice
    );

  return v_return;
end;
$function$;

create or replace function public.create_sales_order_from_approved_payload(target_company uuid, target_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order uuid;
  v_trader uuid;
  v_notes text;
  v_items jsonb;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
  v_total numeric(18,2) := 0;
begin
  v_trader := (target_payload->>'trader_id')::uuid;
  v_notes := target_payload->>'notes';
  v_items := target_payload->'items';

  if not exists(
    select 1 from public.traders
    where id=v_trader and company_id=target_company and status <> 'inactive'
  ) then raise exception 'Invalid trader'; end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items)=0 then
    raise exception 'Invalid approved order payload';
  end if;

  insert into public.sales_orders(company_id,trader_id,status,payment_status,notes)
  values(target_company,v_trader,'new','unpaid',nullif(btrim(v_notes),''))
  returning id into v_order;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_product := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::numeric;
    v_price := (v_item->>'sale_unit_price')::numeric;

    if v_quantity <= 0 or v_price < 0 or not exists(
      select 1 from public.products
      where id=v_product and company_id=target_company and active=true
    ) then raise exception 'Invalid approved order item'; end if;

    insert into public.sales_order_items(
      order_id,product_id,quantity,sale_unit_price,line_total
    ) values(
      v_order,v_product,v_quantity,v_price,round(v_quantity*v_price,2)
    );

    v_total := v_total + round(v_quantity*v_price,2);
  end loop;

  update public.sales_orders set subtotal=v_total,total=v_total where id=v_order;

  perform public.reserve_sales_order(target_company,v_order);

  return v_order;
end;
$function$;

create or replace function public.create_sales_return(target_company uuid, target_invoice uuid, target_warehouse uuid, target_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_return uuid;
  v_number text;

  v_trader uuid;
  v_currency text;

  v_invoice_date date;
  v_return_date date;
  v_today date;

  v_invoice_total numeric(18,2);
  v_invoice_subtotal numeric(18,2);
  v_invoice_discount numeric(18,2);

  v_item jsonb;
  v_invoice_item uuid;
  v_product uuid;
  v_description text;
  v_unit text;
  v_invoice_qty numeric(14,3);
  v_unit_price numeric(18,2);
  v_qty numeric(14,3);

  v_returned numeric(14,3);
  v_line_total numeric(18,2);

  v_subtotal numeric(18,2) := 0;
  v_discount numeric(18,2) := 0;
  v_total numeric(18,2) := 0;

  v_prior_discount numeric(18,2);
  v_prior_returns numeric(18,2);
  v_paid numeric(18,2);
  v_open_ar numeric(18,2);

  v_ar_part numeric(18,2);
  v_credit_part numeric(18,2);

  v_cost numeric(18,4);

  v_return_item uuid;

  v_sales_returns_account uuid;
  v_discount_account uuid;
  v_ar_account uuid;
  v_customer_advance uuid;

  v_lines jsonb := '[]'::jsonb;
  v_entry uuid;

  v_alloc record;
  v_to_free numeric(18,2);
  v_cut numeric(18,2);
  v_cut_pay numeric(20,2);
  v_release uuid;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if items_payload is null
     or jsonb_typeof(
          items_payload
        ) <> 'array'
     or jsonb_array_length(
          items_payload
        ) = 0
  then
    raise exception
      'Return requires items';
  end if;

  select
    trader_id,
    currency,
    invoice_date,
    total,
    subtotal,
    discount_total
  into
    v_trader,
    v_currency,
    v_invoice_date,
    v_invoice_total,
    v_invoice_subtotal,
    v_invoice_discount
  from public.sales_invoices
  where id =
        target_invoice

    and company_id =
        target_company

    and status =
        'posted'
  for update;

  if v_trader is null then
    raise exception
      'Posted sales invoice not found';
  end if;

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  v_return_date :=
    coalesce(
      target_date,
      v_today
    );

  if v_return_date <
     v_invoice_date
  then
    raise exception
      'Return date cannot be before invoice date';
  end if;

  if v_return_date >
     v_today
  then
    raise exception
      'Return date cannot be in the future';
  end if;

  if not exists(
    select 1
    from public.warehouses
    where id =
          target_warehouse
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid warehouse';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      v_return_date
    );

  v_number :=
    public.next_sales_return_number(
      target_company,
      v_return_date
    );

  insert into public.sales_returns(
    company_id,
    return_number,
    sales_invoice_id,
    trader_id,
    warehouse_id,
    return_date,
    status,
    currency,
    notes
  )
  values(
    target_company,
    v_number,
    target_invoice,
    v_trader,
    target_warehouse,
    v_return_date,
    'posted',
    v_currency,
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_return;

  for v_item in
    select value
    from jsonb_array_elements(
      items_payload
    )
  loop
    begin
      v_invoice_item :=
        (
          v_item->>'sales_invoice_item_id'
        )::uuid;

      v_qty :=
        (
          v_item->>'quantity'
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid sales return item';
    end;

    if v_qty is null
       or v_qty <= 0
    then
      raise exception
        'Return quantity must be greater than zero';
    end if;

    select
      product_id,
      description,
      unit,
      quantity,
      unit_price
    into
      v_product,
      v_description,
      v_unit,
      v_invoice_qty,
      v_unit_price
    from public.sales_invoice_items
    where id =
          v_invoice_item

      and invoice_id =
          target_invoice

      and company_id =
          target_company;

    if v_product is null then
      raise exception
        'Invalid sales invoice item';
    end if;

    select
      coalesce(
        sum(sri.quantity),
        0
      )
    into v_returned
    from public.sales_return_items sri

    join public.sales_returns sr
      on sr.id =
         sri.sales_return_id

    where sri.sales_invoice_item_id =
          v_invoice_item

      and sr.status =
          'posted';

    if round(
         v_returned +
         v_qty,
         3
       ) >
       round(
         v_invoice_qty,
         3
       )
    then
      raise exception
        'Returned quantity exceeds invoiced quantity';
    end if;

    v_line_total :=
      round(
        v_unit_price *
        v_qty,
        2
      );

    insert into public.sales_return_items(
      company_id,
      sales_return_id,
      sales_invoice_item_id,
      product_id,
      description,
      unit,
      quantity,
      unit_price,
      line_total
    )
    values(
      target_company,
      v_return,
      v_invoice_item,
      v_product,
      v_description,
      v_unit,
      v_qty,
      v_unit_price,
      v_line_total
    )
    returning id
    into v_return_item;

    select
      coalesce(
        (
          select
            sum(
              abs(im.quantity) *
              coalesce(
                im.unit_cost,
                0
              )
            )
            /
            nullif(
              sum(
                abs(im.quantity)
              ),
              0
            )

          from public.inventory_movements im

          where im.company_id =
                target_company

            and im.product_id =
                v_product

            and im.movement_type =
                'sales_delivery'

            and im.source_table =
                'deliveries'

            and im.source_id in (
              select
                l.delivery_id
              from public.sales_invoice_delivery_links l
              where l.sales_invoice_id =
                    target_invoice
            )
        ),
        (
          select average_cost
          from public.inventory_stock
          where company_id =
                target_company
            and warehouse_id =
                target_warehouse
            and product_id =
                v_product
          limit 1
        ),
        0
      )
    into v_cost;

    perform
      public.post_inventory_movement(
        target_company,
        target_warehouse,
        v_product,
        'sales_return',
        v_qty,
        v_cost,
        'sales_returns',
        v_return,
        v_return_item,
        v_number,
        target_notes,
        (v_return_date::timestamp at time zone 'Asia/Damascus')
      );

    perform
      public.reserve_pending_orders_for_product(
        target_company,
        target_warehouse,
        v_product
      );

    v_subtotal :=
      v_subtotal +
      v_line_total;
  end loop;

  select
    coalesce(
      sum(discount_total),
      0
    ),
    coalesce(
      sum(total),
      0
    )
  into
    v_prior_discount,
    v_prior_returns
  from public.sales_returns
  where sales_invoice_id =
        target_invoice

    and status =
        'posted'

    and id <>
        v_return;

  if v_invoice_subtotal > 0
     and v_invoice_discount > 0
  then
    v_discount :=
      least(
        greatest(
          v_invoice_discount -
          v_prior_discount,
          0
        ),

        round(
          v_invoice_discount *
          (
            v_subtotal /
            v_invoice_subtotal
          ),
          2
        )
      );
  else
    v_discount := 0;
  end if;

  v_total :=
    greatest(
      round(
        v_subtotal -
        v_discount,
        2
      ),
      0
    );

  select
    coalesce(
      sum(a.amount),
      0
    )
  into v_paid
  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id =
       a.payment_id

  where a.sales_invoice_id =
        target_invoice

    and p.status =
        'posted';

  v_open_ar :=
    greatest(
      round(
        v_invoice_total -
        v_paid -
        v_prior_returns,
        2
      ),
      0
    );

  v_ar_part :=
    least(
      v_total,
      v_open_ar
    );

  v_credit_part :=
    greatest(
      v_total -
      v_ar_part,
      0
    );

  v_sales_returns_account :=
    public.finance_system_account(
      target_company,
      'sales_returns'
    );

  v_discount_account :=
    public.finance_system_account(
      target_company,
      'sales_discounts'
    );

  v_ar_account :=
    public.finance_system_account(
      target_company,
      'accounts_receivable'
    );

  v_customer_advance :=
    public.finance_system_account(
      target_company,
      'customer_advances'
    );

  -- الفاتورة مدفوعة (كلها أو قسم منها) أكتر من اللي ضل عليها بعد المرتجع:
  -- منحرّر الفرق من آخر دفعات انخصمت عليها، فبيصير رصيد للزبون بينخصم من فواتيره الجاية.
  v_to_free := v_credit_part;

  for v_alloc in
    select
      a.*,
      (
        select je.exchange_rate_to_base
        from public.journal_entries je
        where je.company_id = target_company
          and je.source_type = 'customer_payment_allocation'
          and je.source_id = a.id
          and je.reversed_from_id is null
        limit 1
      ) as journal_rate
    from public.customer_payment_allocations a
    join public.customer_payments p
      on p.id = a.payment_id
    where a.sales_invoice_id = target_invoice
      and p.status = 'posted'
    order by p.payment_date desc, p.created_at desc
    for update of a
  loop
    exit when v_to_free <= 0;

    v_cut := least(v_alloc.amount, v_to_free);

    v_cut_pay :=
      case
        when v_cut >= v_alloc.amount
          then coalesce(v_alloc.payment_amount, v_alloc.amount)
        else round(
          coalesce(v_alloc.payment_amount, v_alloc.amount) * v_cut / v_alloc.amount,
          2
        )
      end;

    insert into public.customer_payment_releases(
      company_id,
      payment_id,
      allocation_id,
      sales_return_id,
      sales_invoice_id,
      amount,
      payment_amount,
      payment_currency
    )
    values(
      target_company,
      v_alloc.payment_id,
      v_alloc.id,
      v_return,
      target_invoice,
      v_cut,
      v_cut_pay,
      coalesce(v_alloc.payment_currency, v_currency)
    )
    returning id
    into v_release;

    -- عكس جزء التخصيص: الذمة بترجع، ورصيد الزبون الدائن بيزيد (بنفس عملة وسعر الدفعة).
    perform
      public.post_system_journal(
        target_company,
        v_return_date,
        'تحرير دفعة بسبب مرتجع ' || v_number,
        coalesce(v_alloc.payment_currency, v_currency),
        v_alloc.journal_rate,
        'customer_payment_release',
        v_release,
        jsonb_build_array(
          jsonb_build_object(
            'account_id', v_ar_account,
            'debit', v_cut_pay,
            'credit', 0,
            'party_type', 'trader',
            'party_id', v_trader,
            'memo', 'تحرير دفعة'
          ),
          jsonb_build_object(
            'account_id', v_customer_advance,
            'debit', 0,
            'credit', v_cut_pay,
            'party_type', 'trader',
            'party_id', v_trader,
            'memo', 'رصيد دائن للعميل'
          )
        )
      );

    if v_cut >= v_alloc.amount then
      delete from public.customer_payment_allocations
      where id = v_alloc.id;
    else
      update public.customer_payment_allocations
      set
        amount = amount - v_cut,
        payment_amount = coalesce(payment_amount, amount) - v_cut_pay
      where id = v_alloc.id;
    end if;

    v_to_free := v_to_free - v_cut;
  end loop;

  -- اللي ما لقينالو دفعة (حالة نادرة) بيضل رصيد دائن مباشر متل قبل.
  v_credit_part := greatest(v_to_free, 0);
  v_ar_part := v_total - v_credit_part;

  if v_subtotal > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_sales_returns_account,
          'debit',
          v_subtotal,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          v_trader,
          'memo',
          'مرتجع مبيعات'
        )
      );
  end if;

  if v_discount > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_discount_account,
          'debit',
          0,
          'credit',
          v_discount,
          'party_type',
          'trader',
          'party_id',
          v_trader,
          'memo',
          'عكس خصم مبيعات'
        )
      );
  end if;

  if v_ar_part > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ar_account,
          'debit',
          0,
          'credit',
          v_ar_part,
          'party_type',
          'trader',
          'party_id',
          v_trader,
          'memo',
          'تخفيض ذمة العميل'
        )
      );
  end if;

  if v_credit_part > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_customer_advance,
          'debit',
          0,
          'credit',
          v_credit_part,
          'party_type',
          'trader',
          'party_id',
          v_trader,
          'memo',
          'رصيد دائن للعميل'
        )
      );
  end if;

  v_entry :=
    public.post_system_journal(
      target_company,
      v_return_date,
      'مرتجع مبيعات ' ||
      v_number,
      v_currency,
      null,
      'sales_return',
      v_return,
      v_lines
    );

  update public.sales_returns
  set
    subtotal =
      round(
        v_subtotal,
        2
      ),

    discount_total =
      round(
        v_discount,
        2
      ),

    total =
      round(
        v_total,
        2
      ),

    journal_entry_id =
      v_entry

  where id =
        v_return;

  perform
    public.recalc_sales_invoice_payment(
      target_invoice
    );

  return v_return;
end;
$function$;

create or replace function public.get_purchase_return_candidates(target_company uuid, target_search text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.purchase_invoices pi

  join public.suppliers s
    on s.id =
       pi.supplier_id

  where pi.company_id =
        target_company

    and pi.status =
        'posted'

    and (
      v_search is null

      or pi.invoice_number
         ilike
         '%' || v_search || '%'

      or coalesce(
           pi.supplier_invoice_number,
           ''
         )
         ilike
         '%' || v_search || '%'

      or s.name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.purchase_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = pi.id
          and pr.name ilike '%' || v_search || '%'
      )
    )

    and exists (
      select 1
      from public.purchase_invoice_items pii

      where pii.invoice_id =
            pi.id

        and pii.company_id =
            target_company

        and round(
              coalesce(
                (
                  select
                    sum(gri.quantity)

                  from public.goods_receipt_items gri

                  join public.goods_receipts gr
                    on gr.id =
                       gri.goods_receipt_id

                  where gri.purchase_invoice_item_id =
                        pii.id

                    and gr.company_id =
                        target_company

                    and gr.purchase_invoice_id =
                        pi.id

                    and gr.status =
                        'posted'
                ),
                0
              )
              -
              coalesce(
                (
                  select
                    sum(pri.quantity)

                  from public.purchase_return_items pri

                  join public.purchase_returns pr
                    on pr.id =
                       pri.purchase_return_id

                  where pri.purchase_invoice_item_id =
                        pii.id

                    and pr.company_id =
                        target_company

                    and pr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      pi.invoice_date
        as sort_date,

      pi.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          pi.id,

        'invoice_number',
          pi.invoice_number,

        'supplier_invoice_number',
          pi.supplier_invoice_number,

        'invoice_date',
          pi.invoice_date,

        'currency',
          pi.currency,

        'total',
          pi.total,

        'supplier',
          jsonb_build_object(
            'id',
              s.id,

            'name',
              s.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.purchase_invoices pi

    join public.suppliers s
      on s.id =
         pi.supplier_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'invoiced_quantity',
              x.invoiced_quantity,

            'received_quantity',
              x.received_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.received_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.received_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          pii.id,
          pii.product_id,
          pii.description,
          pii.quantity
            as invoiced_quantity,
          pii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(gri.quantity)

              from public.goods_receipt_items gri

              join public.goods_receipts gr
                on gr.id =
                   gri.goods_receipt_id

              where gri.purchase_invoice_item_id =
                    pii.id

                and gr.company_id =
                    target_company

                and gr.purchase_invoice_id =
                    pi.id

                and gr.status =
                    'posted'
            ),
            0
          ) as received_quantity,

          coalesce(
            (
              select
                sum(pri.quantity)

              from public.purchase_return_items pri

              join public.purchase_returns pr
                on pr.id =
                   pri.purchase_return_id

              where pri.purchase_invoice_item_id =
                    pii.id

                and pr.company_id =
                    target_company

                and pr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.purchase_invoice_items pii

        join public.products p
          on p.id =
             pii.product_id

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company
      ) x
    ) items
      on true

    where pi.company_id =
          target_company

      and pi.status =
          'posted'

      and (
        v_search is null

        or pi.invoice_number
           ilike
           '%' || v_search || '%'

        or coalesce(
             pi.supplier_invoice_number,
             ''
           )
           ilike
           '%' || v_search || '%'

        or s.name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.purchase_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = pi.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

      and exists (
        select 1
        from public.purchase_invoice_items pii

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company

          and round(
                coalesce(
                  (
                    select
                      sum(gri.quantity)

                    from public.goods_receipt_items gri

                    join public.goods_receipts gr
                      on gr.id =
                         gri.goods_receipt_id

                    where gri.purchase_invoice_item_id =
                          pii.id

                      and gr.company_id =
                          target_company

                      and gr.purchase_invoice_id =
                          pi.id

                      and gr.status =
                          'posted'
                  ),
                  0
                )
                -
                coalesce(
                  (
                    select
                      sum(pri.quantity)

                    from public.purchase_return_items pri

                    join public.purchase_returns pr
                      on pr.id =
                         pri.purchase_return_id

                    where pri.purchase_invoice_item_id =
                          pii.id

                      and pr.company_id =
                          target_company

                      and pr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      pi.invoice_date desc,
      pi.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_return_warehouses(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            w.id,

          'name',
            w.name,

          'code',
            w.code,

          'is_default',
            w.is_default
        )
        order by
          w.is_default desc,
          w.name
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from public.warehouses w
  where w.company_id =
        target_company
    and w.active = true;

  return v_rows;
end;
$function$;

create or replace function public.get_returns_history(target_company uuid, target_search text DEFAULT NULL::text, target_kind text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_kind text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_kind :=
    case
      when target_kind in (
        'sales',
        'purchases'
      )
      then target_kind
      else null
    end;

  v_status :=
    case
      when target_status in (
        'posted',
        'reversed',
        'cancelled'
      )
      then target_status
      else null
    end;

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    count(*)::bigint
  into
    v_total
  from history h
  where (
      v_kind is null
      or h.kind =
         v_kind
    )
    and (
      v_status is null
      or h.status =
         v_status
    )
    and (
      v_search is null

      or h.return_number
         ilike
         '%' || v_search || '%'

      or h.invoice_number
         ilike
         '%' || v_search || '%'

      or h.party_name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.sales_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'sales'
          and x.sales_return_id = h.id
          and pr.name ilike '%' || v_search || '%'
      )

      or exists (
        select 1
        from public.purchase_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'purchases'
          and x.purchase_return_id = h.id
          and pr.name ilike '%' || v_search || '%'
      )
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            q.id,

          'kind',
            q.kind,

          'return_number',
            q.return_number,

          'invoice_number',
            q.invoice_number,

          'party_name',
            q.party_name,

          'warehouse_name',
            q.warehouse_name,

          'return_date',
            q.return_date,

          'status',
            q.status,

          'currency',
            q.currency,

          'total',
            q.total,

          'notes',
            q.notes,

          'created_at',
            q.created_at,

          'reversed_at',
            q.reversed_at,

          'reversal_reason',
            q.reversal_reason
        )
        order by
          q.return_date desc,
          q.created_at desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select *
    from history h
    where (
        v_kind is null
        or h.kind =
           v_kind
      )
      and (
        v_status is null
        or h.status =
           v_status
      )
      and (
        v_search is null

        or h.return_number
           ilike
           '%' || v_search || '%'

        or h.invoice_number
           ilike
           '%' || v_search || '%'

        or h.party_name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.sales_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'sales'
            and x.sales_return_id = h.id
            and pr.name ilike '%' || v_search || '%'
        )

        or exists (
          select 1
          from public.purchase_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'purchases'
            and x.purchase_return_id = h.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

    order by
      h.return_date desc,
      h.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_returns_summary(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sales_count bigint;
  v_purchase_count bigint;

  v_sales_posted bigint;
  v_purchase_posted bigint;

  v_sales_reversed bigint;
  v_purchase_reversed bigint;

  v_sales_totals jsonb;
  v_purchase_totals jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_sales_count,
    v_sales_posted,
    v_sales_reversed
  from public.sales_returns
  where company_id =
        target_company;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_purchase_count,
    v_purchase_posted,
    v_purchase_reversed
  from public.purchase_returns
  where company_id =
        target_company;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_sales_totals
  from (
    select
      upper(sr.currency)
        as currency,

      round(
        sum(sr.total),
        2
      ) as total

    from public.sales_returns sr

    where sr.company_id =
          target_company

      and sr.status =
          'posted'

    group by
      upper(sr.currency)
  ) x;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_purchase_totals
  from (
    select
      upper(pr.currency)
        as currency,

      round(
        sum(pr.total),
        2
      ) as total

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.status =
          'posted'

    group by
      upper(pr.currency)
  ) x;

  return
    jsonb_build_object(
      'sales_count',
        v_sales_count,

      'sales_posted_count',
        v_sales_posted,

      'sales_reversed_count',
        v_sales_reversed,

      'purchase_count',
        v_purchase_count,

      'purchase_posted_count',
        v_purchase_posted,

      'purchase_reversed_count',
        v_purchase_reversed,

      'sales_totals',
        v_sales_totals,

      'purchase_totals',
        v_purchase_totals
    );
end;
$function$;

create or replace function public.get_sales_return_candidates(target_company uuid, target_search text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.sales_invoices si

  join public.traders t
    on t.id =
       si.trader_id

  where si.company_id =
        target_company

    and si.status =
        'posted'

    and (
      v_search is null

      or si.invoice_number
         ilike
         '%' || v_search || '%'

      or t.name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.sales_orders so
        where so.id = si.order_id
          and so.order_number ilike '%' || v_search || '%'
      )

      or exists (
        select 1
        from public.sales_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = si.id
          and pr.name ilike '%' || v_search || '%'
      )
    )

    and exists (
      select 1
      from public.sales_invoice_items sii
      where sii.invoice_id =
            si.id
        and sii.company_id =
            target_company

        and round(
              sii.quantity -
              coalesce(
                (
                  select
                    sum(sri.quantity)

                  from public.sales_return_items sri

                  join public.sales_returns sr
                    on sr.id =
                       sri.sales_return_id

                  where sri.sales_invoice_item_id =
                        sii.id

                    and sr.company_id =
                        target_company

                    and sr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      si.invoice_date
        as sort_date,

      si.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          si.id,

        'invoice_number',
          si.invoice_number,

        'invoice_date',
          si.invoice_date,

        'currency',
          si.currency,

        'total',
          si.total,

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_invoices si

    join public.traders t
      on t.id =
         si.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'unit',
              x.unit,

            'invoiced_quantity',
              x.invoiced_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.invoiced_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.invoiced_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          sii.id,
          sii.product_id,
          sii.description,
          sii.unit,
          sii.quantity
            as invoiced_quantity,
          sii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(sri.quantity)

              from public.sales_return_items sri

              join public.sales_returns sr
                on sr.id =
                   sri.sales_return_id

              where sri.sales_invoice_item_id =
                    sii.id

                and sr.company_id =
                    target_company

                and sr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.sales_invoice_items sii

        join public.products p
          on p.id =
             sii.product_id

        where sii.invoice_id =
              si.id

          and sii.company_id =
              target_company
      ) x
    ) items
      on true

    where si.company_id =
          target_company

      and si.status =
          'posted'

      and (
        v_search is null

        or si.invoice_number
           ilike
           '%' || v_search || '%'

        or t.name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.sales_orders so
          where so.id = si.order_id
            and so.order_number ilike '%' || v_search || '%'
        )

        or exists (
          select 1
          from public.sales_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = si.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

      and exists (
        select 1
        from public.sales_invoice_items sii
        where sii.invoice_id =
              si.id
          and sii.company_id =
              target_company

          and round(
                sii.quantity -
                coalesce(
                  (
                    select
                      sum(sri.quantity)

                    from public.sales_return_items sri

                    join public.sales_returns sr
                      on sr.id =
                         sri.sales_return_id

                    where sri.sales_invoice_item_id =
                          sii.id

                      and sr.company_id =
                          target_company

                      and sr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      si.invoice_date desc,
      si.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.next_purchase_return_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'purchase_return',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id =
        target_company
    and document_type =
        'purchase_return'
    and sequence_year =
        v_year
  for update;

  update public.document_sequences
  set next_value =
      next_value + 1
  where company_id =
        target_company
    and document_type =
        'purchase_return'
    and sequence_year =
        v_year;

  return
    'PR-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.next_sales_return_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        current_date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'sales_return',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id =
        target_company
    and document_type =
        'sales_return'
    and sequence_year =
        v_year
  for update;

  update public.document_sequences
  set next_value =
      next_value + 1
  where company_id =
        target_company
    and document_type =
        'sales_return'
    and sequence_year =
        v_year;

  return
    'SR-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.resolve_approval_request(target_company uuid, target_request uuid, target_decision text, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text;
  v_payload jsonb;
  v_reference_type text;
  v_reference_id uuid;
  v_order uuid;
  v_quote uuid;
  v_quote_status text;
  v_valid_until date;
begin
  if not public.has_permission(
    target_company,
    'approvals.resolve'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_decision not in (
    'approved',
    'rejected'
  ) then
    raise exception
      'Invalid approval decision';
  end if;

  select
    request_type,
    payload,
    reference_type,
    reference_id

  into
    v_type,
    v_payload,
    v_reference_type,
    v_reference_id

  from public.approval_requests

  where id =
        target_request

    and company_id =
        target_company

    and status =
        'pending'

  for update;

  if not found then
    raise exception
      'Pending approval request not found';
  end if;

  if v_type =
     'below_cost_order'
  then

    v_quote :=
      nullif(
        v_payload->>'source_quote_id',
        ''
      )::uuid;

    if v_quote is not null then

      select
        q.status,
        q.valid_until

      into
        v_quote_status,
        v_valid_until

      from public.sales_quotes q

      where q.id =
            v_quote

        and q.company_id =
            target_company

      for update;

      if not found then
        raise exception
          'Quote not found';
      end if;

      if target_decision =
         'approved'
      then

        if v_quote_status <>
           'accepted'
        then
          raise exception
            'Quote is no longer accepted';
        end if;

        if v_valid_until is not null
           and v_valid_until <
               (
                 now()
                 at time zone
                 'Asia/Damascus'
               )::date
        then
          raise exception
            'Quote has expired';
        end if;

        perform
          public.validate_sales_quote_conversion_source(
            target_company,
            v_quote,
            (v_payload->>'trader_id')::uuid,
            v_payload->'items'
          );

      end if;

    end if;

    if target_decision =
       'approved'
    then

      v_order :=
        public.create_sales_order_from_approved_payload(
          target_company,
          v_payload
        );

      if v_quote is not null then
        update public.sales_quotes
        set
          status =
            'converted',

          converted_order_id =
            v_order

        where id =
              v_quote

          and company_id =
              target_company

          and converted_order_id
              is null;
      end if;

      v_payload :=
        coalesce(
          v_payload,
          '{}'::jsonb
        ) ||
        jsonb_build_object(
          'order_id',
          v_order
        );

      v_reference_type :=
        'sales_order';

      v_reference_id :=
        v_order;

    elsif v_quote is not null then

      update public.sales_quotes
      set status =
          'rejected'

      where id =
            v_quote

        and company_id =
            target_company

        and status =
            'accepted'

        and converted_order_id
            is null;

    end if;

  end if;

  update public.approval_requests
  set
    status =
      target_decision,

    resolved_by =
      auth.uid(),

    resolved_at =
      now(),

    resolution_notes =
      nullif(
        trim(
          target_notes
        ),
        ''
      ),

    payload =
      v_payload,

    reference_type =
      v_reference_type,

    reference_id =
      v_reference_id

  where id =
        target_request

    and company_id =
        target_company;
end;
$function$;

create or replace function public.reverse_purchase_return(target_company uuid, target_return uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_item record;
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;


  select
    status,
    purchase_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.purchase_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Purchase return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted purchase returns can be reversed';
  end if;


  for v_item in

    select
      pri.id,
      pri.product_id,
      pri.quantity

    from public.purchase_return_items pri

    where pri.purchase_return_id =
          target_return

    order by pri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'purchase_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'purchase_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for purchase return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'purchase_receipt',
        v_item.quantity,
        v_cost,
        'purchase_return_reversals',
        target_return,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );


    perform
      public.reserve_pending_orders_for_product(
        target_company,
        v_warehouse,
        v_item.product_id
      );

  end loop;


  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مشتريات ' ||
      v_number,
      'purchase_return_reversal',
      target_return
    );


  update public.purchase_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_purchase_invoice_payment(
      v_invoice
    );

end;
$function$;

create or replace function public.reverse_return_financial_journal(target_company uuid, target_original_journal uuid, target_currency text, target_description text, target_source_type text, target_source_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lines jsonb;
  v_entry uuid;
  v_reversal_date date;
begin
  if target_original_journal is null then
    raise exception
      'Return financial journal is missing';
  end if;


  select
    coalesce(
      jsonb_agg(
        jsonb_strip_nulls(
          jsonb_build_object(
            'account_id',
            coalesce(
              nullif(
                x->>'account_id',
                ''
              ),
              nullif(
                x->>'finance_account_id',
                ''
              )
            ),

            'debit',
            coalesce(
              nullif(
                x->>'credit',
                ''
              )::numeric,
              nullif(
                x->>'credit_amount',
                ''
              )::numeric,
              0
            ),

            'credit',
            coalesce(
              nullif(
                x->>'debit',
                ''
              )::numeric,
              nullif(
                x->>'debit_amount',
                ''
              )::numeric,
              0
            ),

            'party_type',
            nullif(
              x->>'party_type',
              ''
            ),

            'party_id',
            nullif(
              x->>'party_id',
              ''
            ),

            'memo',
            case
              when nullif(
                     x->>'memo',
                     ''
                   ) is not null
              then
                'عكس - ' ||
                (x->>'memo')
              else
                target_description
            end
          )
        )
      ),
      '[]'::jsonb
    )
  into v_lines
  from (
    select
      to_jsonb(jl) as x
    from public.journal_lines jl
    where
      coalesce(
        to_jsonb(jl)
          ->>'journal_entry_id',

        to_jsonb(jl)
          ->>'entry_id'
      ) =
      target_original_journal::text
  ) q;


  if jsonb_array_length(
       v_lines
     ) = 0
  then
    raise exception
      'Original journal lines not found';
  end if;


  if exists(
    select 1
    from jsonb_array_elements(
      v_lines
    ) line
    where nullif(
            line->>'account_id',
            ''
          ) is null
  ) then
    raise exception
      'Original journal contains an invalid account';
  end if;


  v_reversal_date :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  perform
    public.assert_finance_period_open(
      target_company,
      v_reversal_date
    );


  -- Signature used by the current accounting engine:
  --
  -- post_system_journal(
  --   company,
  --   entry_date,
  --   description,
  --   currency,
  --   exchange_rate,
  --   source_type,
  --   source_id,
  --   lines
  -- )

  execute
    'select public.post_system_journal(
       $1,$2,$3,$4,$5,$6,$7,$8
     )'
  into v_entry
  using
    target_company,
    v_reversal_date,
    target_description,
    upper(target_currency),
    null::numeric,
    target_source_type,
    target_source_id,
    v_lines;


  if v_entry is null then
    raise exception
      'Financial reversal journal was not created';
  end if;

  return v_entry;
end;
$function$;

create or replace function public.reverse_sales_return(target_company uuid, target_return uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_product record;
  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;


  select
    status,
    sales_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.sales_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Sales return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted sales returns can be reversed';
  end if;


  -- ----------------------------------------------------------
  -- Validate the total quantity by product BEFORE changing
  -- anything.
  --
  -- We only remove AVAILABLE stock, never active reservations.
  -- ----------------------------------------------------------

  for v_product in

    select
      sri.product_id,
      sum(
        sri.quantity
      ) as quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    group by
      sri.product_id

  loop

    select
      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                target_company

            and r.warehouse_id =
                v_warehouse

            and r.product_id =
                v_product.product_id

            and r.status =
                'active'
        ),
        0
      )

    into
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          v_warehouse

      and s.product_id =
          v_product.product_id;


    if
      coalesce(
        v_on_hand,
        0
      ) -
      coalesce(
        v_reserved,
        0
      )
      <
      v_product.quantity
    then
      raise exception
        'Cannot reverse sales return: returned stock was already reserved, transferred or used';
    end if;

  end loop;


  -- ----------------------------------------------------------
  -- Reverse every original return stock movement.
  -- ----------------------------------------------------------

  for v_item in

    select
      sri.id,
      sri.product_id,
      sri.quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    order by sri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'sales_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'sales_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for sales return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'sales_delivery',
        -v_item.quantity,
        v_cost,
        'sales_return_reversals',
        target_return,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

  end loop;


  -- ----------------------------------------------------------
  -- Reverse financial credit-note journal.
  -- Inventory accounting is already reversed by the inventory
  -- movements above.
  -- ----------------------------------------------------------

  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مبيعات ' ||
      v_number,
      'sales_return_reversal',
      target_return
    );


  update public.sales_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_sales_invoice_payment(
      v_invoice
    );

  -- الفاتورة رجعت عليها ذمة: إذا الزبون عندو رصيد (من دفعة محرّرة مثلًا) بينخصم فورًا.
  perform
    public.apply_customer_credit_to_invoice(
      v_invoice
    );

end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger approval_requests_updated_at before update on public.approval_requests for each row execute function public.set_updated_at();

create trigger audit_approval_requests after insert or delete or update on public.approval_requests for each row execute function public.write_audit_log();

create trigger block_purchase_invoice_cancel_with_return before update of status on public.purchase_invoices for each row execute function public.block_invoice_cancel_with_posted_return();

create trigger audit_purchase_return_items after insert or delete or update on public.purchase_return_items for each row execute function public.write_audit_log();

create trigger audit_purchase_returns after insert or delete or update on public.purchase_returns for each row execute function public.write_audit_log();

create trigger block_sales_invoice_cancel_with_return before update of status on public.sales_invoices for each row execute function public.block_invoice_cancel_with_posted_return();

create trigger audit_sales_return_items after insert or delete or update on public.sales_return_items for each row execute function public.write_audit_log();

create trigger audit_sales_returns after insert or delete or update on public.sales_returns for each row execute function public.write_audit_log();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;
alter table public.approval_requests enable row level security;
create policy approval_requests_read on public.approval_requests
  for select to authenticated
  using (public.has_permission(company_id, 'approvals.view'::text));
create policy purchase_return_items_read on public.purchase_return_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'purchase_invoices.view'::text, 'products.view_cost'::text, 'reports.finance'::text]));
create policy purchase_returns_read on public.purchase_returns
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'purchase_invoices.view'::text, 'reports.finance'::text]));
create policy sales_return_items_read on public.sales_return_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'sales_invoices.view'::text, 'inventory.returns'::text, 'reports.finance'::text]));
create policy sales_returns_read on public.sales_returns
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'sales_invoices.view'::text, 'inventory.returns'::text, 'reports.finance'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.sales_returns from authenticated;
revoke insert, update, delete on public.sales_return_items from authenticated;
revoke select, insert, update, delete on public.purchase_returns from authenticated;
grant select (id, company_id, return_number, purchase_invoice_id, supplier_id, warehouse_id, return_date, status, currency, total, notes, journal_entry_id, created_by, created_at) on public.purchase_returns to authenticated;
revoke select, insert, update, delete on public.purchase_return_items from authenticated;
grant select (id, company_id, purchase_return_id, purchase_invoice_item_id, product_id, description, quantity, line_total, created_at) on public.purchase_return_items to authenticated;
revoke insert, update, delete on public.approval_requests from authenticated;
revoke execute on function public.can_view_returns(uuid) from authenticated;
revoke execute on function public.create_sales_order_from_approved_payload(uuid,jsonb) from authenticated;
revoke execute on function public.next_purchase_return_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_return_number(uuid,date) from authenticated;
revoke execute on function public.reverse_return_financial_journal(uuid,uuid,text,text,text,uuid) from authenticated;

-- ======================================================================
-- الرواتب
-- الموظفين، مسيرات الرواتب، السلف والقروض
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  employee_number text,
  full_name text not null,
  phone text,
  job_title text,
  department text,
  hire_date date,
  termination_date date,
  status text default 'active'::text not null,
  salary_currency text default 'USD'::text not null,
  base_salary numeric(18,2) default 0 not null,
  fixed_allowances numeric(18,2) default 0 not null,
  overtime_hour_rate numeric(18,4) default 0 not null,
  social_security_employee_rate numeric(9,4) default 0 not null,
  social_security_employer_rate numeric(9,4) default 0 not null,
  income_tax_rate numeric(9,4) default 0 not null,
  default_cashbox_id uuid references public.cashboxes(id) on delete set null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint employees_base_salary_check check ((base_salary >= (0)::numeric)),
  constraint employees_fixed_allowances_check check ((fixed_allowances >= (0)::numeric)),
  constraint employees_income_tax_rate_check check ((income_tax_rate >= (0)::numeric)),
  constraint employees_overtime_hour_rate_check check ((overtime_hour_rate >= (0)::numeric)),
  constraint employees_social_security_employee_rate_check check ((social_security_employee_rate >= (0)::numeric)),
  constraint employees_social_security_employer_rate_check check ((social_security_employer_rate >= (0)::numeric)),
  constraint employees_status_check check ((status = any (array['active'::text, 'inactive'::text, 'terminated'::text])))
);
create index employees_company_status_idx on public.employees using btree (company_id, status, full_name);
create unique index employees_number_unique on public.employees using btree (company_id, employee_number) where (employee_number is not null);

create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date,
  status text default 'draft'::text not null,
  currency text default 'USD'::text not null,
  total_gross numeric(18,2) default 0 not null,
  total_deductions numeric(18,2) default 0 not null,
  total_net numeric(18,2) default 0 not null,
  total_paid numeric(18,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone,
  posted_by uuid references auth.users(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint payroll_runs_check check ((period_end >= period_start)),
  constraint payroll_runs_status_check check ((status = any (array['draft'::text, 'posted'::text, 'partial'::text, 'paid'::text, 'cancelled'::text])))
);
create unique index payroll_runs_period_unique on public.payroll_runs using btree (company_id, period_start, period_end) where (status <> 'cancelled'::text);

create table public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  base_salary numeric(18,2) default 0 not null,
  allowances numeric(18,2) default 0 not null,
  overtime_hours numeric(12,2) default 0 not null,
  overtime_amount numeric(18,2) default 0 not null,
  bonuses numeric(18,2) default 0 not null,
  absent_days numeric(12,2) default 0 not null,
  absence_deduction numeric(18,2) default 0 not null,
  loan_deduction numeric(18,2) default 0 not null,
  social_security_deduction numeric(18,2) default 0 not null,
  tax_deduction numeric(18,2) default 0 not null,
  other_deductions numeric(18,2) default 0 not null,
  employer_contribution numeric(18,2) default 0 not null,
  gross_pay numeric(18,2) default 0 not null,
  total_deductions numeric(18,2) default 0 not null,
  net_pay numeric(18,2) default 0 not null,
  paid_total numeric(18,2) default 0 not null,
  balance_due numeric(18,2) default 0 not null,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint payroll_items_payroll_run_id_employee_id_key unique (payroll_run_id, employee_id),
  constraint payroll_items_check check (((base_salary >= (0)::numeric) and (allowances >= (0)::numeric) and (overtime_hours >= (0)::numeric) and (overtime_amount >= (0)::numeric) and (bonuses >= (0)::numeric) and (absent_days >= (0)::numeric) and (absence_deduction >= (0)::numeric) and (loan_deduction >= (0)::numeric) and (social_security_deduction >= (0)::numeric) and (tax_deduction >= (0)::numeric) and (other_deductions >= (0)::numeric) and (employer_contribution >= (0)::numeric) and (gross_pay >= (0)::numeric) and (total_deductions >= (0)::numeric) and (net_pay >= (0)::numeric) and (paid_total >= (0)::numeric) and (balance_due >= (0)::numeric)))
);
create index payroll_items_employee_idx on public.payroll_items using btree (company_id, employee_id);

create table public.payroll_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payroll_item_id uuid not null references public.payroll_items(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  amount numeric(18,2) not null,
  currency text not null,
  payment_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  payment_method text default 'cash'::text not null,
  status text default 'posted'::text not null,
  reference_number text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint payroll_payments_amount_check check ((amount > (0)::numeric)),
  constraint payroll_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index payroll_payments_employee_idx on public.payroll_payments using btree (company_id, employee_id, payment_date desc);

create table public.employee_loans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  loan_type text not null,
  original_amount numeric(18,2) not null,
  balance_due numeric(18,2) not null,
  installment_amount numeric(18,2) default 0 not null,
  start_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  status text default 'active'::text not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint employee_loans_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint employee_loans_installment_amount_check check ((installment_amount >= (0)::numeric)),
  constraint employee_loans_loan_type_check check ((loan_type = any (array['advance'::text, 'loan'::text]))),
  constraint employee_loans_original_amount_check check ((original_amount > (0)::numeric)),
  constraint employee_loans_status_check check ((status = any (array['active'::text, 'settled'::text, 'cancelled'::text])))
);
create index employee_loans_employee_idx on public.employee_loans using btree (company_id, employee_id, status);

create table public.employee_loan_disbursements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_loan_id uuid not null references public.employee_loans(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  amount numeric(18,2) not null,
  currency text not null,
  disbursement_date date not null,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint employee_loan_disbursements_employee_loan_id_key unique (employee_loan_id),
  constraint employee_loan_disbursements_amount_check check ((amount > (0)::numeric))
);

create table public.employee_loan_repayments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_loan_id uuid not null references public.employee_loans(id) on delete restrict,
  payroll_item_id uuid references public.payroll_items(id) on delete restrict,
  amount numeric(18,2) not null,
  repayment_date date not null,
  created_at timestamp with time zone default now() not null,
  constraint employee_loan_repayments_employee_loan_id_payroll_item_id_key unique (employee_loan_id, payroll_item_id),
  constraint employee_loan_repayments_amount_check check ((amount > (0)::numeric))
);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_employee_id_fkey foreign key (employee_id) references public.employees(id) on delete set null;
alter table public.cash_transactions
  add constraint cash_transactions_payroll_payment_id_fkey foreign key (payroll_payment_id) references public.payroll_payments(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.apply_payroll_loan_deductions(target_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row record;
  v_loan record;

  v_remaining numeric(18,2);
  v_take numeric(18,2);

  v_existing numeric(18,2);
  v_repayment uuid;
begin
  for v_row in
    select
      pi.id as payroll_item_id,
      pi.company_id,
      pi.employee_id,
      pi.loan_deduction,
      pr.period_end

    from public.payroll_items pi

    join public.payroll_runs pr
      on pr.id =
         pi.payroll_run_id

    where pi.payroll_run_id =
          target_run

      and pi.loan_deduction >
          0
  loop

    select
      coalesce(
        sum(r.amount),
        0
      )

    into
      v_existing

    from public.employee_loan_repayments r

    where r.company_id =
          v_row.company_id

      and r.payroll_item_id =
          v_row.payroll_item_id;


    v_remaining :=
      greatest(
        round(
          v_row.loan_deduction -
          v_existing,
          2
        ),
        0
      );


    if v_remaining <= 0.01 then
      continue;
    end if;


    for v_loan in
      select
        el.id,
        el.balance_due

      from public.employee_loans el

      where el.company_id =
            v_row.company_id

        and el.employee_id =
            v_row.employee_id

        and el.status =
            'active'

        and el.balance_due >
            0

      order by
        el.start_date,
        el.created_at

      for update
    loop

      exit when
        v_remaining <= 0.01;


      v_take :=
        round(
          least(
            v_remaining,
            v_loan.balance_due
          ),
          2
        );


      v_repayment := null;


      insert into public.employee_loan_repayments(
        company_id,
        employee_loan_id,
        payroll_item_id,
        amount,
        repayment_date
      )
      values(
        v_row.company_id,
        v_loan.id,
        v_row.payroll_item_id,
        v_take,
        v_row.period_end
      )

      on conflict(
        employee_loan_id,
        payroll_item_id
      )
      do nothing

      returning id
      into v_repayment;


      if v_repayment is null then

        select
          r.amount

        into
          v_existing

        from public.employee_loan_repayments r

        where r.employee_loan_id =
              v_loan.id

          and r.payroll_item_id =
              v_row.payroll_item_id;


        v_remaining :=
          greatest(
            round(
              v_remaining -
              coalesce(
                v_existing,
                0
              ),
              2
            ),
            0
          );

        continue;
      end if;


      update public.employee_loans
      set
        balance_due =
          greatest(
            round(
              balance_due -
              v_take,
              2
            ),
            0
          ),

        status =
          case
            when round(
                   balance_due -
                   v_take,
                   2
                 ) <= 0
              then 'settled'

            else status
          end

      where id =
            v_loan.id;


      v_remaining :=
        greatest(
          round(
            v_remaining -
            v_take,
            2
          ),
          0
        );

    end loop;


    if v_remaining > 0.01 then
      raise exception
        'Payroll loan deduction exceeds employee loan balance';
    end if;

  end loop;
end;
$function$;

create or replace function public.create_employee_loan(target_company uuid, target_employee uuid, target_type text, target_amount numeric, target_installment numeric, target_start_date date, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_type not in (
    'advance',
    'loan'
  ) then
    raise exception
      'Invalid employee loan type';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid employee loan amount';
  end if;

  if coalesce(
       target_installment,
       0
     ) < 0
  then
    raise exception
      'Invalid installment';
  end if;

  if not exists (
    select 1
    from public.employees
    where id =
          target_employee

      and company_id =
          target_company

      and status =
          'active'
  ) then
    raise exception
      'Invalid employee';
  end if;

  insert into public.employee_loans(
    company_id,
    employee_id,
    loan_type,
    original_amount,
    balance_due,
    installment_amount,
    start_date,
    status,
    notes
  )
  values(
    target_company,
    target_employee,
    target_type,
    round(target_amount,2),
    round(target_amount,2),
    round(
      coalesce(
        target_installment,
        0
      ),
      2
    ),
    coalesce(
      target_start_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    'active',
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_id;

  return v_id;
end;
$function$;

create or replace function public.create_payroll_run(target_company uuid, target_period_start date, target_period_end date, target_pay_date date, target_currency text, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid;
  v_count integer;
  v_currency text;
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_period_start is null
     or target_period_end is null
     or target_period_end <
        target_period_start
  then
    raise exception
      'Invalid payroll period';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      target_period_end
    );

  select
    default_currency
  into
    v_currency
  from public.companies
  where id =
        target_company;

  if v_currency is null then
    raise exception
      'Company not found';
  end if;

  v_currency :=
    coalesce(
      nullif(
        trim(target_currency),
        ''
      ),
      v_currency
    );

  insert into public.payroll_runs(
    company_id,
    period_start,
    period_end,
    pay_date,
    status,
    currency,
    notes
  )
  values(
    target_company,
    target_period_start,
    target_period_end,
    target_pay_date,
    'draft',
    v_currency,
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_run;

  insert into public.payroll_items(
    company_id,
    payroll_run_id,
    employee_id,
    base_salary,
    allowances,
    overtime_hours,
    overtime_amount,
    bonuses,
    absent_days,
    absence_deduction,
    loan_deduction,
    social_security_deduction,
    tax_deduction,
    other_deductions,
    employer_contribution,
    gross_pay,
    total_deductions,
    net_pay,
    paid_total,
    balance_due
  )
  select
    target_company,
    v_run,
    e.id,
    e.base_salary,
    e.fixed_allowances,
    0,
    0,
    0,
    0,
    0,
    0,

    round(
      e.base_salary *
      e.social_security_employee_rate /
      100,
      2
    ),

    round(
      e.base_salary *
      e.income_tax_rate /
      100,
      2
    ),

    0,

    round(
      e.base_salary *
      e.social_security_employer_rate /
      100,
      2
    ),

    round(
      e.base_salary +
      e.fixed_allowances,
      2
    ),

    round(
      (
        e.base_salary *
        e.social_security_employee_rate /
        100
      ) +
      (
        e.base_salary *
        e.income_tax_rate /
        100
      ),
      2
    ),

    greatest(
      round(
        e.base_salary +
        e.fixed_allowances -
        (
          e.base_salary *
          e.social_security_employee_rate /
          100
        ) -
        (
          e.base_salary *
          e.income_tax_rate /
          100
        ),
        2
      ),
      0
    ),

    0,

    greatest(
      round(
        e.base_salary +
        e.fixed_allowances -
        (
          e.base_salary *
          e.social_security_employee_rate /
          100
        ) -
        (
          e.base_salary *
          e.income_tax_rate /
          100
        ),
        2
      ),
      0
    )

  from public.employees e

  where e.company_id =
        target_company

    and e.status =
        'active'

    and e.salary_currency =
        v_currency;

  get diagnostics
    v_count = row_count;

  if v_count = 0 then
    delete from public.payroll_runs
    where id = v_run;

    raise exception
      'No active employees for payroll currency';
  end if;

  -- قسط السلف بينخصم تلقائيًا: لكل موظف، مجموع أقساط سلفه المفتوحة
  -- (القسط أو الباقي من السلفة إذا أقل). بيضل قابل للتعديل من شاشة الرواتب.
  update public.payroll_items pi
  set loan_deduction = least(x.installments, pi.gross_pay)
  from (
    select
      el.employee_id,
      sum(least(el.installment_amount, el.balance_due)) as installments
    from public.employee_loans el
    where el.company_id = target_company
      and el.status = 'active'
      and el.balance_due > 0
      and el.installment_amount > 0
      and el.start_date <= target_period_end
    group by el.employee_id
  ) x
  where pi.payroll_run_id = v_run
    and pi.employee_id = x.employee_id;

  perform public.recalculate_payroll_item(pi.id)
  from public.payroll_items pi
  where pi.payroll_run_id = v_run
    and pi.loan_deduction > 0;

  update public.payroll_runs pr
  set
    total_gross =
      x.gross,

    total_deductions =
      x.deductions,

    total_net =
      x.net

  from (
    select
      payroll_run_id,

      coalesce(
        sum(gross_pay),
        0
      ) as gross,

      coalesce(
        sum(total_deductions),
        0
      ) as deductions,

      coalesce(
        sum(net_pay),
        0
      ) as net

    from public.payroll_items

    where payroll_run_id =
          v_run

    group by
      payroll_run_id
  ) x

  where pr.id =
        x.payroll_run_id;

  return v_run;
end;
$function$;

create or replace function public.disburse_employee_loan(target_company uuid, target_loan uuid, target_cashbox uuid, target_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_employee uuid;
  v_amount numeric(18,2);
  v_status text;
  v_currency text;

  v_id uuid;
  v_cash uuid;
  v_advance uuid;
  v_entry uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if exists(
    select 1
    from public.employee_loan_disbursements
    where employee_loan_id =
          target_loan
  ) then
    raise exception
      'Loan already disbursed';
  end if;

  select
    employee_id,
    original_amount,
    status
  into
    v_employee,
    v_amount,
    v_status
  from public.employee_loans
  where id = target_loan
    and company_id =
        target_company
  for update;

  if v_employee is null then
    raise exception
      'Employee loan not found';
  end if;

  if v_status <>
     'active'
  then
    raise exception
      'Loan is not active';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        target_cashbox
    and company_id =
        target_company
    and active = true;

  if v_currency is null then
    raise exception
      'Invalid cashbox';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_cash :=
    public.finance_cashbox_account(
      target_company,
      target_cashbox
    );

  v_advance :=
    public.finance_system_account(
      target_company,
      'employee_advances'
    );

  insert into public.employee_loan_disbursements(
    company_id,
    employee_loan_id,
    employee_id,
    cashbox_id,
    amount,
    currency,
    disbursement_date
  )
  values(
    target_company,
    target_loan,
    v_employee,
    target_cashbox,
    v_amount,
    v_currency,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    )
  )
  returning id
  into v_id;

  v_entry :=
    public.post_system_journal(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      ),
      'صرف سلفة أو قرض موظف',
      v_currency,
      null,
      'employee_loan_disbursement',
      v_id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          v_amount,
          'credit',
          0,
          'party_type',
          'employee',
          'party_id',
          v_employee
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          v_amount,
          'party_type',
          'employee',
          'party_id',
          v_employee
        )
      )
    );

  update public.employee_loan_disbursements
  set journal_entry_id =
      v_entry
  where id =
        v_id;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    employee_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    'out',
    case
      when exists(
        select 1
        from public.employee_loans
        where id = target_loan
          and loan_type =
              'advance'
      )
        then 'employee_advance'
      else 'employee_loan'
    end,
    v_amount,
    v_employee,
    'صرف سلفة أو قرض موظف',
    (
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  return v_id;
end;
$function$;

create or replace function public.payroll_after_post_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if old.status = 'draft'
     and new.status = 'posted'
  then
    perform
      public.apply_payroll_loan_deductions(
        new.id
      );
  end if;

  return new;
end;
$function$;

create or replace function public.post_payroll_run(target_company uuid, target_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_currency text;
  v_period_end date;
  v_pay_date date;

  v_gross numeric(18,2);
  v_employer numeric(18,2);
  v_net numeric(18,2);

  v_social numeric(18,2);
  v_tax numeric(18,2);
  v_loan numeric(18,2);
  v_absence_other numeric(18,2);

  v_salary_expense uuid;
  v_employer_expense uuid;
  v_payable uuid;
  v_withholdings uuid;
  v_employee_advances uuid;

  v_lines jsonb := '[]'::jsonb;
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    status,
    currency,
    period_end,
    pay_date
  into
    v_status,
    v_currency,
    v_period_end,
    v_pay_date
  from public.payroll_runs
  where id = target_run
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Payroll run not found';
  end if;

  if v_status <> 'draft' then
    raise exception
      'Only draft payroll can be posted';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      v_period_end
    );

  select
    round(
      coalesce(
        sum(gross_pay),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(employer_contribution),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(net_pay),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(social_security_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(tax_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(loan_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          absence_deduction +
          other_deductions
        ),
        0
      ),
      2
    )

  into
    v_gross,
    v_employer,
    v_net,
    v_social,
    v_tax,
    v_loan,
    v_absence_other

  from public.payroll_items
  where payroll_run_id =
        target_run;

  if v_gross <= 0 then
    raise exception
      'Payroll has no payable amounts';
  end if;

  v_salary_expense :=
    public.finance_system_account(
      target_company,
      'salary_expense'
    );

  v_employer_expense :=
    public.finance_system_account(
      target_company,
      'employer_contribution_expense'
    );

  v_payable :=
    public.finance_system_account(
      target_company,
      'payroll_payable'
    );

  v_withholdings :=
    public.finance_system_account(
      target_company,
      'payroll_withholdings'
    );

  v_employee_advances :=
    public.finance_system_account(
      target_company,
      'employee_advances'
    );

  v_lines :=
    v_lines ||
    jsonb_build_array(
      jsonb_build_object(
        'account_id',
        v_salary_expense,
        'debit',
        v_gross,
        'credit',
        0,
        'memo',
        'رواتب وأجور'
      )
    );

  if v_employer > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_employer_expense,
          'debit',
          v_employer,
          'credit',
          0,
          'memo',
          'مساهمات صاحب العمل'
        )
      );
  end if;

  if v_net > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_payable,
          'debit',
          0,
          'credit',
          v_net,
          'memo',
          'صافي رواتب مستحق'
        )
      );
  end if;

  if (
    v_social +
    v_tax +
    v_employer
  ) > 0
  then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_withholdings,
          'debit',
          0,
          'credit',
          round(
            v_social +
            v_tax +
            v_employer,
            2
          ),
          'memo',
          'اقتطاعات ومستحقات رواتب'
        )
      );
  end if;

  if v_loan > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_employee_advances,
          'debit',
          0,
          'credit',
          v_loan,
          'memo',
          'حسم سلفة أو قرض موظف'
        )
      );
  end if;

  if v_absence_other > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_salary_expense,
          'debit',
          0,
          'credit',
          v_absence_other,
          'memo',
          'حسم غياب وخصومات أخرى'
        )
      );
  end if;

  perform
    public.post_system_journal(
      target_company,
      v_period_end,
      'ترحيل رواتب حتى ' ||
      v_period_end::text,
      v_currency,
      null,
      'payroll_run',
      target_run,
      v_lines
    );

  update public.payroll_runs
  set
    status = 'posted',
    posted_at = now(),
    posted_by = auth.uid()
  where id = target_run;
end;
$function$;

create or replace function public.recalculate_payroll_item(target_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_gross numeric(18,2);
  v_deductions numeric(18,2);
  v_net numeric(18,2);
  v_run uuid;
begin
  select
    payroll_run_id,

    round(
      base_salary +
      allowances +
      overtime_amount +
      bonuses,
      2
    ),

    round(
      absence_deduction +
      loan_deduction +
      social_security_deduction +
      tax_deduction +
      other_deductions,
      2
    )

  into
    v_run,
    v_gross,
    v_deductions

  from public.payroll_items
  where id =
        target_item;

  if v_run is null then
    raise exception
      'Payroll item not found';
  end if;

  v_net :=
    greatest(
      v_gross -
      v_deductions,
      0
    );

  update public.payroll_items
  set
    gross_pay =
      v_gross,

    total_deductions =
      v_deductions,

    net_pay =
      v_net,

    balance_due =
      greatest(
        v_net -
        paid_total,
        0
      )

  where id =
        target_item;

  update public.payroll_runs pr
  set
    total_gross =
      x.gross,

    total_deductions =
      x.deductions,

    total_net =
      x.net,

    total_paid =
      x.paid

  from (
    select
      payroll_run_id,

      coalesce(
        sum(gross_pay),
        0
      ) as gross,

      coalesce(
        sum(total_deductions),
        0
      ) as deductions,

      coalesce(
        sum(net_pay),
        0
      ) as net,

      coalesce(
        sum(paid_total),
        0
      ) as paid

    from public.payroll_items
    where payroll_run_id =
          v_run

    group by payroll_run_id
  ) x

  where pr.id =
        x.payroll_run_id;
end;
$function$;

create or replace function public.record_payroll_payment(target_company uuid, target_payroll_item uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid;
  v_employee uuid;
  v_balance numeric(18,2);
  v_run_status text;
  v_currency text;

  v_cashbox_currency text;
  v_payment uuid;

  v_cash uuid;
  v_payable uuid;

  v_total_net numeric(18,2);
  v_total_paid numeric(18,2);
begin
  if not public.has_permission(
    target_company,
    'payroll.pay'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid payroll payment amount';
  end if;

  select
    pi.payroll_run_id,
    pi.employee_id,
    pi.balance_due,
    pr.status,
    pr.currency
  into
    v_run,
    v_employee,
    v_balance,
    v_run_status,
    v_currency
  from public.payroll_items pi

  join public.payroll_runs pr
    on pr.id =
       pi.payroll_run_id

  where pi.id =
        target_payroll_item

    and pi.company_id =
        target_company

  for update of pi, pr;

  if v_run is null then
    raise exception
      'Payroll item not found';
  end if;

  if v_run_status not in (
    'posted',
    'partial'
  ) then
    raise exception
      'Payroll is not ready for payment';
  end if;

  if round(
       target_amount,
       2
     ) >
     round(
       v_balance,
       2
     )
  then
    raise exception
      'Payment exceeds employee payroll balance';
  end if;

  select currency
  into v_cashbox_currency
  from public.cashboxes
  where id = target_cashbox
    and company_id =
        target_company
    and active = true;

  if v_cashbox_currency is null then
    raise exception
      'Invalid cashbox';
  end if;

  if upper(v_cashbox_currency) <>
     upper(v_currency)
  then
    raise exception
      'Payroll cashbox currency must match payroll currency';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.payroll_payments(
    company_id,
    payroll_item_id,
    employee_id,
    cashbox_id,
    amount,
    currency,
    payment_date,
    payment_method,
    status,
    reference_number,
    notes
  )
  values(
    target_company,
    target_payroll_item,
    v_employee,
    target_cashbox,
    round(
      target_amount,
      2
    ),
    upper(v_currency),
    coalesce(
      target_payment_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      nullif(
        trim(target_method),
        ''
      ),
      'cash'
    ),
    'posted',
    nullif(
      trim(target_reference),
      ''
    ),
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_payment;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    employee_id,
    payroll_payment_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    'out',
    'payroll_payment',
    round(
      target_amount,
      2
    ),
    v_employee,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'دفع راتب موظف'
    ),
    (
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  v_cash :=
    public.finance_cashbox_account(
      target_company,
      target_cashbox
    );

  v_payable :=
    public.finance_system_account(
      target_company,
      'payroll_payable'
    );

  perform
    public.post_system_journal(
      target_company,
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      ),
      'دفع راتب موظف',
      v_currency,
      null,
      'payroll_payment',
      v_payment,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_payable,
          'debit',
          round(
            target_amount,
            2
          ),
          'credit',
          0,
          'party_type',
          'employee',
          'party_id',
          v_employee
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          round(
            target_amount,
            2
          ),
          'party_type',
          'employee',
          'party_id',
          v_employee
        )
      )
    );

  update public.payroll_items
  set
    paid_total =
      round(
        paid_total +
        target_amount,
        2
      ),

    balance_due =
      greatest(
        round(
          net_pay -
          (
            paid_total +
            target_amount
          ),
          2
        ),
        0
      )

  where id =
        target_payroll_item;

  select
    coalesce(
      sum(net_pay),
      0
    ),
    coalesce(
      sum(paid_total),
      0
    )
  into
    v_total_net,
    v_total_paid
  from public.payroll_items
  where payroll_run_id =
        v_run;

  update public.payroll_runs
  set
    total_paid =
      round(
        v_total_paid,
        2
      ),

    status =
      case
        when round(
               v_total_paid,
               2
             ) >=
             round(
               v_total_net,
               2
             )
          then 'paid'

        when v_total_paid > 0
          then 'partial'

        else 'posted'
      end

  where id =
        v_run;

  return v_payment;
end;
$function$;

create or replace function public.save_employee(target_company uuid, target_employee uuid, target_employee_number text, target_name text, target_phone text, target_job_title text, target_department text, target_hire_date date, target_salary_currency text, target_base_salary numeric, target_fixed_allowances numeric, target_overtime_rate numeric, target_employee_social_rate numeric, target_employer_social_rate numeric, target_income_tax_rate numeric, target_cashbox uuid, target_notes text, target_status text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Employee name is required';
  end if;

  if target_status not in (
    'active',
    'inactive',
    'terminated'
  ) then
    raise exception
      'Invalid employee status';
  end if;

  if upper(
       trim(
         coalesce(
           target_salary_currency,
           ''
         )
       )
     ) !~ '^[A-Z]{3}$'
  then
    raise exception
      'Invalid salary currency';
  end if;

  if coalesce(
       target_base_salary,
       0
     ) < 0
     or coalesce(
       target_fixed_allowances,
       0
     ) < 0
     or coalesce(
       target_overtime_rate,
       0
     ) < 0
     or coalesce(
       target_employee_social_rate,
       0
     ) < 0
     or coalesce(
       target_employer_social_rate,
       0
     ) < 0
     or coalesce(
       target_income_tax_rate,
       0
     ) < 0
  then
    raise exception
      'Payroll values cannot be negative';
  end if;

  if coalesce(
       target_employee_social_rate,
       0
     ) > 100
     or coalesce(
       target_employer_social_rate,
       0
     ) > 100
     or coalesce(
       target_income_tax_rate,
       0
     ) > 100
  then
    raise exception
      'Payroll percentage cannot exceed 100';
  end if;

  if target_cashbox is not null
     and not exists (
       select 1
       from public.cashboxes
       where id = target_cashbox
         and company_id =
             target_company
         and active = true
     )
  then
    raise exception
      'Invalid employee cashbox';
  end if;

  if target_employee is null then

    insert into public.employees(
      company_id,
      employee_number,
      full_name,
      phone,
      job_title,
      department,
      hire_date,
      status,
      salary_currency,
      base_salary,
      fixed_allowances,
      overtime_hour_rate,
      social_security_employee_rate,
      social_security_employer_rate,
      income_tax_rate,
      default_cashbox_id,
      notes
    )
    values(
      target_company,
      nullif(
        trim(target_employee_number),
        ''
      ),
      trim(target_name),
      nullif(trim(target_phone),''),
      nullif(trim(target_job_title),''),
      nullif(trim(target_department),''),
      target_hire_date,
      target_status,
      upper(
        coalesce(
          nullif(
            trim(target_salary_currency),
            ''
          ),
          'USD'
        )
      ),
      coalesce(target_base_salary,0),
      coalesce(target_fixed_allowances,0),
      coalesce(target_overtime_rate,0),
      coalesce(target_employee_social_rate,0),
      coalesce(target_employer_social_rate,0),
      coalesce(target_income_tax_rate,0),
      target_cashbox,
      nullif(trim(target_notes),'')
    )
    returning id
    into v_id;

  else

    update public.employees
    set
      employee_number =
        nullif(
          trim(target_employee_number),
          ''
        ),

      full_name =
        trim(target_name),

      phone =
        nullif(
          trim(target_phone),
          ''
        ),

      job_title =
        nullif(
          trim(target_job_title),
          ''
        ),

      department =
        nullif(
          trim(target_department),
          ''
        ),

      hire_date =
        target_hire_date,

      status =
        target_status,

      salary_currency =
        upper(
          coalesce(
            nullif(
              trim(target_salary_currency),
              ''
            ),
            salary_currency
          )
        ),

      base_salary =
        coalesce(
          target_base_salary,
          0
        ),

      fixed_allowances =
        coalesce(
          target_fixed_allowances,
          0
        ),

      overtime_hour_rate =
        coalesce(
          target_overtime_rate,
          0
        ),

      social_security_employee_rate =
        coalesce(
          target_employee_social_rate,
          0
        ),

      social_security_employer_rate =
        coalesce(
          target_employer_social_rate,
          0
        ),

      income_tax_rate =
        coalesce(
          target_income_tax_rate,
          0
        ),

      default_cashbox_id =
        target_cashbox,

      notes =
        nullif(
          trim(target_notes),
          ''
        )

    where id =
          target_employee

      and company_id =
          target_company

    returning id
    into v_id;

    if v_id is null then
      raise exception
        'Employee not found';
    end if;

  end if;

  return v_id;
end;
$function$;

create or replace function public.update_payroll_item(target_company uuid, target_item uuid, target_allowances numeric, target_overtime_hours numeric, target_overtime_amount numeric, target_bonuses numeric, target_absent_days numeric, target_absence_deduction numeric, target_loan_deduction numeric, target_social_security_deduction numeric, target_tax_deduction numeric, target_other_deductions numeric, target_employer_contribution numeric, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.payroll_items pi

    join public.payroll_runs pr
      on pr.id =
         pi.payroll_run_id

    where pi.id =
          target_item

      and pi.company_id =
          target_company

      and pr.status =
          'draft'
  ) then
    raise exception
      'Payroll item is not editable';
  end if;

  update public.payroll_items
  set
    allowances =
      greatest(
        coalesce(
          target_allowances,
          0
        ),
        0
      ),

    overtime_hours =
      greatest(
        coalesce(
          target_overtime_hours,
          0
        ),
        0
      ),

    overtime_amount =
      greatest(
        coalesce(
          target_overtime_amount,
          0
        ),
        0
      ),

    bonuses =
      greatest(
        coalesce(
          target_bonuses,
          0
        ),
        0
      ),

    absent_days =
      greatest(
        coalesce(
          target_absent_days,
          0
        ),
        0
      ),

    absence_deduction =
      greatest(
        coalesce(
          target_absence_deduction,
          0
        ),
        0
      ),

    loan_deduction =
      greatest(
        coalesce(
          target_loan_deduction,
          0
        ),
        0
      ),

    social_security_deduction =
      greatest(
        coalesce(
          target_social_security_deduction,
          0
        ),
        0
      ),

    tax_deduction =
      greatest(
        coalesce(
          target_tax_deduction,
          0
        ),
        0
      ),

    other_deductions =
      greatest(
        coalesce(
          target_other_deductions,
          0
        ),
        0
      ),

    employer_contribution =
      greatest(
        coalesce(
          target_employer_contribution,
          0
        ),
        0
      ),

    notes =
      nullif(
        trim(target_notes),
        ''
      )

  where id =
        target_item

    and company_id =
        target_company;

  perform
    public.recalculate_payroll_item(
      target_item
    );
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.payroll_employee_summary with (security_invoker=true) as
 select e.company_id,
    e.id as employee_id,
    e.employee_number,
    e.full_name,
    e.job_title,
    e.department,
    e.status,
    e.salary_currency,
    e.base_salary,
    e.fixed_allowances,
    coalesce(loans.active_loan_balance, 0::numeric)::numeric(18,2) as active_loan_balance,
    coalesce(payroll.total_net, 0::numeric)::numeric(18,2) as payroll_net_total,
    coalesce(payroll.total_paid, 0::numeric)::numeric(18,2) as payroll_paid_total,
    coalesce(payroll.total_due, 0::numeric)::numeric(18,2) as payroll_due_total
   from public.employees e
     left join lateral ( select coalesce(sum(employee_loans.balance_due), 0::numeric) as active_loan_balance
           from public.employee_loans
          where employee_loans.employee_id = e.id and employee_loans.status = 'active'::text) loans on true
     left join lateral ( select coalesce(sum(pi.net_pay), 0::numeric) as total_net,
            coalesce(sum(pi.paid_total), 0::numeric) as total_paid,
            coalesce(sum(pi.balance_due), 0::numeric) as total_due
           from public.payroll_items pi
             join public.payroll_runs pr on pr.id = pi.payroll_run_id
          where pi.employee_id = e.id and (pr.status = any (array['posted'::text, 'partial'::text, 'paid'::text]))) payroll on true;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_employee_loan_disbursements after insert or delete or update on public.employee_loan_disbursements for each row execute function public.write_audit_log();

create trigger audit_employee_loan_repayments after insert or delete or update on public.employee_loan_repayments for each row execute function public.write_audit_log();

create trigger audit_employee_loans after insert or delete or update on public.employee_loans for each row execute function public.write_audit_log();

create trigger employee_loans_updated_at before update on public.employee_loans for each row execute function public.set_updated_at();

create trigger audit_employees after insert or delete or update on public.employees for each row execute function public.write_audit_log();

create trigger employees_updated_at before update on public.employees for each row execute function public.set_updated_at();

create trigger audit_payroll_items after insert or delete or update on public.payroll_items for each row execute function public.write_audit_log();

create trigger payroll_items_updated_at before update on public.payroll_items for each row execute function public.set_updated_at();

create trigger audit_payroll_payments after insert or update on public.payroll_payments for each row execute function public.write_audit_log();

create trigger audit_payroll_runs after insert or delete or update on public.payroll_runs for each row execute function public.write_audit_log();

create trigger payroll_apply_loan_deductions after update of status on public.payroll_runs for each row execute function public.payroll_after_post_trigger();

create trigger payroll_runs_updated_at before update on public.payroll_runs for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.employees enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
alter table public.payroll_payments enable row level security;
alter table public.employee_loans enable row level security;
alter table public.employee_loan_disbursements enable row level security;
alter table public.employee_loan_repayments enable row level security;
create policy employee_loan_disbursements_read on public.employee_loan_disbursements
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employee_loan_repayments_read on public.employee_loan_repayments
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employee_loans_read on public.employee_loans
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employees_payroll_read on public.employees
  for select to authenticated
  using ((public.has_permission(company_id, 'payroll.view'::text) or public.has_permission(company_id, 'payroll.manage_employees'::text)));
create policy payroll_items_read on public.payroll_items
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy payroll_payments_read on public.payroll_payments
  for select to authenticated
  using ((public.has_permission(company_id, 'payroll.view'::text) or public.has_permission(company_id, 'payroll.pay'::text)));
create policy payroll_runs_read on public.payroll_runs
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.employees from authenticated;
revoke insert, update, delete on public.payroll_runs from authenticated;
revoke insert, update, delete on public.payroll_items from authenticated;
revoke insert, update, delete on public.payroll_payments from authenticated;
revoke insert, update, delete on public.employee_loans from authenticated;
revoke insert, update, delete on public.employee_loan_disbursements from authenticated;
revoke insert, update, delete on public.employee_loan_repayments from authenticated;
revoke execute on function public.apply_payroll_loan_deductions(uuid) from authenticated;
revoke execute on function public.recalculate_payroll_item(uuid) from authenticated;

-- ======================================================================
-- الأصول والشركاء
-- الأصول الثابتة والإهلاك، الشركاء وحركاتهم
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  asset_number text not null,
  name text not null,
  category text,
  description text,
  purchase_date date not null,
  in_service_date date not null,
  currency text default 'USD'::text not null,
  purchase_cost numeric(18,2) not null,
  salvage_value numeric(18,2) default 0 not null,
  useful_life_months integer not null,
  depreciation_method text default 'straight_line'::text not null,
  accumulated_depreciation numeric(18,2) default 0 not null,
  status text default 'active'::text not null,
  disposal_date date,
  disposal_amount numeric(18,2),
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint fixed_assets_company_id_asset_number_key unique (company_id, asset_number),
  constraint fixed_assets_accumulated_depreciation_check check ((accumulated_depreciation >= (0)::numeric)),
  constraint fixed_assets_check check ((salvage_value <= purchase_cost)),
  constraint fixed_assets_depreciation_method_check check ((depreciation_method = 'straight_line'::text)),
  constraint fixed_assets_purchase_cost_check check ((purchase_cost >= (0)::numeric)),
  constraint fixed_assets_salvage_value_check check ((salvage_value >= (0)::numeric)),
  constraint fixed_assets_status_check check ((status = any (array['active'::text, 'fully_depreciated'::text, 'disposed'::text]))),
  constraint fixed_assets_useful_life_months_check check ((useful_life_months > 0))
);
create index fixed_assets_company_status_idx on public.fixed_assets using btree (company_id, status, in_service_date);

create table public.asset_depreciation_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  asset_id uuid not null references public.fixed_assets(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  amount numeric(18,2) not null,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  posted_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  constraint asset_depreciation_entries_asset_id_period_start_period_end_key unique (asset_id, period_start, period_end),
  constraint asset_depreciation_entries_amount_check check ((amount > (0)::numeric))
);
create index asset_depreciation_entries_asset_idx on public.asset_depreciation_entries using btree (asset_id, period_end desc);

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_number text,
  name text not null,
  phone text,
  ownership_percent numeric(9,4) default 0 not null,
  profit_share_percent numeric(9,4) default 0 not null,
  active boolean default true not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint partners_ownership_percent_check check (((ownership_percent >= (0)::numeric) and (ownership_percent <= (100)::numeric))),
  constraint partners_profit_share_percent_check check (((profit_share_percent >= (0)::numeric) and (profit_share_percent <= (100)::numeric)))
);
create index partners_company_idx on public.partners using btree (company_id, active, name);
create unique index partners_number_unique on public.partners using btree (company_id, partner_number) where (partner_number is not null);

create table public.partner_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete restrict,
  transaction_type text not null,
  amount numeric(18,2) not null,
  currency text not null,
  cashbox_id uuid references public.cashboxes(id) on delete restrict,
  transaction_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint partner_transactions_amount_check check ((amount > (0)::numeric)),
  constraint partner_transactions_transaction_type_check check ((transaction_type = any (array['capital_contribution'::text, 'drawing'::text, 'partner_loan_in'::text, 'partner_loan_repayment'::text, 'profit_distribution'::text])))
);
create index partner_transactions_partner_idx on public.partner_transactions using btree (company_id, partner_id, transaction_date desc);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_partner_transaction_id_fkey foreign key (partner_transaction_id) references public.partner_transactions(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.create_fixed_asset(target_company uuid, target_name text, target_category text, target_description text, target_purchase_date date, target_in_service_date date, target_currency text, target_purchase_cost numeric, target_salvage_value numeric, target_useful_life_months integer, target_notes text, target_cashbox uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_number text;
  v_date date;
  v_currency text;
  v_cost numeric(18,2);
  v_credit uuid;
begin
  if not public.has_permission(
    target_company,
    'assets.manage'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(trim(target_name),'') is null then
    raise exception 'Asset name is required';
  end if;

  if target_purchase_cost is null
     or target_purchase_cost <= 0
  then
    raise exception 'Invalid purchase cost';
  end if;

  if coalesce(
       target_salvage_value,
       0
     ) < 0
  then
    raise exception
      'Invalid salvage value';
  end if;

  if upper(
       trim(
         coalesce(
           target_currency,
           ''
         )
       )
     ) !~ '^[A-Z]{3}$'
  then
    raise exception
      'Invalid asset currency';
  end if;

  if target_purchase_date is not null
     and target_in_service_date is not null
     and target_in_service_date <
         target_purchase_date
  then
    raise exception
      'In-service date cannot be before purchase date';
  end if;

  if target_useful_life_months is null
     or target_useful_life_months <= 0
  then
    raise exception 'Invalid useful life';
  end if;

  if coalesce(
       target_salvage_value,
       0
     ) >
     target_purchase_cost
  then
    raise exception
      'Salvage value cannot exceed cost';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_purchase_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_number :=
    public.next_asset_number(
      target_company,
      coalesce(
        target_purchase_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.fixed_assets(
    company_id,
    asset_number,
    name,
    category,
    description,
    purchase_date,
    in_service_date,
    currency,
    purchase_cost,
    salvage_value,
    useful_life_months,
    notes
  )
  values(
    target_company,
    v_number,
    trim(target_name),
    nullif(trim(target_category),''),
    nullif(trim(target_description),''),
    coalesce(
      target_purchase_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      target_in_service_date,
      target_purchase_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        'USD'
      )
    ),
    round(target_purchase_cost,2),
    round(
      coalesce(
        target_salvage_value,
        0
      ),
      2
    ),
    target_useful_life_months,
    nullif(trim(target_notes),'')
  )
  returning id
  into v_id;

  -- قيد الشراء: الأصل بيدخل الحسابات، ومقابله يا صندوق (دفعنا هلق)
  -- يا أرصدة افتتاحية (أصل كان عنا قبل ما نبلّش بالنظام).
  select purchase_date, currency, purchase_cost
  into v_date, v_currency, v_cost
  from public.fixed_assets
  where id = v_id;

  if target_cashbox is not null then
    if not exists (
      select 1
      from public.cashboxes cb
      where cb.id = target_cashbox
        and cb.company_id = target_company
        and cb.active = true
        and upper(cb.currency) = v_currency
    ) then
      raise exception 'Cashbox must be active and in the asset currency';
    end if;

    insert into public.cash_transactions(
      company_id,
      cashbox_id,
      direction,
      type,
      amount,
      notes,
      occurred_at
    )
    values(
      target_company,
      target_cashbox,
      'out',
      'asset_purchase',
      v_cost,
      'شراء أصل ' || v_number || ' - ' || trim(target_name),
      (v_date::timestamp + time '12:00') at time zone 'Asia/Damascus'
    );

    v_credit := public.finance_cashbox_account(target_company, target_cashbox);
  else
    v_credit := public.finance_system_account(target_company, 'opening_balance_equity');
  end if;

  if v_cost > 0 then
    perform public.post_system_journal(
      target_company,
      v_date,
      'شراء أصل ثابت ' || v_number,
      v_currency,
      null,
      'fixed_asset',
      v_id,
      jsonb_build_array(
        jsonb_build_object(
          'account_id', public.finance_system_account(target_company, 'fixed_assets'),
          'debit', v_cost,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_credit,
          'debit', 0,
          'credit', v_cost
        )
      )
    );
  end if;

  return v_id;
end;
$function$;

create or replace function public.next_asset_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'fixed_asset',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'fixed_asset'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'fixed_asset'
    and sequence_year = v_year;

  return
    'AST-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      5,
      '0'
    );
end;
$function$;

create or replace function public.post_asset_depreciation_month(target_company uuid, target_year integer, target_month integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
  v_end date;

  v_asset record;

  v_depreciable numeric(18,2);
  v_monthly numeric(18,2);
  v_remaining numeric(18,2);
  v_amount numeric(18,2);

  v_expense uuid;
  v_accum uuid;

  v_entry uuid;
  v_count integer := 0;
begin
  if not public.has_permission(
    target_company,
    'assets.depreciate'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_month < 1
     or target_month > 12
  then
    raise exception 'Invalid month';
  end if;

  v_start :=
    make_date(
      target_year,
      target_month,
      1
    );

  v_end :=
    (
      v_start +
      interval '1 month' -
      interval '1 day'
    )::date;

  perform
    public.assert_finance_period_open(
      target_company,
      v_end
    );

  v_expense :=
    public.finance_system_account(
      target_company,
      'depreciation_expense'
    );

  v_accum :=
    public.finance_system_account(
      target_company,
      'accumulated_depreciation'
    );

  for v_asset in
    select *
    from public.fixed_assets
    where company_id =
          target_company
      and status =
          'active'
      and in_service_date <=
          v_end
    order by in_service_date,
             created_at
    for update
  loop
    if exists(
      select 1
      from public.asset_depreciation_entries
      where asset_id =
            v_asset.id
        and period_start =
            v_start
        and period_end =
            v_end
    ) then
      continue;
    end if;

    v_depreciable :=
      round(
        v_asset.purchase_cost -
        v_asset.salvage_value,
        2
      );

    v_remaining :=
      greatest(
        v_depreciable -
        v_asset.accumulated_depreciation,
        0
      );

    if v_remaining <= 0 then
      update public.fixed_assets
      set status =
          'fully_depreciated'
      where id =
            v_asset.id;

      continue;
    end if;

    v_monthly :=
      round(
        v_depreciable /
        v_asset.useful_life_months,
        2
      );

    v_amount :=
      least(
        v_monthly,
        v_remaining
      );

    if v_amount <= 0 then
      continue;
    end if;

    v_entry :=
      public.post_system_journal(
        target_company,
        v_end,
        'إهلاك أصل ' ||
        v_asset.asset_number ||
        ' - ' ||
        v_asset.name,
        v_asset.currency,
        null,
        'asset_depreciation',
        gen_random_uuid(),
        jsonb_build_array(
          jsonb_build_object(
            'account_id',
            v_expense,
            'debit',
            v_amount,
            'credit',
            0,
            'memo',
            v_asset.name
          ),
          jsonb_build_object(
            'account_id',
            v_accum,
            'debit',
            0,
            'credit',
            v_amount,
            'memo',
            v_asset.name
          )
        )
      );

    insert into public.asset_depreciation_entries(
      company_id,
      asset_id,
      period_start,
      period_end,
      amount,
      journal_entry_id
    )
    values(
      target_company,
      v_asset.id,
      v_start,
      v_end,
      v_amount,
      v_entry
    );

    update public.fixed_assets
    set
      accumulated_depreciation =
        round(
          accumulated_depreciation +
          v_amount,
          2
        ),

      status =
        case
          when round(
                 accumulated_depreciation +
                 v_amount,
                 2
               ) >=
               v_depreciable
            then 'fully_depreciated'
          else status
        end

    where id =
          v_asset.id;

    v_count :=
      v_count + 1;
  end loop;

  return v_count;
end;
$function$;

create or replace function public.record_partner_transaction(target_company uuid, target_partner uuid, target_type text, target_amount numeric, target_currency text, target_cashbox uuid, target_date date, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;

  v_cash uuid;
  v_other uuid;

  v_entry uuid;
  v_lines jsonb;

  v_direction text;
  v_cash_type text;
  v_currency text;
begin
  if not public.has_permission(
    target_company,
    'partners.transactions'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_type not in (
    'capital_contribution',
    'drawing',
    'partner_loan_in',
    'partner_loan_repayment',
    'profit_distribution'
  ) then
    raise exception
      'Invalid partner transaction';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid amount';
  end if;

  if not exists (
    select 1
    from public.partners
    where id = target_partner
      and company_id = target_company
      and active = true
  ) then
    raise exception
      'Invalid partner';
  end if;

  v_currency :=
    upper(
      trim(
        coalesce(
          target_currency,
          ''
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception
      'Invalid partner transaction currency';
  end if;

  if target_cashbox is null then
    raise exception
      'Cashbox is required';
  end if;

  if not exists (
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true
      and upper(trim(currency)) =
          v_currency
  ) then
    raise exception
      'Invalid cashbox or currency';
  end if;

  perform public.assert_finance_period_open(
    target_company,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    )
  );

  v_cash :=
    public.finance_cashbox_account(
      target_company,
      target_cashbox
    );

  if target_type = 'capital_contribution' then

    v_other :=
      public.finance_system_account(
        target_company,
        'capital'
      );

    v_direction := 'in';
    v_cash_type := 'partner_deposit';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'drawing' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_drawings'
      );

    v_direction := 'out';
    v_cash_type := 'partner_withdrawal';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'partner_loan_in' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_loans'
      );

    v_direction := 'in';
    v_cash_type := 'partner_deposit';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'partner_loan_repayment' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_loans'
      );

    v_direction := 'out';
    v_cash_type := 'partner_withdrawal';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  else

    v_other :=
      public.finance_system_account(
        target_company,
        'profit_distributions'
      );

    v_direction := 'out';
    v_cash_type := 'partner_distribution';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  end if;

  insert into public.partner_transactions(
    company_id,
    partner_id,
    transaction_type,
    amount,
    currency,
    cashbox_id,
    transaction_date,
    notes
  )
  values(
    target_company,
    target_partner,
    target_type,
    round(target_amount,2),
    v_currency,
    target_cashbox,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_id;

  v_entry :=
    public.post_system_journal(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      ),
      'حركة شريك',
      v_currency,
      null,
      'partner_transaction',
      v_id,
      v_lines
    );

  update public.partner_transactions
  set journal_entry_id =
      v_entry
  where id = v_id;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    partner_transaction_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    v_direction,
    v_cash_type,
    round(target_amount,2),
    v_id,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'حركة شريك'
    ),
    (
      coalesce(
        target_date,
        (
          now()
          at time zone 'Asia/Damascus'
        )::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  return v_id;
end;
$function$;

create or replace function public.save_partner(target_company uuid, target_partner uuid, target_number text, target_name text, target_phone text, target_ownership_percent numeric, target_profit_share_percent numeric, target_notes text, target_active boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'partners.manage'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Partner name is required';
  end if;

  if coalesce(
       target_ownership_percent,
       0
     ) < 0
     or coalesce(
       target_ownership_percent,
       0
     ) > 100
  then
    raise exception
      'Invalid ownership percent';
  end if;

  if coalesce(
       target_profit_share_percent,
       0
     ) < 0
     or coalesce(
       target_profit_share_percent,
       0
     ) > 100
  then
    raise exception
      'Invalid profit share percent';
  end if;

  if target_partner is null then

    insert into public.partners(
      company_id,
      partner_number,
      name,
      phone,
      ownership_percent,
      profit_share_percent,
      notes,
      active
    )
    values(
      target_company,
      nullif(
        trim(target_number),
        ''
      ),
      trim(target_name),
      nullif(
        trim(target_phone),
        ''
      ),
      coalesce(
        target_ownership_percent,
        0
      ),
      coalesce(
        target_profit_share_percent,
        0
      ),
      nullif(
        trim(target_notes),
        ''
      ),
      coalesce(
        target_active,
        true
      )
    )
    returning id
    into v_id;

  else

    update public.partners
    set
      partner_number =
        nullif(
          trim(target_number),
          ''
        ),
      name =
        trim(target_name),
      phone =
        nullif(
          trim(target_phone),
          ''
        ),
      ownership_percent =
        coalesce(
          target_ownership_percent,
          0
        ),
      profit_share_percent =
        coalesce(
          target_profit_share_percent,
          0
        ),
      notes =
        nullif(
          trim(target_notes),
          ''
        ),
      active =
        coalesce(
          target_active,
          true
        )
    where id =
          target_partner
      and company_id =
          target_company
    returning id
    into v_id;

    if v_id is null then
      raise exception
        'Partner not found';
    end if;

  end if;

  return v_id;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.fixed_asset_summary with (security_invoker=true) as
 select id,
    company_id,
    asset_number,
    name,
    category,
    description,
    purchase_date,
    in_service_date,
    currency,
    purchase_cost,
    salvage_value,
    useful_life_months,
    depreciation_method,
    accumulated_depreciation,
    status,
    disposal_date,
    disposal_amount,
    notes,
    created_by,
    created_at,
    updated_at,
    round(greatest(purchase_cost - accumulated_depreciation, salvage_value), 2) as book_value,
    round((purchase_cost - salvage_value) / useful_life_months::numeric, 2) as monthly_depreciation
   from public.fixed_assets a;

create view public.partner_summary with (security_invoker=true) as
 select p.id,
    p.company_id,
    p.partner_number,
    p.name,
    p.phone,
    p.ownership_percent,
    p.profit_share_percent,
    p.active,
    p.notes,
    p.created_by,
    p.created_at,
    p.updated_at,
    coalesce(sum(
        case
            when pt.transaction_type = 'capital_contribution'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as capital_contributions,
    coalesce(sum(
        case
            when pt.transaction_type = 'drawing'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as drawings,
    coalesce(sum(
        case
            when pt.transaction_type = 'partner_loan_in'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            when pt.transaction_type = 'partner_loan_repayment'::text then - (pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date))
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as partner_loan_balance,
    coalesce(sum(
        case
            when pt.transaction_type = 'profit_distribution'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as profit_distributions
   from public.partners p
     left join public.partner_transactions pt on pt.partner_id = p.id
  group by p.id;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_asset_depreciation_entries after insert or delete or update on public.asset_depreciation_entries for each row execute function public.write_audit_log();

create trigger audit_fixed_assets after insert or delete or update on public.fixed_assets for each row execute function public.write_audit_log();

create trigger fixed_assets_updated_at before update on public.fixed_assets for each row execute function public.set_updated_at();

create trigger audit_partner_transactions after insert or delete or update on public.partner_transactions for each row execute function public.write_audit_log();

create trigger audit_partners after insert or delete or update on public.partners for each row execute function public.write_audit_log();

create trigger partners_updated_at before update on public.partners for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.fixed_assets enable row level security;
alter table public.asset_depreciation_entries enable row level security;
alter table public.partners enable row level security;
alter table public.partner_transactions enable row level security;
create policy asset_depreciation_entries_read on public.asset_depreciation_entries
  for select to authenticated
  using (public.has_permission(company_id, 'assets.view'::text));
create policy fixed_assets_read on public.fixed_assets
  for select to authenticated
  using (public.has_permission(company_id, 'assets.view'::text));
create policy partner_transactions_read on public.partner_transactions
  for select to authenticated
  using (public.has_permission(company_id, 'partners.view'::text));
create policy partners_read on public.partners
  for select to authenticated
  using (public.has_permission(company_id, 'partners.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.fixed_assets from authenticated;
revoke insert, update, delete on public.asset_depreciation_entries from authenticated;
revoke insert, update, delete on public.partners from authenticated;
revoke insert, update, delete on public.partner_transactions from authenticated;
revoke execute on function public.next_asset_number(uuid,date) from authenticated;

-- ======================================================================
-- القيود التلقائية
-- كل عملية بيع أو شراء أو دفع أو حركة مخزون بتعمل قيدها المحاسبي لحالها
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.gl_cash_movement_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cash uuid;
  v_other uuid;
  v_currency text;
  v_lines jsonb;
begin
  if new.partner_transaction_id is not null then
    return new;
  end if;

  if new.type not in (
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out'
  ) then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id = new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  if new.type = 'partner_deposit' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'capital'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'partner_withdrawal' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'partner_drawings'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'adjustment_in' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
        )
      );

  else

    v_other :=
      public.finance_system_account(
        new.company_id,
        'operating_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  end if;

  perform public.post_system_journal(
    new.company_id,
    (new.occurred_at at time zone 'Asia/Damascus')::date,
    'حركة صندوق - ' || new.type,
    v_currency,
    null,
    'cash_transaction',
    new.id,
    v_lines
  );

  return new;
end;
$function$;

create or replace function public.gl_customer_allocation_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_trader uuid;
  v_payment_date date;
  v_cashbox uuid;
  v_currency text;
  v_payment_status text;

  v_advance uuid;
  v_ar uuid;
begin
  select
    company_id,
    trader_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_trader,
    v_payment_date,
    v_cashbox,
    v_payment_status
  from public.customer_payments
  where id =
        new.payment_id;

  if v_payment_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'customer_advances'
    );

  v_ar :=
    public.finance_system_account(
      v_company,
      'accounts_receivable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_payment_date,
      'تخصيص قبض على فاتورة بيع',
      -- الدفعة ممكن تكون بعملة غير عملة الفاتورة (مثلًا ليرة على فاتورة دولار)،
      -- فالقيد لازم ينكتب بمبلغ الدفعة وعملتها وسعر صرفها، مش بمبلغ الفاتورة.
      coalesce(new.payment_currency, v_currency),
      new.payment_rate_to_base,
      'customer_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          coalesce(new.payment_amount, new.amount),
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          v_trader
        ),
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          0,
          'credit',
          coalesce(new.payment_amount, new.amount),
          'party_type',
          'trader',
          'party_id',
          v_trader
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_customer_payment_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'customer_payment',
        new.id,
        new.payment_date,
        'عكس قبض عميل ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.customer_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'customer_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص قبض عميل'
        );
    end loop;

    -- التحريرات بسبب المرتجعات لازم تنعكس مع تخصيصها (إذا التخصيص انحذف كلو، القيدين بيلغوا بعض).
    for v_alloc in
      select id
      from public.customer_payment_releases
      where payment_id = new.id
        and allocation_id is not null
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'customer_payment_release',
          v_alloc.id,
          new.payment_date,
          'عكس تحرير دفعة'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'customer_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'قبض من عميل ' ||
      new.payment_number,
      v_currency,
      null,
      'customer_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_expense_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_expense uuid;
begin
  if new.cashbox_id is null then
    raise exception
      'Expense requires cashbox for automatic accounting';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_expense :=
    public.finance_system_account(
      new.company_id,
      'operating_expense'
    );

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'مصروف - ' ||
      new.category,
      v_currency,
      null,
      'expense',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_expense,
          'debit',
          new.amount,
          'credit',
          0,
          'memo',
          new.category
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'memo',
          new.category
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_inventory_movement_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_amount numeric(18,2);

  v_inventory uuid;
  v_clearing uuid;
  v_cogs uuid;
  v_adjustment uuid;
  v_opening uuid;

  v_lines jsonb;
  v_currency text;
begin
  if new.movement_type in (
    'transfer_in',
    'transfer_out'
  ) then
    return new;
  end if;

  v_amount :=
    round(
      abs(new.quantity) *
      coalesce(
        new.unit_cost,
        0
      ),
      2
    );

  if v_amount <= 0 then
    return new;
  end if;

  select default_currency
  into v_currency
  from public.companies
  where id =
        new.company_id;

  v_inventory :=
    public.finance_system_account(
      new.company_id,
      'inventory'
    );

  if new.movement_type =
     'purchase_receipt'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_delivery'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_return'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'purchase_return'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_in'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_out'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'opening'
  then
    v_opening :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_opening,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  else
    return new;
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'حركة مخزون - ' ||
      new.movement_type,
      v_currency,
      1,
      'inventory_movement',
      new.id,
      v_lines
    );

  return new;
end;
$function$;

create or replace function public.gl_purchase_invoice_status_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'purchase_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة شراء ' ||
        new.invoice_number
      );

  elsif old.status <> 'posted'
        and new.status = 'posted'
  then
    perform
      public.sync_purchase_invoice_journal(
        new.id
      );
  end if;

  return new;
end;
$function$;

create or replace function public.gl_purchase_item_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.sync_purchase_invoice_journal(
      case
        when tg_op = 'DELETE'
          then old.invoice_id
        else new.invoice_id
      end
    );

  return coalesce(new,old);
end;
$function$;

create or replace function public.gl_sales_invoice_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ar uuid;
  v_sales uuid;
  v_discount uuid;
  v_lines jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'sales_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة بيع ' ||
        new.invoice_number
      );

    return new;
  end if;

  if new.status <> 'posted' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = new.status
  then
    return new;
  end if;

  if new.total <= 0
     and new.subtotal <= 0
  then
    return new;
  end if;

  v_ar :=
    public.finance_system_account(
      new.company_id,
      'accounts_receivable'
    );

  v_sales :=
    public.finance_system_account(
      new.company_id,
      'sales_revenue'
    );

  v_discount :=
    public.finance_system_account(
      new.company_id,
      'sales_discounts'
    );

  if new.total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          new.total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'ذمة فاتورة بيع'
        )
      );
  end if;

  if new.discount_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_discount,
          'debit',
          new.discount_total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'خصم مبيعات'
        )
      );
  end if;

  if new.subtotal > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_sales,
          'debit',
          0,
          'credit',
          new.subtotal,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'إيراد مبيعات'
        )
      );
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      new.invoice_date,
      'فاتورة بيع ' ||
      new.invoice_number,
      new.currency,
      null,
      'sales_invoice',
      new.id,
      v_lines
    );

  return new;
end;
$function$;

create or replace function public.gl_supplier_allocation_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_supplier uuid;
  v_date date;
  v_cashbox uuid;
  v_currency text;
  v_status text;

  v_advance uuid;
  v_ap uuid;
begin
  select
    company_id,
    supplier_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_supplier,
    v_date,
    v_cashbox,
    v_status
  from public.supplier_payments
  where id =
        new.payment_id;

  if v_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'supplier_advances'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'تخصيص دفعة على فاتورة شراء',
      -- الدفعة ممكن تكون بعملة غير عملة الفاتورة (مثلًا ليرة على فاتورة دولار)،
      -- فالقيد لازم ينكتب بمبلغ الدفعة وعملتها وسعر صرفها، مش بمبلغ الفاتورة.
      coalesce(new.payment_currency, v_currency),
      new.payment_rate_to_base,
      'supplier_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          coalesce(new.payment_amount, new.amount),
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          coalesce(new.payment_amount, new.amount),
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_supplier_payment_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'supplier_payment',
        new.id,
        new.payment_date,
        'عكس دفعة مورد ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.supplier_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'supplier_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص دفعة مورد'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'supplier_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'دفعة إلى مورد ' ||
      new.payment_number,
      v_currency,
      null,
      'supplier_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.sync_purchase_invoice_journal(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_supplier uuid;
  v_number text;
  v_currency text;
  v_date date;
  v_status text;

  v_cost numeric(18,2);
  v_total numeric(18,2);
  v_variance numeric(18,2);

  v_clearing uuid;
  v_ap uuid;
  v_variance_account uuid;

  v_lines jsonb := '[]'::jsonb;
begin
  select
    company_id,
    supplier_id,
    invoice_number,
    currency,
    invoice_date,
    status
  into
    v_company,
    v_supplier,
    v_number,
    v_currency,
    v_date,
    v_status
  from public.purchase_invoices
  where id = target_invoice;

  if v_company is null
     or v_status <> 'posted'
  then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          quantity *
          unit_cost
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(line_total),
        0
      ),
      2
    )
  into
    v_cost,
    v_total
  from public.purchase_invoice_items
  where invoice_id =
        target_invoice;

  if v_total <= 0
     and v_cost <= 0
  then
    return;
  end if;

  delete from public.journal_entries
  where company_id =
        v_company
    and source_type =
        'purchase_invoice'
    and source_id =
        target_invoice
    and reversed_from_id
        is null
    and status =
        'posted';

  v_clearing :=
    public.finance_system_account(
      v_company,
      'inventory_clearing'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  v_variance_account :=
    public.finance_system_account(
      v_company,
      'purchase_variance'
    );

  if v_cost > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_cost,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'قيمة بضاعة مشتراة'
        )
      );
  end if;

  v_variance :=
    round(
      v_total -
      v_cost,
      2
    );

  if v_variance > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          v_variance,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'فروقات وتكاليف شراء'
        )
      );

  elsif v_variance < 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          0,
          'credit',
          abs(v_variance),
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'خصم شراء'
        )
      );
  end if;

  if v_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          0,
          'credit',
          v_total,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'ذمة مورد'
        )
      );
  end if;

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'فاتورة شراء ' ||
      v_number,
      v_currency,
      null,
      'purchase_invoice',
      target_invoice,
      v_lines
    );
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger gl_cash_movement after insert on public.cash_transactions for each row execute function public.gl_cash_movement_trigger();

create trigger gl_customer_payment_allocation after insert on public.customer_payment_allocations for each row execute function public.gl_customer_allocation_trigger();

create trigger gl_customer_payment after insert or update of status on public.customer_payments for each row execute function public.gl_customer_payment_trigger();

create trigger gl_expense after insert on public.expenses for each row execute function public.gl_expense_trigger();

create trigger gl_inventory_movement after insert on public.inventory_movements for each row execute function public.gl_inventory_movement_trigger();

create trigger gl_purchase_invoice_item after insert or delete or update on public.purchase_invoice_items for each row execute function public.gl_purchase_item_trigger();

create trigger gl_purchase_invoice_status after update of status on public.purchase_invoices for each row execute function public.gl_purchase_invoice_status_trigger();

create trigger gl_sales_invoice after insert or update of status on public.sales_invoices for each row execute function public.gl_sales_invoice_trigger();

create trigger gl_supplier_payment_allocation after insert on public.supplier_payment_allocations for each row execute function public.gl_supplier_allocation_trigger();

create trigger gl_supplier_payment after insert or update of status on public.supplier_payments for each row execute function public.gl_supplier_payment_trigger();


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke execute on function public.sync_purchase_invoice_journal(uuid) from authenticated;

-- ======================================================================
-- التقارير
-- لوحة التحكم، التقارير المالية، أعمار الديون، التقارير الشهرية
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.get_dashboard_summary(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_business_date date;
  v_day_start timestamptz;
  v_day_end timestamptz;

  v_currency text;

  v_today_sales numeric(18,2) := 0;
  v_today_invoice_count bigint := 0;

  v_open_orders bigint := 0;
  v_purchasing_orders bigint := 0;
  v_ready_orders bigint := 0;
  v_delivery_orders bigint := 0;
  v_delivered_today bigint := 0;

  v_unpaid_invoices bigint := 0;

  v_customer_count bigint := 0;
  v_product_count bigint := 0;
  v_supplier_count bigint := 0;
  v_order_count bigint := 0;

  v_recent_customers jsonb := '[]'::jsonb;
  v_can_view_traders boolean := false;
begin
  -- Dashboard access is checked here, not only in the UI.
  if not public.has_permission(
    target_company,
    'dashboard.view'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    upper(coalesce(c.default_currency, 'USD'))
  into
    v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  -- One canonical business day for Syria/Lebanon operations.
  v_business_date :=
    (now() at time zone 'Asia/Damascus')::date;

  v_day_start :=
    (
      v_business_date::timestamp
      at time zone 'Asia/Damascus'
    );

  v_day_end :=
    (
      (v_business_date + 1)::timestamp
      at time zone 'Asia/Damascus'
    );

  -- ----------------------------------------------------------
  -- TODAY'S ACTUAL INVOICED SALES
  -- Uses posted sales invoices, not newly-created orders.
  -- Cancelled invoices are excluded.
  -- ----------------------------------------------------------

  select
    round(
      coalesce(sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))), 0),
      2
    ),
    count(*)
  into
    v_today_sales,
    v_today_invoice_count
  from public.sales_invoices si
  where si.company_id = target_company
    and si.status = 'posted'
    and si.posted_at >= v_day_start
    and si.posted_at < v_day_end;

  -- ----------------------------------------------------------
  -- ORDER WORKFLOW
  -- No LIMIT: counts the complete company dataset.
  -- Drafts are not considered active execution.
  -- ----------------------------------------------------------

  select
    count(*) filter (
      where so.status in (
        'new',
        'to_purchase',
        'purchasing',
        'ready',
        'out_for_delivery'
      )
    ),

    count(*) filter (
      where so.status in (
        'to_purchase',
        'purchasing'
      )
    ),

    count(*) filter (
      where so.status = 'ready'
    ),

    count(*) filter (
      where so.status = 'out_for_delivery'
    ),

    count(*) filter (
      where so.status <> 'cancelled'
    )
  into
    v_open_orders,
    v_purchasing_orders,
    v_ready_orders,
    v_delivery_orders,
    v_order_count
  from public.sales_orders so
  where so.company_id = target_company;

  -- Delivered TODAY, not lifetime delivered orders.
  select
    count(*)
  into
    v_delivered_today
  from public.sales_orders so
  where so.company_id = target_company
    and so.status = 'delivered'
    and so.delivered_at >= v_day_start
    and so.delivered_at < v_day_end;

  -- Actual posted invoices that still have money due.
  select
    count(*)
  into
    v_unpaid_invoices
  from public.sales_invoices si
  where si.company_id = target_company
    and si.status = 'posted'
    and (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date)) > 0;

  -- "Customers" means actual customer status, not leads/inactive.
  select
    count(*)
  into
    v_customer_count
  from public.traders t
  where t.company_id = target_company
    and t.status = 'customer';

  -- Active catalog records only.
  select
    count(*)
  into
    v_product_count
  from public.products p
  where p.company_id = target_company
    and p.active = true;

  select
    count(*)
  into
    v_supplier_count
  from public.suppliers s
  where s.company_id = target_company
    and s.active = true;

  -- Customer names/phones are only returned when the user
  -- actually has traders.view. dashboard.view alone exposes
  -- aggregate numbers, not customer details.
  v_can_view_traders :=
    public.has_permission(
      target_company,
      'traders.view'
    );

  if v_can_view_traders then
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'name', r.name,
            'area', r.area,
            'phone', r.phone,
            'created_at', r.created_at
          )
          order by r.created_at desc
        ),
        '[]'::jsonb
      )
    into
      v_recent_customers
    from (
      select
        t.id,
        t.name,
        t.area,
        t.phone,
        t.created_at
      from public.traders t
      where t.company_id = target_company
        and t.status = 'customer'
      order by t.created_at desc
      limit 5
    ) r;
  end if;

  return jsonb_build_object(
    'business_date', v_business_date,
    'currency', v_currency,

    'today_sales', v_today_sales,
    'today_invoice_count', v_today_invoice_count,

    'open_orders', v_open_orders,
    'purchasing_orders', v_purchasing_orders,
    'ready_orders', v_ready_orders,
    'delivery_orders', v_delivery_orders,
    'delivered_today', v_delivered_today,

    'unpaid_invoices', v_unpaid_invoices,

    'customer_count', v_customer_count,
    'active_product_count', v_product_count,
    'active_supplier_count', v_supplier_count,
    'order_count', v_order_count,

    'recent_customers', v_recent_customers
  );
end;
$function$;

create or replace function public.get_financial_report(target_company uuid, target_start date, target_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
  v_end date;

  v_revenue numeric(18,2);
  v_cogs numeric(18,2);
  v_operating_expenses numeric(18,2);

  v_gross_profit numeric(18,2);
  v_net_profit numeric(18,2);

  v_assets numeric(18,2);
  v_liabilities numeric(18,2);
  v_equity numeric(18,2);

  v_lifetime_revenue numeric(18,2);
  v_lifetime_expenses numeric(18,2);
  v_current_earnings numeric(18,2);

  v_cash_in numeric(18,2);
  v_cash_out numeric(18,2);
  v_cash_net numeric(18,2);

  v_ar numeric(18,2);
  v_ap numeric(18,2);

  v_inventory_value numeric(18,2);

  v_base_currency text;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'reports.profit',
      'finance.accounts_view'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_start :=
    coalesce(
      target_start,
      date_trunc(
        'year',
        (now() at time zone 'Asia/Damascus')::date
      )::date
    );

  v_end :=
    coalesce(
      target_end,
      (now() at time zone 'Asia/Damascus')::date
    );

  if v_end < v_start then
    raise exception
      'Invalid report date range';
  end if;

  select default_currency
  into v_base_currency
  from public.companies
  where id = target_company;

  if v_base_currency is null then
    raise exception
      'Company not found';
  end if;


  -- ----------------------------------------------------------
  -- REVENUE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_revenue
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_type =
        'revenue';


  -- ----------------------------------------------------------
  -- COST OF GOODS SOLD
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_cogs
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and (
      a.system_key =
        'cogs'

      or a.account_group =
         'cost_of_sales'
    );


  -- ----------------------------------------------------------
  -- OTHER EXPENSES
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_operating_expenses
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_type =
        'expense'

    and coalesce(
          a.system_key,
          ''
        ) <>
        'cogs'

    and coalesce(
          a.account_group,
          ''
        ) <>
        'cost_of_sales';


  v_gross_profit :=
    round(
      v_revenue -
      v_cogs,
      2
    );

  v_net_profit :=
    round(
      v_revenue -
      v_cogs -
      v_operating_expenses,
      2
    );


  -- ----------------------------------------------------------
  -- BALANCE SHEET AS OF END DATE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_assets
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'asset';


  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_liabilities
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'liability';


  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_equity
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'equity';


  -- ----------------------------------------------------------
  -- CURRENT EARNINGS THROUGH END DATE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          case
            when a.account_type =
                 'revenue'
              then
                jl.base_credit -
                jl.base_debit

            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when a.account_type =
                 'expense'
              then
                jl.base_debit -
                jl.base_credit

            else 0
          end
        ),
        0
      ),
      2
    )

  into
    v_lifetime_revenue,
    v_lifetime_expenses

  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end;


  v_current_earnings :=
    round(
      v_lifetime_revenue -
      v_lifetime_expenses,
      2
    );


  -- ----------------------------------------------------------
  -- CASH FLOW
  -- Debit to cash = cash in
  -- Credit from cash = cash out
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          jl.base_credit
        ),
        0
      ),
      2
    )

  into
    v_cash_in,
    v_cash_out

  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_group =
        'cash_bank';


  v_cash_net :=
    round(
      v_cash_in -
      v_cash_out,
      2
    );


  -- ----------------------------------------------------------
  -- ACCOUNTS RECEIVABLE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(balance_due),
        0
      ),
      2
    )
  into v_ar
  from public.sales_invoices
  where company_id =
        target_company

    and status =
        'posted'

    and invoice_date <=
        v_end;


  -- ----------------------------------------------------------
  -- ACCOUNTS PAYABLE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(balance_due),
        0
      ),
      2
    )
  into v_ap
  from public.purchase_invoices
  where company_id =
        target_company

    and status =
        'posted'

    and invoice_date <=
        v_end;


  -- ----------------------------------------------------------
  -- INVENTORY VALUE - weighted average
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          on_hand *
          average_cost
        ),
        0
      ),
      2
    )
  into v_inventory_value
  from public.inventory_stock
  where company_id =
        target_company;


  return jsonb_build_object(
    'currency',
      v_base_currency,

    'start_date',
      v_start,

    'end_date',
      v_end,

    'profit_loss',
      jsonb_build_object(
        'revenue',
          v_revenue,

        'cost_of_goods_sold',
          v_cogs,

        'gross_profit',
          v_gross_profit,

        'operating_expenses',
          v_operating_expenses,

        'net_profit',
          v_net_profit
      ),

    'balance_sheet',
      jsonb_build_object(
        'assets',
          v_assets,

        'liabilities',
          v_liabilities,

        'equity_posted',
          v_equity,

        'current_earnings',
          v_current_earnings,

        'equity_with_current_earnings',
          round(
            v_equity +
            v_current_earnings,
            2
          )
      ),

    'cash_flow',
      jsonb_build_object(
        'cash_in',
          v_cash_in,

        'cash_out',
          v_cash_out,

        'net_cash_flow',
          v_cash_net
      ),

    'working_capital',
      jsonb_build_object(
        'accounts_receivable',
          v_ar,

        'accounts_payable',
          v_ap,

        'inventory_value',
          v_inventory_value
      )
  );
end;
$function$;

create or replace function public.get_payables_aging(target_company uuid, target_as_of date)
 RETURNS TABLE(supplier_id uuid, supplier_name text, current_amount numeric, days_1_30 numeric, days_31_60 numeric, days_61_90 numeric, over_90 numeric, total_due numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'purchases.view',
      'payments.supplier_view',
      'suppliers.view_finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    s.id,
    s.name,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) <= 0
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 1 and 30
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 31 and 60
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 61 and 90
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) > 90
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))),
        0
      ),
      2
    )

  from public.suppliers s

  join public.purchase_invoices pi
    on pi.supplier_id = s.id
   and pi.company_id =
       target_company
   and pi.status = 'posted'
   and pi.invoice_date <=
       coalesce(
         target_as_of,
         current_date
       )
   and pi.balance_due > 0

  where s.company_id =
        target_company

  group by
    s.id,
    s.name

  having
    sum(public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))) > 0

  order by
    total_due desc,
    s.name;
end;
$function$;

create or replace function public.get_purchase_monthly_report(target_company uuid, target_start date, target_end date)
 RETURNS TABLE(month_start date, invoice_count bigint, gross_purchases numeric, purchase_returns numeric, net_purchases numeric, paid numeric, outstanding numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'purchases.view',
      'reports.profit',
      'reports.finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with invoice_data as (
    select
      date_trunc(
        'month',
        pi.invoice_date
      )::date as month_start,

      count(*) as invoice_count,

      coalesce(
        sum((pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as gross_purchases,

      coalesce(
        sum((pi.paid_total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as paid,

      coalesce(
        sum((pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as outstanding

    from public.purchase_invoices pi

    where pi.company_id =
          target_company

      and pi.status =
          'posted'

      and pi.invoice_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  ),

  return_data as (
    select
      date_trunc(
        'month',
        pr.return_date
      )::date as month_start,

      coalesce(
        sum((pr.total * public.finance_rate_to_base(target_company, pr.currency, pr.return_date))),
        0
      ) as return_total

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.status =
          'posted'

      and pr.return_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  )

  select
    i.month_start,
    i.invoice_count,

    round(
      i.gross_purchases,
      2
    ),

    round(
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.gross_purchases -
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.paid,
      2
    ),

    round(
      i.outstanding,
      2
    )

  from invoice_data i

  left join return_data r
    on r.month_start =
       i.month_start

  order by
    i.month_start;
end;
$function$;

create or replace function public.get_receivables_aging(target_company uuid, target_as_of date)
 RETURNS TABLE(trader_id uuid, trader_name text, current_amount numeric, days_1_30 numeric, days_31_60 numeric, days_61_90 numeric, over_90 numeric, total_due numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'reports.sales',
      'payments.sales_view',
      'traders.view_balance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    t.id,
    t.name,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) <= 0
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 1 and 30
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 31 and 60
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 61 and 90
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) > 90
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))),
        0
      ),
      2
    )

  from public.traders t

  join public.sales_invoices si
    on si.trader_id = t.id
   and si.company_id =
       target_company
   and si.status = 'posted'
   and si.invoice_date <=
       coalesce(
         target_as_of,
         current_date
       )
   and si.balance_due > 0

  where t.company_id =
        target_company

  group by
    t.id,
    t.name

  having
    sum(public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))) > 0

  order by
    total_due desc,
    t.name;
end;
$function$;

create or replace function public.get_sales_monthly_report(target_company uuid, target_start date, target_end date)
 RETURNS TABLE(month_start date, invoice_count bigint, gross_sales numeric, sales_returns numeric, net_sales numeric, collected numeric, outstanding numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.sales',
      'reports.profit',
      'reports.finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with invoice_data as (
    select
      date_trunc(
        'month',
        si.invoice_date
      )::date as month_start,

      count(*) as invoice_count,

      coalesce(
        sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as gross_sales,

      coalesce(
        sum((si.paid_total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as collected,

      coalesce(
        sum((si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as outstanding

    from public.sales_invoices si

    where si.company_id =
          target_company

      and si.status =
          'posted'

      and si.invoice_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  ),

  return_data as (
    select
      date_trunc(
        'month',
        sr.return_date
      )::date as month_start,

      coalesce(
        sum((sr.total * public.finance_rate_to_base(target_company, sr.currency, sr.return_date))),
        0
      ) as return_total

    from public.sales_returns sr

    where sr.company_id =
          target_company

      and sr.status =
          'posted'

      and sr.return_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  )

  select
    i.month_start,
    i.invoice_count,

    round(
      i.gross_sales,
      2
    ),

    round(
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.gross_sales -
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.collected,
      2
    ),

    round(
      i.outstanding,
      2
    )

  from invoice_data i

  left join return_data r
    on r.month_start =
       i.month_start

  order by
    i.month_start;
end;
$function$;

