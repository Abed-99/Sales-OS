begin;

-- ============================================================
-- REVERSAL METADATA
-- ============================================================

alter table public.goods_receipts
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid
    references auth.users(id)
    on delete set null,
  add column if not exists cancellation_reason text;

alter table public.inventory_transfers
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid
    references auth.users(id)
    on delete set null,
  add column if not exists reversal_reason text;

alter table public.inventory_counts
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid
    references auth.users(id)
    on delete set null,
  add column if not exists reversal_reason text;


-- ============================================================
-- INVENTORY COUNT STATUS
-- posted -> reversed
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid =
          'public.inventory_counts'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid)
          ilike '%status%'
  loop
    execute format(
      'alter table public.inventory_counts drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;

alter table public.inventory_counts
add constraint inventory_counts_status_check
check(
  status in (
    'posted',
    'reversed'
  )
);


-- ============================================================
-- COST PERMISSION HELPER
-- ============================================================

create or replace function public.can_view_inventory_cost(
  target_company uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.can_view_inventory_cost(uuid)
from public;

grant execute
on function public.can_view_inventory_cost(uuid)
to authenticated;


-- ============================================================
-- SECURE INVENTORY SUMMARY
-- Stock quantities remain visible to inventory staff.
-- Cost is returned only to authorized users.
-- ============================================================

drop view if exists public.inventory_summary;

create view public.inventory_summary
as
select
  s.company_id,

  s.warehouse_id,

  w.name as warehouse_name,

  s.product_id,

  p.sku,

  p.name as product_name,

  p.unit,

  round(
    s.on_hand,
    3
  ) as on_hand,

  round(
    coalesce(
      (
        select
          sum(r.quantity)

        from public.inventory_reservations r

        where r.company_id =
              s.company_id

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
  ) as reserved,

  round(
    greatest(
      s.on_hand -
      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                s.company_id

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
  ) as available,

  case
    when public.can_view_inventory_cost(
      s.company_id
    )
    then round(
      s.average_cost,
      4
    )
    else null
  end as average_cost,

  case
    when public.can_view_inventory_cost(
      s.company_id
    )
    then round(
      s.on_hand *
      s.average_cost,
      2
    )
    else null
  end as stock_value,

  s.updated_at

from public.inventory_stock s

join public.warehouses w
  on w.id =
     s.warehouse_id

join public.products p
  on p.id =
     s.product_id

where
  public.has_any_permission(
    s.company_id,
    array[
      'inventory.view',
      'inventory.adjust',
      'inventory.returns',
      'purchases.view',
      'purchase_invoices.view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  );

revoke all
on public.inventory_summary
from public;

grant select
on public.inventory_summary
to authenticated;


-- ============================================================
-- BLOCK DIRECT COST ACCESS
-- inventory_stock / movements contain sensitive cost.
-- ============================================================

revoke select
on public.inventory_stock
from authenticated;

revoke select
on public.inventory_movements
from authenticated;


-- Goods receipt line:
-- warehouse users can see product + qty, never direct unit_cost.
revoke select
on public.goods_receipt_items
from authenticated;

grant select(
  id,
  company_id,
  goods_receipt_id,
  purchase_invoice_item_id,
  product_id,
  quantity,
  created_at
)
on public.goods_receipt_items
to authenticated;


-- Transfer cost is internal.
revoke select
on public.inventory_transfer_items
from authenticated;

grant select(
  id,
  company_id,
  transfer_id,
  product_id,
  quantity
)
on public.inventory_transfer_items
to authenticated;


-- Count cost is internal.
revoke select
on public.inventory_count_items
from authenticated;

grant select(
  id,
  company_id,
  count_id,
  product_id,
  system_quantity,
  counted_quantity,
  difference_quantity
)
on public.inventory_count_items
to authenticated;


-- ============================================================
-- SAFE MOVEMENT HISTORY
-- Cost is masked at database level.
-- ============================================================

drop view if exists public.inventory_movement_history;

create view public.inventory_movement_history
as
select
  m.id,
  m.company_id,
  m.warehouse_id,
  m.product_id,
  m.movement_type,
  m.quantity,

  case
    when public.can_view_inventory_cost(
      m.company_id
    )
    then m.unit_cost
    else null
  end as unit_cost,

  m.source_table,
  m.source_id,
  m.source_line_id,
  m.reference_number,
  m.notes,
  m.occurred_at,
  m.created_at

from public.inventory_movements m

where
  public.has_any_permission(
    m.company_id,
    array[
      'inventory.view',
      'inventory.adjust',
      'reports.finance',
      'reports.profit'
    ]::text[]
  );

revoke all
on public.inventory_movement_history
from public;

grant select
on public.inventory_movement_history
to authenticated;


-- ============================================================
-- REVERSE GOODS RECEIPT
-- Stock received from supplier is removed.
-- Uses purchase_return inventory movement so accounting reverses:
-- Dr Inventory Clearing / Cr Inventory
-- ============================================================

create or replace function public.reverse_goods_receipt(
  target_company uuid,
  target_receipt uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.reverse_goods_receipt(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.reverse_goods_receipt(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- REVERSE INVENTORY TRANSFER
-- Destination -> source.
-- Transfer itself has no P&L effect.
-- ============================================================

create or replace function public.reverse_inventory_transfer(
  target_company uuid,
  target_transfer uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.reverse_inventory_transfer(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.reverse_inventory_transfer(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- REVERSE PHYSICAL COUNT
-- Reverse only the difference originally posted.
-- ============================================================

create or replace function public.reverse_inventory_count(
  target_company uuid,
  target_count uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.reverse_inventory_count(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.reverse_inventory_count(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- HARDEN PURCHASE INVOICE CANCELLATION
-- Must first reverse receipts and payments.
-- A posted purchase return also prevents cancellation.
-- ============================================================

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
$$;

revoke all
on function public.cancel_purchase_invoice(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.cancel_purchase_invoice(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- AUDIT INDEXES FOR REVERSALS
-- ============================================================

create index if not exists
goods_receipts_company_status_idx
on public.goods_receipts(
  company_id,
  status,
  receipt_date desc
);

create index if not exists
inventory_transfers_company_status_idx
on public.inventory_transfers(
  company_id,
  status,
  transfer_date desc
);

create index if not exists
inventory_counts_company_status_idx
on public.inventory_counts(
  company_id,
  status,
  count_date desc
);

commit;