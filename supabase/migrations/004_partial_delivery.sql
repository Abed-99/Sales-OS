begin;

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
  v_quantity numeric(14,3);
  v_order_quantity numeric(14,3);
  v_used_quantity numeric(14,3);
  v_product uuid;
  v_unit text;

  v_rows integer := 0;
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

  if v_status <> 'ready' then
    raise exception 'Order is not ready for delivery';
  end if;

  if exists (
    select 1
    from public.deliveries
    where company_id = target_company
      and order_id = target_order
      and status = 'out_for_delivery'
  ) then
    raise exception 'Order already has an active delivery';
  end if;

  if items_payload is null
     or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0
  then
    raise exception 'Delivery must contain items';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(items_payload) x
    group by x->>'sales_order_item_id'
    having count(*) > 1
  ) then
    raise exception 'Duplicate delivery item';
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
    from jsonb_array_elements(items_payload)
  loop
    begin
      v_order_item :=
        (v_item->>'sales_order_item_id')::uuid;

      v_quantity :=
        (v_item->>'quantity')::numeric;
    exception
      when others then
        raise exception 'Invalid delivery item';
    end;

    if v_quantity is null
       or v_quantity <= 0
    then
      raise exception
        'Delivery quantity must be greater than zero';
    end if;

    select
      soi.quantity,
      soi.product_id,
      p.unit
    into
      v_order_quantity,
      v_product,
      v_unit
    from public.sales_order_items soi

    join public.sales_orders so
      on so.id = soi.order_id

    join public.products p
      on p.id = soi.product_id

    where soi.id = v_order_item
      and soi.order_id = target_order
      and so.company_id = target_company;

    if v_order_quantity is null then
      raise exception
        'Sales order item not found';
    end if;

    select
      coalesce(
        sum(di.quantity),
        0
      )
    into v_used_quantity
    from public.delivery_items di

    join public.deliveries d
      on d.id = di.delivery_id

    where di.sales_order_item_id =
          v_order_item

      and d.status in (
        'out_for_delivery',
        'delivered'
      );

    if
      round(
        v_used_quantity +
        v_quantity,
        3
      ) >
      round(
        v_order_quantity,
        3
      )
    then
      raise exception
        'Delivery quantity exceeds remaining quantity';
    end if;

    insert into public.delivery_items(
      company_id,
      delivery_id,
      sales_order_item_id,
      product_id,
      quantity,
      unit
    )
    values(
      target_company,
      v_delivery,
      v_order_item,
      v_product,
      v_quantity,
      v_unit
    );

    v_rows := v_rows + 1;
  end loop;

  if v_rows = 0 then
    raise exception
      'Delivery must contain items';
  end if;

  update public.sales_orders
  set status = 'out_for_delivery'
  where id = target_order
    and company_id = target_company;

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

commit;