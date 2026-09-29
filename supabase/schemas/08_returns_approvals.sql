-- ======================================================================
-- المرتجعات والموافقات
-- مرتجعات البيع والشراء، طلبات الموافقة
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  return_number text not null,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  trader_id uuid not null references public.traders(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  return_date date default current_date not null,
  status text default 'posted'::text not null,
  currency text not null,
  subtotal numeric(18,2) default 0 not null,
  discount_total numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  reversal_journal_entry_id uuid references public.journal_entries(id) on delete set null,
  constraint sales_returns_company_id_return_number_key unique (company_id, return_number),
  constraint sales_returns_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint sales_returns_status_check check ((status = any (array['posted'::text, 'cancelled'::text, 'reversed'::text]))),
  constraint sales_returns_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_returns_total_check check ((total >= (0)::numeric))
);
create index sales_returns_company_status_idx on public.sales_returns using btree (company_id, status, return_date desc);
create index sales_returns_invoice_idx on public.sales_returns using btree (sales_invoice_id, return_date desc);

create table public.sales_return_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  sales_invoice_item_id uuid not null references public.sales_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  description text not null,
  unit text,
  quantity numeric(14,3) not null,
  unit_price numeric(18,4) not null,
  line_total numeric(18,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_return_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_return_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_return_items_unit_price_check check ((unit_price >= (0)::numeric))
);
create index sales_return_items_invoice_item_idx on public.sales_return_items using btree (sales_invoice_item_id);
create index sales_return_items_return_idx on public.sales_return_items using btree (sales_return_id);

create table public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  return_number text not null,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  return_date date default current_date not null,
  status text default 'posted'::text not null,
  currency text not null,
  inventory_cost_total numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  reversal_journal_entry_id uuid references public.journal_entries(id) on delete set null,
  constraint purchase_returns_company_id_return_number_key unique (company_id, return_number),
  constraint purchase_returns_inventory_cost_total_check check ((inventory_cost_total >= (0)::numeric)),
  constraint purchase_returns_status_check check ((status = any (array['posted'::text, 'cancelled'::text, 'reversed'::text]))),
  constraint purchase_returns_total_check check ((total >= (0)::numeric))
);
create index purchase_returns_company_status_idx on public.purchase_returns using btree (company_id, status, return_date desc);
create index purchase_returns_invoice_idx on public.purchase_returns using btree (purchase_invoice_id, return_date desc);

create table public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  description text,
  quantity numeric(14,3) not null,
  unit_cost numeric(18,4) not null,
  inventory_cost numeric(18,2) not null,
  line_total numeric(18,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint purchase_return_items_inventory_cost_check check ((inventory_cost >= (0)::numeric)),
  constraint purchase_return_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint purchase_return_items_quantity_check check ((quantity > (0)::numeric)),
  constraint purchase_return_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index purchase_return_items_invoice_item_idx on public.purchase_return_items using btree (purchase_invoice_item_id);
create index purchase_return_items_return_idx on public.purchase_return_items using btree (purchase_return_id);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  request_type text not null,
  reference_type text,
  reference_id uuid,
  title text not null,
  description text,
  payload jsonb default '{}'::jsonb not null,
  status text default 'pending'::text not null,
  requested_by uuid default auth.uid() references auth.users(id) on delete set null,
  requested_at timestamp with time zone default now() not null,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamp with time zone,
  resolution_notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint approval_requests_status_check check ((status = any (array['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);
create index approval_requests_company_status_idx on public.approval_requests using btree (company_id, status, requested_at desc);
create index approval_requests_reference_idx on public.approval_requests using btree (company_id, reference_type, reference_id);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

-- لما الزبون يرجّع بضاعة من فاتورة كان دافعها، جزء من دفعته بيتحرّر وبيصير رصيد إلو
-- (بينخصم تلقائي من فاتورته الجاية). كل تحرير إلو قيد خاص، لحتى إذا انعكست الدفعة ينعكس معها.
create table public.customer_payment_releases (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete restrict,
  allocation_id uuid references public.customer_payment_allocations(id) on delete set null,
  sales_return_id uuid not null references public.sales_returns(id) on delete restrict,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_amount numeric(20,2) not null check (payment_amount > 0),
  payment_currency text not null,
  created_at timestamp with time zone default now() not null
);
create index customer_payment_releases_payment_idx on public.customer_payment_releases using btree (payment_id);
create index customer_payment_releases_return_idx on public.customer_payment_releases using btree (sales_return_id);
revoke insert, update, delete on public.customer_payment_releases from authenticated;
alter table public.customer_payment_releases enable row level security;
create policy customer_payment_releases_read on public.customer_payment_releases
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'reports.finance'::text]));

create or replace function public.block_invoice_cancel_with_posted_return()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  if old.status = 'posted'
     and new.status = 'cancelled'
  then

    if tg_table_name =
       'sales_invoices'
    then

      if exists(
        select 1
        from public.sales_returns sr
        where sr.company_id =
              new.company_id
          and sr.sales_invoice_id =
              new.id
          and sr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted sales returns before cancelling sales invoice';
      end if;


    elsif tg_table_name =
          'purchase_invoices'
    then

      if exists(
        select 1
        from public.purchase_returns pr
        where pr.company_id =
              new.company_id
          and pr.purchase_invoice_id =
              new.id
          and pr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted purchase returns before cancelling purchase invoice';
      end if;

    end if;

  end if;

  return new;
end;
$function$;

create or replace function public.can_view_returns(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    public.has_any_permission(
      target_company,
      array[
        'returns.view',
        'returns.create',
        'inventory.returns',
        'returns.reverse'
      ]::text[]
    );
$function$;

create or replace function public.create_purchase_return(target_company uuid, target_invoice uuid, target_warehouse uuid, target_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_unit_cost numeric(18,4);
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
  v_stock_cost numeric(18,4);

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
        s.average_cost,
        0
      ),

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

    -- الكلفة لازم تنقرا مع الكمية: البضاعة بترجع للمورد بمتوسط كلفتها بالمستودع.
    into
      v_stock_cost,
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
        v_stock_cost *
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
        v_stock_cost,
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
$function$;

create or replace function public.create_sales_order_from_approved_payload(target_company uuid, target_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order uuid;
  v_trader uuid;
  v_notes text;
  v_items jsonb;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,4);
  v_total numeric(18,2) := 0;
begin
  v_trader := (target_payload->>'trader_id')::uuid;
  v_notes := target_payload->>'notes';
  v_items := target_payload->'items';

  if not exists(
    select 1 from public.traders
    where id=v_trader and company_id=target_company and status <> 'inactive'
  ) then raise exception 'Invalid trader'; end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items)=0 then
    raise exception 'Invalid approved order payload';
  end if;

  insert into public.sales_orders(company_id,trader_id,status,payment_status,notes)
  values(target_company,v_trader,'new','unpaid',nullif(btrim(v_notes),''))
  returning id into v_order;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_product := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::numeric;
    v_price := (v_item->>'sale_unit_price')::numeric;

    if v_quantity <= 0 or v_price < 0 or not exists(
      select 1 from public.products
      where id=v_product and company_id=target_company and active=true
    ) then raise exception 'Invalid approved order item'; end if;

    insert into public.sales_order_items(
      order_id,product_id,quantity,sale_unit_price,line_total
    ) values(
      v_order,v_product,v_quantity,v_price,round(v_quantity*v_price,2)
    );

    v_total := v_total + round(v_quantity*v_price,2);
  end loop;

  update public.sales_orders set subtotal=v_total,total=v_total where id=v_order;

  perform public.reserve_sales_order(target_company,v_order);

  return v_order;
end;
$function$;

create or replace function public.create_sales_return(target_company uuid, target_invoice uuid, target_warehouse uuid, target_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_return uuid;
  v_number text;

  v_trader uuid;
  v_currency text;

  v_invoice_date date;
  v_return_date date;
  v_today date;

  v_invoice_total numeric(18,2);
  v_invoice_subtotal numeric(18,2);
  v_invoice_discount numeric(18,2);

  v_item jsonb;
  v_invoice_item uuid;
  v_product uuid;
  v_description text;
  v_unit text;
  v_invoice_qty numeric(14,3);
  v_unit_price numeric(18,4);
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

  v_alloc record;
  v_to_free numeric(18,2);
  v_cut numeric(18,2);
  v_cut_pay numeric(20,2);
  v_release uuid;
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
    invoice_date,
    total,
    subtotal,
    discount_total
  into
    v_trader,
    v_currency,
    v_invoice_date,
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

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  v_return_date :=
    coalesce(
      target_date,
      v_today
    );

  if v_return_date <
     v_invoice_date
  then
    raise exception
      'Return date cannot be before invoice date';
  end if;

  if v_return_date >
     v_today
  then
    raise exception
      'Return date cannot be in the future';
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
      v_return_date
    );

  v_number :=
    public.next_sales_return_number(
      target_company,
      v_return_date
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
    v_return_date,
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
        (v_return_date::timestamp at time zone 'Asia/Damascus')
      );

    -- الزبون رجّع بضاعة خربانة: بتدخل وبتطلع فورًا كتالفة (ما بتنباع ولا بتنحجز).
    if coalesce((v_item->>'damaged')::boolean, false) then
      perform
        public.post_inventory_movement(
          target_company,
          target_warehouse,
          v_product,
          'damage',
          -v_qty,
          v_cost,
          'sales_returns',
          v_return,
          v_return_item,
          v_number,
          'تالف من مرتجع',
          (v_return_date::timestamp at time zone 'Asia/Damascus')
        );
    end if;

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

  -- الفاتورة مدفوعة (كلها أو قسم منها) أكتر من اللي ضل عليها بعد المرتجع:
  -- منحرّر الفرق من آخر دفعات انخصمت عليها، فبيصير رصيد للزبون بينخصم من فواتيره الجاية.
  v_to_free := v_credit_part;

  for v_alloc in
    select
      a.*,
      (
        select je.exchange_rate_to_base
        from public.journal_entries je
        where je.company_id = target_company
          and je.source_type = 'customer_payment_allocation'
          and je.source_id = a.id
          and je.reversed_from_id is null
        limit 1
      ) as journal_rate
    from public.customer_payment_allocations a
    join public.customer_payments p
      on p.id = a.payment_id
    where a.sales_invoice_id = target_invoice
      and p.status = 'posted'
    order by p.payment_date desc, p.created_at desc
    for update of a
  loop
    exit when v_to_free <= 0;

    v_cut := least(v_alloc.amount, v_to_free);

    v_cut_pay :=
      case
        when v_cut >= v_alloc.amount
          then coalesce(v_alloc.payment_amount, v_alloc.amount)
        else round(
          coalesce(v_alloc.payment_amount, v_alloc.amount) * v_cut / v_alloc.amount,
          2
        )
      end;

    insert into public.customer_payment_releases(
      company_id,
      payment_id,
      allocation_id,
      sales_return_id,
      sales_invoice_id,
      amount,
      payment_amount,
      payment_currency
    )
    values(
      target_company,
      v_alloc.payment_id,
      v_alloc.id,
      v_return,
      target_invoice,
      v_cut,
      v_cut_pay,
      coalesce(v_alloc.payment_currency, v_currency)
    )
    returning id
    into v_release;

    -- عكس جزء التخصيص: الذمة بترجع، ورصيد الزبون الدائن بيزيد (بنفس عملة وسعر الدفعة).
    perform
      public.post_system_journal(
        target_company,
        v_return_date,
        'تحرير دفعة بسبب مرتجع ' || v_number,
        coalesce(v_alloc.payment_currency, v_currency),
        v_alloc.journal_rate,
        'customer_payment_release',
        v_release,
        jsonb_build_array(
          jsonb_build_object(
            'account_id', v_ar_account,
            'debit', v_cut_pay,
            'credit', 0,
            'party_type', 'trader',
            'party_id', v_trader,
            'memo', 'تحرير دفعة'
          ),
          jsonb_build_object(
            'account_id', v_customer_advance,
            'debit', 0,
            'credit', v_cut_pay,
            'party_type', 'trader',
            'party_id', v_trader,
            'memo', 'رصيد دائن للعميل'
          )
        )
      );

    if v_cut >= v_alloc.amount then
      delete from public.customer_payment_allocations
      where id = v_alloc.id;
    else
      update public.customer_payment_allocations
      set
        amount = amount - v_cut,
        payment_amount = coalesce(payment_amount, amount) - v_cut_pay
      where id = v_alloc.id;
    end if;

    v_to_free := v_to_free - v_cut;
  end loop;

  -- اللي ما لقينالو دفعة (حالة نادرة) بيضل رصيد دائن مباشر متل قبل.
  v_credit_part := greatest(v_to_free, 0);
  v_ar_part := v_total - v_credit_part;

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
      v_return_date,
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
$function$;

create or replace function public.get_purchase_return_candidates(target_company uuid, target_search text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
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

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.purchase_invoices pi

  join public.suppliers s
    on s.id =
       pi.supplier_id

  where pi.company_id =
        target_company

    and pi.status =
        'posted'

    and (
      v_search is null

      or pi.invoice_number
         ilike
         '%' || v_search || '%'

      or coalesce(
           pi.supplier_invoice_number,
           ''
         )
         ilike
         '%' || v_search || '%'

      or s.name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.purchase_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = pi.id
          and pr.name ilike '%' || v_search || '%'
      )
    )

    and exists (
      select 1
      from public.purchase_invoice_items pii

      where pii.invoice_id =
            pi.id

        and pii.company_id =
            target_company

        and round(
              coalesce(
                (
                  select
                    sum(gri.quantity)

                  from public.goods_receipt_items gri

                  join public.goods_receipts gr
                    on gr.id =
                       gri.goods_receipt_id

                  where gri.purchase_invoice_item_id =
                        pii.id

                    and gr.company_id =
                        target_company

                    and gr.purchase_invoice_id =
                        pi.id

                    and gr.status =
                        'posted'
                ),
                0
              )
              -
              coalesce(
                (
                  select
                    sum(pri.quantity)

                  from public.purchase_return_items pri

                  join public.purchase_returns pr
                    on pr.id =
                       pri.purchase_return_id

                  where pri.purchase_invoice_item_id =
                        pii.id

                    and pr.company_id =
                        target_company

                    and pr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      pi.invoice_date
        as sort_date,

      pi.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          pi.id,

        'invoice_number',
          pi.invoice_number,

        'supplier_invoice_number',
          pi.supplier_invoice_number,

        'invoice_date',
          pi.invoice_date,

        'currency',
          pi.currency,

        'total',
          pi.total,

        'supplier',
          jsonb_build_object(
            'id',
              s.id,

            'name',
              s.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.purchase_invoices pi

    join public.suppliers s
      on s.id =
         pi.supplier_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'invoiced_quantity',
              x.invoiced_quantity,

            'received_quantity',
              x.received_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.received_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.received_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          pii.id,
          pii.product_id,
          pii.description,
          pii.quantity
            as invoiced_quantity,
          pii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(gri.quantity)

              from public.goods_receipt_items gri

              join public.goods_receipts gr
                on gr.id =
                   gri.goods_receipt_id

              where gri.purchase_invoice_item_id =
                    pii.id

                and gr.company_id =
                    target_company

                and gr.purchase_invoice_id =
                    pi.id

                and gr.status =
                    'posted'
            ),
            0
          ) as received_quantity,

          coalesce(
            (
              select
                sum(pri.quantity)

              from public.purchase_return_items pri

              join public.purchase_returns pr
                on pr.id =
                   pri.purchase_return_id

              where pri.purchase_invoice_item_id =
                    pii.id

                and pr.company_id =
                    target_company

                and pr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.purchase_invoice_items pii

        join public.products p
          on p.id =
             pii.product_id

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company
      ) x
    ) items
      on true

    where pi.company_id =
          target_company

      and pi.status =
          'posted'

      and (
        v_search is null

        or pi.invoice_number
           ilike
           '%' || v_search || '%'

        or coalesce(
             pi.supplier_invoice_number,
             ''
           )
           ilike
           '%' || v_search || '%'

        or s.name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.purchase_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = pi.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

      and exists (
        select 1
        from public.purchase_invoice_items pii

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company

          and round(
                coalesce(
                  (
                    select
                      sum(gri.quantity)

                    from public.goods_receipt_items gri

                    join public.goods_receipts gr
                      on gr.id =
                         gri.goods_receipt_id

                    where gri.purchase_invoice_item_id =
                          pii.id

                      and gr.company_id =
                          target_company

                      and gr.purchase_invoice_id =
                          pi.id

                      and gr.status =
                          'posted'
                  ),
                  0
                )
                -
                coalesce(
                  (
                    select
                      sum(pri.quantity)

                    from public.purchase_return_items pri

                    join public.purchase_returns pr
                      on pr.id =
                         pri.purchase_return_id

                    where pri.purchase_invoice_item_id =
                          pii.id

                      and pr.company_id =
                          target_company

                      and pr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      pi.invoice_date desc,
      pi.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_return_warehouses(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rows jsonb;
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

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            w.id,

          'name',
            w.name,

          'code',
            w.code,

          'is_default',
            w.is_default
        )
        order by
          w.is_default desc,
          w.name
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from public.warehouses w
  where w.company_id =
        target_company
    and w.active = true;

  return v_rows;
end;
$function$;

create or replace function public.get_returns_history(target_company uuid, target_search text DEFAULT NULL::text, target_kind text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_kind text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_kind :=
    case
      when target_kind in (
        'sales',
        'purchases'
      )
      then target_kind
      else null
    end;

  v_status :=
    case
      when target_status in (
        'posted',
        'reversed',
        'cancelled'
      )
      then target_status
      else null
    end;

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    count(*)::bigint
  into
    v_total
  from history h
  where (
      v_kind is null
      or h.kind =
         v_kind
    )
    and (
      v_status is null
      or h.status =
         v_status
    )
    and (
      v_search is null

      or h.return_number
         ilike
         '%' || v_search || '%'

      or h.invoice_number
         ilike
         '%' || v_search || '%'

      or h.party_name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.sales_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'sales'
          and x.sales_return_id = h.id
          and pr.name ilike '%' || v_search || '%'
      )

      or exists (
        select 1
        from public.purchase_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'purchases'
          and x.purchase_return_id = h.id
          and pr.name ilike '%' || v_search || '%'
      )
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            q.id,

          'kind',
            q.kind,

          'return_number',
            q.return_number,

          'invoice_number',
            q.invoice_number,

          'party_name',
            q.party_name,

          'warehouse_name',
            q.warehouse_name,

          'return_date',
            q.return_date,

          'status',
            q.status,

          'currency',
            q.currency,

          'total',
            q.total,

          'notes',
            q.notes,

          'created_at',
            q.created_at,

          'reversed_at',
            q.reversed_at,

          'reversal_reason',
            q.reversal_reason
        )
        order by
          q.return_date desc,
          q.created_at desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select *
    from history h
    where (
        v_kind is null
        or h.kind =
           v_kind
      )
      and (
        v_status is null
        or h.status =
           v_status
      )
      and (
        v_search is null

        or h.return_number
           ilike
           '%' || v_search || '%'

        or h.invoice_number
           ilike
           '%' || v_search || '%'

        or h.party_name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.sales_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'sales'
            and x.sales_return_id = h.id
            and pr.name ilike '%' || v_search || '%'
        )

        or exists (
          select 1
          from public.purchase_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'purchases'
            and x.purchase_return_id = h.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

    order by
      h.return_date desc,
      h.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_returns_summary(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sales_count bigint;
  v_purchase_count bigint;

  v_sales_posted bigint;
  v_purchase_posted bigint;

  v_sales_reversed bigint;
  v_purchase_reversed bigint;

  v_sales_totals jsonb;
  v_purchase_totals jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_sales_count,
    v_sales_posted,
    v_sales_reversed
  from public.sales_returns
  where company_id =
        target_company;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_purchase_count,
    v_purchase_posted,
    v_purchase_reversed
  from public.purchase_returns
  where company_id =
        target_company;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_sales_totals
  from (
    select
      upper(sr.currency)
        as currency,

      round(
        sum(sr.total),
        2
      ) as total

    from public.sales_returns sr

    where sr.company_id =
          target_company

      and sr.status =
          'posted'

    group by
      upper(sr.currency)
  ) x;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_purchase_totals
  from (
    select
      upper(pr.currency)
        as currency,

      round(
        sum(pr.total),
        2
      ) as total

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.status =
          'posted'

    group by
      upper(pr.currency)
  ) x;

  return
    jsonb_build_object(
      'sales_count',
        v_sales_count,

      'sales_posted_count',
        v_sales_posted,

      'sales_reversed_count',
        v_sales_reversed,

      'purchase_count',
        v_purchase_count,

      'purchase_posted_count',
        v_purchase_posted,

      'purchase_reversed_count',
        v_purchase_reversed,

      'sales_totals',
        v_sales_totals,

      'purchase_totals',
        v_purchase_totals
    );
end;
$function$;

create or replace function public.get_sales_return_candidates(target_company uuid, target_search text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
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

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.sales_invoices si

  join public.traders t
    on t.id =
       si.trader_id

  where si.company_id =
        target_company

    and si.status =
        'posted'

    and (
      v_search is null

      or si.invoice_number
         ilike
         '%' || v_search || '%'

      or t.name
         ilike
         '%' || v_search || '%'

      or exists (
        select 1
        from public.sales_orders so
        where so.id = si.order_id
          and so.order_number ilike '%' || v_search || '%'
      )

      or exists (
        select 1
        from public.sales_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = si.id
          and pr.name ilike '%' || v_search || '%'
      )
    )

    and exists (
      select 1
      from public.sales_invoice_items sii
      where sii.invoice_id =
            si.id
        and sii.company_id =
            target_company

        and round(
              sii.quantity -
              coalesce(
                (
                  select
                    sum(sri.quantity)

                  from public.sales_return_items sri

                  join public.sales_returns sr
                    on sr.id =
                       sri.sales_return_id

                  where sri.sales_invoice_item_id =
                        sii.id

                    and sr.company_id =
                        target_company

                    and sr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      si.invoice_date
        as sort_date,

      si.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          si.id,

        'invoice_number',
          si.invoice_number,

        'invoice_date',
          si.invoice_date,

        'currency',
          si.currency,

        'total',
          si.total,

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_invoices si

    join public.traders t
      on t.id =
         si.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'unit',
              x.unit,

            'invoiced_quantity',
              x.invoiced_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.invoiced_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.invoiced_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          sii.id,
          sii.product_id,
          sii.description,
          sii.unit,
          sii.quantity
            as invoiced_quantity,
          sii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(sri.quantity)

              from public.sales_return_items sri

              join public.sales_returns sr
                on sr.id =
                   sri.sales_return_id

              where sri.sales_invoice_item_id =
                    sii.id

                and sr.company_id =
                    target_company

                and sr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.sales_invoice_items sii

        join public.products p
          on p.id =
             sii.product_id

        where sii.invoice_id =
              si.id

          and sii.company_id =
              target_company
      ) x
    ) items
      on true

    where si.company_id =
          target_company

      and si.status =
          'posted'

      and (
        v_search is null

        or si.invoice_number
           ilike
           '%' || v_search || '%'

        or t.name
           ilike
           '%' || v_search || '%'

        or exists (
          select 1
          from public.sales_orders so
          where so.id = si.order_id
            and so.order_number ilike '%' || v_search || '%'
        )

        or exists (
          select 1
          from public.sales_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = si.id
            and pr.name ilike '%' || v_search || '%'
        )
      )

      and exists (
        select 1
        from public.sales_invoice_items sii
        where sii.invoice_id =
              si.id
          and sii.company_id =
              target_company

          and round(
                sii.quantity -
                coalesce(
                  (
                    select
                      sum(sri.quantity)

                    from public.sales_return_items sri

                    join public.sales_returns sr
                      on sr.id =
                         sri.sales_return_id

                    where sri.sales_invoice_item_id =
                          sii.id

                      and sr.company_id =
                          target_company

                      and sr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      si.invoice_date desc,
      si.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.next_purchase_return_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.next_sales_return_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.resolve_approval_request(target_company uuid, target_request uuid, target_decision text, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text;
  v_payload jsonb;
  v_reference_type text;
  v_reference_id uuid;
  v_order uuid;
  v_quote uuid;
  v_quote_status text;
  v_valid_until date;
begin
  if not public.has_permission(
    target_company,
    'approvals.resolve'
  ) and not public.use_owner_override(target_company, 'approve') then
    raise exception 'Not allowed';
  end if;

  if target_decision not in (
    'approved',
    'rejected'
  ) then
    raise exception
      'Invalid approval decision';
  end if;

  select
    request_type,
    payload,
    reference_type,
    reference_id

  into
    v_type,
    v_payload,
    v_reference_type,
    v_reference_id

  from public.approval_requests

  where id =
        target_request

    and company_id =
        target_company

    and status =
        'pending'

  for update;

  if not found then
    raise exception
      'Pending approval request not found';
  end if;

  if v_type =
     'below_cost_order'
  then

    v_quote :=
      nullif(
        v_payload->>'source_quote_id',
        ''
      )::uuid;

    if v_quote is not null then

      select
        q.status,
        q.valid_until

      into
        v_quote_status,
        v_valid_until

      from public.sales_quotes q

      where q.id =
            v_quote

        and q.company_id =
            target_company

      for update;

      if not found then
        raise exception
          'Quote not found';
      end if;

      if target_decision =
         'approved'
      then

        if v_quote_status <>
           'accepted'
        then
          raise exception
            'Quote is no longer accepted';
        end if;

        if v_valid_until is not null
           and v_valid_until <
               (
                 now()
                 at time zone
                 'Asia/Damascus'
               )::date
        then
          raise exception
            'Quote has expired';
        end if;

        perform
          public.validate_sales_quote_conversion_source(
            target_company,
            v_quote,
            (v_payload->>'trader_id')::uuid,
            v_payload->'items'
          );

      end if;

    end if;

    if target_decision =
       'approved'
    then

      v_order :=
        public.create_sales_order_from_approved_payload(
          target_company,
          v_payload
        );

      if v_quote is not null then
        update public.sales_quotes
        set
          status =
            'converted',

          converted_order_id =
            v_order

        where id =
              v_quote

          and company_id =
              target_company

          and converted_order_id
              is null;
      end if;

      v_payload :=
        coalesce(
          v_payload,
          '{}'::jsonb
        ) ||
        jsonb_build_object(
          'order_id',
          v_order
        );

      v_reference_type :=
        'sales_order';

      v_reference_id :=
        v_order;

    elsif v_quote is not null then

      update public.sales_quotes
      set status =
          'rejected'

      where id =
            v_quote

        and company_id =
            target_company

        and status =
            'accepted'

        and converted_order_id
            is null;

    end if;

  end if;

  update public.approval_requests
  set
    status =
      target_decision,

    resolved_by =
      auth.uid(),

    resolved_at =
      now(),

    resolution_notes =
      nullif(
        trim(
          target_notes
        ),
        ''
      ),

    payload =
      v_payload,

    reference_type =
      v_reference_type,

    reference_id =
      v_reference_id

  where id =
        target_request

    and company_id =
        target_company;
end;
$function$;

create or replace function public.reverse_purchase_return(target_company uuid, target_return uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_item record;
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) and not public.use_owner_override(target_company, 'reverse_return') then
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
    purchase_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.purchase_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Purchase return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted purchase returns can be reversed';
  end if;


  for v_item in

    select
      pri.id,
      pri.product_id,
      pri.quantity

    from public.purchase_return_items pri

    where pri.purchase_return_id =
          target_return

    order by pri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'purchase_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'purchase_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for purchase return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'purchase_receipt',
        v_item.quantity,
        v_cost,
        'purchase_return_reversals',
        target_return,
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

  end loop;


  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مشتريات ' ||
      v_number,
      'purchase_return_reversal',
      target_return
    );


  update public.purchase_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_purchase_invoice_payment(
      v_invoice
    );

end;
$function$;

create or replace function public.reverse_return_financial_journal(target_company uuid, target_original_journal uuid, target_currency text, target_description text, target_source_type text, target_source_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lines jsonb;
  v_entry uuid;
  v_reversal_date date;
begin
  if target_original_journal is null then
    raise exception
      'Return financial journal is missing';
  end if;


  select
    coalesce(
      jsonb_agg(
        jsonb_strip_nulls(
          jsonb_build_object(
            'account_id',
            coalesce(
              nullif(
                x->>'account_id',
                ''
              ),
              nullif(
                x->>'finance_account_id',
                ''
              )
            ),

            'debit',
            coalesce(
              nullif(
                x->>'credit',
                ''
              )::numeric,
              nullif(
                x->>'credit_amount',
                ''
              )::numeric,
              0
            ),

            'credit',
            coalesce(
              nullif(
                x->>'debit',
                ''
              )::numeric,
              nullif(
                x->>'debit_amount',
                ''
              )::numeric,
              0
            ),

            'party_type',
            nullif(
              x->>'party_type',
              ''
            ),

            'party_id',
            nullif(
              x->>'party_id',
              ''
            ),

            'memo',
            case
              when nullif(
                     x->>'memo',
                     ''
                   ) is not null
              then
                'عكس - ' ||
                (x->>'memo')
              else
                target_description
            end
          )
        )
      ),
      '[]'::jsonb
    )
  into v_lines
  from (
    select
      to_jsonb(jl) as x
    from public.journal_lines jl
    where
      coalesce(
        to_jsonb(jl)
          ->>'journal_entry_id',

        to_jsonb(jl)
          ->>'entry_id'
      ) =
      target_original_journal::text
  ) q;


  if jsonb_array_length(
       v_lines
     ) = 0
  then
    raise exception
      'Original journal lines not found';
  end if;


  if exists(
    select 1
    from jsonb_array_elements(
      v_lines
    ) line
    where nullif(
            line->>'account_id',
            ''
          ) is null
  ) then
    raise exception
      'Original journal contains an invalid account';
  end if;


  v_reversal_date :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  perform
    public.assert_finance_period_open(
      target_company,
      v_reversal_date
    );


  -- Signature used by the current accounting engine:
  --
  -- post_system_journal(
  --   company,
  --   entry_date,
  --   description,
  --   currency,
  --   exchange_rate,
  --   source_type,
  --   source_id,
  --   lines
  -- )

  execute
    'select public.post_system_journal(
       $1,$2,$3,$4,$5,$6,$7,$8
     )'
  into v_entry
  using
    target_company,
    v_reversal_date,
    target_description,
    upper(target_currency),
    null::numeric,
    target_source_type,
    target_source_id,
    v_lines;


  if v_entry is null then
    raise exception
      'Financial reversal journal was not created';
  end if;

  return v_entry;
end;
$function$;

create or replace function public.reverse_sales_return(target_company uuid, target_return uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_product record;
  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) and not public.use_owner_override(target_company, 'reverse_return') then
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
    sales_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.sales_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Sales return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted sales returns can be reversed';
  end if;


  -- ----------------------------------------------------------
  -- Validate the total quantity by product BEFORE changing
  -- anything.
  --
  -- We only remove AVAILABLE stock, never active reservations.
  -- ----------------------------------------------------------

  for v_product in

    select
      sri.product_id,
      sum(
        sri.quantity
      ) as quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    group by
      sri.product_id

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
                v_product.product_id

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
          v_product.product_id;


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
      v_product.quantity
    then
      raise exception
        'Cannot reverse sales return: returned stock was already reserved, transferred or used';
    end if;

  end loop;


  -- ----------------------------------------------------------
  -- Reverse every original return stock movement.
  -- ----------------------------------------------------------

  for v_item in

    select
      sri.id,
      sri.product_id,
      sri.quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    order by sri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'sales_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'sales_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for sales return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'sales_delivery',
        -v_item.quantity,
        v_cost,
        'sales_return_reversals',
        target_return,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

  end loop;


  -- ----------------------------------------------------------
  -- Reverse financial credit-note journal.
  -- Inventory accounting is already reversed by the inventory
  -- movements above.
  -- ----------------------------------------------------------

  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مبيعات ' ||
      v_number,
      'sales_return_reversal',
      target_return
    );


  update public.sales_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_sales_invoice_payment(
      v_invoice
    );

  -- الفاتورة رجعت عليها ذمة: إذا الزبون عندو رصيد (من دفعة محرّرة مثلًا) بينخصم فورًا.
  perform
    public.apply_customer_credit_to_invoice(
      v_invoice
    );

end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger approval_requests_updated_at before update on public.approval_requests for each row execute function public.set_updated_at();

create trigger audit_approval_requests after insert or delete or update on public.approval_requests for each row execute function public.write_audit_log();

create trigger block_purchase_invoice_cancel_with_return before update of status on public.purchase_invoices for each row execute function public.block_invoice_cancel_with_posted_return();

create trigger audit_purchase_return_items after insert or delete or update on public.purchase_return_items for each row execute function public.write_audit_log();

create trigger audit_purchase_returns after insert or delete or update on public.purchase_returns for each row execute function public.write_audit_log();

create trigger block_sales_invoice_cancel_with_return before update of status on public.sales_invoices for each row execute function public.block_invoice_cancel_with_posted_return();

create trigger audit_sales_return_items after insert or delete or update on public.sales_return_items for each row execute function public.write_audit_log();

create trigger audit_sales_returns after insert or delete or update on public.sales_returns for each row execute function public.write_audit_log();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;
alter table public.approval_requests enable row level security;
create policy approval_requests_read on public.approval_requests
  for select to authenticated
  using (public.has_permission(company_id, 'approvals.view'::text));
create policy purchase_return_items_read on public.purchase_return_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'purchase_invoices.view'::text, 'products.view_cost'::text, 'reports.finance'::text]));
create policy purchase_returns_read on public.purchase_returns
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'purchase_invoices.view'::text, 'reports.finance'::text]));
create policy sales_return_items_read on public.sales_return_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'sales_invoices.view'::text, 'inventory.returns'::text, 'reports.finance'::text]));
create policy sales_returns_read on public.sales_returns
  for select to authenticated
  using (public.has_any_permission(company_id, array['returns.view'::text, 'sales_invoices.view'::text, 'inventory.returns'::text, 'reports.finance'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.sales_returns from authenticated;
revoke insert, update, delete on public.sales_return_items from authenticated;
revoke select, insert, update, delete on public.purchase_returns from authenticated;
grant select (id, company_id, return_number, purchase_invoice_id, supplier_id, warehouse_id, return_date, status, currency, total, notes, journal_entry_id, created_by, created_at) on public.purchase_returns to authenticated;
revoke select, insert, update, delete on public.purchase_return_items from authenticated;
grant select (id, company_id, purchase_return_id, purchase_invoice_item_id, product_id, description, quantity, line_total, created_at) on public.purchase_return_items to authenticated;
revoke insert, update, delete on public.approval_requests from authenticated;
revoke execute on function public.can_view_returns(uuid) from authenticated;
revoke execute on function public.create_sales_order_from_approved_payload(uuid,jsonb) from authenticated;
revoke execute on function public.next_purchase_return_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_return_number(uuid,date) from authenticated;
revoke execute on function public.reverse_return_financial_journal(uuid,uuid,text,text,text,uuid) from authenticated;
