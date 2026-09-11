begin;

-- ============================================================
-- DELIVERY + MULTIPLE SALES INVOICES WORKFLOW
-- ============================================================

alter table public.deliveries
add column if not exists delivery_number text;

alter table public.deliveries
add column if not exists started_at timestamptz;

alter table public.deliveries
add column if not exists created_by uuid
references auth.users(id)
on delete set null;

-- Remove old "one delivery per order" restriction if it still exists.
do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.deliveries'::regclass
      and c.contype = 'u'
      and pg_get_constraintdef(c.oid) = 'UNIQUE (order_id)'
  loop
    execute format(
      'alter table public.deliveries drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;

drop index if exists public.deliveries_order_id_key;

create index if not exists deliveries_order_status_idx
on public.deliveries(
  company_id,
  order_id,
  status,
  created_at desc
);

create unique index if not exists deliveries_number_unique
on public.deliveries(
  company_id,
  delivery_number
)
where delivery_number is not null;


-- ============================================================
-- DELIVERY ITEMS
-- Each delivery can contain part of an order.
-- ============================================================

create table if not exists public.delivery_items (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  delivery_id uuid not null
    references public.deliveries(id)
    on delete cascade,

  sales_order_item_id uuid not null
    references public.sales_order_items(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  quantity numeric(14,3) not null
    check (quantity > 0),

  unit text,

  created_at timestamptz not null default now(),

  unique(
    delivery_id,
    sales_order_item_id
  )
);

create index if not exists delivery_items_delivery_idx
on public.delivery_items(delivery_id);

create index if not exists delivery_items_order_item_idx
on public.delivery_items(sales_order_item_id);


-- ============================================================
-- LINK SALES INVOICE TO DELIVERY
-- Multiple invoices can belong to the same sales order.
-- ============================================================

create table if not exists public.sales_invoice_delivery_links (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  sales_invoice_id uuid not null
    references public.sales_invoices(id)
    on delete cascade,

  delivery_id uuid not null
    references public.deliveries(id)
    on delete restrict,

  created_at timestamptz not null default now(),

  unique(delivery_id)
);

create index if not exists sales_invoice_delivery_invoice_idx
on public.sales_invoice_delivery_links(
  sales_invoice_id
);

-- Old restriction: one active sales invoice per order.
drop index if exists public.sales_invoices_active_order_unique;


-- ============================================================
-- RLS
-- ============================================================

alter table public.delivery_items
enable row level security;

alter table public.sales_invoice_delivery_links
enable row level security;

drop policy if exists delivery_items_read
on public.delivery_items;

create policy delivery_items_read
on public.delivery_items
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'deliveries.view',
      'deliveries.update',
      'orders.view',
      'sales_invoices.view'
    ]::text[]
  )
);

drop policy if exists sales_invoice_delivery_links_read
on public.sales_invoice_delivery_links;

create policy sales_invoice_delivery_links_read
on public.sales_invoice_delivery_links
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'deliveries.view',
      'orders.view',
      'sales_invoices.view',
      'payments.sales_view'
    ]::text[]
  )
);

revoke insert, update, delete
on public.delivery_items
from authenticated;

revoke insert, update, delete
on public.sales_invoice_delivery_links
from authenticated;

grant select
on public.delivery_items
to authenticated;

grant select
on public.sales_invoice_delivery_links
to authenticated;


-- ============================================================
-- DELIVERY NUMBER
-- DN-2026-000001
-- ============================================================

create or replace function public.next_delivery_number(
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
$$;

revoke all
on function public.next_delivery_number(uuid,date)
from public, authenticated;


-- ============================================================
-- RECALCULATE WHOLE SALES ORDER PAYMENT STATUS
-- Works correctly with multiple invoices.
-- ============================================================

create or replace function public.recalc_sales_order_payment(
  target_order uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric(14,2);
  v_paid numeric(14,2);
  v_status text;
begin
  select
    total,
    status
  into
    v_total,
    v_status
  from public.sales_orders
  where id = target_order;

  if v_total is null then
    return;
  end if;

  select
    coalesce(sum(a.amount),0)
  into v_paid
  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id = a.payment_id
   and p.status = 'posted'

  join public.sales_invoices si
    on si.id = a.sales_invoice_id
   and si.status = 'posted'

  where si.order_id = target_order;

  v_paid :=
    least(
      round(v_paid,2),
      round(v_total,2)
    );

  update public.sales_orders
  set
    payment_status =
      case
        when coalesce(v_total,0) = 0
          or v_paid >= v_total
          then 'paid'

        when v_paid > 0
          then 'partial'

        else 'unpaid'
      end,

    paid_at =
      case
        when coalesce(v_total,0) = 0
          or v_paid >= v_total
          then coalesce(
            paid_at,
            now()
          )

        else null
      end

  where id = target_order;
end;
$$;

revoke all
on function public.recalc_sales_order_payment(uuid)
from public, authenticated;


-- ============================================================
-- RECALCULATE ONE INVOICE + ITS WHOLE ORDER
-- ============================================================

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

  select
    coalesce(sum(a.amount),0)
  into v_paid
  from public.customer_payment_allocations a

  join public.customer_payments p
    on p.id = a.payment_id

  where a.sales_invoice_id = target_invoice
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

  if v_order is not null then
    perform
      public.recalc_sales_order_payment(
        v_order
      );
  end if;
end;
$$;

revoke all
on function public.recalc_sales_invoice_payment(uuid)
from public, authenticated;


-- ============================================================
-- START DELIVERY
-- Current UI sends all remaining items.
-- Structure already supports partial delivery later.
-- ============================================================

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
  v_number text;
  v_count integer;
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
    raise exception
      'Order is not ready for delivery';
  end if;

  -- Idempotent: do not create another active delivery.
  if exists (
    select 1
    from public.deliveries d
    where d.company_id = target_company
      and d.order_id = target_order
      and d.status = 'out_for_delivery'
  ) then
    update public.sales_orders
    set status = 'out_for_delivery'
    where id = target_order;

    return;
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

  insert into public.delivery_items(
    company_id,
    delivery_id,
    sales_order_item_id,
    product_id,
    quantity,
    unit
  )
  select
    target_company,
    v_delivery,
    soi.id,
    soi.product_id,

    round(
      soi.quantity -
      coalesce(done.quantity,0),
      3
    ),

    p.unit

  from public.sales_order_items soi

  join public.products p
    on p.id = soi.product_id

  left join lateral (
    select
      coalesce(sum(di.quantity),0)
        as quantity

    from public.delivery_items di

    join public.deliveries d
      on d.id = di.delivery_id

    where di.sales_order_item_id =
          soi.id

      and d.status in (
        'out_for_delivery',
        'delivered'
      )
  ) done on true

  where soi.order_id =
        target_order

    and (
      soi.quantity -
      coalesce(done.quantity,0)
    ) > 0;

  get diagnostics
    v_count = row_count;

  if v_count = 0 then
    delete from public.deliveries
    where id = v_delivery;

    raise exception
      'No remaining items to deliver';
  end if;

  update public.sales_orders
  set status = 'out_for_delivery'
  where id = target_order
    and company_id = target_company;
end;
$$;


-- ============================================================
-- COMPLETE DELIVERY
-- Every delivery gets its own sales invoice.
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
  where id = target_order
    and company_id = target_company
  for update;

  if v_order_status is null then
    raise exception 'Order not found';
  end if;

  -- Network retry after a fully completed delivery.
  if v_order_status = 'delivered' then
    select l.sales_invoice_id
    into v_invoice
    from public.sales_invoice_delivery_links l

    join public.deliveries d
      on d.id = l.delivery_id

    where d.company_id = target_company
      and d.order_id = target_order
      and d.status = 'delivered'

    order by d.delivered_at desc nulls last
    limit 1;

    if v_invoice is not null then
      return v_invoice;
    end if;
  end if;

  if v_order_status <> 'out_for_delivery' then
    raise exception
      'Order is not currently out for delivery';
  end if;

  select d.id
  into v_delivery
  from public.deliveries d
  where d.company_id = target_company
    and d.order_id = target_order
    and d.status = 'out_for_delivery'
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
  where l.delivery_id = v_delivery;

  if v_invoice is not null then
    return v_invoice;
  end if;

  v_now := now();

  update public.deliveries
  set
    status = 'delivered',
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
    updated_at = v_now
  where id = v_delivery;

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
    on c.id = o.company_id

  where o.id = target_order
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
          ) as delivered_quantity

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

        and delivered.delivered_quantity <
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
    and si.status = 'posted';

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
      v_subtotal
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
    round(v_subtotal,2),
    round(v_discount,2),
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
    di.quantity,
    soi.sale_unit_price,

    round(
      di.quantity *
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
        v_delivery;

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

  update public.sales_orders
  set
    status =
      case
        when v_fully_delivered
          then 'delivered'
        else 'ready'
      end,

    delivered_at =
      case
        when v_fully_delivered
          then coalesce(
            delivered_at,
            v_now
          )
        else null
      end

  where id = target_order
    and company_id =
        target_company;

  return v_invoice;
end;
$$;


revoke all
on function public.start_order_delivery(uuid,uuid)
from public;

revoke all
on function public.complete_order_delivery(uuid,uuid,text)
from public;

grant execute
on function public.start_order_delivery(uuid,uuid)
to authenticated;

grant execute
on function public.complete_order_delivery(uuid,uuid,text)
to authenticated;

commit;