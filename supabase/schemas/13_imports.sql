-- ======================================================================
-- الاستيراد (الكونتينر): شحنة بتجمع فواتير شراء + مصاريفها (شحن، جمارك، تخليص...).
-- المصاريف بتتجمّع بحساب "تكاليف استيراد بانتظار التوزيع"، ولما تنسكّر الشحنة بتتوزّع
-- على أصنافها: كل مصروف إلو طريقة (حسب السعر، الوزن، الحجم، أو العدد). الوزن والحجم
-- بينكتبوا بكل كونتينر من البيان الجمركي أو الفاتورة. حصة الموجود بالمخزون بترفع كلفتو، وحصة المباع بتروح لكلفة المبيعات.
-- ======================================================================

create table public.import_shipments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  shipment_number text not null,
  container_number text,
  origin_country text,
  shipped_on date,
  expected_on date,
  arrived_on date,
  status text default 'ordered'::text not null,
  notes text,
  closed_at timestamp with time zone,
  journal_entry_id uuid references public.journal_entries(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint import_shipments_number_key unique (company_id, shipment_number),
  constraint import_shipments_status_check check (status in ('ordered','shipped','at_port','customs','arrived','closed','cancelled'))
);

alter table public.purchase_invoices
  add column shipment_id uuid references public.import_shipments(id) on delete set null;

create table public.import_shipment_costs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  shipment_id uuid not null references public.import_shipments(id) on delete cascade,
  cost_type text not null,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null,
  base_amount numeric(18,2) not null,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  cost_date date not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  -- كيف يتوزّع هالمصروف عالأصناف. الافتراضي: الشحن حسب الحجم، والباقي حسب الوزن.
  allocation_method text default 'weight'::text not null,
  constraint import_shipment_costs_type_check check (cost_type in ('freight','customs','clearance','transport','insurance','other')),
  constraint import_shipment_costs_method_check check (allocation_method in ('value','weight','volume','quantity'))
);

-- وزن وحجم كل صنف بالكونتينر (المجموع، مش للقطعة)، من البيان الجمركي أو الفاتورة.
create table public.import_shipment_measures (
  company_id uuid not null references public.companies(id) on delete cascade,
  shipment_id uuid not null references public.import_shipments(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  weight_kg numeric(18,3) check (weight_kg is null or weight_kg >= 0),
  volume_cbm numeric(18,4) check (volume_cbm is null or volume_cbm >= 0),
  updated_at timestamp with time zone default now() not null,
  primary key (shipment_id, product_id)
);

-- آخر وزن وحجم للقطعة (من آخر كونتينر)، مشان يطلعو جاهزين بالكونتينر الجاي.
alter table public.products
  add column unit_weight_kg numeric(18,6),
  add column unit_volume_cbm numeric(18,8);

-- نتيجة التوزيع لكل صنف (للتقرير: الكلفة الواصلة للقطعة).
create table public.import_shipment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  shipment_id uuid not null references public.import_shipments(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null,
  goods_value numeric(18,2) not null,
  allocated_cost numeric(18,2) not null,
  to_inventory numeric(18,2) not null,
  to_cogs numeric(18,2) not null,
  unit_goods_cost numeric(18,4) not null,
  unit_landed_cost numeric(18,4) not null
);

create index purchase_invoices_shipment_idx on public.purchase_invoices using btree (shipment_id) where (shipment_id is not null);
create index import_shipment_costs_shipment_idx on public.import_shipment_costs using btree (shipment_id);

alter table public.import_shipments enable row level security;
alter table public.import_shipment_costs enable row level security;
alter table public.import_shipment_allocations enable row level security;
alter table public.import_shipment_measures enable row level security;

create policy import_shipment_measures_read on public.import_shipment_measures
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));

create policy import_shipments_read on public.import_shipments
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));
create policy import_shipment_costs_read on public.import_shipment_costs
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));
create policy import_shipment_allocations_read on public.import_shipment_allocations
  for select to authenticated
  using (public.has_any_permission(company_id, array['purchases.view'::text, 'purchase_invoices.view'::text]));

create or replace function public.save_import_shipment(target_company uuid, target_shipment uuid, target_container text, target_origin text, target_shipped_on date, target_expected_on date, target_arrived_on date, target_status text, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid := target_shipment;
  v_year integer := extract(year from (now() at time zone 'Asia/Damascus'))::integer;
  v_value bigint;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if coalesce(target_status, 'ordered') not in ('ordered','shipped','at_port','customs','arrived','cancelled') then
    raise exception 'Invalid shipment status';
  end if;

  if v_id is null then
    insert into public.document_sequences(company_id, document_type, sequence_year, next_value)
    values (target_company, 'import_shipment', v_year, 1)
    on conflict (company_id, document_type, sequence_year) do nothing;

    update public.document_sequences
    set next_value = next_value + 1
    where company_id = target_company and document_type = 'import_shipment' and sequence_year = v_year
    returning next_value - 1 into v_value;

    insert into public.import_shipments(company_id, shipment_number, container_number, origin_country,
      shipped_on, expected_on, arrived_on, status, notes)
    values (target_company, 'IMP-' || v_year::text || '-' || lpad(v_value::text, 4, '0'),
      nullif(trim(target_container), ''), nullif(trim(target_origin), ''),
      target_shipped_on, target_expected_on, target_arrived_on, coalesce(target_status, 'ordered'),
      nullif(trim(target_notes), ''))
    returning id into v_id;
  else
    update public.import_shipments
    set container_number = nullif(trim(target_container), ''),
        origin_country = nullif(trim(target_origin), ''),
        shipped_on = target_shipped_on,
        expected_on = target_expected_on,
        arrived_on = target_arrived_on,
        status = coalesce(target_status, status),
        notes = nullif(trim(target_notes), ''),
        updated_at = now()
    where id = v_id and company_id = target_company and status <> 'closed';

    if not found then
      raise exception 'Shipment not found or closed';
    end if;
  end if;

  return v_id;
end;
$function$;

create or replace function public.link_invoice_to_shipment(target_company uuid, target_invoice uuid, target_shipment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if target_shipment is not null and not exists (
    select 1 from public.import_shipments
    where id = target_shipment and company_id = target_company and status not in ('closed','cancelled')
  ) then
    raise exception 'Shipment not found or closed';
  end if;

  if exists (
    select 1 from public.purchase_invoices pi
    join public.import_shipments s on s.id = pi.shipment_id
    where pi.id = target_invoice and s.status = 'closed'
  ) then
    raise exception 'Shipment is closed';
  end if;

  update public.purchase_invoices
  set shipment_id = target_shipment
  where id = target_invoice and company_id = target_company and status = 'posted';

  if not found then
    raise exception 'Posted purchase invoice not found';
  end if;
end;
$function$;

-- مصروف على الشحنة (شحن، جمارك...) مدفوع من صندوق.
create or replace function public.add_shipment_cost(target_company uuid, target_shipment uuid, target_type text, target_amount numeric, target_cashbox uuid, target_date date, target_notes text, target_method text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_currency text;
  v_date date := coalesce(target_date, (now() at time zone 'Asia/Damascus')::date);
  v_entry uuid;
  v_labels jsonb := '{"freight":"شحن بحري","customs":"جمارك","clearance":"تخليص","transport":"نقل","insurance":"تأمين","other":"مصاريف أخرى"}'::jsonb;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if not public.has_any_permission(target_company, array['finance.cashbox_write','payments.supplier_create','finance.expenses_write']) then
    raise exception 'Not allowed to pay from cashbox';
  end if;

  if not exists (
    select 1 from public.import_shipments
    where id = target_shipment and company_id = target_company and status not in ('closed','cancelled')
  ) then
    raise exception 'Shipment not found or closed';
  end if;

  if target_amount is null or target_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  select currency into v_currency
  from public.cashboxes
  where id = target_cashbox and company_id = target_company and active;

  if v_currency is null then
    raise exception 'Invalid cashbox';
  end if;

  perform public.assert_finance_period_open(target_company, v_date);

  if target_method is not null and target_method not in ('value','weight','volume','quantity') then
    raise exception 'Invalid allocation method';
  end if;

  insert into public.import_shipment_costs(company_id, shipment_id, cost_type, amount, currency, base_amount, cashbox_id, cost_date, notes, allocation_method)
  values (target_company, target_shipment, target_type, round(target_amount, 2), upper(v_currency),
          round(target_amount * public.finance_rate_to_base(target_company, v_currency, v_date), 2),
          target_cashbox, v_date, nullif(trim(target_notes), ''),
          coalesce(target_method, case when target_type = 'freight' then 'volume' else 'weight' end))
  returning id into v_id;

  v_entry := public.post_system_journal(
    target_company, v_date,
    'مصروف استيراد: ' || (v_labels->>target_type),
    v_currency, null, 'import_cost', v_id,
    jsonb_build_array(
      jsonb_build_object('account_id', public.finance_system_account(target_company, 'import_costs_pending'),
                         'debit', round(target_amount, 2), 'credit', 0),
      jsonb_build_object('account_id', public.finance_cashbox_account(target_company, target_cashbox),
                         'debit', 0, 'credit', round(target_amount, 2))
    )
  );

  update public.import_shipment_costs set journal_entry_id = v_entry where id = v_id;

  insert into public.cash_transactions(company_id, cashbox_id, direction, type, amount, notes, occurred_at)
  values (target_company, target_cashbox, 'out', 'import_cost', round(target_amount, 2),
          (v_labels->>target_type) || coalesce(' - ' || nullif(trim(target_notes), ''), ''),
          (v_date::timestamp + time '12:00') at time zone 'Asia/Damascus');

  return v_id;
end;
$function$;

-- تغيير طريقة توزيع مصروف (قبل الإقفال).
create or replace function public.set_shipment_cost_method(target_company uuid, target_cost uuid, target_method text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if target_method is null or target_method not in ('value','weight','volume','quantity') then
    raise exception 'Invalid allocation method';
  end if;

  update public.import_shipment_costs c
  set allocation_method = target_method
  from public.import_shipments s
  where c.id = target_cost and c.company_id = target_company
    and s.id = c.shipment_id and s.status not in ('closed','cancelled');

  if not found then
    raise exception 'Shipment not found or closed';
  end if;
end;
$function$;

-- حفظ وزن وحجم أصناف الكونتينر (المجموع لكل صنف). فاضي = بينمسح.
-- وبيتذكّر وزن وحجم القطعة مشان يطلعو جاهزين بالكونتينر الجاي.
create or replace function public.save_shipment_measures(target_company uuid, target_shipment uuid, items_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb;
  v_product uuid;
  v_weight numeric;
  v_volume numeric;
  v_qty numeric;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1 from public.import_shipments
    where id = target_shipment and company_id = target_company and status not in ('closed','cancelled')
  ) then
    raise exception 'Shipment not found or closed';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(items_payload, '[]'::jsonb)) loop
    begin
      v_product := (v_item->>'product_id')::uuid;
      v_weight := nullif(v_item->>'weight_kg', '')::numeric;
      v_volume := nullif(v_item->>'volume_cbm', '')::numeric;
    exception when others then
      raise exception 'Invalid measures';
    end;

    if coalesce(v_weight, 0) < 0 or coalesce(v_volume, 0) < 0 then
      raise exception 'Invalid measures';
    end if;

    -- لازم الصنف يكون بفواتير هالكونتينر.
    select sum(pii.quantity) into v_qty
    from public.purchase_invoices pi
    join public.purchase_invoice_items pii on pii.invoice_id = pi.id
    where pi.company_id = target_company and pi.shipment_id = target_shipment
      and pi.status = 'posted' and pii.product_id = v_product;

    if v_qty is null then
      raise exception 'Product is not in this shipment';
    end if;

    if v_weight is null and v_volume is null then
      delete from public.import_shipment_measures
      where shipment_id = target_shipment and product_id = v_product;
    else
      insert into public.import_shipment_measures(company_id, shipment_id, product_id, weight_kg, volume_cbm)
      values (target_company, target_shipment, v_product, v_weight, v_volume)
      on conflict (shipment_id, product_id)
      do update set weight_kg = excluded.weight_kg, volume_cbm = excluded.volume_cbm, updated_at = now();

      if v_qty > 0 then
        update public.products
        set unit_weight_kg = case when v_weight > 0 then round(v_weight / v_qty, 6) else unit_weight_kg end,
            unit_volume_cbm = case when v_volume > 0 then round(v_volume / v_qty, 8) else unit_volume_cbm end
        where id = v_product and company_id = target_company;
      end if;
    end if;
  end loop;
end;
$function$;

-- معاينة التوزيع قبل الإقفال: حصة كل صنف من كل مصروف (حسب طريقة المصروف) والكلفة الواصلة للقطعة.
-- missing: مصروف بدو وزن أو حجم وهالصنف ما إلو. suggested_*: من آخر كونتينر (للتعبئة بس، ما بينحسب عليهن).
create or replace function public.preview_shipment_allocation(target_company uuid, target_shipment uuid)
 RETURNS TABLE(product_id uuid, product_name text, quantity numeric, received numeric, goods_value numeric,
               weight_kg numeric, volume_cbm numeric, suggested_weight_kg numeric, suggested_volume_cbm numeric,
               missing text, cost_breakdown jsonb,
               allocated_cost numeric, unit_goods_cost numeric, unit_landed_cost numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with lines as (
    select pii.product_id,
           sum(pii.quantity) as quantity,
           sum(public.finance_to_base(target_company, pi.currency, pii.quantity * pii.unit_cost - coalesce(pii.discount_amount, 0), pi.invoice_date)) as goods_value
    from public.purchase_invoices pi
    join public.purchase_invoice_items pii on pii.invoice_id = pi.id
    where pi.company_id = target_company and pi.shipment_id = target_shipment and pi.status = 'posted'
    group by pii.product_id
  ),
  received as (
    select gri.product_id, sum(gri.quantity) as qty
    from public.goods_receipt_items gri
    join public.goods_receipts gr on gr.id = gri.goods_receipt_id and gr.status = 'posted'
    join public.purchase_invoices pi on pi.id = gr.purchase_invoice_id
    where pi.company_id = target_company and pi.shipment_id = target_shipment and pi.status = 'posted'
    group by gri.product_id
  ),
  basis as (
    select l.product_id, l.quantity, l.goods_value, m.weight_kg, m.volume_cbm
    from lines l
    left join public.import_shipment_measures m on m.shipment_id = target_shipment and m.product_id = l.product_id
  ),
  totals as (
    select sum(goods_value) as value, sum(quantity) as quantity,
           sum(coalesce(weight_kg, 0)) as weight, sum(coalesce(volume_cbm, 0)) as volume
    from basis
  ),
  costs as (
    select c.cost_type, c.allocation_method, c.base_amount
    from public.import_shipment_costs c
    where c.shipment_id = target_shipment and c.company_id = target_company
  ),
  -- حصة كل صنف من كل مصروف، حسب طريقة هالمصروف.
  shares as (
    select b.product_id, c.cost_type,
           sum(c.base_amount * case c.allocation_method
             when 'value' then b.goods_value / nullif(t.value, 0)
             when 'quantity' then b.quantity / nullif(t.quantity, 0)
             when 'weight' then coalesce(b.weight_kg, 0) / nullif(t.weight, 0)
             when 'volume' then coalesce(b.volume_cbm, 0) / nullif(t.volume, 0)
           end) as share
    from basis b cross join costs c cross join totals t
    group by b.product_id, c.cost_type
  ),
  per_product as (
    select product_id,
           coalesce(sum(share), 0) as allocated,
           jsonb_object_agg(cost_type, round(share, 2)) filter (where share is not null) as breakdown
    from shares
    group by product_id
  ),
  needs as (
    select coalesce(bool_or(allocation_method = 'weight'), false) as weight,
           coalesce(bool_or(allocation_method = 'volume'), false) as volume
    from costs
  )
  select b.product_id, p.name, b.quantity, coalesce(r.qty, 0), round(b.goods_value, 2),
         b.weight_kg, b.volume_cbm,
         round(p.unit_weight_kg * b.quantity, 3), round(p.unit_volume_cbm * b.quantity, 4),
         nullif(concat_ws(',',
           case when n.weight and coalesce(b.weight_kg, 0) = 0 then 'weight' end,
           case when n.volume and coalesce(b.volume_cbm, 0) = 0 then 'volume' end), ''),
         coalesce(pp.breakdown, '{}'::jsonb),
         round(coalesce(pp.allocated, 0), 2),
         round(b.goods_value / nullif(b.quantity, 0), 4),
         round((b.goods_value + coalesce(pp.allocated, 0)) / nullif(b.quantity, 0), 4)
  from basis b
  join public.products p on p.id = b.product_id
  left join received r on r.product_id = b.product_id
  left join per_product pp on pp.product_id = b.product_id
  cross join needs n
  where public.has_any_permission(target_company, array['purchases.view','purchase_invoices.view'])
  order by p.name;
$function$;

-- إقفال الشحنة: توزيع المصاريف. لازم كل البضاعة تكون مستلمة.
create or replace function public.close_import_shipment(target_company uuid, target_shipment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row record;
  v_stock record;
  v_total_costs numeric(18,2);
  v_to_inventory numeric := 0;
  v_share numeric;
  v_stock_share numeric;
  v_on_hand_total numeric;
  v_delta numeric;
  v_line_inventory numeric;
  v_new_avg numeric(18,4);
  v_old_value numeric;
  v_entry uuid;
  v_date date := (now() at time zone 'Asia/Damascus')::date;
begin
  if not public.has_any_permission(target_company, array['purchases.create','purchase_invoices.create']) then
    raise exception 'Not allowed';
  end if;

  perform 1 from public.import_shipments
  where id = target_shipment and company_id = target_company and status not in ('closed','cancelled')
  for update;

  if not found then
    raise exception 'Shipment not found or closed';
  end if;

  if not exists (
    select 1 from public.purchase_invoices
    where shipment_id = target_shipment and company_id = target_company and status = 'posted'
  ) then
    raise exception 'Shipment has no purchase invoices';
  end if;

  if exists (
    select 1 from public.preview_shipment_allocation(target_company, target_shipment) x
    where x.received < x.quantity
  ) then
    raise exception 'Receive all shipment goods before closing';
  end if;

  -- مصروف حسب الوزن أو الحجم وفي صنف ما إلو وزن أو حجم = التوزيع بيطلع غلط.
  if exists (
    select 1 from public.preview_shipment_allocation(target_company, target_shipment) x
    where x.missing is not null
  ) then
    raise exception 'Missing weight or volume for some products';
  end if;

  perform public.assert_finance_period_open(target_company, v_date);

  select coalesce(sum(base_amount), 0) into v_total_costs
  from public.import_shipment_costs
  where shipment_id = target_shipment and company_id = target_company;

  for v_row in select * from public.preview_shipment_allocation(target_company, target_shipment) loop
    v_share := v_row.allocated_cost;
    v_line_inventory := 0;

    select coalesce(sum(on_hand), 0) into v_on_hand_total
    from public.inventory_stock
    where company_id = target_company and product_id = v_row.product_id;

    -- الموجود من هالصنف (لحد كمية الشحنة) بياخد حصتو بالمخزون، والباقي انباع.
    v_stock_share := case when v_row.quantity > 0
                          then v_share * least(v_on_hand_total, v_row.quantity) / v_row.quantity
                          else 0 end;

    if v_stock_share > 0 and v_on_hand_total > 0 then
      for v_stock in
        select * from public.inventory_stock
        where company_id = target_company and product_id = v_row.product_id and on_hand > 0
        for update
      loop
        v_delta := v_stock_share * v_stock.on_hand / v_on_hand_total;
        v_old_value := round(v_stock.on_hand * v_stock.average_cost, 2);
        v_new_avg := round((v_old_value + v_delta) / v_stock.on_hand, 4);
        update public.inventory_stock set average_cost = v_new_avg
        where warehouse_id = v_stock.warehouse_id and product_id = v_stock.product_id;
        -- القيمة الفعلية بعد التقريب هي اللي بتنقيّد (مشان حساب المخزون = قيمة البضاعة).
        v_line_inventory := v_line_inventory + (round(v_stock.on_hand * v_new_avg, 2) - v_old_value);
      end loop;
    end if;

    v_to_inventory := v_to_inventory + v_line_inventory;

    insert into public.import_shipment_allocations(company_id, shipment_id, product_id, quantity, goods_value,
      allocated_cost, to_inventory, to_cogs, unit_goods_cost, unit_landed_cost)
    values (target_company, target_shipment, v_row.product_id, v_row.quantity, v_row.goods_value,
      v_share, round(v_line_inventory, 2), round(v_share - v_line_inventory, 2),
      coalesce(v_row.unit_goods_cost, 0), coalesce(v_row.unit_landed_cost, 0));
  end loop;

  v_to_inventory := round(v_to_inventory, 2);

  if v_total_costs > 0 then
    v_entry := public.post_system_journal(
      target_company, v_date,
      'توزيع مصاريف الاستيراد على البضاعة',
      (select default_currency from public.companies where id = target_company),
      1, 'import_shipment', target_shipment,
      (
        select jsonb_agg(line) from (
          select jsonb_build_object('account_id', public.finance_system_account(target_company, 'inventory'),
                                    'debit', v_to_inventory, 'credit', 0) as line
          where v_to_inventory > 0
          union all
          -- تقريب كلفة القطعة لـ 4 خانات ممكن يخلّي المخزون ياخد قروش أكتر من المصاريف:
          -- الفرق (زايد أو ناقص) بيروح لكلفة المبيعات.
          select jsonb_build_object('account_id', public.finance_system_account(target_company, 'cogs'),
                                    'debit', greatest(v_total_costs - v_to_inventory, 0),
                                    'credit', greatest(v_to_inventory - v_total_costs, 0))
          where v_total_costs - v_to_inventory <> 0
          union all
          select jsonb_build_object('account_id', public.finance_system_account(target_company, 'import_costs_pending'),
                                    'debit', 0, 'credit', v_total_costs)
        ) lines
      )
    );
  end if;

  update public.import_shipments
  set status = 'closed', closed_at = now(), journal_entry_id = v_entry,
      arrived_on = coalesce(arrived_on, v_date), updated_at = now()
  where id = target_shipment;

  return jsonb_build_object('total_costs', v_total_costs, 'to_inventory', v_to_inventory,
                            'to_cogs', v_total_costs - v_to_inventory);
end;
$function$;
