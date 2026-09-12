begin;

-- ============================================================
-- SALES QUOTES + BELOW-COST APPROVAL GUARD
-- Reuses existing orders / approvals permissions.
-- ============================================================

create table if not exists public.sales_quotes(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  trader_id uuid not null references public.traders(id) on delete restrict,
  quote_number text not null,
  quote_date date not null default current_date,
  valid_until date,
  status text not null default 'draft'
    check(status in ('draft','sent','accepted','rejected','cancelled','converted')),
  currency text not null,
  subtotal numeric(18,2) not null default 0 check(subtotal >= 0),
  total numeric(18,2) not null default 0 check(total >= 0),
  notes text,
  accepted_at timestamptz,
  converted_order_id uuid references public.sales_orders(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, quote_number)
);

create index if not exists sales_quotes_company_status_idx
on public.sales_quotes(company_id,status,quote_date desc);

create index if not exists sales_quotes_trader_idx
on public.sales_quotes(trader_id,quote_date desc);

create table if not exists public.sales_quote_items(
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.sales_quotes(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null check(quantity > 0),
  sale_unit_price numeric(18,2) not null check(sale_unit_price >= 0),
  line_total numeric(18,2) not null default 0 check(line_total >= 0),
  minimum_sale_price_snapshot numeric(18,2),
  reference_cost_snapshot numeric(18,4),
  created_at timestamptz not null default now(),
  unique(quote_id, product_id)
);

alter table public.sales_quotes enable row level security;
alter table public.sales_quote_items enable row level security;

drop trigger if exists sales_quotes_updated_at on public.sales_quotes;
create trigger sales_quotes_updated_at
before update on public.sales_quotes
for each row execute function public.set_updated_at();

drop policy if exists sales_quotes_read on public.sales_quotes;
create policy sales_quotes_read
on public.sales_quotes
for select
to authenticated
using(public.has_permission(company_id,'orders.view'));

drop policy if exists sales_quote_items_read on public.sales_quote_items;
create policy sales_quote_items_read
on public.sales_quote_items
for select
to authenticated
using(
  exists(
    select 1
    from public.sales_quotes q
    where q.id = sales_quote_items.quote_id
      and public.has_permission(q.company_id,'orders.view')
  )
);

grant select
on public.sales_quotes
to authenticated;

revoke select
on public.sales_quote_items
from authenticated;

grant select (
  id,
  quote_id,
  product_id,
  quantity,
  sale_unit_price,
  line_total,
  minimum_sale_price_snapshot,
  created_at
)
on public.sales_quote_items
to authenticated;

revoke insert,update,delete
on public.sales_quotes,
   public.sales_quote_items
from authenticated;

-- ------------------------------------------------------------
-- Product reference cost.
-- Prefer weighted inventory average cost when stock exists.
-- Fall back to cheapest currently available supplier price.
-- ------------------------------------------------------------
create or replace function public.product_reference_cost(
  target_company uuid,
  target_product uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.product_reference_cost(
  uuid,
  uuid
)
from public, authenticated;

-- ------------------------------------------------------------
-- Quote numbering.
-- ------------------------------------------------------------
create or replace function public.next_sales_quote_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.next_sales_quote_number(uuid,date) from public,authenticated;

-- ------------------------------------------------------------
-- Create a quote.
-- ------------------------------------------------------------
create or replace function public.create_sales_quote(
  target_company uuid,
  target_trader uuid,
  target_valid_until date,
  target_notes text,
  items_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote uuid;
  v_number text;
  v_currency text;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
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
$$;

revoke all on function public.create_sales_quote(uuid,uuid,date,text,jsonb) from public;
grant execute on function public.create_sales_quote(uuid,uuid,date,text,jsonb) to authenticated;

-- ------------------------------------------------------------
-- Quote lifecycle.
-- ------------------------------------------------------------
create or replace function public.set_sales_quote_status(
  target_company uuid,
  target_quote uuid,
  target_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $
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
$;

revoke all
on function public.set_sales_quote_status(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.set_sales_quote_status(
  uuid,
  uuid,
  text
)
to authenticated;


-- ------------------------------------------------------------
-- Validate quote -> order binding.
-- Prevents an app caller from attaching an arbitrary accepted
-- quote ID to unrelated order contents.
-- ------------------------------------------------------------
create or replace function public.validate_sales_quote_conversion_source(
  target_company uuid,
  target_quote uuid,
  target_trader uuid,
  items_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.validate_sales_quote_conversion_source(
  uuid,
  uuid,
  uuid,
  jsonb
)
from public, authenticated;
-- ------------------------------------------------------------
-- Create order with automatic below-cost / below-minimum approval.
-- Return: {status, order_id, approval_id}
-- ------------------------------------------------------------
create or replace function public.create_sales_order_v2(
  target_company uuid,
  target_trader uuid,
  target_notes text,
  items_payload jsonb,
  target_source_quote uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $
declare
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
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
$;

revoke all on function public.create_sales_order_v2(uuid,uuid,text,jsonb,uuid) from public;
grant execute on function public.create_sales_order_v2(uuid,uuid,text,jsonb,uuid) to authenticated;

-- Internal helper: only called from approval resolution.
create or replace function public.create_sales_order_from_approved_payload(
  target_company uuid,
  target_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order uuid;
  v_trader uuid;
  v_notes text;
  v_items jsonb;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
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
$$;

revoke all on function public.create_sales_order_from_approved_payload(uuid,jsonb) from public,authenticated;

-- Override generic approval resolver to execute approved below-cost orders.
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
as $
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
$;

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

-- ------------------------------------------------------------
-- Convert accepted quote to order; may return pending approval.
-- ------------------------------------------------------------
create or replace function public.convert_sales_quote_to_order(
  target_company uuid,
  target_quote uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.convert_sales_quote_to_order(uuid,uuid) from public;
grant execute on function public.convert_sales_quote_to_order(uuid,uuid) to authenticated;


-- Audit quote header lifecycle.
drop trigger if exists audit_sales_quotes on public.sales_quotes;
create trigger audit_sales_quotes
after insert or update or delete on public.sales_quotes
for each row execute function public.write_audit_log();


-- ============================================================
-- QUOTES SUMMARY
-- Exact counts across the whole company.
-- ============================================================

create or replace function public.get_quotes_summary(
  target_company uuid
)
returns table(
  all_count bigint,
  open_count bigint,
  accepted_count bigint,
  converted_count bigint,
  expired_open_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_quotes_summary(
  uuid
)
from public;

grant execute
on function public.get_quotes_summary(
  uuid
)
to authenticated;


-- ============================================================
-- QUOTES QUEUE
-- Search/filter/pagination without exposing reference cost.
-- ============================================================

create or replace function public.get_quotes_queue(
  target_company uuid,
  target_search text default null,
  target_status text default null,
  target_limit integer default 50,
  target_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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

      or q.quote_number
         ilike
         '%' || v_search || '%'

      or t.name
         ilike
         '%' || v_search || '%'

      or coalesce(
           t.area,
           ''
         )
         ilike
         '%' || v_search || '%'
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

        or q.quote_number
           ilike
           '%' || v_search || '%'

        or t.name
           ilike
           '%' || v_search || '%'

        or coalesce(
             t.area,
             ''
           )
           ilike
           '%' || v_search || '%'
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
$$;

revoke all
on function public.get_quotes_queue(
  uuid,
  text,
  text,
  integer,
  integer
)
from public;

grant execute
on function public.get_quotes_queue(
  uuid,
  text,
  text,
  integer,
  integer
)
to authenticated;
commit;
