-- ======================================================================
-- الاستيراد (الكونتينر): شحنة بتجمع فواتير شراء + مصاريفها (شحن، جمارك، تخليص...).
-- المصاريف بتتجمّع بحساب "تكاليف استيراد بانتظار التوزيع"، ولما تنسكّر الشحنة بتتوزّع
-- على أصنافها حسب القيمة: حصة الموجود بالمخزون بترفع كلفتو، وحصة المباع بتروح لكلفة المبيعات.
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
  constraint import_shipment_costs_type_check check (cost_type in ('freight','customs','clearance','transport','insurance','other'))
);

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
create or replace function public.add_shipment_cost(target_company uuid, target_shipment uuid, target_type text, target_amount numeric, target_cashbox uuid, target_date date, target_notes text)
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
  v_labels jsonb := '{"freight":"شحن بحري","customs":"جمارك","clearance":"تخليص","transport":"نقل","insurance":"تأمين","other":"مصاريف أخرى"}';
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

  insert into public.import_shipment_costs(company_id, shipment_id, cost_type, amount, currency, base_amount, cashbox_id, cost_date, notes)
  values (target_company, target_shipment, target_type, round(target_amount, 2), upper(v_currency),
          round(target_amount * public.finance_rate_to_base(target_company, v_currency, v_date), 2),
          target_cashbox, v_date, nullif(trim(target_notes), ''))
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

-- معاينة التوزيع قبل الإقفال: حصة كل صنف والكلفة الواصلة للقطعة.
create or replace function public.preview_shipment_allocation(target_company uuid, target_shipment uuid)
 RETURNS TABLE(product_id uuid, product_name text, quantity numeric, received numeric, goods_value numeric, allocated_cost numeric, unit_goods_cost numeric, unit_landed_cost numeric)
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
  costs as (
    select coalesce(sum(base_amount), 0) as total
    from public.import_shipment_costs
    where shipment_id = target_shipment and company_id = target_company
  ),
  totals as (select coalesce(sum(goods_value), 0) as value from lines)
  select l.product_id, p.name, l.quantity, coalesce(r.qty, 0), round(l.goods_value, 2),
         round(case when t.value > 0 then c.total * l.goods_value / t.value else 0 end, 2),
         round(l.goods_value / nullif(l.quantity, 0), 4),
         round((l.goods_value + case when t.value > 0 then c.total * l.goods_value / t.value else 0 end) / nullif(l.quantity, 0), 4)
  from lines l
  join public.products p on p.id = l.product_id
  left join received r on r.product_id = l.product_id
  cross join costs c
  cross join totals t
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
        v_old_value := v_stock.on_hand * v_stock.average_cost;
        v_new_avg := round((v_old_value + v_delta) / v_stock.on_hand, 4);
        update public.inventory_stock set average_cost = v_new_avg
        where warehouse_id = v_stock.warehouse_id and product_id = v_stock.product_id;
        -- القيمة الفعلية بعد التقريب هي اللي بتنقيّد (مشان حساب المخزون = قيمة البضاعة).
        v_line_inventory := v_line_inventory + (v_stock.on_hand * v_new_avg - v_old_value);
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
          select jsonb_build_object('account_id', public.finance_system_account(target_company, 'cogs'),
                                    'debit', v_total_costs - v_to_inventory, 'credit', 0)
          where v_total_costs - v_to_inventory > 0
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
