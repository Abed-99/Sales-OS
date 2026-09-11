begin;

-- ============================================================
-- INVENTORY TRANSFERS
-- ============================================================

create table if not exists public.inventory_transfers (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  transfer_number text not null,

  source_warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  destination_warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  status text not null default 'posted'
    check (
      status in (
        'posted',
        'reversed'
      )
    ),

  transfer_date date not null default current_date,

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  reversed_at timestamptz,

  reversed_by uuid
    references auth.users(id)
    on delete set null,

  reversal_reason text,

  unique(
    company_id,
    transfer_number
  ),

  check (
    source_warehouse_id <>
    destination_warehouse_id
  )
);

create index if not exists
inventory_transfers_company_date_idx
on public.inventory_transfers(
  company_id,
  transfer_date desc,
  created_at desc
);


create table if not exists public.inventory_transfer_items (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  transfer_id uuid not null
    references public.inventory_transfers(id)
    on delete cascade,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  quantity numeric(18,3) not null
    check(quantity > 0),

  unit_cost numeric(18,4) not null
    check(unit_cost >= 0),

  created_at timestamptz not null default now(),

  unique(
    transfer_id,
    product_id
  )
);

create index if not exists
inventory_transfer_items_transfer_idx
on public.inventory_transfer_items(
  transfer_id
);


-- ============================================================
-- STOCK COUNTS / PHYSICAL INVENTORY
-- ============================================================

create table if not exists public.inventory_counts (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  count_number text not null,

  count_date date not null default current_date,

  status text not null default 'posted'
    check (
      status in (
        'posted'
      )
    ),

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  unique(
    company_id,
    count_number
  )
);

create index if not exists
inventory_counts_company_date_idx
on public.inventory_counts(
  company_id,
  count_date desc,
  created_at desc
);


create table if not exists public.inventory_count_items (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  count_id uuid not null
    references public.inventory_counts(id)
    on delete cascade,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  system_quantity numeric(18,3) not null,

  counted_quantity numeric(18,3) not null
    check(counted_quantity >= 0),

  difference_quantity numeric(18,3) not null,

  unit_cost numeric(18,4) not null
    check(unit_cost >= 0),

  created_at timestamptz not null default now(),

  unique(
    count_id,
    product_id
  )
);

create index if not exists
inventory_count_items_count_idx
on public.inventory_count_items(
  count_id
);


-- ============================================================
-- DOCUMENT NUMBERS
-- ============================================================

create or replace function public.next_inventory_transfer_number(
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
$$;


create or replace function public.next_inventory_count_number(
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
$$;

revoke all
on function public.next_inventory_transfer_number(uuid,date)
from public, authenticated;

revoke all
on function public.next_inventory_count_number(uuid,date)
from public, authenticated;


-- ============================================================
-- WAREHOUSE MANAGEMENT
-- ============================================================

create or replace function public.create_warehouse(
  target_company uuid,
  target_name text,
  target_code text default null,
  target_address text default null,
  target_is_default boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create or replace function public.set_default_warehouse(
  target_company uuid,
  target_warehouse uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;


revoke all
on function public.create_warehouse(
  uuid,
  text,
  text,
  text,
  boolean
)
from public;

revoke all
on function public.set_default_warehouse(
  uuid,
  uuid
)
from public;

grant execute
on function public.create_warehouse(
  uuid,
  text,
  text,
  text,
  boolean
)
to authenticated;

grant execute
on function public.set_default_warehouse(
  uuid,
  uuid
)
to authenticated;


-- ============================================================
-- POST WAREHOUSE TRANSFER
-- Reserved stock cannot be transferred.
-- ============================================================

create or replace function public.post_inventory_transfer(
  target_company uuid,
  target_source_warehouse uuid,
  target_destination_warehouse uuid,
  target_transfer_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.post_inventory_transfer(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
from public;

grant execute
on function public.post_inventory_transfer(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- PHYSICAL STOCK COUNT
-- The entered quantity is the real counted quantity.
-- System posts only the difference.
-- ============================================================

create or replace function public.post_inventory_count(
  target_company uuid,
  target_warehouse uuid,
  target_count_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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

    v_cost :=
      coalesce(
        v_supplied_cost,
        v_average_cost,
        0
      );

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
$$;

revoke all
on function public.post_inventory_count(
  uuid,
  uuid,
  date,
  text,
  jsonb
)
from public;

grant execute
on function public.post_inventory_count(
  uuid,
  uuid,
  date,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- RLS
-- ============================================================

alter table public.inventory_transfers
enable row level security;

alter table public.inventory_transfer_items
enable row level security;

alter table public.inventory_counts
enable row level security;

alter table public.inventory_count_items
enable row level security;


drop policy if exists inventory_transfers_read
on public.inventory_transfers;

create policy inventory_transfers_read
on public.inventory_transfers
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


drop policy if exists inventory_transfer_items_read
on public.inventory_transfer_items;

create policy inventory_transfer_items_read
on public.inventory_transfer_items
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


drop policy if exists inventory_counts_read
on public.inventory_counts;

create policy inventory_counts_read
on public.inventory_counts
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


drop policy if exists inventory_count_items_read
on public.inventory_count_items;

create policy inventory_count_items_read
on public.inventory_count_items
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'inventory.view'
  )
);


revoke insert, update, delete
on public.inventory_transfers,
   public.inventory_transfer_items,
   public.inventory_counts,
   public.inventory_count_items
from authenticated;

grant select
on public.inventory_transfers,
   public.inventory_transfer_items,
   public.inventory_counts,
   public.inventory_count_items
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists audit_inventory_transfers
on public.inventory_transfers;

create trigger audit_inventory_transfers
after insert or update or delete
on public.inventory_transfers
for each row
execute function public.write_audit_log();


drop trigger if exists audit_inventory_transfer_items
on public.inventory_transfer_items;

create trigger audit_inventory_transfer_items
after insert or update or delete
on public.inventory_transfer_items
for each row
execute function public.write_audit_log();


drop trigger if exists audit_inventory_counts
on public.inventory_counts;

create trigger audit_inventory_counts
after insert or update or delete
on public.inventory_counts
for each row
execute function public.write_audit_log();


drop trigger if exists audit_inventory_count_items
on public.inventory_count_items;

create trigger audit_inventory_count_items
after insert or update or delete
on public.inventory_count_items
for each row
execute function public.write_audit_log();

commit;