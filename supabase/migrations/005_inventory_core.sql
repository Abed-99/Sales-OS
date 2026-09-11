begin;

-- ============================================================
-- WAREHOUSES
-- ============================================================

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  code text,
  name text not null,

  address text,

  is_default boolean not null default false,
  active boolean not null default true,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(company_id, name)
);

create unique index if not exists
warehouses_one_default_per_company
on public.warehouses(company_id)
where is_default = true
  and active = true;

create index if not exists
warehouses_company_idx
on public.warehouses(
  company_id,
  active,
  name
);

drop trigger if exists warehouses_updated_at
on public.warehouses;

create trigger warehouses_updated_at
before update
on public.warehouses
for each row
execute function public.set_updated_at();


-- ============================================================
-- DEFAULT WAREHOUSE FOR CURRENT COMPANIES
-- ============================================================

insert into public.warehouses(
  company_id,
  code,
  name,
  is_default,
  active
)
select
  c.id,
  'MAIN',
  'المستودع الرئيسي',
  true,
  true
from public.companies c
where not exists (
  select 1
  from public.warehouses w
  where w.company_id = c.id
);


create or replace function public.create_default_warehouse()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists company_default_warehouse
on public.companies;

create trigger company_default_warehouse
after insert
on public.companies
for each row
execute function public.create_default_warehouse();


-- ============================================================
-- STOCK BALANCE
-- Physical balance per warehouse + product.
-- ============================================================

create table if not exists public.inventory_stock (
  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  on_hand numeric(18,3) not null default 0,

  average_cost numeric(18,4)
    not null default 0
    check (average_cost >= 0),

  updated_at timestamptz not null default now(),

  primary key(
    warehouse_id,
    product_id
  ),

  check(on_hand >= 0)
);

create index if not exists
inventory_stock_company_product_idx
on public.inventory_stock(
  company_id,
  product_id
);


-- ============================================================
-- INVENTORY MOVEMENT LEDGER
-- Never edit/delete posted movements.
-- ============================================================

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  movement_type text not null
    check (
      movement_type in (
        'opening',
        'purchase_receipt',
        'sales_delivery',
        'sales_return',
        'purchase_return',
        'adjustment_in',
        'adjustment_out',
        'transfer_in',
        'transfer_out'
      )
    ),

  quantity numeric(18,3) not null
    check(quantity <> 0),

  unit_cost numeric(18,4)
    check (
      unit_cost is null
      or unit_cost >= 0
    ),

  source_table text,
  source_id uuid,
  source_line_id uuid,

  reference_number text,
  notes text,

  occurred_at timestamptz not null default now(),

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index if not exists
inventory_movements_company_date_idx
on public.inventory_movements(
  company_id,
  occurred_at desc
);

create index if not exists
inventory_movements_stock_idx
on public.inventory_movements(
  warehouse_id,
  product_id,
  occurred_at desc
);

create unique index if not exists
inventory_movements_source_unique
on public.inventory_movements(
  source_table,
  source_line_id,
  movement_type
)
where source_table is not null
  and source_line_id is not null;


-- ============================================================
-- RESERVATIONS
-- ============================================================

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  sales_order_item_id uuid not null
    references public.sales_order_items(id)
    on delete cascade,

  quantity numeric(18,3) not null
    check(quantity > 0),

  status text not null default 'active'
    check (
      status in (
        'active',
        'released',
        'fulfilled',
        'cancelled'
      )
    ),

  created_at timestamptz not null default now(),
  released_at timestamptz,

  unique(
    warehouse_id,
    sales_order_item_id
  )
);

create index if not exists
inventory_reservations_product_idx
on public.inventory_reservations(
  company_id,
  product_id,
  status
);


-- ============================================================
-- GOODS RECEIPTS / GRN
-- ============================================================

create table if not exists public.goods_receipts (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  supplier_id uuid not null
    references public.suppliers(id)
    on delete restrict,

  purchase_invoice_id uuid
    references public.purchase_invoices(id)
    on delete restrict,

  receipt_number text not null,

  status text not null default 'posted'
    check (
      status in (
        'posted',
        'cancelled'
      )
    ),

  receipt_date date not null default current_date,

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  cancelled_at timestamptz,
  cancelled_by uuid
    references auth.users(id)
    on delete set null,

  cancellation_reason text,

  unique(
    company_id,
    receipt_number
  )
);

create index if not exists
goods_receipts_company_date_idx
on public.goods_receipts(
  company_id,
  receipt_date desc,
  created_at desc
);


create table if not exists public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  goods_receipt_id uuid not null
    references public.goods_receipts(id)
    on delete cascade,

  purchase_invoice_item_id uuid not null
    references public.purchase_invoice_items(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  quantity numeric(18,3) not null
    check(quantity > 0),

  unit_cost numeric(18,4) not null
    check(unit_cost >= 0),

  created_at timestamptz not null default now()
);

create index if not exists
goods_receipt_items_receipt_idx
on public.goods_receipt_items(
  goods_receipt_id
);

create index if not exists
goods_receipt_items_purchase_item_idx
on public.goods_receipt_items(
  purchase_invoice_item_id
);


-- ============================================================
-- DOCUMENT NUMBER
-- GRN-2026-000001
-- ============================================================

create or replace function public.next_goods_receipt_number(
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
$$;

revoke all
on function public.next_goods_receipt_number(
  uuid,
  date
)
from public, authenticated;


-- ============================================================
-- CENTRAL STOCK POSTING FUNCTION
-- ============================================================

create or replace function public.post_inventory_movement(
  target_company uuid,
  target_warehouse uuid,
  target_product uuid,
  target_type text,
  target_quantity numeric,
  target_unit_cost numeric default null,
  target_source_table text default null,
  target_source_id uuid default null,
  target_source_line_id uuid default null,
  target_reference text default null,
  target_notes text default null,
  target_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock public.inventory_stock%rowtype;
  v_new_on_hand numeric(18,3);
  v_new_average numeric(18,4);
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
      and p.active = true
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

  if target_quantity > 0
     and target_unit_cost is not null
  then
    if v_new_on_hand > 0 then
      v_new_average :=
        round(
          (
            (
              v_stock.on_hand *
              v_stock.average_cost
            ) +
            (
              target_quantity *
              target_unit_cost
            )
          ) /
          v_new_on_hand,
          4
        );
    else
      v_new_average :=
        round(
          target_unit_cost,
          4
        );
    end if;
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
$$;

revoke all
on function public.post_inventory_movement(
  uuid,
  uuid,
  uuid,
  text,
  numeric,
  numeric,
  text,
  uuid,
  uuid,
  text,
  text,
  timestamptz
)
from public, authenticated;


-- ============================================================
-- RECEIVE PURCHASE INVOICE
-- Supports partial receipt.
-- ============================================================

create or replace function public.receive_purchase_invoice(
  target_company uuid,
  target_invoice uuid,
  target_warehouse uuid,
  target_receipt_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
      'purchases.update',
      'purchase_invoices.create'
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
  where id = target_invoice
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
          v_item ->> 'purchase_invoice_item_id'
        )::uuid;

      v_requested :=
        (
          v_item ->> 'quantity'
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
  end loop;

  return v_receipt;
end;
$$;

revoke all
on function public.receive_purchase_invoice(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
from public;

grant execute
on function public.receive_purchase_invoice(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- STOCK SUMMARY VIEW
-- ============================================================

create or replace view public.inventory_summary
with (security_invoker = true)
as
select
  s.company_id,
  s.warehouse_id,
  w.name as warehouse_name,

  s.product_id,
  p.sku,
  p.name as product_name,
  p.unit,

  s.on_hand,

  coalesce(
    r.reserved,
    0
  )::numeric(18,3)
  as reserved,

  greatest(
    s.on_hand -
    coalesce(
      r.reserved,
      0
    ),
    0
  )::numeric(18,3)
  as available,

  s.average_cost,

  round(
    s.on_hand *
    s.average_cost,
    2
  ) as stock_value,

  s.updated_at

from public.inventory_stock s

join public.warehouses w
  on w.id = s.warehouse_id

join public.products p
  on p.id = s.product_id

left join lateral (
  select
    coalesce(
      sum(ir.quantity),
      0
    ) as reserved

  from public.inventory_reservations ir

  where ir.warehouse_id =
        s.warehouse_id

    and ir.product_id =
        s.product_id

    and ir.status =
        'active'
) r on true;


-- ============================================================
-- RLS
-- ============================================================

alter table public.warehouses
enable row level security;

alter table public.inventory_stock
enable row level security;

alter table public.inventory_movements
enable row level security;

alter table public.inventory_reservations
enable row level security;

alter table public.goods_receipts
enable row level security;

alter table public.goods_receipt_items
enable row level security;


drop policy if exists warehouses_read
on public.warehouses;

create policy warehouses_read
on public.warehouses
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'inventory.view',
      'inventory.adjust',
      'purchases.view',
      'deliveries.view',
      'reports.view'
    ]::text[]
  )
);


drop policy if exists inventory_stock_read
on public.inventory_stock;

create policy inventory_stock_read
on public.inventory_stock
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


drop policy if exists inventory_movements_read
on public.inventory_movements;

create policy inventory_movements_read
on public.inventory_movements
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


drop policy if exists inventory_reservations_read
on public.inventory_reservations;

create policy inventory_reservations_read
on public.inventory_reservations
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'inventory.view',
      'orders.view',
      'deliveries.view'
    ]::text[]
  )
);


drop policy if exists goods_receipts_read
on public.goods_receipts;

create policy goods_receipts_read
on public.goods_receipts
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'inventory.view',
      'purchases.view',
      'purchase_invoices.view'
    ]::text[]
  )
);


drop policy if exists goods_receipt_items_read
on public.goods_receipt_items;

create policy goods_receipt_items_read
on public.goods_receipt_items
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'inventory.view',
      'purchases.view',
      'purchase_invoices.view'
    ]::text[]
  )
);


revoke insert, update, delete
on public.inventory_stock,
   public.inventory_movements,
   public.inventory_reservations,
   public.goods_receipts,
   public.goods_receipt_items
from authenticated;


grant select
on public.warehouses,
   public.inventory_stock,
   public.inventory_movements,
   public.inventory_reservations,
   public.goods_receipts,
   public.goods_receipt_items
to authenticated;

grant select
on public.inventory_summary
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists audit_warehouses
on public.warehouses;

create trigger audit_warehouses
after insert or update or delete
on public.warehouses
for each row
execute function public.write_audit_log();


drop trigger if exists audit_goods_receipts
on public.goods_receipts;

create trigger audit_goods_receipts
after insert or update or delete
on public.goods_receipts
for each row
execute function public.write_audit_log();


drop trigger if exists audit_goods_receipt_items
on public.goods_receipt_items;

create trigger audit_goods_receipt_items
after insert or update or delete
on public.goods_receipt_items
for each row
execute function public.write_audit_log();


drop trigger if exists audit_inventory_movements
on public.inventory_movements;

create trigger audit_inventory_movements
after insert
on public.inventory_movements
for each row
execute function public.write_audit_log();

commit;