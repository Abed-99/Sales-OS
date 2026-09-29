-- ======================================================================
-- المبيعات
-- عروض الأسعار، الطلبيات، الحجز، التوصيل، فواتير البيع، قبض الزبائن
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  status text default 'new'::text not null,
  payment_status text default 'unpaid'::text not null,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  notes text,
  ordered_at timestamp with time zone default now() not null,
  delivered_at timestamp with time zone,
  paid_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  order_number text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_orders_company_order_number_key unique (company_id, order_number),
  constraint sales_orders_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text, 'credit'::text]))),
  constraint sales_orders_status_check check ((status = any (array['draft'::text, 'new'::text, 'to_purchase'::text, 'purchasing'::text, 'ready'::text, 'out_for_delivery'::text, 'delivered'::text, 'cancelled'::text])))
);
create index dashboard_sales_orders_delivered_idx on public.sales_orders using btree (company_id, delivered_at) where (status = 'delivered'::text);
create index dashboard_sales_orders_status_idx on public.sales_orders using btree (company_id, status);
create index sales_orders_company_idx on public.sales_orders using btree (company_id, created_at desc);
create index sales_orders_trader_idx on public.sales_orders using btree (trader_id, created_at desc);

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null,
  sale_unit_price numeric(18,4) not null,
  line_total numeric(14,2) default 0 not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_order_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_order_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_order_items_sale_unit_price_check check ((sale_unit_price >= (0)::numeric))
);
create index sales_order_items_order_idx on public.sales_order_items using btree (order_id);

create table public.sales_quotes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  quote_number text not null,
  quote_date date default current_date not null,
  valid_until date,
  status text default 'draft'::text not null,
  currency text not null,
  subtotal numeric(18,2) default 0 not null,
  total numeric(18,2) default 0 not null,
  notes text,
  accepted_at timestamp with time zone,
  converted_order_id uuid references public.sales_orders(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_quotes_company_id_quote_number_key unique (company_id, quote_number),
  constraint sales_quotes_status_check check ((status = any (array['draft'::text, 'sent'::text, 'accepted'::text, 'rejected'::text, 'cancelled'::text, 'converted'::text]))),
  constraint sales_quotes_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_quotes_total_check check ((total >= (0)::numeric))
);
create index sales_quotes_company_status_idx on public.sales_quotes using btree (company_id, status, quote_date desc);
create index sales_quotes_trader_idx on public.sales_quotes using btree (trader_id, quote_date desc);

create table public.sales_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.sales_quotes(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  sale_unit_price numeric(18,4) not null,
  line_total numeric(18,2) default 0 not null,
  minimum_sale_price_snapshot numeric(18,2),
  reference_cost_snapshot numeric(18,4),
  created_at timestamp with time zone default now() not null,
  constraint sales_quote_items_quote_id_product_id_key unique (quote_id, product_id),
  constraint sales_quote_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_quote_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_quote_items_sale_unit_price_check check ((sale_unit_price >= (0)::numeric))
);

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete cascade,
  quantity numeric(18,3) not null,
  status text default 'active'::text not null,
  created_at timestamp with time zone default now() not null,
  released_at timestamp with time zone,
  constraint inventory_reservations_warehouse_id_sales_order_item_id_key unique (warehouse_id, sales_order_item_id),
  constraint inventory_reservations_quantity_check check ((quantity > (0)::numeric)),
  constraint inventory_reservations_status_check check ((status = any (array['active'::text, 'released'::text, 'fulfilled'::text, 'cancelled'::text])))
);
create index inventory_reservations_product_idx on public.inventory_reservations using btree (company_id, product_id, status);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  status text default 'pending'::text not null,
  delivered_at timestamp with time zone,
  failed_at timestamp with time zone,
  failed_by uuid references auth.users(id) on delete set null,
  failure_reason text,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  delivery_number text,
  started_at timestamp with time zone,
  created_by uuid references auth.users(id) on delete set null,
  constraint deliveries_status_check check ((status = any (array['pending'::text, 'out_for_delivery'::text, 'delivered'::text, 'failed'::text])))
);
create unique index deliveries_number_unique on public.deliveries using btree (company_id, delivery_number) where (delivery_number is not null);
create index deliveries_order_idx on public.deliveries using btree (order_id, created_at desc);
create index deliveries_order_status_idx on public.deliveries using btree (company_id, order_id, status, created_at desc);

create table public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null,
  unit text,
  created_at timestamp with time zone default now() not null,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  constraint delivery_items_quantity_check check ((quantity > (0)::numeric))
);
create index delivery_items_delivery_idx on public.delivery_items using btree (delivery_id);
create unique index delivery_items_delivery_order_wh_unique on public.delivery_items using btree (delivery_id, sales_order_item_id, warehouse_id);
create index delivery_items_order_item_idx on public.delivery_items using btree (sales_order_item_id);

create table public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  order_id uuid not null references public.sales_orders(id) on delete restrict,
  invoice_number text not null,
  status text default 'posted'::text not null,
  payment_status text default 'unpaid'::text not null,
  currency text default 'USD'::text not null,
  invoice_date date default current_date not null,
  due_date date,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  paid_total numeric(14,2) default 0 not null,
  balance_due numeric(14,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone default now() not null,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint sales_invoices_company_id_invoice_number_key unique (company_id, invoice_number),
  constraint sales_invoices_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint sales_invoices_check check (((due_date is null) or (due_date >= invoice_date))),
  constraint sales_invoices_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint sales_invoices_paid_total_check check ((paid_total >= (0)::numeric)),
  constraint sales_invoices_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text]))),
  constraint sales_invoices_status_check check ((status = any (array['posted'::text, 'cancelled'::text]))),
  constraint sales_invoices_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint sales_invoices_total_check check ((total >= (0)::numeric))
);
create index dashboard_sales_invoices_posted_idx on public.sales_invoices using btree (company_id, posted_at) where (status = 'posted'::text);
create index sales_invoices_company_date_idx on public.sales_invoices using btree (company_id, invoice_date desc, created_at desc);
create index sales_invoices_due_idx on public.sales_invoices using btree (company_id, due_date) where ((status = 'posted'::text) and (payment_status <> 'paid'::text));
create index sales_invoices_order_idx on public.sales_invoices using btree (order_id, created_at desc);
create index sales_invoices_trader_date_idx on public.sales_invoices using btree (trader_id, invoice_date desc, created_at desc);

create table public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  sales_order_item_id uuid references public.sales_order_items(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  description text not null,
  unit text,
  quantity numeric(14,3) not null,
  unit_price numeric(18,4) not null,
  line_total numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  constraint sales_invoice_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint sales_invoice_items_quantity_check check ((quantity > (0)::numeric)),
  constraint sales_invoice_items_unit_price_check check ((unit_price >= (0)::numeric))
);
create index sales_invoice_items_invoice_idx on public.sales_invoice_items using btree (invoice_id);
create index sales_invoice_items_order_item_idx on public.sales_invoice_items using btree (sales_order_item_id) where (sales_order_item_id is not null);
create index sales_invoice_items_product_idx on public.sales_invoice_items using btree (company_id, product_id);

create table public.sales_invoice_delivery_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  delivery_id uuid not null references public.deliveries(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint sales_invoice_delivery_links_delivery_id_key unique (delivery_id)
);
create index sales_invoice_delivery_invoice_idx on public.sales_invoice_delivery_links using btree (sales_invoice_id);

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  payment_number text not null,
  status text default 'posted'::text not null,
  payment_date date default current_date not null,
  amount numeric(14,2) not null,
  allocated_total numeric(14,2) default 0 not null,
  unallocated_total numeric(14,2) default 0 not null,
  payment_method text default 'cash'::text not null,
  reference_number text,
  notes text,
  reversed_at timestamp with time zone,
  reversed_by uuid references auth.users(id) on delete set null,
  reversal_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  payment_currency text,
  exchange_rate_to_base numeric(30,18),
  base_amount numeric(20,4),
  constraint customer_payments_company_id_payment_number_key unique (company_id, payment_number),
  constraint customer_payments_amount_check check ((amount > (0)::numeric)),
  constraint customer_payments_check check (((allocated_total >= (0)::numeric) and (allocated_total <= amount))),
  constraint customer_payments_check1 check (((unallocated_total >= (0)::numeric) and (unallocated_total <= amount))),
  constraint customer_payments_check2 check (((allocated_total + unallocated_total) = amount)),
  constraint customer_payments_payment_method_check check ((payment_method = any (array['cash'::text, 'bank'::text, 'card'::text, 'check'::text, 'other'::text]))),
  constraint customer_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index customer_payments_company_date_idx on public.customer_payments using btree (company_id, payment_date desc, created_at desc);
create index customer_payments_currency_idx on public.customer_payments using btree (company_id, payment_currency, payment_date desc);
create index customer_payments_trader_date_idx on public.customer_payments using btree (trader_id, payment_date desc, created_at desc);

create table public.customer_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete restrict,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  payment_amount numeric(20,2),
  payment_currency text,
  invoice_currency text,
  payment_rate_to_base numeric(30,18),
  constraint customer_payment_allocations_payment_id_sales_invoice_id_key unique (payment_id, sales_invoice_id),
  constraint customer_payment_allocations_amount_check check ((amount > (0)::numeric))
);
create index customer_payment_allocations_invoice_idx on public.customer_payment_allocations using btree (sales_invoice_id);
create index customer_payment_allocations_payment_idx on public.customer_payment_allocations using btree (payment_id);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_customer_payment_fk foreign key (customer_payment_id) references public.customer_payments(id) on delete set null;
alter table public.cash_transactions
  add constraint cash_transactions_order_id_fkey foreign key (order_id) references public.sales_orders(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.apply_customer_credit_to_invoice(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_trader uuid;
  v_company uuid;
  v_balance numeric(20,2);
  v_invoice_currency text;

  v_payment record;
  v_apply numeric(20,2);
begin
  select
    trader_id,
    company_id,
    balance_due,
    upper(currency)

  into
    v_trader,
    v_company,
    v_balance,
    v_invoice_currency

  from public.sales_invoices

  where id =
        target_invoice
    and status =
        'posted';

  if v_trader is null
     or coalesce(
          v_balance,
          0
        ) <= 0
  then
    return;
  end if;


  for v_payment in

    select
      p.id,
      p.unallocated_total,
      upper(
        coalesce(
          p.payment_currency,
          cb.currency
        )
      ) as payment_currency

    from public.customer_payments p

    join public.cashboxes cb
      on cb.id =
         p.cashbox_id

    where p.company_id =
          v_company
      and p.trader_id =
          v_trader
      and p.status =
          'posted'
      and p.unallocated_total >
          0
      and upper(
            coalesce(
              p.payment_currency,
              cb.currency
            )
          ) =
          v_invoice_currency

    order by
      p.payment_date,
      p.created_at

  loop

    select balance_due
    into v_balance
    from public.sales_invoices
    where id =
          target_invoice
    for update;

    exit when
      coalesce(
        v_balance,
        0
      ) <= 0;

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
        amount,
        payment_amount,
        payment_currency,
        invoice_currency,
        payment_rate_to_base
      )
      values(
        v_company,
        v_payment.id,
        target_invoice,
        round(
          v_apply,
          2
        ),
        round(
          v_apply,
          2
        ),
        v_payment.payment_currency,
        v_invoice_currency,
        -- نفس سعر قيد القبض الأصلي (سعر يوم الدفعة)، مش 1، وإلا الليرة بتنحسب دولار.
        null
      )
      on conflict(
        payment_id,
        sales_invoice_id
      )
      do nothing;

    end if;

  end loop;
end;
$function$;

create or replace function public.apply_customer_payment_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_days integer := 0;
begin
  select
    coalesce(
      t.payment_terms_days,
      0
    )
  into v_days
  from public.traders t
  where t.id = new.trader_id
    and t.company_id =
        new.company_id;

  if new.due_date is null
     or new.due_date =
        new.invoice_date
  then
    new.due_date :=
      new.invoice_date +
      v_days;
  end if;

  return new;
end;
$function$;

create or replace function public.can_access_order(target_order uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.cancel_sales_invoice(target_company uuid, target_invoice uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_order uuid;
  v_number text;
  v_line record;
begin
  if not public.has_permission(
    target_company,
    'sales_invoices.cancel'
  ) and not public.use_owner_override(target_company, 'cancel_invoice') then
    raise exception 'Not allowed';
  end if;

  select
    status,
    order_id,
    invoice_number
  into
    v_status,
    v_order,
    v_number
  from public.sales_invoices
  where id = target_invoice
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Sales invoice not found';
  end if;

  if v_status =
     'cancelled'
  then
    return;
  end if;

  if exists(
    select 1
    from public.customer_payment_allocations a

    join public.customer_payments p
      on p.id =
         a.payment_id

    where a.sales_invoice_id =
          target_invoice

      and p.status =
          'posted'

      and a.amount > 0
  ) then
    raise exception
      'Reverse allocated customer payments before cancelling invoice';
  end if;

  update public.sales_invoices
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),

    cancellation_reason =
      coalesce(
        nullif(
          trim(target_reason),
          ''
        ),
        'Cancelled'
      )

  where id =
        target_invoice;

  -- إلغاء البيعة معناه ما صارت: البضاعة المسلّمة بترجع لمستودعها بنفس كلفة خروجها،
  -- والقيد التلقائي بيعكس كلفة البضاعة المباعة. (الفاتورة اللي عليها مرتجع ما بتنلغى أصلًا.)
  for v_line in
    select
      di.id,
      di.warehouse_id,
      di.product_id,
      di.quantity,
      m.unit_cost
    from public.sales_invoice_delivery_links l
    join public.delivery_items di
      on di.delivery_id = l.delivery_id
    left join public.inventory_movements m
      on m.source_table = 'deliveries'
     and m.source_line_id = di.id
     and m.movement_type = 'sales_delivery'
    where l.sales_invoice_id = target_invoice
  loop
    perform public.post_inventory_movement(
      target_company,
      v_line.warehouse_id,
      v_line.product_id,
      'sales_return',
      v_line.quantity,
      v_line.unit_cost,
      'sales_invoice_cancellations',
      target_invoice,
      v_line.id,
      v_number,
      'إلغاء فاتورة ' || v_number,
      now()
    );
  end loop;

  perform
    public.recalc_sales_order_payment(
      v_order
    );
end;
$function$;

create or replace function public.cancel_sales_order(target_company uuid, target_order uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.complete_order_delivery(target_company uuid, target_order uuid, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.convert_sales_quote_to_order(target_company uuid, target_quote uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_quote public.sales_quotes%rowtype;
  v_items jsonb;
begin
  if not public.has_permission(target_company,'orders.create') then
    raise exception 'Not allowed';
  end if;

  select * into v_quote
  from public.sales_quotes
  where id=target_quote and company_id=target_company
  for update;

  if not found then raise exception 'Quote not found'; end if;
  if v_quote.converted_order_id is not null or v_quote.status='converted' then
    return jsonb_build_object('status','created','order_id',v_quote.converted_order_id,'approval_id',null);
  end if;
  if v_quote.status <> 'accepted' then raise exception 'Quote must be accepted first'; end if;
  if v_quote.valid_until is not null and v_quote.valid_until < (now() at time zone 'Asia/Damascus')::date then
    raise exception 'Quote has expired';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'product_id',i.product_id,
      'quantity',i.quantity,
      'sale_unit_price',i.sale_unit_price
    ) order by i.created_at
  ) into v_items
  from public.sales_quote_items i
  where i.quote_id=target_quote;

  return public.create_sales_order_v2(
    target_company,
    v_quote.trader_id,
    v_quote.notes,
    v_items,
    target_quote
  );
end;
$function$;

create or replace function public.create_order_delivery(target_company uuid, target_order uuid, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.create_sales_order(target_company uuid, target_trader uuid, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order uuid;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(14,3);
  v_price numeric(18,4);
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
       and not public.use_owner_override(target_company, 'below_min')
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
$function$;

create or replace function public.create_sales_order_v2(target_company uuid, target_trader uuid, target_notes text, items_payload jsonb, target_source_quote uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,4);
  v_minimum numeric(18,2);
  v_cost numeric(18,4);
  v_threshold numeric(18,4);

  v_requires_approval boolean := false;

  v_details jsonb :=
    '[]'::jsonb;

  v_approval uuid;
  v_order uuid;
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
       where t.id =
             target_trader
         and t.company_id =
             target_company
         and t.status <>
             'inactive'
     )
  then
    raise exception
      'Invalid trader';
  end if;

  if target_source_quote is not null then
    perform
      public.validate_sales_quote_conversion_source(
        target_company,
        target_source_quote,
        target_trader,
        items_payload
      );
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
    group by
      x->>'product_id'
    having count(*) > 1
  ) then
    raise exception
      'Duplicate products are not allowed';
  end if;

  if target_source_quote is not null
     and not exists (
       select 1
       from public.sales_quotes q
       where q.id =
             target_source_quote
         and q.company_id =
             target_company
         and q.trader_id =
             target_trader
         and q.status =
             'accepted'
         and q.converted_order_id
             is null
         and (
           q.valid_until is null
           or
           q.valid_until >=
             current_date
         )
     )
  then
    raise exception
      'Invalid or unavailable source quote';
  end if;

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

    select
      p.minimum_sale_price
    into
      v_minimum
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

    v_cost :=
      public.product_reference_cost(
        target_company,
        v_product
      );

    v_threshold :=
      greatest(
        coalesce(
          v_minimum,
          0
        ),
        coalesce(
          v_cost,
          0
        )
      );

    if v_price <
       v_threshold
    then
      v_requires_approval :=
        true;

      v_details :=
        v_details ||
        jsonb_build_array(
          jsonb_build_object(
            'product_id',
            v_product,

            'sale_price',
            v_price,

            'minimum_sale_price',
            v_minimum,

            'reference_cost',
            v_cost,

            'required_minimum',
            v_threshold
          )
        );
    end if;
  end loop;

  if v_requires_approval
     and not public.has_permission(
       target_company,
       'orders.approve_discount'
     )
  then

    if target_source_quote is not null then
      select ar.id
      into v_approval
      from public.approval_requests ar
      where ar.company_id =
            target_company
        and ar.request_type =
            'below_cost_order'
        and ar.reference_type =
            'sales_quote'
        and ar.reference_id =
            target_source_quote
        and ar.status =
            'pending'
      order by
        ar.requested_at desc
      limit 1;
    end if;

    if v_approval is null then
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

        'below_cost_order',

        case
          when target_source_quote
               is null
            then 'sales_order_request'
          else 'sales_quote'
        end,

        target_source_quote,

        'موافقة بيع تحت التكلفة أو الحد الأدنى',

        'الطلب يحتوي على صنف بسعر أقل من التكلفة المرجعية أو الحد الأدنى المسموح.',

        jsonb_build_object(
          'trader_id',
          target_trader,

          'notes',
          target_notes,

          'items',
          items_payload,

          'source_quote_id',
          target_source_quote,

          'price_guard_details',
          v_details
        )
      )
      returning id
      into v_approval;
    end if;

    return
      jsonb_build_object(
        'status',
        'pending_approval',

        'order_id',
        null,

        'approval_id',
        v_approval
      );
  end if;

  v_order :=
    public.create_sales_order(
      target_company,
      target_trader,
      target_notes,
      items_payload
    );

  if target_source_quote is not null then
    update public.sales_quotes
    set
      status =
        'converted',

      converted_order_id =
        v_order

    where id =
          target_source_quote

      and company_id =
          target_company

      and status =
          'accepted'

      and converted_order_id
          is null;
  end if;

  return
    jsonb_build_object(
      'status',
      'created',

      'order_id',
      v_order,

      'approval_id',
      null
    );
end;
$function$;

create or replace function public.create_sales_quote(target_company uuid, target_trader uuid, target_valid_until date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_quote uuid;
  v_number text;
  v_currency text;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,4);
  v_minimum numeric(18,2);
  v_cost numeric(18,4);
  v_total numeric(18,2) := 0;
begin
  if not public.has_permission(target_company,'orders.create') then
    raise exception 'Not allowed';
  end if;

  if not exists(
    select 1 from public.traders
    where id = target_trader
      and company_id = target_company
      and status <> 'inactive'
  ) then
    raise exception 'Invalid trader';
  end if;

  if target_valid_until is not null and target_valid_until < (now() at time zone 'Asia/Damascus')::date then
    raise exception 'Quote validity date cannot be in the past';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0 then
    raise exception 'Quote must contain items';
  end if;

  if exists(
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception 'Duplicate products are not allowed';
  end if;

  select coalesce(default_currency,'USD')
  into v_currency
  from public.companies
  where id = target_company;

  v_number := public.next_sales_quote_number(target_company,(now() at time zone 'Asia/Damascus')::date);

  insert into public.sales_quotes(
    company_id,trader_id,quote_number,quote_date,valid_until,status,currency,notes
  ) values(
    target_company,target_trader,v_number,(now() at time zone 'Asia/Damascus')::date,target_valid_until,'draft',v_currency,
    nullif(btrim(target_notes),'')
  ) returning id into v_quote;

  for v_item in select value from jsonb_array_elements(items_payload)
  loop
    begin
      v_product := (v_item->>'product_id')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'sale_unit_price')::numeric;
    exception when others then
      raise exception 'Invalid quote item';
    end;

    if v_quantity <= 0 or v_price < 0 then
      raise exception 'Invalid quote item values';
    end if;

    select minimum_sale_price
    into v_minimum
    from public.products
    where id = v_product
      and company_id = target_company
      and active = true;

    if not found then
      raise exception 'Invalid or inactive product';
    end if;

    v_cost := public.product_reference_cost(target_company,v_product);

    insert into public.sales_quote_items(
      quote_id,product_id,quantity,sale_unit_price,line_total,
      minimum_sale_price_snapshot,reference_cost_snapshot
    ) values(
      v_quote,v_product,v_quantity,v_price,round(v_quantity*v_price,2),
      v_minimum,v_cost
    );

    v_total := v_total + round(v_quantity*v_price,2);
  end loop;

  update public.sales_quotes
  set subtotal = v_total,
      total = v_total
  where id = v_quote;

  return v_quote;
end;
$function$;

create or replace function public.customer_payment_allocation_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.customer_payment_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.enforce_sales_order_credit_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_limit numeric(14,2);
  v_receivables numeric(14,2);
  v_other_orders numeric(14,2);
  v_invoiced_for_order numeric(14,2);
  v_this_order numeric(14,2);
  v_exposure numeric(14,2);
begin
  if new.status = 'cancelled' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.trader_id = old.trader_id
       and coalesce(new.total,0) <=
           coalesce(old.total,0)
    then
      return new;
    end if;
  end if;

  select t.credit_limit
  into v_limit
  from public.traders t
  where t.id = new.trader_id
    and t.company_id = new.company_id;

  if v_limit is null then
    return new;
  end if;

  if public.has_permission(
    new.company_id,
    'orders.override_credit_limit'
  ) then
    return new;
  end if;

  select
    coalesce(
      sum(si.balance_due),
      0
    )
  into v_receivables
  from public.sales_invoices si
  where si.company_id = new.company_id
    and si.trader_id = new.trader_id
    and si.status = 'posted'
    and si.balance_due > 0;

  select
    coalesce(
      sum(
        greatest(
          so.total -
          coalesce(
            (
              select sum(si.total)
              from public.sales_invoices si
              where si.company_id =
                    new.company_id
                and si.order_id =
                    so.id
                and si.status =
                    'posted'
            ),
            0
          ),
          0
        )
      ),
      0
    )
  into v_other_orders
  from public.sales_orders so
  where so.company_id = new.company_id
    and so.trader_id = new.trader_id
    and so.status <> 'cancelled'
    and so.id <> new.id;

  select
    coalesce(
      sum(si.total),
      0
    )
  into v_invoiced_for_order
  from public.sales_invoices si
  where si.company_id =
        new.company_id
    and si.order_id =
        new.id
    and si.status =
        'posted';

  v_this_order :=
    greatest(
      coalesce(new.total,0) -
      v_invoiced_for_order,
      0
    );

  v_exposure :=
    round(
      v_receivables +
      v_other_orders +
      v_this_order,
      2
    );

  if v_exposure >
     v_limit + 0.01
     and not public.use_owner_override(new.company_id, 'credit_limit')
  then
    raise exception
      'تم تجاوز حد ائتمان العميل. الحد: %، الانكشاف بعد الطلب: %',
      round(v_limit,2),
      round(v_exposure,2);
  end if;

  return new;
end;
$function$;

create or replace function public.fail_order_delivery(target_company uuid, target_order uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_deliveries_summary(target_company uuid)
 RETURNS TABLE(ready_count bigint, road_count bigint, road_units numeric, remaining_units numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'deliveries.view',
      'deliveries.update'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    (
      select count(*)::bigint
      from public.sales_orders so
      where so.company_id =
            target_company
        and so.status =
            'ready'
    ),

    (
      select count(*)::bigint
      from public.sales_orders so
      where so.company_id =
            target_company
        and so.status =
            'out_for_delivery'
    ),

    (
      select round(
        coalesce(
          sum(di.quantity),
          0
        ),
        3
      )
      from public.delivery_items di
      join public.deliveries d
        on d.id =
           di.delivery_id
      where d.company_id =
            target_company
        and d.status =
            'out_for_delivery'
    ),

    (
      select round(
        coalesce(
          sum(
            greatest(
              soi.quantity -
              coalesce(
                delivered.qty,
                0
              ) -
              coalesce(
                active.qty,
                0
              ),
              0
            )
          ),
          0
        ),
        3
      )

      from public.sales_order_items soi

      join public.sales_orders so
        on so.id =
           soi.order_id

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
      ) delivered
        on true

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
              'out_for_delivery'
      ) active
        on true

      where so.company_id =
            target_company

        and so.status in (
          'ready',
          'out_for_delivery'
        )
    );
end;
$function$;

create or replace function public.get_delivery_queue(target_company uuid, target_search text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'deliveries.view',
      'deliveries.update'
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

  v_status :=
    case
      when target_status in (
        'ready',
        'out_for_delivery'
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

  select
    count(*)::bigint

  into
    v_total

  from public.sales_orders so

  join public.traders t
    on t.id =
       so.trader_id

  where so.company_id =
        target_company

    and so.status in (
      'ready',
      'out_for_delivery'
    )

    and (
      v_status is null
      or so.status =
         v_status
    )

    and (
      v_search is null

      or t.name ilike
         '%' || v_search || '%'

      or coalesce(
           t.phone,
           ''
         ) ilike
         '%' || v_search || '%'

      or coalesce(
           t.whatsapp,
           ''
         ) ilike
         '%' || v_search || '%'

      or coalesce(
           t.area,
           ''
         ) ilike
         '%' || v_search || '%'

      or so.id::text ilike
         '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date,
          sort_created
      ),
      '[]'::jsonb
    )

  into
    v_rows

  from (
    select
      coalesce(
        so.ordered_at,
        so.created_at
      ) as sort_date,

      so.created_at as sort_created,

      jsonb_build_object(
        'id',
          so.id,

        'order_number',
          so.order_number,

        'status',
          so.status,

        'payment_status',
          so.payment_status,

        'total',
          so.total,

        'created_at',
          so.created_at,

        'ordered_at',
          so.ordered_at,

        -- التوصيلة المفتوحة وسائقها (إذا في).
        'delivery',
          (
            select jsonb_build_object('id', d.id, 'driver_id', d.driver_id)
            from public.deliveries d
            where d.order_id = so.id
              and d.status in ('pending', 'out_for_delivery')
            order by d.created_at desc
            limit 1
          ),

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name,

            'area',
              t.area,

            'address',
              t.address,

            'phone',
              t.phone,

            'whatsapp',
              t.whatsapp,

            'latitude',
              t.latitude,

            'longitude',
              t.longitude
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_orders so

    join public.traders t
      on t.id =
         so.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              soi.id,

            'product_id',
              soi.product_id,

            'quantity',
              soi.quantity,

            'sale_unit_price',
              soi.sale_unit_price,

            'product_name',
              p.name,

            'sku',
              p.sku,

            'unit',
              p.unit,

            'delivered_quantity',
              coalesce(
                delivered.qty,
                0
              ),

            'active_quantity',
              coalesce(
                active.qty,
                0
              ),

            'remaining_quantity',
              greatest(
                soi.quantity -
                coalesce(
                  delivered.qty,
                  0
                ) -
                coalesce(
                  active.qty,
                  0
                ),
                0
              )
          )
          order by
            soi.created_at
        ) as payload

      from public.sales_order_items soi

      join public.products p
        on p.id =
           soi.product_id

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
      ) delivered
        on true

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
              'out_for_delivery'
      ) active
        on true

      where soi.order_id =
            so.id
    ) items
      on true

    where so.company_id =
          target_company

      and so.status in (
        'ready',
        'out_for_delivery'
      )

      and (
        v_status is null
        or so.status =
           v_status
      )

      and (
        v_search is null

        or t.name ilike
           '%' || v_search || '%'

        or coalesce(
             t.phone,
             ''
           ) ilike
           '%' || v_search || '%'

        or coalesce(
             t.whatsapp,
             ''
           ) ilike
           '%' || v_search || '%'

        or coalesce(
             t.area,
             ''
           ) ilike
           '%' || v_search || '%'

        or so.id::text ilike
           '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
      )

    order by
      coalesce(
        so.ordered_at,
        so.created_at
      ),
      so.created_at

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

create or replace function public.get_orders_summary(target_company uuid)
 RETURNS TABLE(total_count bigint, active_count bigint, new_count bigint, ready_delivery_count bigint, total_active_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'orders.view'
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    count(*)::bigint,

    count(*) filter (
      where so.status <>
            'cancelled'
    )::bigint,

    count(*) filter (
      where so.status =
            'new'
    )::bigint,

    count(*) filter (
      where so.status in (
        'ready',
        'out_for_delivery'
      )
    )::bigint,

    round(
      coalesce(
        sum(so.total)
        filter (
          where so.status <>
                'cancelled'
        ),
        0
      ),
      2
    )

  from public.sales_orders so
  where so.company_id =
        target_company;
end;
$function$;

create or replace function public.sales_quote_matches(target_quote uuid, target_search text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- البحث بعروض الأسعار بكل شي: رقم العرض، الزبون (اسم، منطقة، هاتف)، الملاحظات،
  -- المبلغ، أو اسم/كود/ماركة صنف موجود بالعرض.
  select exists (
    select 1
    from public.sales_quotes q
    join public.traders t on t.id = q.trader_id
    where q.id = target_quote
      and (
        q.quote_number ilike '%' || target_search || '%'
        or t.name ilike '%' || target_search || '%'
        or coalesce(t.area, '') ilike '%' || target_search || '%'
        or coalesce(t.phone, '') ilike '%' || target_search || '%'
        or coalesce(t.whatsapp, '') ilike '%' || target_search || '%'
        or coalesce(q.notes, '') ilike '%' || target_search || '%'
        or q.total = case
          when replace(target_search, ',', '') ~ '^[0-9]+([.][0-9]+)?$'
            then replace(target_search, ',', '')::numeric
        end
        or exists (
          select 1
          from public.sales_quote_items qi
          join public.products p on p.id = qi.product_id
          where qi.quote_id = q.id
            and (
              p.name ilike '%' || target_search || '%'
              or coalesce(p.sku, '') ilike '%' || target_search || '%'
              or coalesce(p.brand, '') ilike '%' || target_search || '%'
            )
        )
      )
  )
$function$;

create or replace function public.get_quotes_queue(target_company uuid, target_search text DEFAULT NULL::text, target_status text DEFAULT NULL::text, target_limit integer DEFAULT 50, target_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_search text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_today date;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_permission(
    target_company,
    'orders.view'
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

  v_status :=
    case
      when target_status in (
        'draft',
        'sent',
        'accepted',
        'rejected',
        'cancelled',
        'converted',
        'expired'
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

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  select
    count(*)::bigint

  into
    v_total

  from public.sales_quotes q

  join public.traders t
    on t.id =
       q.trader_id

  where q.company_id =
        target_company

    and (
      v_status is null

      or (
        v_status =
        'expired'

        and q.status in (
          'draft',
          'sent',
          'accepted'
        )

        and q.valid_until
            is not null

        and q.valid_until <
            v_today
      )

      or (
        v_status <>
        'expired'

        and q.status =
            v_status
      )
    )

    and (
        v_search is null
        or public.sales_quote_matches(q.id, v_search)
      );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_quote_date desc,
          sort_created_at desc
      ),
      '[]'::jsonb
    )

  into
    v_rows

  from (
    select
      q.quote_date
        as sort_quote_date,

      q.created_at
        as sort_created_at,

      jsonb_build_object(
        'id',
          q.id,

        'trader_id',
          q.trader_id,

        'quote_number',
          q.quote_number,

        'quote_date',
          q.quote_date,

        'valid_until',
          q.valid_until,

        'status',
          q.status,

        'currency',
          q.currency,

        'subtotal',
          q.subtotal,

        'total',
          q.total,

        'notes',
          q.notes,

        'accepted_at',
          q.accepted_at,

        'converted_order_id',
          q.converted_order_id,

        'created_at',
          q.created_at,

        'expired',
          (
            q.status in (
              'draft',
              'sent',
              'accepted'
            )
            and q.valid_until
                is not null
            and q.valid_until <
                v_today
          ),

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name,

            'area',
              t.area
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_quotes q

    join public.traders t
      on t.id =
         q.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              i.id,

            'product_id',
              i.product_id,

            'quantity',
              i.quantity,

            'sale_unit_price',
              i.sale_unit_price,

            'line_total',
              i.line_total,

            'product_name',
              p.name,

            'sku',
              p.sku,

            'unit',
              p.unit
          )
          order by
            i.created_at
        ) as payload

      from public.sales_quote_items i

      join public.products p
        on p.id =
           i.product_id

      where i.quote_id =
            q.id
    ) items
      on true

    where q.company_id =
          target_company

      and (
        v_status is null

        or (
          v_status =
          'expired'

          and q.status in (
            'draft',
            'sent',
            'accepted'
          )

          and q.valid_until
              is not null

          and q.valid_until <
              v_today
        )

        or (
          v_status <>
          'expired'

          and q.status =
              v_status
        )
      )

      and (
        v_search is null
        or public.sales_quote_matches(q.id, v_search)
      )

    order by
      q.quote_date desc,
      q.created_at desc

    limit v_limit
    offset v_offset
  ) q_rows;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$function$;

create or replace function public.get_quotes_summary(target_company uuid)
 RETURNS TABLE(all_count bigint, open_count bigint, accepted_count bigint, converted_count bigint, expired_open_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date;
begin
  if not public.has_permission(
    target_company,
    'orders.view'
  ) then
    raise exception 'Not allowed';
  end if;

  v_today :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  return query
  select
    count(*)::bigint,

    count(*) filter (
      where q.status in (
        'draft',
        'sent'
      )
    )::bigint,

    count(*) filter (
      where q.status =
            'accepted'
    )::bigint,

    count(*) filter (
      where q.status =
            'converted'
    )::bigint,

    count(*) filter (
      where q.status in (
        'draft',
        'sent',
        'accepted'
      )
        and q.valid_until
            is not null
        and q.valid_until <
            v_today
    )::bigint

  from public.sales_quotes q

  where q.company_id =
        target_company;
end;
$function$;

create or replace function public.get_trader_sales_summary(target_company uuid, target_trader uuid)
 RETURNS TABLE(invoice_count bigint, total_invoiced numeric, outstanding numeric, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'sales_invoices.view',
      'payments.sales_view',
      'payments.sales_create',
      'traders.view_balance',
      'reports.sales',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.traders t
    where t.id = target_trader
      and t.company_id = target_company
  ) then
    raise exception 'Trader not found';
  end if;

  select upper(
    coalesce(c.default_currency,'USD')
  )
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  return query
  select
    count(si.id)::bigint,

    round(
      coalesce(sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),0),
      2
    )::numeric,

    round(
      coalesce(sum((si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),0),
      2
    )::numeric,

    v_currency
  from public.sales_invoices si
  where si.company_id = target_company
    and si.trader_id = target_trader
    and si.status = 'posted';
end;
$function$;

create or replace function public.next_customer_payment_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.next_delivery_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.next_sales_invoice_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.next_sales_order_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer := extract(year from coalesce(target_date, current_date))::integer;
  v_value integer;
begin
  insert into public.document_sequences(company_id, document_type, sequence_year, next_value)
  values(target_company, 'sales_order', v_year, 1)
  on conflict(company_id, document_type, sequence_year) do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'sales_order'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'sales_order'
    and sequence_year = v_year;

  return 'SO-' || v_year::text || '-' || lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.assign_sales_order_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- كل طلبية بتاخد رقم مقروء (SO-2026-000001) بدل ما تنعرض بجزء من الـ UUID.
  if new.order_number is null then
    new.order_number := public.next_sales_order_number(
      new.company_id,
      (coalesce(new.ordered_at, now()) at time zone 'Asia/Damascus')::date
    );
  end if;
  return new;
end;
$function$;

create or replace function public.next_sales_quote_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer := extract(year from coalesce(target_date,current_date))::integer;
  v_value integer;
begin
  insert into public.document_sequences(company_id,document_type,sequence_year,next_value)
  values(target_company,'sales_quote',v_year,1)
  on conflict(company_id,document_type,sequence_year) do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'sales_quote'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'sales_quote'
    and sequence_year = v_year;

  return 'Q-' || v_year::text || '-' || lpad(v_value::text,6,'0');
end;
$function$;

-- أول فاتورة للزبون بتحوّلو من "جديد/تواصلنا/مهتم" لـ "عميل" تلقائيًا.
create or replace function public.promote_trader_on_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'posted' then
    update public.traders
    set status = 'customer'
    where id = new.trader_id
      and status in ('new', 'contacted', 'interested');
  end if;
  return new;
end;
$function$;

-- ----------------------------------------------------------------------
-- البيع السريع: زبون بالمحل بياخد البضاعة وبيدفع. طلبية + تسليم + فاتورة + قبض بخطوة وحدة.
-- ----------------------------------------------------------------------
create or replace function public.quick_sale(target_company uuid, target_trader uuid, items_payload jsonb, target_cashbox uuid, target_paid_amount numeric, target_cash_amount numeric, target_method text DEFAULT 'cash'::text, target_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_trader uuid := target_trader;
  v_item jsonb;
  v_needs_approval boolean := false;
  v_result jsonb;
  v_order uuid;
  v_status text;
  v_delivery_items jsonb;
  v_invoice uuid;
  v_total numeric(18,2);
  v_currency text;
  v_paid numeric(18,2) := round(coalesce(target_paid_amount, 0), 2);
  v_today date := (now() at time zone 'Asia/Damascus')::date;
begin
  if not public.has_any_permission(target_company, array['sales.quick_sale']) then
    raise exception 'Not allowed';
  end if;

  if items_payload is null or jsonb_typeof(items_payload) <> 'array' or jsonb_array_length(items_payload) = 0 then
    raise exception 'Quick sale requires items';
  end if;

  -- أي سعر تحت الكلفة أو أقل سعر: بدها صلاحية الخصم أو رمز المالك (بدون ما نعمل طلب موافقة معلّق).
  for v_item in select value from jsonb_array_elements(items_payload) loop
    if (v_item->>'sale_unit_price')::numeric < (
      select greatest(coalesce(p.minimum_sale_price, 0), coalesce(public.product_reference_cost(target_company, p.id), 0))
      from public.products p
      where p.id = (v_item->>'product_id')::uuid and p.company_id = target_company
    ) then
      v_needs_approval := true;
    end if;
  end loop;

  if v_needs_approval
     and not public.has_permission(target_company, 'orders.approve_discount')
     and not public.use_owner_override(target_company, 'approve')
  then
    raise exception 'Owner approval required for this price';
  end if;

  perform set_config('app.elevated_company', target_company::text, true);
  perform set_config(
    'app.elevated_permissions',
    'orders.create,deliveries.update,payments.sales_create'
      || case when v_needs_approval then ',orders.approve_discount' else '' end,
    true
  );

  -- بدون زبون: "زبون نقدي" (بينعمل مرة وحدة لكل شركة).
  if v_trader is null then
    select id into v_trader
    from public.traders
    where company_id = target_company and name = 'زبون نقدي'
    limit 1;

    if v_trader is null then
      insert into public.traders(company_id, name, status, notes)
      values (target_company, 'زبون نقدي', 'customer', 'للبيع السريع بدون اسم')
      returning id into v_trader;
    end if;
  end if;

  v_result := public.create_sales_order_v2(target_company, v_trader, target_notes, items_payload, null);
  v_order := nullif(v_result->>'order_id', '')::uuid;

  if v_order is null then
    raise exception 'Quick sale could not create the order';
  end if;

  select status into v_status from public.sales_orders where id = v_order;

  if v_status <> 'ready' then
    raise exception 'Not enough stock for quick sale';
  end if;

  select jsonb_agg(jsonb_build_object('sales_order_item_id', soi.id, 'quantity', soi.quantity))
  into v_delivery_items
  from public.sales_order_items soi
  where soi.order_id = v_order;

  perform public.create_order_delivery(target_company, v_order, v_delivery_items);
  v_invoice := public.complete_order_delivery(target_company, v_order, 'بيع سريع');

  select total, currency into v_total, v_currency from public.sales_invoices where id = v_invoice;

  if v_paid > v_total then
    raise exception 'Paid amount exceeds invoice total';
  end if;

  if v_paid > 0 then
    perform public.record_customer_payment(
      target_company,
      v_trader,
      target_cashbox,
      round(coalesce(target_cash_amount, v_paid), 2),
      v_today,
      coalesce(target_method, 'cash'),
      null,
      'بيع سريع',
      jsonb_build_array(jsonb_build_object('sales_invoice_id', v_invoice, 'amount', v_paid))
    );
  end if;

  return jsonb_build_object(
    'status', 'done',
    'order_id', v_order,
    'order_number', (select order_number from public.sales_orders where id = v_order),
    'invoice_id', v_invoice,
    'total', v_total,
    'currency', v_currency,
    'paid', v_paid
  );
end;
$function$;

create or replace function public.recalc_sales_invoice_payment(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.recalc_sales_order(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.recalc_sales_order_payment(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.record_customer_payment(target_company uuid, target_trader uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text, allocations_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;

  v_method text;

  v_base_currency text;
  v_payment_currency text;
  v_payment_rate numeric(30,18);
  v_base_amount numeric(20,4);

  v_allocation jsonb;

  v_invoice uuid;
  v_alloc_amount numeric(20,2);
  v_payment_alloc_amount numeric(20,2);

  v_balance numeric(20,2);
  v_invoice_status text;
  v_invoice_trader uuid;
  v_invoice_currency text;
  v_order uuid;

  v_allocated_payment_sum numeric(20,2) := 0;

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
    raise exception
      'Invalid payment amount';
  end if;

  if not exists(
    select 1
    from public.traders
    where id =
          target_trader
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid trader';
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
    raise exception
      'Invalid payment method';
  end if;

  target_payment_date :=
    coalesce(
      target_payment_date,
      current_date
    );

  if target_cashbox is not null then

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.id =
          target_cashbox
      and cb.company_id =
          target_company
      and cb.active = true;

  else

    select
      cb.id,
      upper(cb.currency),
      upper(c.default_currency)

    into
      v_cashbox,
      v_payment_currency,
      v_base_currency

    from public.cashboxes cb

    join public.companies c
      on c.id =
         cb.company_id

    where cb.company_id =
          target_company
      and cb.active = true

    order by
      case
        when upper(cb.currency) =
             upper(c.default_currency)
          then 0
        else 1
      end,
      cb.created_at

    limit 1;

  end if;

  if v_cashbox is null then
    raise exception
      'No valid active cashbox';
  end if;

  v_payment_rate :=
    public.finance_rate_to_base(
      target_company,
      v_payment_currency,
      target_payment_date
    );

  v_base_amount :=
    round(
      target_amount *
      v_payment_rate,
      4
    );

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
    notes,
    payment_currency,
    exchange_rate_to_base,
    base_amount
  )
  values(
    target_company,
    target_trader,
    v_cashbox,
    v_number,
    'posted',
    target_payment_date,
    round(
      target_amount,
      2
    ),
    0,
    round(
      target_amount,
      2
    ),
    v_method,
    nullif(
      trim(target_reference),
      ''
    ),
    nullif(
      trim(target_notes),
      ''
    ),
    v_payment_currency,
    v_payment_rate,
    v_base_amount
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

    begin
      v_invoice :=
        nullif(
          v_allocation ->
          'sales_invoice_id' #>> '{}',
          ''
        )::uuid;

      v_alloc_amount :=
        nullif(
          v_allocation ->
          'amount' #>> '{}',
          ''
        )::numeric;
    exception
      when others then
        raise exception
          'Invalid payment allocation';
    end;

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
      upper(currency),
      order_id

    into
      v_balance,
      v_invoice_status,
      v_invoice_trader,
      v_invoice_currency,
      v_order

    from public.sales_invoices

    where id =
          v_invoice
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
        'Cannot pay cancelled or unposted invoice';
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
       ) >
       round(
         v_balance,
         2
       )
    then
      raise exception
        'Allocation exceeds invoice balance';
    end if;


    if v_invoice_currency =
       v_payment_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount,
          2
        );

    elsif v_invoice_currency =
          v_base_currency
    then

      v_payment_alloc_amount :=
        round(
          v_alloc_amount /
          v_payment_rate,
          2
        );

    else

      raise exception
        'Cross-currency settlement currently requires invoice currency to be company base currency';

    end if;


    v_allocated_payment_sum :=
      round(
        v_allocated_payment_sum +
        v_payment_alloc_amount,
        2
      );

    if v_allocated_payment_sum >
       round(
         target_amount,
         2
       ) + 0.01
    then
      raise exception
        'Allocations exceed payment amount after currency conversion';
    end if;


    insert into public.customer_payment_allocations(
      company_id,
      payment_id,
      sales_invoice_id,
      amount,
      payment_amount,
      payment_currency,
      invoice_currency,
      payment_rate_to_base
    )
    values(
      target_company,
      v_payment,
      v_invoice,
      round(
        v_alloc_amount,
        2
      ),
      v_payment_alloc_amount,
      v_payment_currency,
      v_invoice_currency,
      v_payment_rate
    );


    v_allocation_count :=
      v_allocation_count + 1;

    if v_allocation_count = 1 then
      v_single_order :=
        v_order;

    elsif v_single_order is distinct from
          v_order
    then
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
    round(
      target_amount,
      2
    ),
    v_single_order,
    target_trader,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'قبض عميل ' ||
      v_number
    ),
    target_payment_date::timestamptz
  );

  return v_payment;
end;
$function$;

create or replace function public.refresh_customer_payment_totals(target_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_amount numeric(20,2);
  v_allocated numeric(20,2);
begin
  select amount
  into v_amount
  from public.customer_payments
  where id =
        target_payment
  for update;

  if v_amount is null then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          coalesce(
            payment_amount,
            amount
          )
        ),
        0
      ),
      2
    )
  into v_allocated
  from public.customer_payment_allocations
  where payment_id =
        target_payment;

  if v_allocated >
     round(
       v_amount,
       2
     ) + 0.01
  then
    raise exception
      'Payment allocations exceed cash payment amount';
  end if;

  update public.customer_payments
  set
    allocated_total =
      round(
        v_allocated,
        2
      ),

    unallocated_total =
      greatest(
        round(
          v_amount -
          v_allocated,
          2
        ),
        0
      )

  where id =
        target_payment;
end;
$function$;

create or replace function public.refresh_sales_order_inventory_status(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.reserve_pending_orders_for_product(target_company uuid, target_warehouse uuid, target_product uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.reserve_sales_order(target_company uuid, target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.reverse_customer_payment(target_company uuid, target_payment uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ) and not public.use_owner_override(target_company, 'reverse_payment') then
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
    'customer_payment_reversal',
    v_amount,
    v_trader,
    target_payment,
    'عكس دفعة تاجر ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$function$;

create or replace function public.sales_order_items_recalc_after_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    perform public.recalc_sales_order(old.order_id);
    return old;
  end if;

  perform public.recalc_sales_order(new.order_id);
  return new;
end;
$function$;

create or replace function public.set_sales_order_item_line_total()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.line_total := round(new.quantity * new.sale_unit_price, 2);
  return new;
end;
$function$;

create or replace function public.set_sales_quote_status(target_company uuid, target_quote uuid, target_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current text;
  v_valid_until date;
begin
  if not public.has_permission(
    target_company,
    'orders.update'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_status not in (
    'sent',
    'accepted',
    'rejected',
    'cancelled'
  ) then
    raise exception 'Invalid quote status';
  end if;

  select
    status,
    valid_until
  into
    v_current,
    v_valid_until
  from public.sales_quotes
  where id = target_quote
    and company_id = target_company
  for update;

  if not found then
    raise exception 'Quote not found';
  end if;

  if v_current = 'draft' then

    if target_status not in (
      'sent',
      'cancelled'
    ) then
      raise exception
        'Invalid quote status transition';
    end if;

  elsif v_current = 'sent' then

    if target_status not in (
      'accepted',
      'rejected',
      'cancelled'
    ) then
      raise exception
        'Invalid quote status transition';
    end if;

  elsif v_current = 'accepted' then

    if target_status <> 'cancelled' then
      raise exception
        'Invalid quote status transition';
    end if;

  else
    raise exception
      'Quote status cannot be changed';
  end if;

  if target_status = 'accepted'
     and v_valid_until is not null
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

  update public.sales_quotes
  set
    status =
      target_status,

    accepted_at =
      case
        when target_status =
             'accepted'
          then now()
        else accepted_at
      end

  where id =
        target_quote

    and company_id =
        target_company;
end;
$function$;

create or replace function public.validate_sales_quote_conversion_source(target_company uuid, target_quote uuid, target_trader uuid, items_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_trader uuid;
  v_valid_until date;
  v_converted uuid;
  v_expected jsonb;
  v_actual jsonb;
begin
  select
    q.status,
    q.trader_id,
    q.valid_until,
    q.converted_order_id
  into
    v_status,
    v_trader,
    v_valid_until,
    v_converted
  from public.sales_quotes q
  where q.id = target_quote
    and q.company_id = target_company
  for update;

  if not found then
    raise exception 'Quote not found';
  end if;

  if v_converted is not null
     or v_status = 'converted'
  then
    raise exception 'Quote already converted';
  end if;

  if v_status <> 'accepted' then
    raise exception
      'Quote must be accepted first';
  end if;

  if v_valid_until is not null
     and v_valid_until <
         (
           now()
           at time zone
           'Asia/Damascus'
         )::date
  then
    raise exception 'Quote has expired';
  end if;

  if v_trader <> target_trader then
    raise exception
      'Quote trader mismatch';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception
      'Invalid quote order payload';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'product_id',
          i.product_id,

        'quantity',
          i.quantity,

        'sale_unit_price',
          i.sale_unit_price
      )
      order by
        i.product_id::text
    )
  into
    v_expected
  from public.sales_quote_items i
  where i.quote_id =
        target_quote;

  begin
    select
      jsonb_agg(
        jsonb_build_object(
          'product_id',
            (x->>'product_id')::uuid,

          'quantity',
            (x->>'quantity')::numeric,

          'sale_unit_price',
            (x->>'sale_unit_price')::numeric
        )
        order by
          (x->>'product_id')
      )
    into
      v_actual
    from jsonb_array_elements(
      items_payload
    ) x;

  exception
    when others then
      raise exception
        'Invalid quote order payload';
  end;

  if v_expected is null
     or v_actual is null
     or v_expected <> v_actual
  then
    raise exception
      'Order payload does not match quote';
  end if;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.inventory_summary as
 select s.company_id,
    s.warehouse_id,
    w.name as warehouse_name,
    s.product_id,
    p.sku,
    p.name as product_name,
    p.unit,
    round(s.on_hand, 3) as on_hand,
    round(coalesce(( select sum(r.quantity) as sum
           from public.inventory_reservations r
          where r.company_id = s.company_id and r.warehouse_id = s.warehouse_id and r.product_id = s.product_id and r.status = 'active'::text), 0::numeric), 3) as reserved,
    round(greatest(s.on_hand - coalesce(( select sum(r.quantity) as sum
           from public.inventory_reservations r
          where r.company_id = s.company_id and r.warehouse_id = s.warehouse_id and r.product_id = s.product_id and r.status = 'active'::text), 0::numeric), 0::numeric), 3) as available,
        case
            when public.can_view_inventory_cost(s.company_id) then round(s.average_cost, 4)
            else null::numeric
        end as average_cost,
        case
            when public.can_view_inventory_cost(s.company_id) then round(s.on_hand * s.average_cost, 2)
            else null::numeric
        end as stock_value,
    s.updated_at
   from public.inventory_stock s
     join public.warehouses w on w.id = s.warehouse_id
     join public.products p on p.id = s.product_id
  where public.has_any_permission(s.company_id, array['inventory.view'::text, 'inventory.adjust'::text, 'inventory.returns'::text, 'purchases.view'::text, 'purchase_invoices.view'::text, 'reports.finance'::text, 'reports.profit'::text]);


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger sales_orders_assign_number before insert on public.sales_orders for each row execute function public.assign_sales_order_number();
create trigger promote_trader_on_invoice after insert on public.sales_invoices for each row execute function public.promote_trader_on_invoice();

create trigger audit_customer_payment_allocations after insert or delete or update on public.customer_payment_allocations for each row execute function public.write_audit_log();

create trigger customer_payment_allocation_changed_trigger after insert or delete or update on public.customer_payment_allocations for each row execute function public.customer_payment_allocation_changed();

create trigger audit_customer_payments after insert or delete or update on public.customer_payments for each row execute function public.write_audit_log();

create trigger customer_payment_status_changed_trigger after update of status on public.customer_payments for each row execute function public.customer_payment_status_changed();

create trigger customer_payments_updated_at before update on public.customer_payments for each row execute function public.set_updated_at();

create trigger audit_deliveries after insert or delete or update on public.deliveries for each row execute function public.write_audit_log();

create trigger deliveries_updated_at before update on public.deliveries for each row execute function public.set_updated_at();

create trigger audit_inventory_reservations after insert or delete or update on public.inventory_reservations for each row execute function public.write_audit_log();

create trigger audit_sales_invoice_items after insert or delete or update on public.sales_invoice_items for each row execute function public.write_audit_log();

create trigger audit_sales_invoices after insert or delete or update on public.sales_invoices for each row execute function public.write_audit_log();

create trigger sales_invoice_payment_terms before insert on public.sales_invoices for each row execute function public.apply_customer_payment_terms();

create trigger sales_invoices_updated_at before update on public.sales_invoices for each row execute function public.set_updated_at();

create trigger sales_order_items_line_total_before before insert or update of quantity, sale_unit_price on public.sales_order_items for each row execute function public.set_sales_order_item_line_total();

create trigger sales_order_items_recalc_after after insert or delete or update on public.sales_order_items for each row execute function public.sales_order_items_recalc_after_trigger();

create trigger audit_sales_orders after insert or delete or update on public.sales_orders for each row execute function public.write_audit_log();

create trigger sales_orders_credit_limit_guard before insert or update of trader_id, total on public.sales_orders for each row execute function public.enforce_sales_order_credit_limit();

create trigger sales_orders_updated_at before update on public.sales_orders for each row execute function public.set_updated_at();

create trigger audit_sales_quotes after insert or delete or update on public.sales_quotes for each row execute function public.write_audit_log();

create trigger sales_quotes_updated_at before update on public.sales_quotes for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.sales_quotes enable row level security;
alter table public.sales_quote_items enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_items enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;
alter table public.sales_invoice_delivery_links enable row level security;
alter table public.customer_payments enable row level security;
alter table public.customer_payment_allocations enable row level security;
create policy customer_payment_allocations_read on public.customer_payment_allocations
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'reports.finance'::text]));
create policy customer_payments_read on public.customer_payments
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.sales_view'::text, 'traders.view_balance'::text, 'finance.cashbox_view'::text, 'finance.accounts_view'::text, 'reports.finance'::text]));
create policy deliveries_read on public.deliveries
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'deliveries.update'::text]));
create policy delivery_items_read on public.delivery_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'deliveries.update'::text, 'orders.view'::text, 'sales_invoices.view'::text]));
create policy inventory_reservations_read on public.inventory_reservations
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'orders.view'::text, 'deliveries.view'::text]));
create policy sales_invoice_delivery_links_read on public.sales_invoice_delivery_links
  for select to authenticated
  using (public.has_any_permission(company_id, array['deliveries.view'::text, 'orders.view'::text, 'sales_invoices.view'::text, 'payments.sales_view'::text]));
create policy sales_invoice_items_read on public.sales_invoice_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['sales_invoices.view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'traders.view_balance'::text, 'reports.sales'::text, 'reports.profit'::text]));
create policy sales_invoices_read on public.sales_invoices
  for select to authenticated
  using (public.has_any_permission(company_id, array['sales_invoices.view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'traders.view_balance'::text, 'reports.sales'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy sales_order_items_read on public.sales_order_items
  for select to authenticated
  using (public.can_access_order(order_id));
create policy sales_orders_create on public.sales_orders
  for insert to authenticated
  with check (public.has_permission(company_id, 'orders.create'::text));
create policy sales_orders_read on public.sales_orders
  for select to authenticated
  using (public.has_any_permission(company_id, array['orders.view'::text, 'deliveries.view'::text, 'payments.sales_view'::text, 'reports.sales'::text, 'reports.profit'::text, 'reports.finance'::text]));
create policy sales_orders_update on public.sales_orders
  for update to authenticated
  using (public.has_permission(company_id, 'orders.update'::text))
  with check (public.has_permission(company_id, 'orders.update'::text));
create policy sales_quote_items_read on public.sales_quote_items
  for select to authenticated
  using ((exists ( select 1
   from public.sales_quotes q
  where ((q.id = sales_quote_items.quote_id) and public.has_permission(q.company_id, 'orders.view'::text)))));
create policy sales_quotes_read on public.sales_quotes
  for select to authenticated
  using (public.has_permission(company_id, 'orders.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.sales_quotes from authenticated;
revoke select, insert, update, delete on public.sales_quote_items from authenticated;
grant select (id, quote_id, product_id, quantity, sale_unit_price, line_total, minimum_sale_price_snapshot, created_at) on public.sales_quote_items to authenticated;
revoke insert, update, delete on public.inventory_reservations from authenticated;
revoke insert, update, delete on public.deliveries from authenticated;
revoke insert, update, delete on public.delivery_items from authenticated;
revoke insert, update, delete on public.sales_invoices from authenticated;
revoke insert, update, delete on public.sales_invoice_items from authenticated;
revoke insert, update, delete on public.sales_invoice_delivery_links from authenticated;
revoke insert, update, delete on public.customer_payments from authenticated;
revoke insert, update, delete on public.customer_payment_allocations from authenticated;
revoke execute on function public.apply_customer_credit_to_invoice(uuid) from authenticated;
revoke execute on function public.next_customer_payment_number(uuid,date) from authenticated;
revoke execute on function public.next_delivery_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_invoice_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_quote_number(uuid,date) from authenticated;
revoke execute on function public.next_sales_order_number(uuid,date) from authenticated;
revoke execute on function public.assign_sales_order_number() from authenticated;
revoke execute on function public.recalc_sales_invoice_payment(uuid) from authenticated;
revoke execute on function public.recalc_sales_order(uuid) from authenticated;
revoke execute on function public.recalc_sales_order_payment(uuid) from authenticated;
revoke execute on function public.refresh_customer_payment_totals(uuid) from authenticated;
revoke execute on function public.refresh_sales_order_inventory_status(uuid) from authenticated;
revoke execute on function public.reserve_pending_orders_for_product(uuid,uuid,uuid) from authenticated;
revoke execute on function public.reserve_sales_order(uuid,uuid) from authenticated;
revoke execute on function public.sales_quote_matches(uuid,text) from authenticated;
revoke execute on function public.validate_sales_quote_conversion_source(uuid,uuid,uuid,jsonb) from authenticated;
