begin;

-- ============================================================
-- PERMISSIONS
-- ============================================================

insert into public.permissions(
  code,
  module,
  action,
  label,
  sort_order
)
values
(
  'approvals.view',
  'approvals',
  'view',
  'عرض الموافقات',
  240
),
(
  'approvals.create',
  'approvals',
  'create',
  'إنشاء طلب موافقة',
  241
),
(
  'approvals.resolve',
  'approvals',
  'resolve',
  'اعتماد أو رفض الموافقات',
  242
),
(
  'returns.view',
  'returns',
  'view',
  'عرض المرتجعات',
  250
),
(
  'returns.create',
  'returns',
  'create',
  'إنشاء مرتجع',
  251
)
on conflict(code)
do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  sort_order = excluded.sort_order;


insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  p.code
from public.company_roles r
cross join public.permissions p
where r.is_owner = true
  and p.code in (
    'approvals.view',
    'approvals.create',
    'approvals.resolve',
    'returns.view',
    'returns.create'
  )
on conflict do nothing;


insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  p.code
from public.company_roles r
cross join public.permissions p
where r.name = 'محاسب'
  and r.is_owner = false
  and p.code in (
    'approvals.view',
    'approvals.create',
    'approvals.resolve',
    'returns.view',
    'returns.create'
  )
on conflict do nothing;


-- ============================================================
-- CENTRAL APPROVAL REQUESTS
-- ============================================================

create table if not exists public.approval_requests(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  request_type text not null,

  reference_type text,

  reference_id uuid,

  title text not null,

  description text,

  payload jsonb not null default '{}'::jsonb,

  status text not null default 'pending'
    check(
      status in (
        'pending',
        'approved',
        'rejected',
        'cancelled'
      )
    ),

  requested_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  requested_at timestamptz
    not null default now(),

  resolved_by uuid
    references auth.users(id)
    on delete set null,

  resolved_at timestamptz,

  resolution_notes text,

  created_at timestamptz
    not null default now(),

  updated_at timestamptz
    not null default now()
);

create index if not exists
approval_requests_company_status_idx
on public.approval_requests(
  company_id,
  status,
  requested_at desc
);

create index if not exists
approval_requests_reference_idx
on public.approval_requests(
  company_id,
  reference_type,
  reference_id
);

drop trigger if exists
approval_requests_updated_at
on public.approval_requests;

create trigger
approval_requests_updated_at
before update
on public.approval_requests
for each row
execute function public.set_updated_at();


create or replace function public.create_approval_request(
  target_company uuid,
  target_type text,
  target_reference_type text,
  target_reference_id uuid,
  target_title text,
  target_description text,
  target_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'approvals.create'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_type),
       ''
     ) is null
  then
    raise exception
      'Approval type is required';
  end if;

  if nullif(
       trim(target_title),
       ''
     ) is null
  then
    raise exception
      'Approval title is required';
  end if;

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
    trim(target_type),

    nullif(
      trim(target_reference_type),
      ''
    ),

    target_reference_id,

    trim(target_title),

    nullif(
      trim(target_description),
      ''
    ),

    coalesce(
      target_payload,
      '{}'::jsonb
    )
  )
  returning id
  into v_id;

  return v_id;
end;
$$;

revoke all
on function public.create_approval_request(
  uuid,
  text,
  text,
  uuid,
  text,
  text,
  jsonb
)
from public;

grant execute
on function public.create_approval_request(
  uuid,
  text,
  text,
  uuid,
  text,
  text,
  jsonb
)
to authenticated;


create or replace function public.resolve_approval_request(
  target_company uuid,
  target_request uuid,
  target_decision text,
  target_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

  update public.approval_requests
  set
    status = target_decision,

    resolved_by =
      auth.uid(),

    resolved_at =
      now(),

    resolution_notes =
      nullif(
        trim(target_notes),
        ''
      )
  where id =
        target_request

    and company_id =
        target_company

    and status =
        'pending';

  if not found then
    raise exception
      'Pending approval request not found';
  end if;
end;
$$;

revoke all
on function public.resolve_approval_request(
  uuid,
  uuid,
  text,
  text
)
from public;

grant execute
on function public.resolve_approval_request(
  uuid,
  uuid,
  text,
  text
)
to authenticated;


-- ============================================================
-- SALES RETURNS
-- ============================================================

create table if not exists public.sales_returns(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  return_number text not null,

  sales_invoice_id uuid not null
    references public.sales_invoices(id)
    on delete restrict,

  trader_id uuid not null
    references public.traders(id)
    on delete restrict,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  return_date date not null
    default current_date,

  status text not null default 'posted'
    check(
      status in (
        'posted',
        'cancelled'
      )
    ),

  currency text not null,

  subtotal numeric(18,2)
    not null default 0
    check(subtotal >= 0),

  discount_total numeric(18,2)
    not null default 0
    check(discount_total >= 0),

  total numeric(18,2)
    not null default 0
    check(total >= 0),

  notes text,

  journal_entry_id uuid
    references public.journal_entries(id)
    on delete restrict,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz
    not null default now(),

  unique(
    company_id,
    return_number
  )
);

create index if not exists
sales_returns_invoice_idx
on public.sales_returns(
  sales_invoice_id,
  return_date desc
);


create table if not exists public.sales_return_items(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  sales_return_id uuid not null
    references public.sales_returns(id)
    on delete cascade,

  sales_invoice_item_id uuid not null
    references public.sales_invoice_items(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  description text not null,

  unit text,

  quantity numeric(14,3)
    not null
    check(quantity > 0),

  unit_price numeric(18,2)
    not null
    check(unit_price >= 0),

  line_total numeric(18,2)
    not null
    check(line_total >= 0),

  created_at timestamptz
    not null default now()
);

create index if not exists
sales_return_items_return_idx
on public.sales_return_items(
  sales_return_id
);

create index if not exists
sales_return_items_invoice_item_idx
on public.sales_return_items(
  sales_invoice_item_id
);


-- ============================================================
-- PURCHASE RETURNS
-- ============================================================

create table if not exists public.purchase_returns(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  return_number text not null,

  purchase_invoice_id uuid not null
    references public.purchase_invoices(id)
    on delete restrict,

  supplier_id uuid not null
    references public.suppliers(id)
    on delete restrict,

  warehouse_id uuid not null
    references public.warehouses(id)
    on delete restrict,

  return_date date not null
    default current_date,

  status text not null default 'posted'
    check(
      status in (
        'posted',
        'cancelled'
      )
    ),

  currency text not null,

  inventory_cost_total numeric(18,2)
    not null default 0
    check(inventory_cost_total >= 0),

  total numeric(18,2)
    not null default 0
    check(total >= 0),

  notes text,

  journal_entry_id uuid
    references public.journal_entries(id)
    on delete restrict,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz
    not null default now(),

  unique(
    company_id,
    return_number
  )
);

create index if not exists
purchase_returns_invoice_idx
on public.purchase_returns(
  purchase_invoice_id,
  return_date desc
);


create table if not exists public.purchase_return_items(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  purchase_return_id uuid not null
    references public.purchase_returns(id)
    on delete cascade,

  purchase_invoice_item_id uuid not null
    references public.purchase_invoice_items(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  description text,

  quantity numeric(14,3)
    not null
    check(quantity > 0),

  unit_cost numeric(18,2)
    not null
    check(unit_cost >= 0),

  inventory_cost numeric(18,2)
    not null
    check(inventory_cost >= 0),

  line_total numeric(18,2)
    not null
    check(line_total >= 0),

  created_at timestamptz
    not null default now()
);

create index if not exists
purchase_return_items_return_idx
on public.purchase_return_items(
  purchase_return_id
);

create index if not exists
purchase_return_items_invoice_item_idx
on public.purchase_return_items(
  purchase_invoice_item_id
);


-- ============================================================
-- DOCUMENT NUMBERS
-- ============================================================

create or replace function public.next_sales_return_number(
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
$$;


create or replace function public.next_purchase_return_number(
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
$$;

revoke all
on function public.next_sales_return_number(
  uuid,
  date
)
from public, authenticated;

revoke all
on function public.next_purchase_return_number(
  uuid,
  date
)
from public, authenticated;


-- ============================================================
-- SALES INVOICE PAYMENT RECALC INCLUDING RETURNS
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
$$;

revoke all
on function public.recalc_sales_invoice_payment(uuid)
from public, authenticated;


-- ============================================================
-- SALES ORDER PAYMENT RECALC INCLUDING RETURNS
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
$$;

revoke all
on function public.recalc_sales_order_payment(uuid)
from public, authenticated;


-- ============================================================
-- PURCHASE INVOICE PAYMENT RECALC INCLUDING RETURNS
-- ============================================================

create or replace function public.recalc_purchase_invoice_payment(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.recalc_purchase_invoice_payment(uuid)
from public, authenticated;


-- ============================================================
-- CREATE SALES RETURN
-- payload:
-- [
--   {
--     "sales_invoice_item_id": "...",
--     "quantity": 2
--   }
-- ]
-- ============================================================

create or replace function public.create_sales_return(
  target_company uuid,
  target_invoice uuid,
  target_warehouse uuid,
  target_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_return uuid;
  v_number text;

  v_trader uuid;
  v_currency text;
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
    total,
    subtotal,
    discount_total
  into
    v_trader,
    v_currency,
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
    public.next_sales_return_number(
      target_company,
      coalesce(
        target_date,
        current_date
      )
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
        coalesce(
          target_date,
          current_date
        )::timestamptz
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
      coalesce(
        target_date,
        current_date
      ),
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
$$;

revoke all
on function public.create_sales_return(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
from public;

grant execute
on function public.create_sales_return(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- CREATE PURCHASE RETURN
-- payload:
-- [
--   {
--     "purchase_invoice_item_id": "...",
--     "quantity": 2
--   }
-- ]
-- ============================================================

create or replace function public.create_purchase_return(
  target_company uuid,
  target_invoice uuid,
  target_warehouse uuid,
  target_date date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
      'inventory.returns',
      'purchase_invoices.cancel'
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

    into
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
        v_unit_cost *
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
        v_unit_cost,
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
$$;

revoke all
on function public.create_purchase_return(
  uuid,
  uuid,
  uuid,
  date,
  text,
  jsonb
)
from public;

grant execute
on function public.create_purchase_return(
  uuid,
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

alter table public.approval_requests
enable row level security;

alter table public.sales_returns
enable row level security;

alter table public.sales_return_items
enable row level security;

alter table public.purchase_returns
enable row level security;

alter table public.purchase_return_items
enable row level security;


drop policy if exists
approval_requests_read
on public.approval_requests;

create policy approval_requests_read
on public.approval_requests
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'approvals.view'
  )
);


drop policy if exists
sales_returns_read
on public.sales_returns;

create policy sales_returns_read
on public.sales_returns
for select
to authenticated
using(
  public.has_any_permission(
    company_id,
    array[
      'returns.view',
      'sales_invoices.view',
      'inventory.returns',
      'reports.finance'
    ]::text[]
  )
);


drop policy if exists
sales_return_items_read
on public.sales_return_items;

create policy sales_return_items_read
on public.sales_return_items
for select
to authenticated
using(
  public.has_any_permission(
    company_id,
    array[
      'returns.view',
      'sales_invoices.view',
      'inventory.returns',
      'reports.finance'
    ]::text[]
  )
);


drop policy if exists
purchase_returns_read
on public.purchase_returns;

create policy purchase_returns_read
on public.purchase_returns
for select
to authenticated
using(
  public.has_any_permission(
    company_id,
    array[
      'returns.view',
      'purchase_invoices.view',
      'reports.finance'
    ]::text[]
  )
);


drop policy if exists
purchase_return_items_read
on public.purchase_return_items;

create policy purchase_return_items_read
on public.purchase_return_items
for select
to authenticated
using(
  public.has_any_permission(
    company_id,
    array[
      'returns.view',
      'purchase_invoices.view',
      'products.view_cost',
      'reports.finance'
    ]::text[]
  )
);


revoke insert, update, delete
on public.approval_requests,
   public.sales_returns,
   public.sales_return_items,
   public.purchase_returns,
   public.purchase_return_items
from authenticated;


grant select
on public.approval_requests,
   public.sales_returns,
   public.sales_return_items,
   public.purchase_returns,
   public.purchase_return_items
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists
audit_approval_requests
on public.approval_requests;

create trigger audit_approval_requests
after insert or update or delete
on public.approval_requests
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_sales_returns
on public.sales_returns;

create trigger audit_sales_returns
after insert or update or delete
on public.sales_returns
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_sales_return_items
on public.sales_return_items;

create trigger audit_sales_return_items
after insert or update or delete
on public.sales_return_items
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_purchase_returns
on public.purchase_returns;

create trigger audit_purchase_returns
after insert or update or delete
on public.purchase_returns
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_purchase_return_items
on public.purchase_return_items;

create trigger audit_purchase_return_items
after insert or update or delete
on public.purchase_return_items
for each row
execute function public.write_audit_log();

commit;