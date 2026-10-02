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
  address text,
  -- الضريبة خيار: مطفية افتراضيًا.
  tax_enabled boolean default false not null,
  tax_rate numeric(5,2) default 0 not null check (tax_rate >= 0 and tax_rate <= 100),
  tax_number text,
  tax_label text default 'ضريبة المبيعات'::text not null,
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
  ('sales.quick_sale', 'orders', 'quick_sale', 'بيع سريع (كاشير)', null, 72),
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

-- ----------------------------------------------------------------------
-- رمز المالك: المالك بيكتبو قدام الموظف ليمشّي عملية حساسة لمرة وحدة.
-- ----------------------------------------------------------------------
create table public.company_owner_pins (
  company_id uuid primary key references public.companies(id) on delete cascade,
  pin_hash text not null,
  updated_at timestamp with time zone default now() not null
);

create table public.owner_overrides (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  action text not null,
  succeeded boolean not null,
  expires_at timestamp with time zone not null default (now() + interval '3 minutes'),
  used_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  constraint owner_overrides_action_check check (action in ('approve','below_min','credit_limit','cancel_invoice','reverse_payment','reverse_return'))
);

create index owner_overrides_lookup_idx on public.owner_overrides using btree (company_id, user_id, action, created_at desc);

-- ما في سياسات قراءة: الجدولين بيتعاملوا معهن الدوال بس.
alter table public.company_owner_pins enable row level security;
alter table public.owner_overrides enable row level security;

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


  -- صفة المالك (أو تغيير صفة شريك مالك) بيعملها مالك بس، مش المدير.
  if (
       coalesce(v_role_owner, false)
       or exists(
         select 1
         from public.company_members m
         join public.company_roles r on r.id = m.role_id
         where m.company_id = target_company
           and m.user_id = target_user
           and r.is_owner
       )
     )
     and not public.is_company_owner(target_company)
  then
    raise exception
      'Only an owner can manage owners';
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
    'orders.view','orders.create','orders.update','orders.cancel','orders.approve_discount','sales.quick_sale',
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
    'traders.view_balance',
    'visits.view','visits.create','visits.update',
    'suppliers.view','products.view',
    'orders.view','orders.create','orders.update','orders.cancel','sales.quick_sale',
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
    )
    -- جوّا "البيع السريع" بس: صلاحية البيع السريع بتغطي الطلبية والتسليم والقبض لهالعملية.
    or (
      target_permission = any(string_to_array(coalesce(current_setting('app.elevated_permissions', true), ''), ','))
      and coalesce(current_setting('app.elevated_company', true), '') = target_company::text
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

create or replace function public.set_owner_pin(target_company uuid, target_pin text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_company_owner(target_company) then
    raise exception 'Only the owner can set the approval code';
  end if;

  if target_pin is null or target_pin !~ '^[0-9]{4,8}$' then
    raise exception 'Approval code must be 4 to 8 digits';
  end if;

  insert into public.company_owner_pins(company_id, pin_hash)
  values (target_company, extensions.crypt(target_pin, extensions.gen_salt('bf')))
  on conflict (company_id)
  do update set pin_hash = excluded.pin_hash, updated_at = now();
end;
$function$;

create or replace function public.has_owner_pin(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_company_member(target_company)
     and exists (select 1 from public.company_owner_pins where company_id = target_company);
$function$;

-- الموظف بيكتب رمز المالك → بينفتح إذن لعملية وحدة من نوع معيّن، صالح 3 دقايق.
create or replace function public.unlock_owner_override(target_company uuid, target_action text, target_pin text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_hash text;
  v_ok boolean;
begin
  if not public.is_company_member(target_company) then
    raise exception 'Not allowed';
  end if;

  if (
    select count(*) from public.owner_overrides
    where company_id = target_company
      and user_id = auth.uid()
      and not succeeded
      and created_at > now() - interval '10 minutes'
  ) >= 5 then
    raise exception 'Too many wrong approval codes';
  end if;

  select pin_hash into v_hash from public.company_owner_pins where company_id = target_company;

  if v_hash is null then
    raise exception 'Owner approval code is not set';
  end if;

  v_ok := extensions.crypt(coalesce(target_pin, ''), v_hash) = v_hash;

  insert into public.owner_overrides(company_id, action, succeeded)
  values (target_company, target_action, v_ok);

  return v_ok;
end;
$function$;

-- جوّا العملية الحساسة: إذا في إذن صالح منستعملو (مرة وحدة، بس بيضل ساري لآخر هالعملية).
create or replace function public.use_owner_override(target_company uuid, target_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if coalesce(current_setting('app.owner_override_' || target_action, true), '') = 'on' then
    return true;
  end if;

  select id into v_id
  from public.owner_overrides
  where company_id = target_company
    and user_id = auth.uid()
    and action = target_action
    and succeeded
    and used_at is null
    and expires_at > now()
  order by created_at desc
  limit 1
  for update skip locked;

  if v_id is null then
    return false;
  end if;

  update public.owner_overrides set used_at = now() where id = v_id;
  perform set_config('app.owner_override_' || target_action, 'on', true);
  return true;
end;
$function$;

create or replace function public.is_company_owner(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- المالك الأول (يلي عمل الشركة) أو أي شريك أعطاه مالك صفة "المالك".
  select exists(
    select 1
    from public.companies c
    where c.id = target_company
      and c.owner_user_id = auth.uid()
  )
  or exists(
    select 1
    from public.company_members m
    join public.company_roles r on r.id = m.role_id
    where m.company_id = target_company
      and m.user_id = auth.uid()
      and r.is_owner
      and r.active
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

  -- شريك مالك ما بيشيلو ولا بيغيّر صفتو غير مالك.
  if tg_op in ('DELETE','UPDATE')
     and auth.uid() is not null
     and exists(select 1 from public.company_roles r where r.id = old.role_id and r.is_owner)
     and not public.is_company_owner(old.company_id)
  then
    raise exception 'Only an owner can manage owners';
  end if;

  if tg_op in ('INSERT','UPDATE') then
    select is_owner
    into v_role_owner
    from public.company_roles
    where id = new.role_id
      and company_id = new.company_id;

    if coalesce(v_role_owner,false)
       and new.user_id <> v_owner
       and auth.uid() is not null
       and not public.is_company_owner(new.company_id)
    then
      raise exception 'Only an owner can manage owners';
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

revoke execute on function public.use_owner_override(uuid,text) from authenticated;
