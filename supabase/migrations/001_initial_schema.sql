-- SALES OS CLEAN BASELINE
-- Fresh database schema consolidated from historical migrations 001-016.
-- Built for a full reset: no legacy purchase_runs, no legacy order-paid RPC,
-- no supplier/cost fields on sales order items, and no one-order/one-document constraints.

begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =========================================================
-- IDENTITY / COMPANY / TEAM
-- =========================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  phone text,
  whatsapp text,
  logo_url text,
  default_currency text not null default 'USD',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger companies_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

create table public.permissions (
  code text primary key,
  module text not null,
  action text not null,
  label text not null,
  description text,
  sort_order integer not null default 0
);

create table public.company_roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  is_owner boolean not null default false,
  is_protected boolean not null default false,
  active boolean not null default true,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index company_roles_name_unique
on public.company_roles(company_id, lower(name));

create unique index company_roles_one_owner
on public.company_roles(company_id)
where is_owner = true;

create index company_roles_company_idx
on public.company_roles(company_id);

create trigger company_roles_updated_at
before update on public.company_roles
for each row execute function public.set_updated_at();

create table public.company_members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.company_roles(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key(company_id, user_id)
);

create index company_members_role_idx
on public.company_members(role_id);

create table public.role_permissions (
  role_id uuid not null references public.company_roles(id) on delete cascade,
  permission_code text not null references public.permissions(code) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(role_id, permission_code)
);

create index role_permissions_role_idx
on public.role_permissions(role_id);

insert into public.permissions(code,module,action,label,sort_order)
values
('dashboard.view','dashboard','view','عرض لوحة التحكم',10),

('team.view','team','view','عرض الفريق',20),
('team.manage_members','team','manage_members','إدارة الموظفين',21),
('team.manage_roles','team','manage_roles','إدارة الصفات والصلاحيات',22),

('traders.view','traders','view','عرض التجار',30),
('traders.create','traders','create','إضافة تاجر',31),
('traders.update','traders','update','تعديل تاجر',32),
('traders.archive','traders','archive','تعطيل أو أرشفة تاجر',33),
('traders.assign_rep','traders','assign_rep','تعيين مندوب للتاجر',34),
('traders.view_balance','traders','view_balance','عرض حساب التاجر',35),

('visits.view','visits','view','عرض الزيارات',40),
('visits.create','visits','create','تسجيل زيارة',41),
('visits.update','visits','update','تعديل زيارة',42),

('suppliers.view','suppliers','view','عرض الموردين',50),
('suppliers.create','suppliers','create','إضافة مورد',51),
('suppliers.update','suppliers','update','تعديل مورد',52),
('suppliers.archive','suppliers','archive','تعطيل أو أرشفة مورد',53),
('suppliers.view_finance','suppliers','view_finance','عرض حساب المورد',54),

('products.view','products','view','عرض الأصناف',60),
('products.create','products','create','إضافة صنف',61),
('products.update','products','update','تعديل صنف وأسعار الموردين',62),
('products.archive','products','archive','تعطيل أو أرشفة صنف',63),
('products.view_cost','products','view_cost','عرض تكلفة الشراء',64),

('orders.view','orders','view','عرض الطلبيات',70),
('orders.create','orders','create','إنشاء طلبية',71),
('orders.update','orders','update','تعديل طلبية',72),
('orders.cancel','orders','cancel','إلغاء طلبية',73),
('orders.approve_discount','orders','approve_discount','الموافقة على الخصومات',74),

('deliveries.view','deliveries','view','عرض التوصيل',80),
('deliveries.update','deliveries','update','تحديث حالة التوصيل',81),

('purchases.view','purchases','view','عرض المشتريات',90),
('purchases.create','purchases','create','تسجيل شراء',91),
('purchases.update','purchases','update','تعديل شراء',92),
('purchases.cancel','purchases','cancel','إلغاء شراء',93),

('sales_invoices.view','sales_invoices','view','عرض فواتير البيع',100),
('sales_invoices.create','sales_invoices','create','إنشاء فاتورة بيع',101),
('sales_invoices.cancel','sales_invoices','cancel','إلغاء فاتورة بيع',102),

('purchase_invoices.view','purchase_invoices','view','عرض فواتير الشراء',110),
('purchase_invoices.create','purchase_invoices','create','إنشاء فاتورة شراء',111),
('purchase_invoices.cancel','purchase_invoices','cancel','إلغاء فاتورة شراء',112),

('payments.sales_view','payments','sales_view','عرض دفعات التجار',120),
('payments.sales_create','payments','sales_create','قبض من تاجر',121),
('payments.supplier_view','payments','supplier_view','عرض دفعات الموردين',122),
('payments.supplier_create','payments','supplier_create','دفع لمورد',123),
('payments.supplier_reverse','payments','supplier_reverse','عكس دفعة مورد',124),
('payments.sales_reverse','payments','sales_reverse','عكس دفعة تاجر',125),

('inventory.view','inventory','view','عرض المخزون',130),
('inventory.adjust','inventory','adjust','تسوية المخزون',131),
('inventory.returns','inventory','returns','إدارة المرتجعات',132),

('finance.cashbox_view','finance','cashbox_view','عرض الصندوق والحسابات',140),
('finance.cashbox_write','finance','cashbox_write','إدارة حركات الصندوق',141),
('finance.expenses_view','finance','expenses_view','عرض المصاريف',142),
('finance.expenses_write','finance','expenses_write','إضافة وتعديل المصاريف',143),
('finance.expense_categories','finance','expense_categories','إدارة فئات المصاريف',144),
('finance.accounts_view','finance','accounts_view','عرض الحسابات المالية',145),
('finance.accounts_write','finance','accounts_write','إدارة الحسابات المالية',146),
('finance.month_close','finance','month_close','إقفال الشهر',147),
('finance.month_reopen','finance','month_reopen','إعادة فتح شهر مقفل',148),

('map.view','map','view','عرض الخريطة',150),

('reports.view','reports','view','عرض التقارير',160),
('reports.sales','reports','sales','تقارير المبيعات',161),
('reports.profit','reports','profit','تقارير الأرباح',162),
('reports.finance','reports','finance','التقارير المالية',163),
('reports.team','reports','team','تقارير الموظفين والمندوبين',164),

('settings.view','settings','view','عرض الإعدادات',180),
('settings.manage_company','settings','manage_company','تعديل معلومات الشركة',181),

('audit.view','audit','view','عرض سجل التعديلات',190);

create or replace function public.is_company_member(target_company uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.company_members cm
    where cm.company_id = target_company
      and cm.user_id = auth.uid()
  );
$$;

create or replace function public.is_company_owner(target_company uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.companies c
    where c.id = target_company
      and c.owner_user_id = auth.uid()
  );
$$;

create or replace function public.has_permission(
  target_company uuid,
  target_permission text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
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
$$;

create or replace function public.has_any_permission(
  target_company uuid,
  target_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
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
$$;



create or replace function public.protect_owner_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create trigger protect_owner_role_trigger
before update or delete on public.company_roles
for each row execute function public.protect_owner_role();

create or replace function public.protect_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create trigger protect_owner_membership_trigger
before insert or update or delete on public.company_members
for each row execute function public.protect_owner_membership();

create or replace function public.handle_company_access_setup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
    'audit.view'
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
    'settings.view'
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
$$;

create trigger on_company_access_setup
after insert on public.companies
for each row execute function public.handle_company_access_setup();



-- =========================================================
-- CRM / CATALOG
-- =========================================================

create table public.traders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  area text,
  address text,
  latitude numeric(10,7)
    check (latitude is null or latitude between -90 and 90),
  longitude numeric(10,7)
    check (longitude is null or longitude between -180 and 180),
  check (
    (latitude is null and longitude is null)
    or
    (latitude is not null and longitude is not null)
  ),
  status text not null default 'new'
    check(status in ('new','contacted','interested','customer','inactive')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index traders_company_phone_unique
on public.traders(company_id, phone)
where phone is not null;

create unique index traders_company_whatsapp_unique
on public.traders(company_id, whatsapp)
where whatsapp is not null;

create trigger traders_updated_at
before update on public.traders
for each row execute function public.set_updated_at();

create or replace function public.prevent_duplicate_trader_contact()
returns trigger
language plpgsql
set search_path = public
as $$
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
$$;

create trigger traders_prevent_duplicate_contact
before insert or update of phone, whatsapp on public.traders
for each row execute function public.prevent_duplicate_trader_contact();


create or replace function public.enforce_trader_archive_permission()
returns trigger
language plpgsql
set search_path = public
as $
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
$;

drop trigger if exists
traders_archive_permission_guard
on public.traders;

create trigger traders_archive_permission_guard
before insert or update
on public.traders
for each row
execute function public.enforce_trader_archive_permission();
create table public.trader_visits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete cascade,
  result text not null default 'زيارة',
  notes text,
  contacted_at timestamptz not null default now(),
  next_follow_up_at timestamptz,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.enforce_trader_visit_company()
returns trigger
language plpgsql
set search_path = public
as $$
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
$$;

create trigger trader_visits_company_guard
before insert or update of company_id, trader_id
on public.trader_visits
for each row
execute function public.enforce_trader_visit_company();
create index trader_visits_company_idx
on public.trader_visits(company_id);

create index trader_visits_trader_idx
on public.trader_visits(trader_id, contacted_at desc);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  address text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();


create or replace function public.enforce_supplier_active_permission()
returns trigger
language plpgsql
set search_path = public
as $$
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
$$;

drop trigger if exists
suppliers_active_permission_guard
on public.suppliers;

create trigger suppliers_active_permission_guard
before insert or update of active
on public.suppliers
for each row
execute function public.enforce_supplier_active_permission();
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, name)
);

create trigger categories_updated_at
before update on public.categories
for each row execute function public.set_updated_at();

create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  brand text,
  unit text not null default 'piece',
  sale_price numeric(14,2) check (sale_price is null or sale_price >= 0),
  minimum_sale_price numeric(14,2) check (minimum_sale_price is null or minimum_sale_price >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, sku)
);

create trigger products_updated_at
before update on public.products
for each row execute function public.set_updated_at();


create or replace function public.enforce_product_active_permission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.enforce_product_active_permission()
from public, authenticated;

drop trigger if exists
products_active_permission_guard
on public.products;

create trigger products_active_permission_guard
before insert or update of active
on public.products
for each row
execute function public.enforce_product_active_permission();

create or replace function public.enforce_product_category_company()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.enforce_product_category_company()
from public, authenticated;

drop trigger if exists
products_category_company_guard
on public.products;

create trigger products_category_company_guard
before insert or update of
  company_id,
  category_id
on public.products
for each row
execute function public.enforce_product_category_company();
create table public.supplier_prices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  purchase_price numeric(14,2) not null check(purchase_price >= 0),
  available boolean not null default true,
  notes text,
  last_checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(supplier_id, product_id)
);

create trigger supplier_prices_updated_at
before update on public.supplier_prices
for each row execute function public.set_updated_at();


create or replace function public.enforce_supplier_price_company()
returns trigger
language plpgsql
set search_path = public
as $$
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
$$;

drop trigger if exists
supplier_prices_company_guard
on public.supplier_prices;

create trigger supplier_prices_company_guard
before insert or update of
  company_id,
  supplier_id,
  product_id
on public.supplier_prices
for each row
execute function public.enforce_supplier_price_company();
create table public.supplier_price_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  purchase_price numeric(14,2) not null check (purchase_price >= 0),
  available boolean not null default true,
  notes text,
  effective_at timestamptz not null default now(),
  changed_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index supplier_price_history_company_idx
on public.supplier_price_history(company_id, effective_at desc);

create index supplier_price_history_product_idx
on public.supplier_price_history(product_id, effective_at desc);

create index supplier_price_history_supplier_idx
on public.supplier_price_history(supplier_id, effective_at desc);

create index supplier_price_history_lookup_idx
on public.supplier_price_history(company_id, product_id, supplier_id, effective_at desc);


create or replace function public.capture_supplier_price_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create trigger supplier_prices_history_trigger
after insert or update on public.supplier_prices
for each row execute function public.capture_supplier_price_history();

-- =========================================================
-- SALES ORDERS / DELIVERY
-- =========================================================

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  status text not null default 'new'
    check (
      status in (
        'draft',
        'new',
        'to_purchase',
        'purchasing',
        'ready',
        'out_for_delivery',
        'delivered',
        'cancelled'
      )
    ),
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','partial','paid','credit')),
  subtotal numeric(14,2) not null default 0,
  discount_total numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notes text,
  ordered_at timestamptz not null default now(),
  delivered_at timestamptz,
  paid_at timestamptz,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sales_orders_company_idx
on public.sales_orders(company_id, created_at desc);

create index sales_orders_trader_idx
on public.sales_orders(trader_id, created_at desc);

create trigger sales_orders_updated_at
before update on public.sales_orders
for each row execute function public.set_updated_at();

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  sale_unit_price numeric(14,2) not null check (sale_unit_price >= 0),
  line_total numeric(14,2) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default now()
);

create index sales_order_items_order_idx
on public.sales_order_items(order_id);

create or replace function public.set_sales_order_item_line_total()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.line_total := round(new.quantity * new.sale_unit_price, 2);
  return new;
end;
$$;

create trigger sales_order_items_line_total_before
before insert or update of quantity, sale_unit_price
on public.sales_order_items
for each row execute function public.set_sales_order_item_line_total();

create or replace function public.recalc_sales_order(target_order uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.sales_order_items_recalc_after_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalc_sales_order(old.order_id);
    return old;
  end if;

  perform public.recalc_sales_order(new.order_id);
  return new;
end;
$$;

create trigger sales_order_items_recalc_after
after insert or update or delete on public.sales_order_items
for each row execute function public.sales_order_items_recalc_after_trigger();

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','out_for_delivery','delivered','failed')),
  scheduled_for timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  failed_by uuid
    references auth.users(id)
    on delete set null,
  failure_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index deliveries_order_idx
on public.deliveries(order_id, created_at desc);

create trigger deliveries_updated_at
before update on public.deliveries
for each row execute function public.set_updated_at();

create or replace function public.can_access_order(target_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
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
$$;

create or replace function public.can_write_order(target_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.sales_orders o
    where o.id = target_order
      and public.has_any_permission(
        o.company_id,
        array['orders.update']::text[]
      )
  );
$$;



-- =========================================================
-- CASH / EXPENSES
-- =========================================================

create table public.cashboxes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null default 'الصندوق الرئيسي',
  currency text not null default 'USD',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index cashboxes_company_name_unique
on public.cashboxes(company_id, name);

create or replace function public.handle_company_default_cashbox()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.cashboxes(company_id,name,currency)
  values(new.id,'الصندوق الرئيسي',coalesce(new.default_currency,'USD'))
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_company_default_cashbox
after insert on public.companies
for each row execute function public.handle_company_default_cashbox();

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid references public.cashboxes(id) on delete set null,
  category text not null,
  amount numeric(14,2) not null check(amount > 0),
  notes text,
  occurred_at timestamptz not null default now(),
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index expenses_company_idx
on public.expenses(company_id, occurred_at desc);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  direction text not null check(direction in ('in','out')),
  type text not null check(
    type in (
      'sale_receipt',
      'supplier_payment',
      'expense',
      'partner_deposit',
      'partner_withdrawal',
      'adjustment_in',
      'adjustment_out'
    )
  ),
  amount numeric(14,2) not null check(amount > 0),
  order_id uuid references public.sales_orders(id) on delete set null,
  trader_id uuid references public.traders(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  expense_id uuid references public.expenses(id) on delete set null,
  supplier_payment_id uuid,
  customer_payment_id uuid,
  notes text,
  occurred_at timestamptz not null default now(),
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index cash_transactions_company_idx
on public.cash_transactions(company_id, occurred_at desc);

create index cash_transactions_trader_idx
on public.cash_transactions(trader_id, occurred_at desc)
where trader_id is not null;

-- Payment foreign keys are added after their tables are created.

-- =========================================================
-- DOCUMENT SEQUENCES
-- =========================================================

create table public.document_sequences (
  company_id uuid not null references public.companies(id) on delete cascade,
  document_type text not null,
  sequence_year integer not null,
  next_value bigint not null default 1 check(next_value > 0),
  primary key(company_id, document_type, sequence_year)
);

-- =========================================================
-- PURCHASE INVOICES
-- =========================================================

create table public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  invoice_number text not null,
  supplier_invoice_number text,
  status text not null default 'posted'
    check(status in ('draft','posted','cancelled')),
  payment_status text not null default 'unpaid'
    check(payment_status in ('unpaid','partial','paid')),
  currency text not null default 'USD',
  invoice_date date not null default current_date,
  due_date date,
  subtotal numeric(14,2) not null default 0 check(subtotal >= 0),
  discount_total numeric(14,2) not null default 0 check(discount_total >= 0),
  tax_total numeric(14,2) not null default 0 check(tax_total >= 0),
  total numeric(14,2) not null default 0 check(total >= 0),
  paid_total numeric(14,2) not null default 0 check(paid_total >= 0),
  balance_due numeric(14,2) not null default 0 check(balance_due >= 0),
  notes text,
  posted_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, invoice_number),
  check(due_date is null or due_date >= invoice_date)
);

create index purchase_invoices_company_date_idx
on public.purchase_invoices(company_id, invoice_date desc, created_at desc);

create index purchase_invoices_supplier_idx
on public.purchase_invoices(supplier_id, invoice_date desc);

create unique index purchase_invoices_supplier_number_unique
on public.purchase_invoices(company_id, supplier_id, supplier_invoice_number)
where supplier_invoice_number is not null
  and status <> 'cancelled';

create trigger purchase_invoices_updated_at
before update on public.purchase_invoices
for each row execute function public.set_updated_at();

create table public.purchase_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.purchase_invoices(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  description text,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_cost numeric(14,2) not null check(unit_cost >= 0),
  discount_amount numeric(14,2) not null default 0 check(discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check(tax_amount >= 0),
  line_total numeric(14,2) not null check(line_total >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create index purchase_invoice_items_invoice_idx
on public.purchase_invoice_items(invoice_id);

create index purchase_invoice_items_product_idx
on public.purchase_invoice_items(company_id, product_id);

create table public.purchase_invoice_item_sources (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_invoice_item_id uuid not null
    references public.purchase_invoice_items(id) on delete cascade,
  sales_order_item_id uuid not null
    references public.sales_order_items(id) on delete restrict,
  quantity numeric(14,3) not null check(quantity > 0),
  created_at timestamptz not null default now(),
  unique(purchase_invoice_item_id, sales_order_item_id)
);

create index purchase_invoice_sources_order_item_idx
on public.purchase_invoice_item_sources(sales_order_item_id);


create or replace function public.next_purchase_invoice_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create or replace function public.refresh_sales_order_purchase_status(
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_items integer;
  v_fully_purchased integer;
  v_partly_purchased integer;
  v_current_status text;
begin
  select status
  into v_current_status
  from public.sales_orders
  where id = target_order;

  if v_current_status is null
     or v_current_status = 'cancelled'
  then
    return;
  end if;

  select
    count(*),
    count(*) filter (
      where coalesce(x.allocated,0) >= soi.quantity
    ),
    count(*) filter (
      where coalesce(x.allocated,0) > 0
    )
  into
    v_total_items,
    v_fully_purchased,
    v_partly_purchased
  from public.sales_order_items soi
  left join lateral (
    select coalesce(sum(src.quantity),0) as allocated
    from public.purchase_invoice_item_sources src
    join public.purchase_invoice_items pii
      on pii.id = src.purchase_invoice_item_id
    join public.purchase_invoices pi
      on pi.id = pii.invoice_id
    where src.sales_order_item_id = soi.id
      and pi.status <> 'cancelled'
  ) x on true
  where soi.order_id = target_order;

  update public.sales_orders
  set
    status =
      case
        when v_total_items > 0
         and v_fully_purchased = v_total_items
          then 'ready'
        when v_partly_purchased > 0
          then 'purchasing'
        else 'to_purchase'
      end,
    updated_at = now()
  where id = target_order
    and status not in (
      'out_for_delivery',
      'delivered',
      'cancelled'
    );
end;
$$;

create or replace function public.create_purchase_invoice(
  target_company uuid,
  target_supplier uuid,
  target_supplier_invoice_number text,
  target_invoice_date date,
  target_due_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.get_purchase_needs(
  target_company uuid
)
returns table(
  sales_order_item_id uuid,
  order_id uuid,
  trader_name text,
  product_id uuid,
  product_name text,
  sku text,
  required_quantity numeric,
  allocated_quantity numeric,
  remaining_quantity numeric,
  ordered_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
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
    soi.quantity,
    coalesce(alloc.allocated,0),
    greatest(
      soi.quantity - coalesce(alloc.allocated,0),
      0
    ),
    so.ordered_at
  from public.sales_order_items soi
  join public.sales_orders so
    on so.id = soi.order_id
  join public.traders t
    on t.id = so.trader_id
  join public.products p
    on p.id = soi.product_id
  left join lateral (
    select coalesce(sum(src.quantity),0) as allocated
    from public.purchase_invoice_item_sources src
    join public.purchase_invoice_items pii
      on pii.id = src.purchase_invoice_item_id
    join public.purchase_invoices pi
      on pi.id = pii.invoice_id
    where src.sales_order_item_id = soi.id
      and pi.status <> 'cancelled'
  ) alloc on true
  where so.company_id = target_company
    and so.status in ('new','to_purchase','purchasing')
    and greatest(
      soi.quantity - coalesce(alloc.allocated,0),
      0
    ) > 0
  order by so.ordered_at, p.name;
end;
$$;



-- =========================================================
-- SUPPLIER PAYMENTS
-- =========================================================

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  payment_number text not null,
  status text not null default 'posted'
    check(status in ('posted','reversed')),
  payment_date date not null default current_date,
  amount numeric(14,2) not null check(amount > 0),
  allocated_total numeric(14,2) not null default 0
    check(allocated_total >= 0 and allocated_total <= amount),
  unallocated_total numeric(14,2) not null default 0
    check(unallocated_total >= 0 and unallocated_total <= amount),
  payment_method text not null default 'cash'
    check(payment_method in ('cash','bank','card','check','other')),
  reference_number text,
  notes text,
  reversed_at timestamptz,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, payment_number),
  check(allocated_total + unallocated_total = amount)
);

create index supplier_payments_company_date_idx
on public.supplier_payments(company_id, payment_date desc, created_at desc);

create index supplier_payments_supplier_date_idx
on public.supplier_payments(supplier_id, payment_date desc, created_at desc);

create trigger supplier_payments_updated_at
before update on public.supplier_payments
for each row execute function public.set_updated_at();

create table public.supplier_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.supplier_payments(id) on delete restrict,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  amount numeric(14,2) not null check(amount > 0),
  created_at timestamptz not null default now(),
  unique(payment_id, purchase_invoice_id)
);

create index supplier_payment_allocations_invoice_idx
on public.supplier_payment_allocations(purchase_invoice_id);

create index supplier_payment_allocations_payment_idx
on public.supplier_payment_allocations(payment_id);

alter table public.cash_transactions
add constraint cash_transactions_supplier_payment_fk
foreign key (supplier_payment_id)
references public.supplier_payments(id)
on delete set null;

create index cash_transactions_supplier_payment_idx
on public.cash_transactions(supplier_payment_id)
where supplier_payment_id is not null;

create unique index cash_transactions_supplier_payment_type_unique
on public.cash_transactions(supplier_payment_id, type)
where supplier_payment_id is not null
  and type in ('supplier_payment','adjustment_in');


create or replace function public.next_supplier_payment_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.refresh_supplier_payment_totals(
  target_payment uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(14,2);
  v_allocated numeric(14,2);
begin

  select amount
  into v_amount
  from public.supplier_payments
  where id = target_payment;

  if v_amount is null then
    return;
  end if;


  select coalesce(sum(amount),0)
  into v_allocated
  from public.supplier_payment_allocations
  where payment_id = target_payment;


  update public.supplier_payments
  set
    allocated_total =
      round(v_allocated,2),

    unallocated_total =
      round(
        greatest(
          v_amount - v_allocated,
          0
        ),
        2
      )

  where id = target_payment;
end;
$$;

create or replace function public.recalc_purchase_invoice_payment(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric(14,2);
  v_paid numeric(14,2);
begin

  select total
  into v_total
  from public.purchase_invoices
  where id = target_invoice;

  if v_total is null then
    return;
  end if;


  select coalesce(sum(a.amount),0)
  into v_paid

  from public.supplier_payment_allocations a

  join public.supplier_payments p
    on p.id = a.payment_id

  where a.purchase_invoice_id =
    target_invoice

    and p.status = 'posted';


  v_paid :=
    least(
      round(v_paid,2),
      v_total
    );


  update public.purchase_invoices
  set
    paid_total = v_paid,

    balance_due =
      round(
        greatest(
          v_total - v_paid,
          0
        ),
        2
      ),

    payment_status =
      case
        when v_total = 0
          or v_paid >= v_total
          then 'paid'

        when v_paid > 0
          then 'partial'

        else 'unpaid'
      end

  where id = target_invoice;
end;
$$;

create or replace function
public.supplier_payment_allocation_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create trigger supplier_payment_allocation_changed_trigger
after insert or update or delete
on public.supplier_payment_allocations
for each row
execute function public.supplier_payment_allocation_changed();


create or replace function
public.supplier_payment_status_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create trigger supplier_payment_status_changed_trigger
after update of status
on public.supplier_payments
for each row
execute function public.supplier_payment_status_changed();


create or replace function public.record_supplier_payment(
  target_company uuid,
  target_supplier uuid,
  target_cashbox uuid,
  target_amount numeric,
  target_payment_date date,
  target_method text,
  target_reference text,
  target_notes text,
  allocations_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment uuid;
  v_payment_number text;
  v_cashbox uuid;

  v_allocation jsonb;
  v_invoice uuid;
  v_alloc_amount numeric(14,2);

  v_balance numeric(14,2);
  v_invoice_status text;
  v_invoice_supplier uuid;

  v_allocated_sum numeric(14,2) := 0;

  v_method text;
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
    raise exception 'Invalid payment amount';
  end if;


  if not exists (
    select 1
    from public.suppliers
    where id = target_supplier
      and company_id = target_company
  ) then
    raise exception 'Invalid supplier';
  end if;


  v_method :=
    coalesce(
      nullif(trim(target_method),''),
      'cash'
    );


  if v_method not in (
    'cash',
    'bank',
    'card',
    'check',
    'other'
  ) then
    raise exception 'Invalid payment method';
  end if;


  if target_payment_date is null then
    target_payment_date := current_date;
  end if;


  if target_cashbox is not null then

    select id
    into v_cashbox
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true;

  else

    select id
    into v_cashbox
    from public.cashboxes
    where company_id = target_company
      and active = true
    order by created_at
    limit 1;

  end if;


  if v_cashbox is null then
    raise exception 'No valid active cashbox';
  end if;


  if jsonb_typeof(
    coalesce(
      allocations_payload,
      '[]'::jsonb
    )
  ) <> 'array'
  then
    raise exception 'Invalid allocations payload';
  end if;


  v_payment_number :=
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
    notes
  )
  values(
    target_company,
    target_supplier,
    v_cashbox,
    v_payment_number,
    'posted',
    target_payment_date,
    round(target_amount,2),
    0,
    round(target_amount,2),
    v_method,
    nullif(trim(target_reference),''),
    nullif(trim(target_notes),'')
  )
  returning id into v_payment;


  for v_allocation in
    select value
    from jsonb_array_elements(
      coalesce(
        allocations_payload,
        '[]'::jsonb
      )
    )
  loop

    v_invoice :=
      nullif(
        v_allocation ->> 'purchase_invoice_id',
        ''
      )::uuid;

    v_alloc_amount :=
      nullif(
        v_allocation ->> 'amount',
        ''
      )::numeric;


    if v_invoice is null
       or v_alloc_amount is null
       or v_alloc_amount <= 0
    then
      raise exception 'Invalid payment allocation';
    end if;


    v_balance := null;
    v_invoice_status := null;
    v_invoice_supplier := null;


    select
      balance_due,
      status,
      supplier_id

    into
      v_balance,
      v_invoice_status,
      v_invoice_supplier

    from public.purchase_invoices

    where id = v_invoice
      and company_id = target_company

    for update;


    if v_balance is null then
      raise exception 'Purchase invoice not found';
    end if;


    if v_invoice_status <> 'posted' then
      raise exception
        'Cannot pay cancelled or unposted invoice';
    end if;


    if v_invoice_supplier <> target_supplier
    then
      raise exception
        'Invoice belongs to another supplier';
    end if;


    if round(v_alloc_amount,2) > v_balance
    then
      raise exception
        'Allocation exceeds invoice balance';
    end if;


    v_allocated_sum :=
      v_allocated_sum
      + round(v_alloc_amount,2);


    if v_allocated_sum >
       round(target_amount,2)
    then
      raise exception
        'Allocations exceed payment amount';
    end if;


    insert into public.supplier_payment_allocations(
      company_id,
      payment_id,
      purchase_invoice_id,
      amount
    )
    values(
      target_company,
      v_payment,
      v_invoice,
      round(v_alloc_amount,2)
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
    round(target_amount,2),
    target_supplier,
    v_payment,
    'دفعة مورد ' ||
      v_payment_number ||
      case
        when nullif(trim(target_notes),'')
             is not null
          then ' - ' || trim(target_notes)
        else ''
      end,
    target_payment_date::timestamptz
  );


  return v_payment;
end;
$$;

create or replace function public.reverse_supplier_payment(
  target_company uuid,
  target_payment uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    'adjustment_in',
    v_amount,
    v_supplier,
    target_payment,
    'عكس دفعة مورد ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$$;


create or replace function public.cancel_purchase_invoice(
  target_company uuid,
  target_invoice uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
  where id = target_invoice
    and company_id = target_company
  for update;

  if v_status is null then
    raise exception 'Purchase invoice not found';
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

  if exists (
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
      'Reverse goods receipts before cancelling invoice';
  end if;

  if exists (
    select 1
    from public.supplier_payment_allocations a
    join public.supplier_payments p
      on p.id = a.payment_id
    where a.purchase_invoice_id = target_invoice
      and p.status = 'posted'
      and a.amount > 0
  ) then
    raise exception
      'Reverse allocated supplier payments before cancelling invoice';
  end if;

  update public.purchase_invoices
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    cancellation_reason =
      trim(target_reason)
  where id = target_invoice;

  for v_order in
    select distinct soi.order_id
    from public.purchase_invoice_item_sources src
    join public.purchase_invoice_items pii
      on pii.id = src.purchase_invoice_item_id
    join public.sales_order_items soi
      on soi.id = src.sales_order_item_id
    where pii.invoice_id = target_invoice
  loop
    perform public.refresh_sales_order_purchase_status(v_order);
  end loop;
end;
$$;



-- =========================================================
-- SALES INVOICES / CUSTOMER PAYMENTS
-- =========================================================

create table public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  order_id uuid not null references public.sales_orders(id) on delete restrict,
  invoice_number text not null,
  status text not null default 'posted'
    check(status in ('posted','cancelled')),
  payment_status text not null default 'unpaid'
    check(payment_status in ('unpaid','partial','paid')),
  currency text not null default 'USD',
  invoice_date date not null default current_date,
  due_date date,
  subtotal numeric(14,2) not null default 0 check(subtotal >= 0),
  discount_total numeric(14,2) not null default 0 check(discount_total >= 0),
  total numeric(14,2) not null default 0 check(total >= 0),
  paid_total numeric(14,2) not null default 0 check(paid_total >= 0),
  balance_due numeric(14,2) not null default 0 check(balance_due >= 0),
  notes text,
  posted_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, invoice_number),
  check(due_date is null or due_date >= invoice_date)
);

create index sales_invoices_order_idx
on public.sales_invoices(order_id, created_at desc);

create index sales_invoices_company_date_idx
on public.sales_invoices(company_id, invoice_date desc, created_at desc);

create index sales_invoices_trader_date_idx
on public.sales_invoices(trader_id, invoice_date desc, created_at desc);

create index sales_invoices_due_idx
on public.sales_invoices(company_id, due_date)
where status = 'posted'
  and payment_status <> 'paid';

create trigger sales_invoices_updated_at
before update on public.sales_invoices
for each row execute function public.set_updated_at();

create table public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  sales_order_item_id uuid references public.sales_order_items(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  description text not null,
  unit text,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_price numeric(14,2) not null check(unit_price >= 0),
  line_total numeric(14,2) not null check(line_total >= 0),
  created_at timestamptz not null default now()
);

create index sales_invoice_items_invoice_idx
on public.sales_invoice_items(invoice_id);

create index sales_invoice_items_order_item_idx
on public.sales_invoice_items(sales_order_item_id)
where sales_order_item_id is not null;

create index sales_invoice_items_product_idx
on public.sales_invoice_items(company_id, product_id);

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  payment_number text not null,
  status text not null default 'posted'
    check(status in ('posted','reversed')),
  payment_date date not null default current_date,
  amount numeric(14,2) not null check(amount > 0),
  allocated_total numeric(14,2) not null default 0
    check(allocated_total >= 0 and allocated_total <= amount),
  unallocated_total numeric(14,2) not null default 0
    check(unallocated_total >= 0 and unallocated_total <= amount),
  payment_method text not null default 'cash'
    check(payment_method in ('cash','bank','card','check','other')),
  reference_number text,
  notes text,
  reversed_at timestamptz,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  created_by uuid default auth.uid()
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, payment_number),
  check(allocated_total + unallocated_total = amount)
);

create index customer_payments_company_date_idx
on public.customer_payments(company_id, payment_date desc, created_at desc);

create index customer_payments_trader_date_idx
on public.customer_payments(trader_id, payment_date desc, created_at desc);

create trigger customer_payments_updated_at
before update on public.customer_payments
for each row execute function public.set_updated_at();

create table public.customer_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete restrict,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  amount numeric(14,2) not null check(amount > 0),
  created_at timestamptz not null default now(),
  unique(payment_id, sales_invoice_id)
);

create index customer_payment_allocations_invoice_idx
on public.customer_payment_allocations(sales_invoice_id);

create index customer_payment_allocations_payment_idx
on public.customer_payment_allocations(payment_id);

alter table public.cash_transactions
add constraint cash_transactions_customer_payment_fk
foreign key (customer_payment_id)
references public.customer_payments(id)
on delete set null;

create index cash_transactions_customer_payment_idx
on public.cash_transactions(customer_payment_id)
where customer_payment_id is not null;

create unique index cash_transactions_customer_payment_type_unique
on public.cash_transactions(customer_payment_id, type)
where customer_payment_id is not null
  and type in ('sale_receipt','adjustment_out');


create or replace function public.next_sales_invoice_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.next_customer_payment_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.refresh_customer_payment_totals(
  target_payment uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(14,2);
  v_allocated numeric(14,2);
begin

  select amount
  into v_amount
  from public.customer_payments
  where id = target_payment;


  if v_amount is null then
    return;
  end if;


  select coalesce(sum(amount),0)
  into v_allocated
  from public.customer_payment_allocations
  where payment_id = target_payment;


  update public.customer_payments
  set
    allocated_total =
      round(v_allocated,2),

    unallocated_total =
      round(
        greatest(
          v_amount - v_allocated,
          0
        ),
        2
      )

  where id = target_payment;

end;
$$;

create or replace function public.recalc_sales_invoice_payment(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric(14,2);
  v_paid numeric(14,2);
  v_order uuid;
  v_status text;
  v_payment_status text;
begin

  select
    total,
    order_id,
    status

  into
    v_total,
    v_order,
    v_status

  from public.sales_invoices
  where id = target_invoice;


  if v_total is null then
    return;
  end if;


  select coalesce(sum(a.amount),0)
  into v_paid

  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id = a.payment_id

  where a.sales_invoice_id =
    target_invoice

    and p.status = 'posted';


  v_paid :=
    least(
      round(v_paid,2),
      v_total
    );


  v_payment_status :=
    case
      when v_total = 0
        or v_paid >= v_total
        then 'paid'

      when v_paid > 0
        then 'partial'

      else 'unpaid'
    end;


  update public.sales_invoices
  set
    paid_total = v_paid,

    balance_due =
      round(
        greatest(
          v_total - v_paid,
          0
        ),
        2
      ),

    payment_status =
      v_payment_status

  where id = target_invoice;


  -- Payment status is independent from delivery/order status.
  if v_order is not null
     and v_status <> 'cancelled'
  then

    update public.sales_orders
    set
      payment_status =
        v_payment_status,

      paid_at =
        case
          when v_payment_status = 'paid'
            then coalesce(
              paid_at,
              now()
            )
          else null
        end

    where id = v_order;

  end if;

end;
$$;

create or replace function
public.customer_payment_allocation_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create trigger customer_payment_allocation_changed_trigger
after insert or update or delete
on public.customer_payment_allocations
for each row
execute function public.customer_payment_allocation_changed();


create or replace function
public.customer_payment_status_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create trigger customer_payment_status_changed_trigger
after update of status
on public.customer_payments
for each row
execute function public.customer_payment_status_changed();


create or replace function public.apply_customer_credit_to_invoice(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trader uuid;
  v_company uuid;
  v_balance numeric(14,2);

  v_payment record;
  v_apply numeric(14,2);
begin

  select
    trader_id,
    company_id,
    balance_due

  into
    v_trader,
    v_company,
    v_balance

  from public.sales_invoices
  where id = target_invoice
    and status = 'posted';


  if v_trader is null
     or coalesce(v_balance,0) <= 0
  then
    return;
  end if;


  for v_payment in

    select
      id,
      unallocated_total

    from public.customer_payments

    where company_id = v_company
      and trader_id = v_trader
      and status = 'posted'
      and unallocated_total > 0

    order by
      payment_date,
      created_at

  loop

    select balance_due
    into v_balance
    from public.sales_invoices
    where id = target_invoice
    for update;


    exit when
      coalesce(v_balance,0) <= 0;


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
        amount
      )
      values(
        v_company,
        v_payment.id,
        target_invoice,
        round(v_apply,2)
      )
      on conflict(
        payment_id,
        sales_invoice_id
      )
      do nothing;

    end if;

  end loop;

end;
$$;

create or replace function public.ensure_sales_invoice_for_order(
  target_company uuid,
  target_order uuid,
  target_invoice_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice uuid;

  v_trader uuid;
  v_subtotal numeric(14,2);
  v_discount numeric(14,2);
  v_total numeric(14,2);
  v_notes text;
  v_currency text;

  v_invoice_number text;
  v_date date;
begin

  select id
  into v_invoice
  from public.sales_invoices
  where company_id = target_company
    and order_id = target_order
    and status <> 'cancelled'
  limit 1;


  if v_invoice is not null then
    return v_invoice;
  end if;


  select
    o.trader_id,
    o.subtotal,
    o.discount_total,
    o.total,
    o.notes,
    coalesce(
      c.default_currency,
      'USD'
    )

  into
    v_trader,
    v_subtotal,
    v_discount,
    v_total,
    v_notes,
    v_currency

  from public.sales_orders o

  join public.companies c
    on c.id = o.company_id

  where o.id = target_order
    and o.company_id = target_company;


  if v_trader is null then
    raise exception 'Order not found';
  end if;


  v_date :=
    coalesce(
      target_invoice_date,
      current_date
    );


  v_invoice_number :=
    public.next_sales_invoice_number(
      target_company,
      v_date
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
      when coalesce(v_total,0) = 0
        then 'paid'
      else 'unpaid'
    end,

    v_currency,
    v_date,
    v_date,

    round(
      coalesce(v_subtotal,0),
      2
    ),

    round(
      coalesce(v_discount,0),
      2
    ),

    round(
      coalesce(v_total,0),
      2
    ),

    0,

    round(
      coalesce(v_total,0),
      2
    ),

    v_notes,
    now()
  )
  returning id
  into v_invoice;


  insert into public.sales_invoice_items(
    company_id,
    invoice_id,
    sales_order_item_id,
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
    soi.id,
    soi.product_id,
    p.name,
    p.unit,
    soi.quantity,
    soi.sale_unit_price,

    round(
      soi.quantity *
      soi.sale_unit_price,
      2
    )

  from public.sales_order_items soi

  join public.products p
    on p.id = soi.product_id

  where soi.order_id =
    target_order;


  perform
    public.apply_customer_credit_to_invoice(
      v_invoice
    );


  perform
    public.recalc_sales_invoice_payment(
      v_invoice
    );


  return v_invoice;

end;
$$;

create or replace function public.create_sales_invoice_for_order(
  target_company uuid,
  target_order uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_date date;
begin

  if not public.has_permission(
    target_company,
    'sales_invoices.create'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    status,
    coalesce(
      delivered_at::date,
      current_date
    )

  into
    v_status,
    v_date

  from public.sales_orders

  where id = target_order
    and company_id = target_company;


  if v_status is null then
    raise exception 'Order not found';
  end if;


  if v_status <> 'delivered' then
    raise exception
      'Sales invoice can be created after delivery';
  end if;


  return
    public.ensure_sales_invoice_for_order(
      target_company,
      target_order,
      v_date
    );

end;
$$;

create or replace function public.start_order_delivery(
  target_company uuid,
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_delivery uuid;
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
  where id = target_order
    and company_id = target_company
  for update;

  if v_status is null then
    raise exception 'Order not found';
  end if;

  if v_status not in (
    'ready',
    'out_for_delivery'
  ) then
    raise exception 'Order is not ready for delivery';
  end if;

  select id
  into v_delivery
  from public.deliveries
  where company_id = target_company
    and order_id = target_order
    and status in ('pending','out_for_delivery')
  order by created_at desc
  limit 1
  for update;

  if v_delivery is null then
    insert into public.deliveries(
      company_id,
      order_id,
      status
    )
    values(
      target_company,
      target_order,
      'out_for_delivery'
    );
  else
    update public.deliveries
    set
      status = 'out_for_delivery',
      updated_at = now()
    where id = v_delivery;
  end if;

  update public.sales_orders
  set status = 'out_for_delivery'
  where id = target_order;

end;
$$;

create or replace function public.complete_order_delivery(
  target_company uuid,
  target_order uuid,
  target_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_now timestamptz;
  v_invoice uuid;
  v_delivery uuid;
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
  where id = target_order
    and company_id = target_company
  for update;

  if v_status is null then
    raise exception 'Order not found';
  end if;

  if v_status not in (
    'ready',
    'out_for_delivery',
    'delivered'
  ) then
    raise exception 'Order cannot be delivered from its current status';
  end if;

  v_now := now();

  select id
  into v_delivery
  from public.deliveries
  where company_id = target_company
    and order_id = target_order
    and status in ('pending','out_for_delivery')
  order by created_at desc
  limit 1
  for update;

  if v_delivery is null then
    insert into public.deliveries(
      company_id,
      order_id,
      status,
      delivered_at,
      notes
    )
    values(
      target_company,
      target_order,
      'delivered',
      v_now,
      nullif(trim(target_notes),'')
    )
    returning id into v_delivery;
  else
    update public.deliveries
    set
      status = 'delivered',
      delivered_at = coalesce(delivered_at, v_now),
      notes = coalesce(nullif(trim(target_notes),''), notes),
      updated_at = now()
    where id = v_delivery;
  end if;

  update public.sales_orders
  set
    status = 'delivered',
    delivered_at = coalesce(delivered_at, v_now)
  where id = target_order;

  -- Current UI posts a full-order invoice on completion.
  -- The schema itself allows multiple invoices per order for future partial invoicing.
  v_invoice := public.ensure_sales_invoice_for_order(
    target_company,
    target_order,
    v_now::date
  );

  return v_invoice;

end;
$$;

create or replace function public.record_customer_payment(
  target_company uuid,
  target_trader uuid,
  target_cashbox uuid,
  target_amount numeric,
  target_payment_date date,
  target_method text,
  target_reference text,
  target_notes text,
  allocations_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;
  v_method text;

  v_allocation jsonb;
  v_invoice uuid;
  v_alloc_amount numeric(14,2);

  v_balance numeric(14,2);
  v_invoice_status text;
  v_invoice_trader uuid;
  v_order uuid;

  v_allocated_sum numeric(14,2) := 0;

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
    raise exception 'Invalid payment amount';
  end if;


  if not exists (
    select 1
    from public.traders
    where id = target_trader
      and company_id = target_company
  ) then
    raise exception 'Invalid trader';
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
    raise exception 'Invalid payment method';
  end if;


  if target_payment_date is null then
    target_payment_date :=
      current_date;
  end if;


  if target_cashbox is not null then

    select id
    into v_cashbox
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true;

  else

    select id
    into v_cashbox
    from public.cashboxes
    where company_id = target_company
      and active = true
    order by created_at
    limit 1;

  end if;


  if v_cashbox is null then
    raise exception
      'No valid active cashbox';
  end if;


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
    notes
  )
  values(
    target_company,
    target_trader,
    v_cashbox,
    v_number,
    'posted',
    target_payment_date,
    round(target_amount,2),
    0,
    round(target_amount,2),
    v_method,
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


  for v_allocation in

    select value
    from jsonb_array_elements(
      coalesce(
        allocations_payload,
        '[]'::jsonb
      )
    )

  loop

    v_invoice :=
      nullif(
        v_allocation
          ->> 'sales_invoice_id',
        ''
      )::uuid;


    v_alloc_amount :=
      nullif(
        v_allocation
          ->> 'amount',
        ''
      )::numeric;


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
      order_id

    into
      v_balance,
      v_invoice_status,
      v_invoice_trader,
      v_order

    from public.sales_invoices

    where id = v_invoice
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
        'Cannot pay cancelled invoice';
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
    ) > v_balance
    then
      raise exception
        'Allocation exceeds invoice balance';
    end if;


    v_allocated_sum :=
      v_allocated_sum +
      round(
        v_alloc_amount,
        2
      );


    if v_allocated_sum >
       round(target_amount,2)
    then
      raise exception
        'Allocations exceed payment amount';
    end if;


    insert into public.customer_payment_allocations(
      company_id,
      payment_id,
      sales_invoice_id,
      amount
    )
    values(
      target_company,
      v_payment,
      v_invoice,
      round(
        v_alloc_amount,
        2
      )
    );


    v_allocation_count :=
      v_allocation_count + 1;


    if v_allocation_count = 1 then
      v_single_order :=
        v_order;
    else
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
    round(target_amount,2),

    case
      when v_allocation_count = 1
        then v_single_order
      else null
    end,

    target_trader,
    v_payment,

    'دفعة تاجر ' ||
      v_number ||
      case
        when nullif(
          trim(target_notes),
          ''
        ) is not null
        then
          ' - ' ||
          trim(target_notes)
        else ''
      end,

    target_payment_date::timestamptz
  );


  return v_payment;

end;
$$;

create or replace function public.reverse_customer_payment(
  target_company uuid,
  target_payment uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    'adjustment_out',
    v_amount,
    v_trader,
    target_payment,
    'عكس دفعة تاجر ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$$;

create or replace function public.cancel_sales_invoice(
  target_company uuid,
  target_invoice uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_order uuid;
begin

  if not public.has_permission(
    target_company,
    'sales_invoices.cancel'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    status,
    order_id

  into
    v_status,
    v_order

  from public.sales_invoices

  where id = target_invoice
    and company_id =
      target_company

  for update;


  if v_status is null then
    raise exception
      'Sales invoice not found';
  end if;


  if v_status = 'cancelled' then
    return;
  end if;


  if exists (
    select 1

    from public.customer_payment_allocations a

    join public.customer_payments p
      on p.id = a.payment_id

    where a.sales_invoice_id =
      target_invoice

      and p.status = 'posted'

      and a.amount > 0
  ) then
    raise exception
      'Reverse allocated customer payments before cancelling invoice';
  end if;


  update public.sales_invoices
  set
    status =
      'cancelled',

    cancelled_at =
      now(),

    cancelled_by =
      auth.uid(),

    cancellation_reason =
      coalesce(
        nullif(
          trim(target_reason),
          ''
        ),
        'Cancelled'
      )

  where id = target_invoice;


  update public.sales_orders
  set
    payment_status =
      'unpaid',

    paid_at =
      null

  where id = v_order;

end;
$$;

create or replace function public.save_company_role(
  target_company uuid,
  target_role uuid,
  role_name text,
  role_description text,
  permission_codes text[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role uuid;
  v_name text;
  v_is_owner boolean;
  v_is_protected boolean;
begin
  if not public.is_company_owner(target_company) then
    raise exception 'Not allowed';
  end if;

  v_name := nullif(trim(role_name), '');

  if v_name is null then
    raise exception 'Role name is required';
  end if;

  if exists (
    select 1
    from unnest(coalesce(permission_codes, '{}'::text[])) as requested(code)
    left join public.permissions p
      on p.code = requested.code
    where p.code is null
  ) then
    raise exception 'Invalid permission';
  end if;

  if target_role is null then
    if exists (
      select 1
      from public.company_roles r
      where r.company_id = target_company
        and lower(r.name) = lower(v_name)
    ) then
      raise exception 'Role name already exists';
    end if;

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
      v_name,
      nullif(trim(role_description), ''),
      false,
      false,
      true,
      auth.uid()
    )
    returning id into v_role;
  else
    select
      r.id,
      r.is_owner,
      r.is_protected
    into
      v_role,
      v_is_owner,
      v_is_protected
    from public.company_roles r
    where r.id = target_role
      and r.company_id = target_company
    for update;

    if v_role is null then
      raise exception 'Role not found';
    end if;

    if v_is_owner or v_is_protected then
      raise exception 'Protected role cannot be edited';
    end if;

    if exists (
      select 1
      from public.company_roles r
      where r.company_id = target_company
        and r.id <> v_role
        and lower(r.name) = lower(v_name)
    ) then
      raise exception 'Role name already exists';
    end if;

    update public.company_roles
    set
      name = v_name,
      description = nullif(trim(role_description), ''),
      updated_at = now()
    where id = v_role;
  end if;

  delete from public.role_permissions
  where role_id = v_role;

  insert into public.role_permissions(
    role_id,
    permission_code
  )
  select
    v_role,
    requested.code
  from (
    select distinct code
    from unnest(
      coalesce(permission_codes, '{}'::text[])
    ) as x(code)
  ) as requested
  join public.permissions p
    on p.code = requested.code
  on conflict do nothing;

  return v_role;
end;
$$;

create or replace function public.delete_company_role(
  target_company uuid,
  target_role uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_owner boolean;
  v_is_protected boolean;
begin
  if not public.is_company_owner(target_company) then
    raise exception 'Not allowed';
  end if;

  select
    r.is_owner,
    r.is_protected
  into
    v_is_owner,
    v_is_protected
  from public.company_roles r
  where r.id = target_role
    and r.company_id = target_company
  for update;

  if not found then
    raise exception 'Role not found';
  end if;

  if v_is_owner or v_is_protected then
    raise exception 'Protected role cannot be deleted';
  end if;

  if exists (
    select 1
    from public.company_members cm
    where cm.company_id = target_company
      and cm.role_id = target_role
  ) then
    raise exception 'Role is assigned to employees';
  end if;

  delete from public.company_roles
  where id = target_role
    and company_id = target_company;
end;
$$;

create or replace function public.assign_company_member_role(
  target_company uuid,
  target_user uuid,
  target_role uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_role_owner boolean;
  v_role_active boolean;
begin
  if not public.is_company_owner(target_company) then
    raise exception 'Not allowed';
  end if;

  select c.owner_user_id
  into v_owner
  from public.companies c
  where c.id = target_company;

  if v_owner is null then
    raise exception 'Company not found';
  end if;

  select
    r.is_owner,
    r.active
  into
    v_role_owner,
    v_role_active
  from public.company_roles r
  where r.id = target_role
    and r.company_id = target_company;

  if not found then
    raise exception 'Role not found';
  end if;

  if not v_role_active then
    raise exception 'Role is inactive';
  end if;

  if target_user = v_owner and not v_role_owner then
    raise exception 'Company owner must keep owner role';
  end if;

  if target_user <> v_owner and v_role_owner then
    raise exception 'Owner role cannot be assigned to an employee';
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = target_user
  ) then
    raise exception 'User not found';
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
  on conflict (company_id, user_id)
  do update set
    role_id = excluded.role_id;
end;
$$;

create or replace function public.remove_company_member(
  target_company uuid,
  target_user uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  if not public.is_company_owner(target_company) then
    raise exception 'Not allowed';
  end if;

  select c.owner_user_id
  into v_owner
  from public.companies c
  where c.id = target_company;

  if v_owner is null then
    raise exception 'Company not found';
  end if;

  if target_user = v_owner then
    raise exception 'Company owner cannot be removed';
  end if;

  delete from public.company_members
  where company_id = target_company
    and user_id = target_user;
end;
$$;

create or replace function public.set_supplier_active(
  target_company uuid,
  target_supplier uuid,
  target_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission(target_company, 'suppliers.archive') then
    raise exception 'Not allowed';
  end if;

  update public.suppliers
  set
    active = target_active,
    updated_at = now()
  where id = target_supplier
    and company_id = target_company;

  if not found then
    raise exception 'Supplier not found';
  end if;
end;
$$;

create or replace function public.set_product_active(
  target_company uuid,
  target_product uuid,
  target_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission(target_company, 'products.archive') then
    raise exception 'Not allowed';
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
$$;

create or replace function public.save_product_with_supplier_prices(
  target_company uuid,
  target_product uuid,
  product_name text,
  product_sku text,
  product_brand text,
  target_category uuid,
  product_unit text,
  product_sale_price numeric,
  product_minimum_sale_price numeric,
  product_image_url text,
  product_active boolean,
  supplier_prices_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
      coalesce(nullif(trim(product_unit), ''), 'piece'),
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
      unit = coalesce(nullif(trim(product_unit), ''), 'piece'),
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
$$;

create or replace function public.record_expense(
  target_company uuid,
  expense_category text,
  expense_amount numeric,
  expense_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cashbox uuid;
  v_expense uuid;
begin
  if not public.has_permission(
    target_company,
    'finance.expenses_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if expense_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if nullif(trim(expense_category),'') is null then
    raise exception 'Category required';
  end if;

  select id
  into v_cashbox
  from public.cashboxes
  where company_id = target_company
    and active = true
  order by created_at
  limit 1;

  if v_cashbox is null then
    raise exception 'No active cashbox';
  end if;

  insert into public.expenses(
    company_id,
    cashbox_id,
    category,
    amount,
    notes
  )
  values(
    target_company,
    v_cashbox,
    trim(expense_category),
    expense_amount,
    expense_notes
  )
  returning id into v_expense;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    expense_id,
    notes
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'expense',
    expense_amount,
    v_expense,
    expense_notes
  );

  return v_expense;
end;
$$;

create or replace function public.record_cash_movement(
  target_company uuid,
  movement_type text,
  movement_amount numeric,
  movement_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cashbox uuid;
  v_id uuid;
  v_direction text;
begin
  if not public.has_permission(
    target_company,
    'finance.cashbox_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if movement_amount <= 0 then
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
      )
      then 'in'
      else 'out'
    end;

  select id
  into v_cashbox
  from public.cashboxes
  where company_id = target_company
    and active = true
  order by created_at
  limit 1;

  if v_cashbox is null then
    raise exception 'No active cashbox';
  end if;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    notes
  )
  values(
    target_company,
    v_cashbox,
    v_direction,
    movement_type,
    movement_amount,
    movement_notes
  )
  returning id into v_id;

  return v_id;
end;
$$;


-- =========================================================
-- AUDIT
-- =========================================================

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_company_created_idx
on public.audit_logs(company_id, created_at desc);


create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;


-- Core audit triggers.
create trigger audit_company_roles
after insert or update or delete on public.company_roles
for each row execute function public.write_audit_log();

create trigger audit_company_members
after insert or update or delete on public.company_members
for each row execute function public.write_audit_log();

create trigger audit_traders
after insert or update or delete on public.traders
for each row execute function public.write_audit_log();

create trigger audit_suppliers
after insert or update or delete on public.suppliers
for each row execute function public.write_audit_log();

create trigger audit_products
after insert or update or delete on public.products
for each row execute function public.write_audit_log();

create trigger audit_sales_orders
after insert or update or delete on public.sales_orders
for each row execute function public.write_audit_log();


create trigger audit_deliveries
after insert or update or delete on public.deliveries
for each row execute function public.write_audit_log();

create trigger audit_expenses
after insert or update or delete on public.expenses
for each row execute function public.write_audit_log();

create trigger audit_cash_transactions
after insert or update or delete on public.cash_transactions
for each row execute function public.write_audit_log();



create trigger audit_purchase_invoices
after insert or update or delete on public.purchase_invoices
for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_items
after insert or update or delete on public.purchase_invoice_items
for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_sources
after insert or update or delete on public.purchase_invoice_item_sources
for each row execute function public.write_audit_log();

create trigger audit_supplier_payments
after insert or update or delete on public.supplier_payments
for each row execute function public.write_audit_log();

create trigger audit_supplier_payment_allocations
after insert or update or delete on public.supplier_payment_allocations
for each row execute function public.write_audit_log();

create trigger audit_sales_invoices
after insert or update or delete on public.sales_invoices
for each row execute function public.write_audit_log();

create trigger audit_sales_invoice_items
after insert or update or delete on public.sales_invoice_items
for each row execute function public.write_audit_log();

create trigger audit_customer_payments
after insert or update or delete on public.customer_payments
for each row execute function public.write_audit_log();

create trigger audit_customer_payment_allocations
after insert or update or delete on public.customer_payment_allocations
for each row execute function public.write_audit_log();



-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.permissions enable row level security;
alter table public.company_roles enable row level security;
alter table public.company_members enable row level security;
alter table public.role_permissions enable row level security;

alter table public.traders enable row level security;
alter table public.trader_visits enable row level security;
alter table public.suppliers enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.supplier_prices enable row level security;
alter table public.supplier_price_history enable row level security;

alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.deliveries enable row level security;

alter table public.cashboxes enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_transactions enable row level security;


alter table public.document_sequences enable row level security;

alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_items enable row level security;
alter table public.purchase_invoice_item_sources enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;

alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;
alter table public.customer_payments enable row level security;
alter table public.customer_payment_allocations enable row level security;

alter table public.audit_logs enable row level security;

-- Profile: self only.
create policy profiles_read
on public.profiles
for select to authenticated
using (id = auth.uid());

create policy profiles_insert
on public.profiles
for insert to authenticated
with check (id = auth.uid());

create policy profiles_update
on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Global permission catalog.
create policy permissions_read
on public.permissions
for select to authenticated
using (true);

-- Companies.
create policy companies_read
on public.companies
for select to authenticated
using (
  owner_user_id = auth.uid()
  or public.is_company_member(id)
);

create policy companies_create
on public.companies
for insert to authenticated
with check (owner_user_id = auth.uid());

create policy companies_update
on public.companies
for update to authenticated
using (public.has_permission(id,'settings.manage_company'))
with check (public.has_permission(id,'settings.manage_company'));

-- Members / roles.
create policy company_members_read
on public.company_members
for select to authenticated
using (
  user_id = auth.uid()
  or public.has_permission(company_id,'team.view')
);

create policy company_members_create
on public.company_members
for insert to authenticated
with check (public.has_permission(company_id,'team.manage_members'));

create policy company_members_update
on public.company_members
for update to authenticated
using (public.has_permission(company_id,'team.manage_members'))
with check (public.has_permission(company_id,'team.manage_members'));

create policy company_members_delete
on public.company_members
for delete to authenticated
using (public.has_permission(company_id,'team.manage_members'));

create policy company_roles_read
on public.company_roles
for select to authenticated
using (public.is_company_member(company_id));

create policy company_roles_owner_write
on public.company_roles
for all to authenticated
using (public.is_company_owner(company_id))
with check (public.is_company_owner(company_id));

create policy role_permissions_read
on public.role_permissions
for select to authenticated
using (
  exists(
    select 1
    from public.company_roles r
    where r.id = role_id
      and public.is_company_member(r.company_id)
  )
);

create policy role_permissions_owner_write
on public.role_permissions
for all to authenticated
using (
  exists(
    select 1
    from public.company_roles r
    where r.id = role_id
      and public.is_company_owner(r.company_id)
  )
)
with check (
  exists(
    select 1
    from public.company_roles r
    where r.id = role_id
      and public.is_company_owner(r.company_id)
  )
);

-- Traders.
create policy traders_read
on public.traders
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'traders.view','orders.view','orders.create','map.view',
      'reports.sales','reports.profit','reports.team'
    ]::text[]
  )
);

create policy traders_create
on public.traders
for insert to authenticated
with check (public.has_permission(company_id,'traders.create'));

create policy traders_update
on public.traders
for update to authenticated
using (
  public.has_permission(company_id,'traders.update')
)
with check (
  public.has_permission(company_id,'traders.update')
);

-- Archiving is a controlled status change, never a physical DELETE.
revoke delete on public.traders from authenticated;

create or replace function public.archive_trader(
  target_company uuid,
  target_trader uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $
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
$;

revoke all
on function public.archive_trader(uuid,uuid)
from public;

grant execute
on function public.archive_trader(uuid,uuid)
to authenticated;
-- Visits.
create policy trader_visits_read
on public.trader_visits
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array['visits.view','reports.team']::text[]
  )
);

create policy trader_visits_create
on public.trader_visits
for insert to authenticated
with check (public.has_permission(company_id,'visits.create'));

create policy trader_visits_update
on public.trader_visits
for update to authenticated
using (public.has_permission(company_id,'visits.update'))
with check (public.has_permission(company_id,'visits.update'));

create policy trader_visits_delete
on public.trader_visits
for delete to authenticated
using (public.has_permission(company_id,'visits.update'));

-- Suppliers.
create policy suppliers_read
on public.suppliers
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'suppliers.view','purchases.view','products.view',
      'reports.finance','reports.profit'
    ]::text[]
  )
);

create policy suppliers_create
on public.suppliers
for insert to authenticated
with check (public.has_permission(company_id,'suppliers.create'));

create policy suppliers_update
on public.suppliers
for update to authenticated
using (
  public.has_permission(
    company_id,
    'suppliers.update'
  )
)
with check (
  public.has_permission(
    company_id,
    'suppliers.update'
  )
);
-- Categories.
create policy categories_read
on public.categories
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array['products.view','orders.view','purchases.view']::text[]
  )
);

create policy categories_create
on public.categories
for insert to authenticated
with check (public.has_permission(company_id,'products.create'));

create policy categories_update
on public.categories
for update to authenticated
using (public.has_permission(company_id,'products.update'))
with check (public.has_permission(company_id,'products.update'));

create policy categories_delete
on public.categories
for delete to authenticated
using (public.has_permission(company_id,'products.archive'));

-- Products.
create policy products_read
on public.products
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'products.view','orders.view','orders.create','purchases.view','inventory.view',
      'reports.sales','reports.profit'
    ]::text[]
  )
);

create policy products_create
on public.products
for insert to authenticated
with check (public.has_permission(company_id,'products.create'));

create policy products_update
on public.products
for update to authenticated
using (
  public.has_permission(
    company_id,
    'products.update'
  )
)
with check (
  public.has_permission(
    company_id,
    'products.update'
  )
);
-- Supplier prices: cost is intentionally hidden from plain products/orders viewers.
create policy supplier_prices_read
on public.supplier_prices
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'products.view_cost',
      'products.update',
      'purchases.view',
      'purchases.create',
      'purchases.update',
      'purchase_invoices.view',
      'purchase_invoices.create',
      'suppliers.view_finance',
      'reports.profit',
      'reports.finance'
    ]::text[]
  )
);

create policy supplier_prices_create
on public.supplier_prices
for insert to authenticated
with check (public.has_permission(company_id,'products.update'));

create policy supplier_prices_update
on public.supplier_prices
for update to authenticated
using (public.has_permission(company_id,'products.update'))
with check (public.has_permission(company_id,'products.update'));

create policy supplier_price_history_select
on public.supplier_price_history
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'products.view_cost',
      'purchases.view',
      'suppliers.view_finance'
    ]::text[]
  )
);

-- Orders.
create policy sales_orders_read
on public.sales_orders
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'orders.view','deliveries.view','payments.sales_view',
      'reports.sales','reports.profit','reports.finance'
    ]::text[]
  )
);

create policy sales_orders_create
on public.sales_orders
for insert to authenticated
with check (public.has_permission(company_id,'orders.create'));

create policy sales_orders_update
on public.sales_orders
for update to authenticated
using (
  public.has_permission(
    company_id,
    'orders.update'
  )
)
with check (
  public.has_permission(
    company_id,
    'orders.update'
  )
);
create policy sales_order_items_read
on public.sales_order_items
for select to authenticated
using (public.can_access_order(order_id));

-- Deliveries.
-- Operational state changes are RPC-only.
create policy deliveries_read
on public.deliveries
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'deliveries.view',
      'deliveries.update'
    ]::text[]
  )
);


-- Finance.
create policy cashboxes_read
on public.cashboxes
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'finance.cashbox_view',
      'finance.accounts_view',
      'payments.sales_view',
      'payments.sales_create',
      'payments.supplier_view',
      'payments.supplier_create',
      'reports.finance'
    ]::text[]
  )
);

create policy cashboxes_write
on public.cashboxes
for all to authenticated
using (public.has_permission(company_id,'finance.cashbox_write'))
with check (public.has_permission(company_id,'finance.cashbox_write'));

create policy expenses_read
on public.expenses
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'finance.expenses_view','reports.finance','reports.profit'
    ]::text[]
  )
);

create policy expenses_write
on public.expenses
for all to authenticated
using (public.has_permission(company_id,'finance.expenses_write'))
with check (public.has_permission(company_id,'finance.expenses_write'));

create policy cash_transactions_read
on public.cash_transactions
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'finance.cashbox_view','finance.accounts_view',
      'payments.sales_view','payments.sales_create',
      'payments.supplier_view','payments.supplier_create',
      'reports.finance'
    ]::text[]
  )
);

create policy cash_transactions_write
on public.cash_transactions
for all to authenticated
using (public.has_permission(company_id,'finance.cashbox_write'))
with check (public.has_permission(company_id,'finance.cashbox_write'));

-- Purchase invoices.
create policy purchase_invoices_read
on public.purchase_invoices
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'suppliers.view_finance',
      'reports.finance',
      'reports.profit'
    ]::text[]
  )
);

create policy purchase_invoice_items_read
on public.purchase_invoice_items
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'suppliers.view_finance',
      'reports.finance',
      'reports.profit'
    ]::text[]
  )
);

create policy purchase_invoice_sources_read
on public.purchase_invoice_item_sources
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'purchase_invoices.view',
      'purchases.view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  )
);

-- Supplier payments.
create policy supplier_payments_read
on public.supplier_payments
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'payments.supplier_view',
      'suppliers.view_finance',
      'finance.cashbox_view',
      'finance.accounts_view',
      'reports.finance'
    ]::text[]
  )
);

create policy supplier_payment_allocations_read
on public.supplier_payment_allocations
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'payments.supplier_view',
      'suppliers.view_finance',
      'reports.finance'
    ]::text[]
  )
);

-- Sales invoices. payments.sales_create can read the invoice it is collecting.
create policy sales_invoices_read
on public.sales_invoices
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'sales_invoices.view',
      'payments.sales_view',
      'payments.sales_create',
      'traders.view_balance',
      'reports.sales',
      'reports.finance',
      'reports.profit'
    ]::text[]
  )
);

create policy sales_invoice_items_read
on public.sales_invoice_items
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'sales_invoices.view',
      'payments.sales_view',
      'payments.sales_create',
      'traders.view_balance',
      'reports.sales',
      'reports.profit'
    ]::text[]
  )
);

create policy customer_payments_read
on public.customer_payments
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'payments.sales_view',
      'traders.view_balance',
      'finance.cashbox_view',
      'finance.accounts_view',
      'reports.finance'
    ]::text[]
  )
);

create policy customer_payment_allocations_read
on public.customer_payment_allocations
for select to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'payments.sales_view',
      'traders.view_balance',
      'reports.finance'
    ]::text[]
  )
);

-- Audit.
create policy audit_logs_read
on public.audit_logs
for select to authenticated
using (public.has_permission(company_id,'audit.view'));



-- =========================================================
-- PRIVILEGES
-- =========================================================

grant select,insert,update on public.profiles to authenticated;

grant select,insert,update on public.companies to authenticated;
grant select on public.permissions to authenticated;
grant select,insert,update,delete on public.company_roles to authenticated;
grant select,insert,update,delete on public.company_members to authenticated;
grant select,insert,update,delete on public.role_permissions to authenticated;

grant select,insert,update,delete on public.traders to authenticated;
grant select,insert,update,delete on public.trader_visits to authenticated;
grant select,insert,update on public.suppliers to authenticated;
grant select,insert,update,delete on public.categories to authenticated;
grant select,insert,update on public.products to authenticated;
grant select,insert,update on public.supplier_prices to authenticated;
grant select on public.supplier_price_history to authenticated;

grant select on public.sales_orders to authenticated;
grant select on public.sales_order_items to authenticated;
revoke insert,update,delete
on public.deliveries
from authenticated;

grant select
on public.deliveries
to authenticated;

grant select,insert,update,delete on public.cashboxes to authenticated;
grant select,insert,update,delete on public.expenses to authenticated;
grant select,insert,update,delete on public.cash_transactions to authenticated;


revoke all on public.document_sequences from public, authenticated;

grant select on public.purchase_invoices,
                public.purchase_invoice_items,
                public.purchase_invoice_item_sources,
                public.supplier_payments,
                public.supplier_payment_allocations,
                public.sales_invoices,
                public.sales_invoice_items,
                public.customer_payments,
                public.customer_payment_allocations,
                public.audit_logs
to authenticated;

revoke insert,update,delete
on public.purchase_invoices,
   public.purchase_invoice_items,
   public.purchase_invoice_item_sources,
   public.supplier_payments,
   public.supplier_payment_allocations,
   public.sales_invoices,
   public.sales_invoice_items,
   public.customer_payments,
   public.customer_payment_allocations,
   public.audit_logs
from authenticated;

-- Permission helpers used by RLS.
revoke all on function public.is_company_member(uuid) from public;
revoke all on function public.is_company_owner(uuid) from public;
revoke all on function public.has_permission(uuid,text) from public;
revoke all on function public.has_any_permission(uuid,text[]) from public;
revoke all on function public.can_access_order(uuid) from public;
revoke all on function public.can_write_order(uuid) from public;

grant execute on function public.is_company_member(uuid) to authenticated;
grant execute on function public.is_company_owner(uuid) to authenticated;
grant execute on function public.has_permission(uuid,text) to authenticated;
grant execute on function public.has_any_permission(uuid,text[]) to authenticated;
grant execute on function public.can_access_order(uuid) to authenticated;
grant execute on function public.can_write_order(uuid) to authenticated;

-- Team management.
revoke all on function public.save_company_role(uuid,uuid,text,text,text[]) from public;
revoke all on function public.delete_company_role(uuid,uuid) from public;
revoke all on function public.assign_company_member_role(uuid,uuid,uuid) from public;
revoke all on function public.remove_company_member(uuid,uuid) from public;

grant execute on function public.save_company_role(uuid,uuid,text,text,text[]) to authenticated;
grant execute on function public.delete_company_role(uuid,uuid) to authenticated;
grant execute on function public.assign_company_member_role(uuid,uuid,uuid) to authenticated;
grant execute on function public.remove_company_member(uuid,uuid) to authenticated;

-- Catalog.
revoke all on function public.set_supplier_active(uuid,uuid,boolean) from public;
revoke all on function public.set_product_active(uuid,uuid,boolean) from public;
revoke all on function public.save_product_with_supplier_prices(
  uuid,uuid,text,text,text,uuid,text,numeric,numeric,text,boolean,jsonb
) from public;

grant execute on function public.set_supplier_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.set_product_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.save_product_with_supplier_prices(
  uuid,uuid,text,text,text,uuid,text,numeric,numeric,text,boolean,jsonb
) to authenticated;

-- Purchase workflow.
revoke all on function public.create_purchase_invoice(
  uuid,uuid,text,date,date,text,jsonb
) from public;
revoke all on function public.cancel_purchase_invoice(uuid,uuid,text) from public;
revoke all on function public.get_purchase_needs(uuid) from public;

grant execute on function public.create_purchase_invoice(
  uuid,uuid,text,date,date,text,jsonb
) to authenticated;
grant execute on function public.cancel_purchase_invoice(uuid,uuid,text) to authenticated;
grant execute on function public.get_purchase_needs(uuid) to authenticated;

-- Supplier payments.
revoke all on function public.record_supplier_payment(
  uuid,uuid,uuid,numeric,date,text,text,text,jsonb
) from public;
revoke all on function public.reverse_supplier_payment(uuid,uuid,text) from public;

grant execute on function public.record_supplier_payment(
  uuid,uuid,uuid,numeric,date,text,text,text,jsonb
) to authenticated;
grant execute on function public.reverse_supplier_payment(uuid,uuid,text) to authenticated;

-- Sales invoices / collections.
revoke all on function public.create_sales_invoice_for_order(uuid,uuid) from public;
revoke all on function public.start_order_delivery(uuid,uuid) from public;
revoke all on function public.complete_order_delivery(uuid,uuid,text) from public;
revoke all on function public.record_customer_payment(
  uuid,uuid,uuid,numeric,date,text,text,text,jsonb
) from public;
revoke all on function public.reverse_customer_payment(uuid,uuid,text) from public;
revoke all on function public.cancel_sales_invoice(uuid,uuid,text) from public;

grant execute on function public.create_sales_invoice_for_order(uuid,uuid) to authenticated;
grant execute on function public.start_order_delivery(uuid,uuid) to authenticated;
grant execute on function public.complete_order_delivery(uuid,uuid,text) to authenticated;
grant execute on function public.record_customer_payment(
  uuid,uuid,uuid,numeric,date,text,text,text,jsonb
) to authenticated;
grant execute on function public.reverse_customer_payment(uuid,uuid,text) to authenticated;
grant execute on function public.cancel_sales_invoice(uuid,uuid,text) to authenticated;

-- Finance.
revoke all on function public.record_expense(uuid,text,numeric,text) from public;
revoke all on function public.record_cash_movement(uuid,text,numeric,text) from public;

grant execute on function public.record_expense(uuid,text,numeric,text) to authenticated;
grant execute on function public.record_cash_movement(uuid,text,numeric,text) to authenticated;

-- Internal/security-definer helpers are not directly callable by app users.
revoke all on function public.next_purchase_invoice_number(uuid,date) from public, authenticated;
revoke all on function public.next_supplier_payment_number(uuid,date) from public, authenticated;
revoke all on function public.next_sales_invoice_number(uuid,date) from public, authenticated;
revoke all on function public.next_customer_payment_number(uuid,date) from public, authenticated;

revoke all on function public.recalc_sales_order(uuid) from public, authenticated;
revoke all on function public.refresh_sales_order_purchase_status(uuid) from public, authenticated;
revoke all on function public.refresh_supplier_payment_totals(uuid) from public, authenticated;
revoke all on function public.recalc_purchase_invoice_payment(uuid) from public, authenticated;
revoke all on function public.refresh_customer_payment_totals(uuid) from public, authenticated;
revoke all on function public.recalc_sales_invoice_payment(uuid) from public, authenticated;
revoke all on function public.apply_customer_credit_to_invoice(uuid) from public, authenticated;
revoke all on function public.ensure_sales_invoice_for_order(uuid,uuid,date) from public, authenticated;

revoke all on function public.set_updated_at() from public;
revoke all on function public.prevent_duplicate_trader_contact() from public;
revoke all on function public.capture_supplier_price_history() from public;
revoke all on function public.set_sales_order_item_line_total() from public;
revoke all on function public.sales_order_items_recalc_after_trigger() from public;
revoke all on function public.supplier_payment_allocation_changed() from public;
revoke all on function public.supplier_payment_status_changed() from public;
revoke all on function public.customer_payment_allocation_changed() from public;
revoke all on function public.customer_payment_status_changed() from public;
revoke all on function public.handle_company_access_setup() from public;
revoke all on function public.handle_company_default_cashbox() from public;
revoke all on function public.protect_owner_role() from public;
revoke all on function public.protect_owner_membership() from public;
revoke all on function public.write_audit_log() from public;

commit;
