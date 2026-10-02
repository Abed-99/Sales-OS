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
  -- التغيّر الفعلي بقيمة المخزون (بالقروش). كلفة القطعة متقرّبة لـ 4 خانات، فممكن يفرق قروش
  -- عن الكمية × الكلفة؛ القيد بياخد الفرق مشان حساب المخزون يضل = قيمة البضاعة بالضبط.
  value_change numeric(18,2),
  constraint inventory_movements_movement_type_check check ((movement_type = any (array['opening'::text, 'purchase_receipt'::text, 'sales_delivery'::text, 'sales_return'::text, 'purchase_return'::text, 'adjustment_in'::text, 'adjustment_out'::text, 'transfer_in'::text, 'transfer_out'::text, 'damage'::text]))),
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

-- بضاعة تالفة: بتطلع من المخزون وكلفتها بتروح على "خسائر بضاعة تالفة".
create or replace function public.record_damaged_goods(target_company uuid, target_warehouse uuid, target_product uuid, target_quantity numeric, target_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_on_hand numeric;
  v_reserved numeric;
  v_cost numeric;
begin
  if not public.has_permission(target_company, 'inventory.adjust') then
    raise exception 'Not allowed';
  end if;

  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Damaged quantity must be greater than zero';
  end if;

  if nullif(trim(coalesce(target_reason, '')), '') is null then
    raise exception 'Damage reason is required';
  end if;

  perform public.assert_finance_period_open(target_company, (now() at time zone 'Asia/Damascus')::date);

  select s.on_hand, s.average_cost,
         coalesce((select sum(r.quantity) from public.inventory_reservations r
                   where r.warehouse_id = s.warehouse_id and r.product_id = s.product_id and r.status = 'active'), 0)
  into v_on_hand, v_cost, v_reserved
  from public.inventory_stock s
  where s.company_id = target_company and s.warehouse_id = target_warehouse and s.product_id = target_product;

  -- المحجوز لطلبيات ما بيتلف من هون (لازم تتلغى الحجوزات أول).
  if coalesce(v_on_hand, 0) - coalesce(v_reserved, 0) < target_quantity then
    raise exception 'Not enough free stock to mark as damaged';
  end if;

  return public.post_inventory_movement(
    target_company, target_warehouse, target_product, 'damage', -target_quantity, v_cost,
    null, null, null, null, 'تالف: ' || trim(target_reason)
  );
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
    occurred_at,
    value_change
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
    ),
    round(v_new_on_hand * v_new_average, 2) - round(v_stock.on_hand * v_stock.average_cost, 2)
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

-- تعديل اسم المستودع وكودو وعنوانو.
create or replace function public.update_warehouse(target_company uuid, target_warehouse uuid, target_name text, target_code text DEFAULT NULL::text, target_address text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(target_company, 'inventory.adjust') then
    raise exception 'Not allowed';
  end if;

  if nullif(trim(target_name), '') is null then
    raise exception 'Warehouse name is required';
  end if;

  update public.warehouses
  set name = trim(target_name),
      code = nullif(trim(target_code), ''),
      address = nullif(trim(target_address), ''),
      updated_at = now()
  where id = target_warehouse and company_id = target_company;

  if not found then
    raise exception 'Invalid warehouse';
  end if;
end;
$function$;

-- إيقاف أو تفعيل مستودع. ما بيتوقف إذا فيه بضاعة أو حجوزات، أو إذا كان آخر مستودع شغّال.
-- إذا كان الرئيسي، بيصير غيرو رئيسي.
create or replace function public.set_warehouse_active(target_company uuid, target_warehouse uuid, target_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_was_default boolean;
begin
  if not public.has_permission(target_company, 'inventory.adjust') then
    raise exception 'Not allowed';
  end if;

  select is_default into v_was_default
  from public.warehouses
  where id = target_warehouse and company_id = target_company
  for update;

  if not found then
    raise exception 'Invalid warehouse';
  end if;

  if coalesce(target_active, false) then
    update public.warehouses set active = true, updated_at = now() where id = target_warehouse;
    return;
  end if;

  if exists (select 1 from public.inventory_stock where warehouse_id = target_warehouse and on_hand <> 0) then
    raise exception 'Warehouse has stock';
  end if;

  if exists (select 1 from public.inventory_reservations where warehouse_id = target_warehouse and status = 'active') then
    raise exception 'Warehouse has active reservations';
  end if;

  if not exists (
    select 1 from public.warehouses
    where company_id = target_company and active and id <> target_warehouse
  ) then
    raise exception 'Cannot deactivate the last warehouse';
  end if;

  update public.warehouses
  set active = false, is_default = false, updated_at = now()
  where id = target_warehouse;

  if v_was_default then
    update public.warehouses
    set is_default = true
    where id = (
      select id from public.warehouses
      where company_id = target_company and active
      order by created_at
      limit 1
    );
  end if;
end;
$function$;

-- حركات صنف: إيمتى دخل وطلع، من وين ولمين، والرصيد بعد كل حركة (كل المستودعات).
create or replace function public.get_product_movements(target_company uuid, target_product uuid, target_limit integer DEFAULT 200)
 RETURNS TABLE(occurred_at timestamp with time zone, movement_type text, quantity numeric, balance numeric,
               warehouse_name text, reference text, party_name text, notes text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from (
    select m.occurred_at, m.movement_type, m.quantity,
           sum(m.quantity) over (order by m.occurred_at, m.created_at, m.id) as balance,
           w.name as warehouse_name,
           coalesce(m.reference_number, so.order_number, gr.receipt_number, sr.return_number, pr.return_number) as reference,
           coalesce(t1.name, t2.name, s1.name, s2.name) as party_name,
           m.notes
    from public.inventory_movements m
    join public.warehouses w on w.id = m.warehouse_id
    left join public.deliveries d on m.source_table = 'deliveries' and d.id = m.source_id
    left join public.sales_orders so on so.id = d.order_id
    left join public.traders t1 on t1.id = so.trader_id
    left join public.sales_returns sr on m.source_table = 'sales_returns' and sr.id = m.source_id
    left join public.traders t2 on t2.id = sr.trader_id
    left join public.goods_receipts gr on m.source_table = 'goods_receipts' and gr.id = m.source_id
    left join public.suppliers s1 on s1.id = gr.supplier_id
    left join public.purchase_returns pr on m.source_table = 'purchase_returns' and pr.id = m.source_id
    left join public.suppliers s2 on s2.id = pr.supplier_id
    where m.company_id = target_company
      and m.product_id = target_product
      and public.has_any_permission(target_company, array['inventory.view','products.view'])
  ) x
  order by x.occurred_at desc
  limit least(greatest(coalesce(target_limit, 200), 1), 1000);
$function$;


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
