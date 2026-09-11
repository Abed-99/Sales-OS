begin;

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
  if not public.has_permission(target_company, 'orders.create') then
    raise exception 'Not allowed';
  end if;

  if target_trader is null or not exists (
    select 1
    from public.traders
    where id = target_trader
      and company_id = target_company
      and status <> 'inactive'
  ) then
    raise exception 'Invalid trader';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0 then
    raise exception 'Order must contain items';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'product_id'
    having count(*) > 1
  ) then
    raise exception 'Duplicate products are not allowed';
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
    nullif(btrim(target_notes), '')
  )
  returning id into v_order;

  for v_item in
    select value
    from jsonb_array_elements(items_payload)
  loop
    begin
      v_product := (v_item->>'product_id')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'sale_unit_price')::numeric;
    exception
      when others then
        raise exception 'Invalid order item';
    end;

    if v_quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    if v_price < 0 then
      raise exception 'Sale price cannot be negative';
    end if;

    select minimum_sale_price
    into v_min_price
    from public.products
    where id = v_product
      and company_id = target_company
      and active = true;

    if not found then
      raise exception 'Invalid or inactive product';
    end if;

    if v_min_price is not null
       and v_price < v_min_price
       and not public.has_permission(
         target_company,
         'orders.approve_discount'
       ) then
      raise exception 'Sale price is below allowed minimum';
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
      round(v_quantity * v_price, 2)
    );

    v_total :=
      v_total + round(v_quantity * v_price, 2);
  end loop;

  update public.sales_orders
  set
    subtotal = v_total,
    total = v_total
  where id = v_order;

  return v_order;
end;
$$;

create or replace function public.cancel_sales_order(
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
begin
  if not public.has_permission(target_company, 'orders.cancel') then
    raise exception 'Not allowed';
  end if;

  select status
  into v_status
  from public.sales_orders
  where id = target_order
    and company_id = target_company
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if v_status in ('out_for_delivery', 'delivered') then
    raise exception 'Order cannot be cancelled at this stage';
  end if;

  if exists (
    select 1
    from public.sales_invoices
    where company_id = target_company
      and order_id = target_order
      and status <> 'cancelled'
  ) then
    raise exception 'Cancel sales invoice first';
  end if;

  update public.sales_orders
  set status = 'cancelled'
  where id = target_order
    and company_id = target_company;
end;
$$;

revoke all
on function public.create_sales_order(uuid,uuid,text,jsonb)
from public;

revoke all
on function public.cancel_sales_order(uuid,uuid)
from public;

grant execute
on function public.create_sales_order(uuid,uuid,text,jsonb)
to authenticated;

grant execute
on function public.cancel_sales_order(uuid,uuid)
to authenticated;

commit;