begin;

-- ============================================================
-- DELIVERY ITEMS MUST KNOW THE SOURCE WAREHOUSE
-- ============================================================

alter table public.delivery_items
add column if not exists warehouse_id uuid
references public.warehouses(id)
on delete restrict;

update public.delivery_items di
set warehouse_id = (
  select w.id
  from public.deliveries d
  join public.warehouses w
    on w.company_id = d.company_id
   and w.active = true
  where d.id = di.delivery_id
  order by
    w.is_default desc,
    w.created_at
  limit 1
)
where di.warehouse_id is null;

do $$
begin
  if exists (
    select 1
    from public.delivery_items
    where warehouse_id is null
  ) then
    raise exception
      'Could not resolve warehouse for old delivery items';
  end if;
end;
$$;

alter table public.delivery_items
alter column warehouse_id set not null;


-- Old unique rule did not allow one order item
-- to be supplied from multiple warehouses.
do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid =
          'public.delivery_items'::regclass
      and c.contype = 'u'
      and position(
        'UNIQUE (delivery_id, sales_order_item_id)'
        in pg_get_constraintdef(c.oid)
      ) > 0
  loop
    execute format(
      'alter table public.delivery_items drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;

drop index if exists
public.delivery_items_delivery_order_wh_unique;

create unique index
delivery_items_delivery_order_wh_unique
on public.delivery_items(
  delivery_id,
  sales_order_item_id,
  warehouse_id
);


-- ============================================================
-- REFRESH SALES ORDER FROM REAL INVENTORY STATE
-- Delivered + Reserved = operationally covered.
-- ============================================================

create or replace function
public.refresh_sales_order_inventory_status(
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function
public.refresh_sales_order_inventory_status(uuid)
from public, authenticated;


-- Existing purchase workflow calls this function.
-- From now on "ready" means physically covered by stock,
-- not merely purchased on paper.
create or replace function
public.refresh_sales_order_purchase_status(
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform
    public.refresh_sales_order_inventory_status(
      target_order
    );
end;
$$;

revoke all
on function
public.refresh_sales_order_purchase_status(uuid)
from public, authenticated;


-- ============================================================
-- AUTO RESERVE AVAILABLE STOCK FIFO
-- ============================================================

create or replace function
public.reserve_pending_orders_for_product(
  target_company uuid,
  target_warehouse uuid,
  target_product uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function
public.reserve_pending_orders_for_product(
  uuid,
  uuid,
  uuid
)
from public, authenticated;


create or replace function
public.reserve_sales_order(
  target_company uuid,
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.reserve_sales_order(
  uuid,
  uuid
)
from public, authenticated;


-- ============================================================
-- SALES ORDER CREATION NOW RESERVES AVAILABLE STOCK
-- ============================================================

create or replace function public.create_sales_order(
  target_company uuid,
  target_trader uuid,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;


-- ============================================================
-- CANCEL ORDER = RELEASE RESERVATIONS + REALLOCATE STOCK
-- ============================================================

drop function if exists public.cancel_sales_order(
  uuid,
  uuid
);

create or replace function public.cancel_sales_order(
  target_company uuid,
  target_order uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;



revoke all
on function public.create_sales_order(
  uuid,
  uuid,
  text,
  jsonb
)
from public;

revoke all
on function public.cancel_sales_order(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.create_sales_order(
  uuid,
  uuid,
  text,
  jsonb
)
to authenticated;

grant execute
on function public.cancel_sales_order(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- PURCHASE NEEDS = ONLY WHAT IS NOT
-- DELIVERED, RESERVED OR ALREADY PURCHASED
-- ============================================================

drop function if exists
public.get_purchase_needs(uuid);

create function public.get_purchase_needs(
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
$$;

revoke all
on function public.get_purchase_needs(uuid)
from public;

grant execute
on function public.get_purchase_needs(uuid)
to authenticated;


-- ============================================================
-- RECEIVING GOODS NOW AUTO-RESERVES THEM TO OPEN ORDERS
-- ============================================================


-- ============================================================
-- RECEIVABLE PURCHASE ITEMS
-- Secure receiving source.
-- Does not expose purchase cost.
-- ============================================================

create or replace function public.get_receivable_purchase_items(
  target_company uuid
)
returns table(
  invoice_id uuid,
  supplier_id uuid,
  invoice_number text,
  supplier_invoice_number text,
  currency text,
  invoice_date date,
  invoice_total numeric,
  supplier_name text,
  item_id uuid,
  product_id uuid,
  description text,
  invoiced_quantity numeric,
  received_quantity numeric,
  remaining_quantity numeric,
  product_name text,
  sku text,
  unit text
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_receivable_purchase_items(
  uuid
)
from public;

grant execute
on function public.get_receivable_purchase_items(
  uuid
)
to authenticated;
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
-- PARTIAL DELIVERY MUST USE RESERVED STOCK
-- ============================================================

create or replace function public.create_order_delivery(
  target_company uuid,
  target_order uuid,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.create_order_delivery(
  uuid,
  uuid,
  jsonb
)
from public;

grant execute
on function public.create_order_delivery(
  uuid,
  uuid,
  jsonb
)
to authenticated;


-- Compatibility wrapper for any older caller.
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
  v_payload jsonb;
begin
  if not public.has_permission(
    target_company,
    'deliveries.update'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'sales_order_item_id',
        soi.id,
        'quantity',
        greatest(
          soi.quantity -
          coalesce(delivered.qty,0),
          0
        )
      )
    )
  into v_payload
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

    and greatest(
      soi.quantity -
      coalesce(delivered.qty,0),
      0
    ) > 0;

  perform
    public.create_order_delivery(
      target_company,
      target_order,
      v_payload
    );
end;
$$;

revoke all
on function public.start_order_delivery(
  uuid,
  uuid
)
from public;

grant execute
on function public.start_order_delivery(
  uuid,
  uuid
)
to authenticated;


-- ============================================================
-- DELIVERY COMPLETION:
-- DEDUCT STOCK + FULFILL RESERVATION + CREATE INVOICE
-- ============================================================

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
$$;

revoke all
on function public.complete_order_delivery(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.complete_order_delivery(
  uuid,
  uuid,
  text
)
to authenticated;



-- ============================================================
-- FAIL ACTIVE DELIVERY
-- No stock movement is reversed because physical stock is only
-- deducted when a delivery is successfully completed.
-- Existing reservations remain available for a retry.
-- ============================================================

create or replace function public.fail_order_delivery(
  target_company uuid,
  target_order uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.fail_order_delivery(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.fail_order_delivery(
  uuid,
  uuid,
  text
)
to authenticated;
-- ============================================================
-- AUDIT RESERVATIONS
-- ============================================================

drop trigger if exists
audit_inventory_reservations
on public.inventory_reservations;

create trigger
audit_inventory_reservations
after insert or update or delete
on public.inventory_reservations
for each row
execute function public.write_audit_log();

commit;
