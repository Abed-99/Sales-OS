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
  reorder_level numeric(14,3),
  -- كم قطعة بالكرتونة (أو العلبة). المخزون دايمًا بالوحدة الأساسية.
  pack_size numeric(14,3) check (pack_size is null or pack_size > 1),
  pack_unit text,
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
  price_level_id uuid,
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
  purchase_price numeric(18,4) not null,
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
  purchase_price numeric(18,4) not null,
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

-- مستويات الأسعار (جملة، نص جملة، مفرق...). كل زبون إلو مستوى، وكل صنف إلو سعر بكل مستوى.
create table public.price_levels (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  sort_order integer default 0 not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  constraint price_levels_company_name_key unique (company_id, name)
);

create table public.product_level_prices (
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  price_level_id uuid not null references public.price_levels(id) on delete cascade,
  price numeric(14,2) not null check (price >= 0),
  updated_at timestamp with time zone default now() not null,
  primary key (product_id, price_level_id)
);

create index product_level_prices_level_idx on public.product_level_prices using btree (price_level_id);

alter table public.traders
  add constraint traders_price_level_fk foreign key (price_level_id) references public.price_levels(id) on delete set null;

alter table public.price_levels enable row level security;
alter table public.product_level_prices enable row level security;

create policy price_levels_read on public.price_levels
  for select to authenticated
  using (public.is_company_member(company_id));
create policy price_levels_write on public.price_levels
  for all to authenticated
  using (public.has_permission(company_id, 'products.update'::text))
  with check (public.has_permission(company_id, 'products.update'::text));
create policy product_level_prices_read on public.product_level_prices
  for select to authenticated
  using (public.has_any_permission(company_id, array['products.view'::text, 'orders.view'::text, 'orders.create'::text, 'purchases.view'::text]));

-- سعر الصنف لزبون معيّن: سعر مستواه إذا موجود، وإلا سعر البيع العادي.
create or replace function public.get_trader_product_prices(target_company uuid, target_trader uuid, target_products uuid[])
 RETURNS TABLE(product_id uuid, price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, coalesce(lp.price, p.sale_price)
  from public.products p
  left join public.traders t on t.id = target_trader and t.company_id = target_company
  left join public.product_level_prices lp on lp.product_id = p.id and lp.price_level_id = t.price_level_id
  where p.company_id = target_company
    and p.id = any(target_products)
    and public.has_any_permission(target_company, array['orders.create','orders.view','products.view']);
$function$;

-- الكرتونة وأسعار المستويات للصنف (بعد حفظ الصنف الأساسي).
create or replace function public.save_product_packaging_and_prices(target_company uuid, target_product uuid, product_pack_size numeric, product_pack_unit text, level_prices jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb;
  v_price numeric;
begin
  if not public.has_any_permission(target_company, array['products.update','products.create']) then
    raise exception 'Not allowed';
  end if;

  update public.products
  set pack_size = case when coalesce(product_pack_size, 0) > 1 then product_pack_size end,
      pack_unit = case when coalesce(product_pack_size, 0) > 1
                       then coalesce(nullif(trim(product_pack_unit), ''), 'كرتونة') end,
      updated_at = now()
  where id = target_product and company_id = target_company;

  if not found then
    raise exception 'Product not found';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(level_prices, '[]'::jsonb)) loop
    v_price := nullif(v_item->>'price', '')::numeric;

    if not exists (
      select 1 from public.price_levels
      where id = (v_item->>'price_level_id')::uuid and company_id = target_company
    ) then
      raise exception 'Invalid price level';
    end if;

    if v_price is null then
      delete from public.product_level_prices
      where product_id = target_product and price_level_id = (v_item->>'price_level_id')::uuid;
    elsif v_price < 0 then
      raise exception 'Price cannot be negative';
    else
      insert into public.product_level_prices(company_id, product_id, price_level_id, price)
      values (target_company, target_product, (v_item->>'price_level_id')::uuid, round(v_price, 2))
      on conflict (product_id, price_level_id)
      do update set price = excluded.price, updated_at = now();
    end if;
  end loop;
end;
$function$;

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
    and (new.credit_limit is not null or new.payment_terms_days <> 0 or new.price_level_id is not null)
  ) or (
    tg_op = 'UPDATE'
    and (
      new.credit_limit is distinct from old.credit_limit
      or new.payment_terms_days is distinct from old.payment_terms_days
      -- مستوى السعر كمان: المندوب ما بيعطي حدا سعر جملة لحالو.
      or new.price_level_id is distinct from old.price_level_id
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

create or replace function public.save_product_with_supplier_prices(target_company uuid, target_product uuid, product_name text, product_sku text, product_brand text, target_category uuid, product_unit text, product_sale_price numeric, product_minimum_sale_price numeric, product_image_url text, product_active boolean, supplier_prices_payload jsonb, product_reorder_level numeric DEFAULT NULL::numeric)
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
      active,
      reorder_level
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
      product_active,
      nullif(greatest(product_reorder_level, 0), 0)
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
      reorder_level = nullif(greatest(product_reorder_level, 0), 0),
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
create trigger traders_credit_permission_guard before insert or update of credit_limit, payment_terms_days, price_level_id on public.traders for each row execute function public.enforce_trader_credit_permission();

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
