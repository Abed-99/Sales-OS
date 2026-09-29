-- ======================================================================
-- المشتريات
-- فواتير الشراء، استلام البضاعة، الدفع للموردين
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  invoice_number text not null,
  supplier_invoice_number text,
  status text default 'posted'::text not null,
  payment_status text default 'unpaid'::text not null,
  currency text default 'USD'::text not null,
  invoice_date date default current_date not null,
  due_date date,
  subtotal numeric(14,2) default 0 not null,
  discount_total numeric(14,2) default 0 not null,
  tax_total numeric(14,2) default 0 not null,
  total numeric(14,2) default 0 not null,
  paid_total numeric(14,2) default 0 not null,
  balance_due numeric(14,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint purchase_invoices_company_id_invoice_number_key unique (company_id, invoice_number),
  constraint purchase_invoices_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint purchase_invoices_check check (((due_date is null) or (due_date >= invoice_date))),
  constraint purchase_invoices_discount_total_check check ((discount_total >= (0)::numeric)),
  constraint purchase_invoices_paid_total_check check ((paid_total >= (0)::numeric)),
  constraint purchase_invoices_payment_status_check check ((payment_status = any (array['unpaid'::text, 'partial'::text, 'paid'::text]))),
  constraint purchase_invoices_status_check check ((status = any (array['draft'::text, 'posted'::text, 'cancelled'::text]))),
  constraint purchase_invoices_subtotal_check check ((subtotal >= (0)::numeric)),
  constraint purchase_invoices_tax_total_check check ((tax_total >= (0)::numeric)),
  constraint purchase_invoices_total_check check ((total >= (0)::numeric))
);
create index purchase_invoices_company_date_idx on public.purchase_invoices using btree (company_id, invoice_date desc, created_at desc);
create index purchase_invoices_due_idx on public.purchase_invoices using btree (company_id, due_date) where ((status = 'posted'::text) and (payment_status <> 'paid'::text));
create index purchase_invoices_supplier_idx on public.purchase_invoices using btree (supplier_id, invoice_date desc);
create unique index purchase_invoices_supplier_number_unique on public.purchase_invoices using btree (company_id, supplier_id, supplier_invoice_number) where ((supplier_invoice_number is not null) and (status <> 'cancelled'::text));

create table public.purchase_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  invoice_id uuid not null references public.purchase_invoices(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  description text,
  quantity numeric(14,3) not null,
  unit_cost numeric(18,4) not null,
  discount_amount numeric(14,2) default 0 not null,
  tax_amount numeric(14,2) default 0 not null,
  line_total numeric(14,2) not null,
  notes text,
  created_at timestamp with time zone default now() not null,
  constraint purchase_invoice_items_discount_amount_check check ((discount_amount >= (0)::numeric)),
  constraint purchase_invoice_items_line_total_check check ((line_total >= (0)::numeric)),
  constraint purchase_invoice_items_quantity_check check ((quantity > (0)::numeric)),
  constraint purchase_invoice_items_tax_amount_check check ((tax_amount >= (0)::numeric)),
  constraint purchase_invoice_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index purchase_invoice_items_invoice_idx on public.purchase_invoice_items using btree (invoice_id);
create index purchase_invoice_items_product_idx on public.purchase_invoice_items using btree (company_id, product_id);

create table public.purchase_invoice_item_sources (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete cascade,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  quantity numeric(14,3) not null,
  created_at timestamp with time zone default now() not null,
  constraint purchase_invoice_item_sources_purchase_invoice_item_id_sale_key unique (purchase_invoice_item_id, sales_order_item_id),
  constraint purchase_invoice_item_sources_quantity_check check ((quantity > (0)::numeric))
);
create index purchase_invoice_sources_order_item_idx on public.purchase_invoice_item_sources using btree (sales_order_item_id);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_invoice_id uuid references public.purchase_invoices(id) on delete restrict,
  receipt_number text not null,
  status text default 'posted'::text not null,
  receipt_date date default current_date not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  cancelled_at timestamp with time zone,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  constraint goods_receipts_company_id_receipt_number_key unique (company_id, receipt_number),
  constraint goods_receipts_status_check check ((status = any (array['posted'::text, 'cancelled'::text])))
);
create index goods_receipts_company_date_idx on public.goods_receipts using btree (company_id, receipt_date desc, created_at desc);
create index goods_receipts_company_status_idx on public.goods_receipts using btree (company_id, status, receipt_date desc);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  goods_receipt_id uuid not null references public.goods_receipts(id) on delete cascade,
  purchase_invoice_item_id uuid not null references public.purchase_invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  unit_cost numeric(18,4) not null,
  created_at timestamp with time zone default now() not null,
  constraint goods_receipt_items_quantity_check check ((quantity > (0)::numeric)),
  constraint goods_receipt_items_unit_cost_check check ((unit_cost >= (0)::numeric))
);
create index goods_receipt_items_purchase_item_idx on public.goods_receipt_items using btree (purchase_invoice_item_id);
create index goods_receipt_items_receipt_idx on public.goods_receipt_items using btree (goods_receipt_id);

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
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
  constraint supplier_payments_company_id_payment_number_key unique (company_id, payment_number),
  constraint supplier_payments_amount_check check ((amount > (0)::numeric)),
  constraint supplier_payments_check check (((allocated_total >= (0)::numeric) and (allocated_total <= amount))),
  constraint supplier_payments_check1 check (((unallocated_total >= (0)::numeric) and (unallocated_total <= amount))),
  constraint supplier_payments_check2 check (((allocated_total + unallocated_total) = amount)),
  constraint supplier_payments_payment_method_check check ((payment_method = any (array['cash'::text, 'bank'::text, 'card'::text, 'check'::text, 'other'::text]))),
  constraint supplier_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index supplier_payments_company_date_idx on public.supplier_payments using btree (company_id, payment_date desc, created_at desc);
create index supplier_payments_currency_idx on public.supplier_payments using btree (company_id, payment_currency, payment_date desc);
create index supplier_payments_supplier_date_idx on public.supplier_payments using btree (supplier_id, payment_date desc, created_at desc);

create table public.supplier_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.supplier_payments(id) on delete restrict,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null,
  payment_amount numeric(20,2),
  payment_currency text,
  invoice_currency text,
  payment_rate_to_base numeric(30,18),
  constraint supplier_payment_allocations_payment_id_purchase_invoice_id_key unique (payment_id, purchase_invoice_id),
  constraint supplier_payment_allocations_amount_check check ((amount > (0)::numeric))
);
create index supplier_payment_allocations_invoice_idx on public.supplier_payment_allocations using btree (purchase_invoice_id);
create index supplier_payment_allocations_payment_idx on public.supplier_payment_allocations using btree (payment_id);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_supplier_payment_fk foreign key (supplier_payment_id) references public.supplier_payments(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

-- ----------------------------------------------------------------------
-- أوامر الشراء: طلب للمورد قبل ما توصل الفاتورة. ما بيأثر عالمخزون ولا عالحسابات.
-- ----------------------------------------------------------------------
create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  po_number text not null,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  order_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  expected_date date,
  status text default 'draft'::text not null,
  currency text not null,
  total numeric(14,2) default 0 not null,
  notes text,
  converted_invoice_id uuid references public.purchase_invoices(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint purchase_orders_number_key unique (company_id, po_number),
  constraint purchase_orders_status_check check (status in ('draft','sent','confirmed','converted','cancelled'))
);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(18,4) not null check (unit_cost >= 0),
  line_total numeric(14,2) not null,
  notes text,
  created_at timestamp with time zone default now() not null
);

create index purchase_orders_company_idx on public.purchase_orders using btree (company_id, order_date desc);
create index purchase_order_items_po_idx on public.purchase_order_items using btree (purchase_order_id);

alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;

create policy purchase_orders_read on public.purchase_orders
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));
create policy purchase_order_items_read on public.purchase_order_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));

create or replace function public.apply_supplier_payment_terms()
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
      s.payment_terms_days,
      0
    )
  into v_days
  from public.suppliers s
  where s.id = new.supplier_id
    and s.company_id =
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

create or replace function public.cancel_purchase_invoice(target_company uuid, target_invoice uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_order uuid;
begin
  if not public.has_permission(
    target_company,
    'purchase_invoices.cancel'
  ) and not public.use_owner_override(target_company, 'cancel_invoice') then
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
$function$;

create or replace function public.create_purchase_order(target_company uuid, target_supplier uuid, target_expected_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_year integer := extract(year from (now() at time zone 'Asia/Damascus'))::integer;
  v_value bigint;
  v_item jsonb;
  v_qty numeric;
  v_cost numeric;
  v_total numeric := 0;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if not exists (select 1 from public.suppliers where id = target_supplier and company_id = target_company and active) then
    raise exception 'Invalid supplier';
  end if;

  if items_payload is null or jsonb_typeof(items_payload) <> 'array' or jsonb_array_length(items_payload) = 0 then
    raise exception 'Purchase order requires items';
  end if;

  insert into public.document_sequences(company_id, document_type, sequence_year, next_value)
  values (target_company, 'purchase_order', v_year, 1)
  on conflict (company_id, document_type, sequence_year) do nothing;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company and document_type = 'purchase_order' and sequence_year = v_year
  returning next_value - 1 into v_value;

  insert into public.purchase_orders(company_id, po_number, supplier_id, expected_date, currency, notes)
  values (
    target_company,
    'PO-' || v_year::text || '-' || lpad(v_value::text, 6, '0'),
    target_supplier,
    target_expected_date,
    (select default_currency from public.companies where id = target_company),
    nullif(trim(target_notes), '')
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(items_payload) loop
    v_qty := (v_item->>'quantity')::numeric;
    v_cost := coalesce((v_item->>'unit_cost')::numeric, 0);

    if v_qty is null or v_qty <= 0 or v_cost < 0 then
      raise exception 'Invalid purchase order item';
    end if;

    if not exists (
      select 1 from public.products
      where id = (v_item->>'product_id')::uuid and company_id = target_company
    ) then
      raise exception 'Invalid purchase order item';
    end if;

    insert into public.purchase_order_items(company_id, purchase_order_id, product_id, quantity, unit_cost, line_total, notes)
    values (
      target_company, v_id, (v_item->>'product_id')::uuid, round(v_qty, 3), round(v_cost, 4),
      round(v_qty * v_cost, 2), nullif(trim(v_item->>'notes'), '')
    );

    v_total := v_total + round(v_qty * v_cost, 2);
  end loop;

  update public.purchase_orders set total = round(v_total, 2) where id = v_id;
  return v_id;
end;
$function$;

create or replace function public.set_purchase_order_status(target_company uuid, target_order uuid, target_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchases.update','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if target_status not in ('draft', 'sent', 'confirmed', 'cancelled') then
    raise exception 'Invalid purchase order status';
  end if;

  select status into v_status
  from public.purchase_orders
  where id = target_order and company_id = target_company
  for update;

  if v_status is null then
    raise exception 'Purchase order not found';
  end if;

  if v_status in ('converted', 'cancelled') then
    raise exception 'Purchase order is closed';
  end if;

  update public.purchase_orders
  set status = target_status, updated_at = now()
  where id = target_order;
end;
$function$;

-- وصلت فاتورة المورد: أمر الشراء بيتحوّل لفاتورة شراء بنفس الأصناف (الكميات والأسعار ممكن تتعدّل).
create or replace function public.convert_purchase_order(target_company uuid, target_order uuid, target_supplier_invoice_number text, target_invoice_date date, items_payload jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_po public.purchase_orders%rowtype;
  v_items jsonb;
  v_invoice uuid;
begin
  select * into v_po
  from public.purchase_orders
  where id = target_order and company_id = target_company
  for update;

  if v_po.id is null then
    raise exception 'Purchase order not found';
  end if;

  if v_po.status in ('converted', 'cancelled') then
    raise exception 'Purchase order is closed';
  end if;

  v_items := coalesce(items_payload, (
    select jsonb_agg(jsonb_build_object(
      'product_id', i.product_id,
      'quantity', i.quantity,
      'unit_cost', i.unit_cost,
      'discount_amount', 0,
      'tax_amount', 0,
      'notes', i.notes,
      'allocations', '[]'::jsonb
    ) order by i.created_at)
    from public.purchase_order_items i
    where i.purchase_order_id = v_po.id
  ));

  v_invoice := public.create_purchase_invoice(
    target_company,
    v_po.supplier_id,
    target_supplier_invoice_number,
    coalesce(target_invoice_date, (now() at time zone 'Asia/Damascus')::date),
    null,
    'من أمر الشراء ' || v_po.po_number,
    v_items
  );

  update public.purchase_orders
  set status = 'converted', converted_invoice_id = v_invoice, updated_at = now()
  where id = v_po.id;

  return v_invoice;
end;
$function$;

create or replace function public.create_purchase_invoice(target_company uuid, target_supplier uuid, target_supplier_invoice_number text, target_invoice_date date, target_due_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invoice uuid;
  v_invoice_number text;
  v_currency text;

  v_item jsonb;
  v_item_id uuid;
  v_product uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(18,4);
  v_discount numeric(14,2);
  v_tax numeric(14,2);
  v_line_total numeric(14,2);

  v_allocation jsonb;
  v_order_item uuid;
  v_alloc_quantity numeric(14,3);
  v_required_quantity numeric(14,3);
  v_existing_allocated numeric(14,3);
  v_this_item_allocated numeric(14,3);
  v_order uuid;

  v_subtotal numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_tax_total numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
begin
  if not public.has_permission(
    target_company,
    'purchase_invoices.create'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers
    where id = target_supplier
      and company_id = target_company
      and active = true
  ) then
    raise exception 'Invalid or archived supplier';
  end if;

  if target_invoice_date is null then
    target_invoice_date := current_date;
  end if;

  if target_due_date is not null
     and target_due_date < target_invoice_date
  then
    raise exception 'Due date cannot be before invoice date';
  end if;

  if jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception 'Purchase invoice needs at least one item';
  end if;

  select default_currency
  into v_currency
  from public.companies
  where id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  v_invoice_number :=
    public.next_purchase_invoice_number(
      target_company,
      target_invoice_date
    );

  insert into public.purchase_invoices(
    company_id,
    supplier_id,
    invoice_number,
    supplier_invoice_number,
    status,
    payment_status,
    currency,
    invoice_date,
    due_date,
    notes,
    posted_at,
    posted_by
  )
  values(
    target_company,
    target_supplier,
    v_invoice_number,
    nullif(trim(target_supplier_invoice_number),''),
    'posted',
    'unpaid',
    v_currency,
    target_invoice_date,
    target_due_date,
    nullif(trim(target_notes),''),
    now(),
    auth.uid()
  )
  returning id into v_invoice;

  for v_item in
    select value
    from jsonb_array_elements(items_payload)
  loop
    v_product := (v_item ->> 'product_id')::uuid;
    v_quantity := (v_item ->> 'quantity')::numeric;
    v_unit_cost := (v_item ->> 'unit_cost')::numeric;

    v_discount :=
      coalesce(
        nullif(v_item ->> 'discount_amount','')::numeric,
        0
      );

    v_tax :=
      coalesce(
        nullif(v_item ->> 'tax_amount','')::numeric,
        0
      );

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Invalid purchase quantity';
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'Invalid purchase cost';
    end if;

    if v_discount < 0 or v_tax < 0 then
      raise exception 'Invalid discount or tax';
    end if;

    if v_discount >
       round(
         v_quantity * v_unit_cost,
         2
       )
    then
      raise exception
        'Discount exceeds purchase line subtotal';
    end if;

    if not exists (
      select 1
      from public.products
      where id = v_product
        and company_id = target_company
        and active = true
    ) then
      raise exception 'Invalid or archived product';
    end if;

    v_line_total :=
      round(
        greatest(
          (v_quantity * v_unit_cost)
          - v_discount
          + v_tax,
          0
        ),
        2
      );

    insert into public.purchase_invoice_items(
      company_id,
      invoice_id,
      product_id,
      description,
      quantity,
      unit_cost,
      discount_amount,
      tax_amount,
      line_total,
      notes
    )
    values(
      target_company,
      v_invoice,
      v_product,
      nullif(trim(v_item ->> 'description'),''),
      v_quantity,
      v_unit_cost,
      v_discount,
      v_tax,
      v_line_total,
      nullif(trim(v_item ->> 'notes'),'')
    )
    returning id into v_item_id;

    v_this_item_allocated := 0;

    if jsonb_typeof(
      coalesce(v_item -> 'allocations','[]'::jsonb)
    ) = 'array'
    then
      for v_allocation in
        select value
        from jsonb_array_elements(
          coalesce(v_item -> 'allocations','[]'::jsonb)
        )
      loop
        v_order_item :=
          nullif(
            v_allocation ->> 'sales_order_item_id',
            ''
          )::uuid;

        v_alloc_quantity :=
          nullif(
            v_allocation ->> 'quantity',
            ''
          )::numeric;

        if v_order_item is null
           or v_alloc_quantity is null
           or v_alloc_quantity <= 0
        then
          raise exception 'Invalid allocated quantity';
        end if;

        select
          soi.quantity,
          so.id
        into
          v_required_quantity,
          v_order
        from public.sales_order_items soi
        join public.sales_orders so
          on so.id = soi.order_id
        where soi.id = v_order_item
          and soi.product_id = v_product
          and so.company_id = target_company
          and so.status <> 'cancelled';

        if v_required_quantity is null then
          raise exception 'Invalid sales order allocation';
        end if;

        select coalesce(sum(src.quantity),0)
        into v_existing_allocated
        from public.purchase_invoice_item_sources src
        join public.purchase_invoice_items pii
          on pii.id = src.purchase_invoice_item_id
        join public.purchase_invoices pi
          on pi.id = pii.invoice_id
        where src.sales_order_item_id = v_order_item
          and pi.status <> 'cancelled';

        if v_existing_allocated + v_alloc_quantity > v_required_quantity then
          raise exception 'Purchase allocation exceeds ordered quantity';
        end if;

        v_this_item_allocated :=
          v_this_item_allocated + v_alloc_quantity;

        if v_this_item_allocated > v_quantity then
          raise exception 'Allocations exceed purchase invoice item quantity';
        end if;

        insert into public.purchase_invoice_item_sources(
          company_id,
          purchase_invoice_item_id,
          sales_order_item_id,
          quantity
        )
        values(
          target_company,
          v_item_id,
          v_order_item,
          v_alloc_quantity
        );

        perform public.refresh_sales_order_purchase_status(v_order);
      end loop;
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
      target_supplier,
      v_product,
      v_unit_cost,
      true,
      'من فاتورة شراء ' || v_invoice_number,
      now()
    )
    on conflict (supplier_id, product_id)
    do update set
      purchase_price = excluded.purchase_price,
      available = true,
      notes = excluded.notes,
      last_checked_at = now(),
      updated_at = now();

    v_subtotal := v_subtotal + (v_quantity * v_unit_cost);
    v_discount_total := v_discount_total + v_discount;
    v_tax_total := v_tax_total + v_tax;
    v_total := v_total + v_line_total;
  end loop;

  update public.purchase_invoices
  set
    subtotal = round(v_subtotal,2),
    discount_total = round(v_discount_total,2),
    tax_total = round(v_tax_total,2),
    total = round(v_total,2),
    paid_total = 0,
    balance_due = round(v_total,2),
    payment_status =
      case
        when v_total = 0 then 'paid'
        else 'unpaid'
      end
  where id = v_invoice;

  return v_invoice;
end;
$function$;

create or replace function public.get_purchase_needs(target_company uuid)
 RETURNS TABLE(sales_order_item_id uuid, order_id uuid, trader_name text, product_id uuid, product_name text, sku text, required_quantity numeric, allocated_quantity numeric, remaining_quantity numeric, ordered_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_purchases_summary(target_company uuid)
 RETURNS TABLE(invoice_count bigint, outstanding_total numeric, supplier_credit_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(
    target_company,
    'purchases.view'
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    (
      select
        count(*)::bigint

      from public.purchase_invoices pi

      where pi.company_id =
            target_company
        and pi.status =
            'posted'
    ),

    (
      select
        round(
          coalesce(
            sum(
              (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            ),
            0
          ),
          2
        )

      from public.purchase_invoices pi

      where pi.company_id =
            target_company
        and pi.status =
            'posted'
    ),

    (
      select
        round(
          coalesce(
            sum(
              case
                when sp.amount > 0
                then
                  coalesce(
                    sp.base_amount,
                    sp.amount *
                    coalesce(
                      sp.exchange_rate_to_base,
                      1
                    )
                  ) *
                  (
                    sp.unallocated_total /
                    sp.amount
                  )
                else 0
              end
            ),
            0
          ),
          2
        )

      from public.supplier_payments sp

      where sp.company_id =
            target_company
        and sp.status =
            'posted'
    );
end;
$function$;

create or replace function public.get_receivable_purchase_items(target_company uuid)
 RETURNS TABLE(invoice_id uuid, supplier_id uuid, invoice_number text, supplier_invoice_number text, currency text, invoice_date date, invoice_total numeric, supplier_name text, item_id uuid, product_id uuid, description text, invoiced_quantity numeric, received_quantity numeric, remaining_quantity numeric, product_name text, sku text, unit text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_supplier_financial_summary(target_company uuid, target_supplier uuid)
 RETURNS TABLE(total_purchases numeric, total_payments numeric, invoice_balance numeric, advance_credit numeric, net_balance numeric, invoice_count bigint, payment_count bigint, available_products bigint, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;

  v_total_purchases numeric := 0;
  v_total_payments numeric := 0;
  v_invoice_balance numeric := 0;
  v_advance_credit numeric := 0;

  v_invoice_count bigint := 0;
  v_payment_count bigint := 0;
  v_available_products bigint := 0;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'suppliers.view_finance',
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers s
    where s.id = target_supplier
      and s.company_id = target_company
  ) then
    raise exception 'Supplier not found';
  end if;

  select upper(c.default_currency)
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  with invoice_values as (
    select
      pi.total,
      pi.balance_due,

      case
        when upper(pi.currency) = v_currency
          then 1::numeric
        else public.finance_rate_to_base(
          target_company,
          pi.currency,
          pi.invoice_date
        )
      end as rate_to_base

    from public.purchase_invoices pi

    where pi.company_id = target_company
      and pi.supplier_id = target_supplier
      and pi.status = 'posted'
  )
  select
    round(
      coalesce(
        sum(
          iv.total *
          iv.rate_to_base
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          iv.balance_due *
          iv.rate_to_base
        ),
        0
      ),
      2
    ),

    count(*)::bigint

  into
    v_total_purchases,
    v_invoice_balance,
    v_invoice_count

  from invoice_values iv;

  select
    round(
      coalesce(
        sum(
          coalesce(
            sp.base_amount,
            sp.amount *
            coalesce(
              sp.exchange_rate_to_base,
              1
            )
          )
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          sp.unallocated_total *
          coalesce(
            sp.exchange_rate_to_base,
            1
          )
        ),
        0
      ),
      2
    ),

    count(*)::bigint

  into
    v_total_payments,
    v_advance_credit,
    v_payment_count

  from public.supplier_payments sp

  where sp.company_id = target_company
    and sp.supplier_id = target_supplier
    and sp.status = 'posted';

  select count(*)::bigint
  into v_available_products
  from public.supplier_prices sp
  where sp.company_id = target_company
    and sp.supplier_id = target_supplier
    and sp.available = true;

  return query
  select
    v_total_purchases,

    v_total_payments,

    v_invoice_balance,

    v_advance_credit,

    round(
      v_invoice_balance -
      v_advance_credit,
      2
    ),

    v_invoice_count,

    v_payment_count,

    v_available_products,

    v_currency;
end;
$function$;

create or replace function public.get_supplier_ledger(target_company uuid, target_supplier uuid, target_limit integer DEFAULT 100)
 RETURNS TABLE(source_id uuid, event_date date, event_created_at timestamp with time zone, row_type text, reference text, description text, debit numeric, credit numeric, balance numeric, total_count bigint, currency text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_limit integer;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'suppliers.view_finance',
      'purchase_invoices.view',
      'purchases.view',
      'payments.supplier_view',
      'reports.finance',
      'reports.profit'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.suppliers s
    where s.id = target_supplier
      and s.company_id = target_company
  ) then
    raise exception 'Supplier not found';
  end if;

  select upper(c.default_currency)
  into v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  v_limit :=
    least(
      greatest(
        coalesce(target_limit,100),
        1
      ),
      200
    );

  return query

  with movements as (

    select
      pi.id as source_id,

      pi.invoice_date as event_date,

      pi.created_at as event_created_at,

      'invoice'::text as row_type,

      pi.invoice_number::text as reference,

      case
        when nullif(
          trim(
            coalesce(
              pi.supplier_invoice_number,
              ''
            )
          ),
          ''
        ) is not null
        then
          'فاتورة مورد ' ||
          pi.supplier_invoice_number

        else
          'فاتورة شراء'
      end::text as description,

      round(
        pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date),
        2
      )::numeric as debit,

      0::numeric as credit

    from public.purchase_invoices pi

    where pi.company_id = target_company
      and pi.supplier_id = target_supplier
      and pi.status = 'posted'


    union all


    select
      sp.id as source_id,

      sp.payment_date as event_date,

      sp.created_at as event_created_at,

      'payment'::text as row_type,

      sp.payment_number::text as reference,

      case
        when nullif(
          trim(
            coalesce(
              sp.reference_number,
              ''
            )
          ),
          ''
        ) is not null
        then
          'دفعة - ' ||
          sp.reference_number

        else
          'دفعة للمورد'
      end::text as description,

      0::numeric as debit,

      round(
        coalesce(
          sp.base_amount,
          sp.amount *
          coalesce(
            sp.exchange_rate_to_base,
            1
          )
        ),
        2
      )::numeric as credit

    from public.supplier_payments sp

    where sp.company_id = target_company
      and sp.supplier_id = target_supplier
      and sp.status = 'posted'

    union all

    -- المرتجع للمورد بينقّص اللي علينا إله، متل الدفعة.
    select
      pr.id as source_id,
      pr.return_date as event_date,
      pr.created_at as event_created_at,
      'return'::text as row_type,
      pr.return_number::text as reference,
      'مرتجع للمورد'::text as description,
      0::numeric as debit,
      round(
        pr.total * public.finance_rate_to_base(target_company, pr.currency, pr.return_date),
        2
      )::numeric as credit
    from public.purchase_returns pr
    where pr.company_id = target_company
      and pr.supplier_id = target_supplier
      and pr.status = 'posted'
  ),

  running as (
    select
      m.*,

      round(
        sum(
          m.debit -
          m.credit
        ) over (
          order by
            m.event_date,
            m.event_created_at,
            m.row_type,
            m.source_id
          rows between
            unbounded preceding
            and current row
        ),
        2
      )::numeric as running_balance,

      count(*) over()::bigint
        as full_count

    from movements m
  )

  select
    r.source_id,

    r.event_date,

    r.event_created_at,

    r.row_type,

    r.reference,

    r.description,

    r.debit,

    r.credit,

    r.running_balance,

    r.full_count,

    v_currency

  from running r

  order by
    r.event_date desc,
    r.event_created_at desc,
    r.row_type desc,
    r.source_id desc

  limit v_limit;
end;
$function$;

create or replace function public.next_goods_receipt_number(target_company uuid, target_date date)
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
$function$;

create or replace function public.next_purchase_invoice_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year := extract(year from coalesce(target_date, current_date));

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'purchase_invoice',
    v_year,
    1
  )
  on conflict (
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id = target_company
    and document_type = 'purchase_invoice'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'purchase_invoice'
    and sequence_year = v_year;

  return
    'PI-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.next_supplier_payment_number(target_company uuid, target_date date)
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
    'supplier_payment',
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
    and document_type = 'supplier_payment'
    and sequence_year = v_year
  for update;


  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'supplier_payment'
    and sequence_year = v_year;


  return
    'SP-' ||
    v_year::text ||
    '-' ||
    lpad(v_value::text, 6, '0');
end;
$function$;

create or replace function public.recalc_purchase_invoice_payment(target_invoice uuid)
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
$function$;

create or replace function public.receive_purchase_invoice(target_company uuid, target_invoice uuid, target_warehouse uuid, target_receipt_date date, target_notes text, items_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.record_supplier_payment(target_company uuid, target_supplier uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text, allocations_payload jsonb)
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
  v_invoice_supplier uuid;
  v_invoice_currency text;

  v_allocated_payment_sum numeric(20,2) := 0;
begin
  if not public.has_permission(
    target_company,
    'payments.supplier_create'
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
    from public.suppliers
    where id =
          target_supplier
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid supplier';
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
    public.next_supplier_payment_number(
      target_company,
      target_payment_date
    );

  insert into public.supplier_payments(
    company_id,
    supplier_id,
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
    target_supplier,
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
          'purchase_invoice_id' #>> '{}',
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
      supplier_id,
      upper(currency)

    into
      v_balance,
      v_invoice_status,
      v_invoice_supplier,
      v_invoice_currency

    from public.purchase_invoices

    where id =
          v_invoice
      and company_id =
          target_company

    for update;

    if v_balance is null then
      raise exception
        'Purchase invoice not found';
    end if;

    if v_invoice_status <>
       'posted'
    then
      raise exception
        'Cannot pay cancelled or unposted invoice';
    end if;

    if v_invoice_supplier <>
       target_supplier
    then
      raise exception
        'Invoice belongs to another supplier';
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


    insert into public.supplier_payment_allocations(
      company_id,
      payment_id,
      purchase_invoice_id,
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

  end loop;


  perform
    public.refresh_supplier_payment_totals(
      v_payment
    );


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    supplier_id,
    supplier_payment_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'supplier_payment',
    round(
      target_amount,
      2
    ),
    target_supplier,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'دفعة مورد ' ||
      v_number
    ),
    target_payment_date::timestamptz
  );

  return v_payment;
end;
$function$;

create or replace function public.refresh_sales_order_purchase_status(target_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.refresh_sales_order_inventory_status(
      target_order
    );
end;
$function$;

create or replace function public.refresh_supplier_payment_totals(target_payment uuid)
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
  from public.supplier_payments
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
  from public.supplier_payment_allocations
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

  update public.supplier_payments
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

create or replace function public.reverse_goods_receipt(target_company uuid, target_receipt uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.reverse_supplier_payment(target_company uuid, target_payment uuid, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_cashbox uuid;
  v_amount numeric(14,2);
  v_supplier uuid;
  v_number text;
begin

  if not public.has_permission(
    target_company,
    'payments.supplier_reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    status,
    cashbox_id,
    amount,
    supplier_id,
    payment_number

  into
    v_status,
    v_cashbox,
    v_amount,
    v_supplier,
    v_number

  from public.supplier_payments

  where id = target_payment
    and company_id = target_company

  for update;


  if v_status is null then
    raise exception 'Supplier payment not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if nullif(trim(target_reason),'') is null
  then
    raise exception 'Reversal reason required';
  end if;


  update public.supplier_payments
  set
    status = 'reversed',
    reversed_at = now(),
    reversed_by = auth.uid(),
    reversal_reason =
      trim(target_reason)

  where id = target_payment;


  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    supplier_id,
    supplier_payment_id,
    notes
  )
  values(
    target_company,
    v_cashbox,
    'in',
    'supplier_payment_reversal',
    v_amount,
    v_supplier,
    target_payment,
    'عكس دفعة مورد ' ||
      v_number ||
      ' - ' ||
      trim(target_reason)
  );

end;
$function$;

create or replace function public.supplier_payment_allocation_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  if tg_op = 'DELETE' then

    perform
      public.refresh_supplier_payment_totals(
        old.payment_id
      );

    perform
      public.recalc_purchase_invoice_payment(
        old.purchase_invoice_id
      );

    return old;

  end if;


  if tg_op = 'UPDATE' then

    if old.payment_id is distinct from
       new.payment_id
    then
      perform
        public.refresh_supplier_payment_totals(
          old.payment_id
        );
    end if;

    if old.purchase_invoice_id
       is distinct from
       new.purchase_invoice_id
    then
      perform
        public.recalc_purchase_invoice_payment(
          old.purchase_invoice_id
        );
    end if;

  end if;


  perform
    public.refresh_supplier_payment_totals(
      new.payment_id
    );

  perform
    public.recalc_purchase_invoice_payment(
      new.purchase_invoice_id
    );

  return new;
end;
$function$;

create or replace function public.supplier_payment_status_changed()
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
      select distinct purchase_invoice_id
      from public.supplier_payment_allocations
      where payment_id = new.id
    loop

      perform
        public.recalc_purchase_invoice_payment(
          v_invoice
        );

    end loop;

  end if;

  return new;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_goods_receipt_items after insert or delete or update on public.goods_receipt_items for each row execute function public.write_audit_log();

create trigger audit_goods_receipts after insert or delete or update on public.goods_receipts for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_sources after insert or delete or update on public.purchase_invoice_item_sources for each row execute function public.write_audit_log();

create trigger audit_purchase_invoice_items after insert or delete or update on public.purchase_invoice_items for each row execute function public.write_audit_log();

create trigger audit_purchase_invoices after insert or delete or update on public.purchase_invoices for each row execute function public.write_audit_log();

create trigger purchase_invoice_payment_terms before insert on public.purchase_invoices for each row execute function public.apply_supplier_payment_terms();

create trigger purchase_invoices_updated_at before update on public.purchase_invoices for each row execute function public.set_updated_at();

create trigger audit_supplier_payment_allocations after insert or delete or update on public.supplier_payment_allocations for each row execute function public.write_audit_log();

create trigger supplier_payment_allocation_changed_trigger after insert or delete or update on public.supplier_payment_allocations for each row execute function public.supplier_payment_allocation_changed();

create trigger audit_supplier_payments after insert or delete or update on public.supplier_payments for each row execute function public.write_audit_log();

create trigger supplier_payment_status_changed_trigger after update of status on public.supplier_payments for each row execute function public.supplier_payment_status_changed();

create trigger supplier_payments_updated_at before update on public.supplier_payments for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_items enable row level security;
alter table public.purchase_invoice_item_sources enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
create policy goods_receipt_items_read on public.goods_receipt_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'purchases.view'::text, 'purchase_invoices.view'::text]));
create policy goods_receipts_read on public.goods_receipts
  for select to authenticated
  using (public.has_any_permission(company_id, array['inventory.view'::text, 'purchases.view'::text, 'purchase_invoices.view'::text]));
create policy purchase_invoice_sources_read on public.purchase_invoice_item_sources
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy purchase_invoice_items_read on public.purchase_invoice_items
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy purchase_invoices_read on public.purchase_invoices
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchase_invoices.view'::text, 'purchases.view'::text, 'payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text, 'reports.profit'::text]));
create policy supplier_payment_allocations_read on public.supplier_payment_allocations
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.supplier_view'::text, 'suppliers.view_finance'::text, 'reports.finance'::text]));
create policy supplier_payments_read on public.supplier_payments
  for select to authenticated
  using (public.has_any_permission(company_id, array['payments.supplier_view'::text, 'suppliers.view_finance'::text, 'finance.cashbox_view'::text, 'finance.accounts_view'::text, 'reports.finance'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.purchase_invoices from authenticated;
revoke insert, update, delete on public.purchase_invoice_items from authenticated;
revoke insert, update, delete on public.purchase_invoice_item_sources from authenticated;
revoke insert, update, delete on public.goods_receipts from authenticated;
revoke select, insert, update, delete on public.goods_receipt_items from authenticated;
grant select (id, company_id, goods_receipt_id, purchase_invoice_item_id, product_id, quantity, created_at) on public.goods_receipt_items to authenticated;
revoke insert, update, delete on public.supplier_payments from authenticated;
revoke insert, update, delete on public.supplier_payment_allocations from authenticated;
revoke execute on function public.next_goods_receipt_number(uuid,date) from authenticated;
revoke execute on function public.next_purchase_invoice_number(uuid,date) from authenticated;
revoke execute on function public.next_supplier_payment_number(uuid,date) from authenticated;
revoke execute on function public.recalc_purchase_invoice_payment(uuid) from authenticated;
revoke execute on function public.refresh_sales_order_purchase_status(uuid) from authenticated;
revoke execute on function public.refresh_supplier_payment_totals(uuid) from authenticated;
