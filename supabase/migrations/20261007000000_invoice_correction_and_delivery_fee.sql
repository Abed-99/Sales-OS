-- تصحيح فاتورة البيع + أجرة التوصيل (على الزبون أو علينا).
-- ما بيمسح ولا بيغيّر أي بيانات موجودة: أعمدة جديدة بقيم افتراضية، ودوال جديدة/محدّثة،
-- وحسابين جداد (4500 إيرادات التوصيل، 6700 مصاريف التوصيل) بينضافوا لكل شركة.

SET local check_function_bodies = off;

-- الأعمدة الجديدة بالفاتورة (الفواتير القديمة بتاخد 0 / فاضي).
alter table public.sales_invoices
  add column delivery_fee numeric(14,2) default 0 not null,
  add column delivery_expense_id uuid references public.expenses(id) on delete set null,
  add column corrected_from_id uuid references public.sales_invoices(id) on delete restrict,
  add constraint sales_invoices_delivery_fee_check check ((delivery_fee >= (0)::numeric));

-- تحرير الدفعة صار ممكن بسبب تصحيح فاتورة كمان (مش بس مرتجع).
alter table public.customer_payment_releases
  alter column sales_return_id drop not null;

-- الدوال اللي تغيّرت مدخلاتها: منشيل النسخة القديمة لحتى ما يصير في نسختين.
drop function public.complete_order_delivery(uuid, uuid, text);
drop function public.quick_sale(uuid, uuid, jsonb, uuid, numeric, numeric, text, text);

create or replace function public.complete_order_delivery(target_company uuid, target_order uuid, target_notes text DEFAULT NULL::text, target_delivery_fee numeric DEFAULT 0, target_delivery_cost numeric DEFAULT 0, target_cost_cashbox uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fee numeric(14,2) := round(coalesce(target_delivery_fee, 0), 2);
  v_cost numeric(14,2) := round(coalesce(target_delivery_cost, 0), 2);
  v_expense uuid;
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
  v_tax numeric(14,2) := 0;

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

  if v_fee < 0 or v_cost < 0 then
    raise exception 'Invalid delivery fee';
  end if;

  if v_cost > 0 and target_cost_cashbox is null then
    raise exception 'Cashbox required';
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

  -- الضريبة (إذا مفعّلة بالإعدادات) بتنضاف عالصافي.
  select case when c.tax_enabled then round(v_total * c.tax_rate / 100, 2) else 0 end
  into v_tax
  from public.companies c
  where c.id = target_company;

  v_tax := coalesce(v_tax, 0);
  -- أجرة التوصيل عالزبون بتنضاف بعد الضريبة (ما عليها ضريبة).
  v_total := v_total + v_tax + v_fee;

  v_invoice_number :=
    public.next_sales_invoice_number(
      target_company,
      v_now::date
    );

  -- أجرة التوصيل علينا: مصروف "توصيل" من الصندوق (بدها صلاحية المصاريف).
  if v_cost > 0 then
    v_expense := public.record_expense(
      target_company,
      target_cost_cashbox,
      'توصيل',
      v_cost,
      'توصيل فاتورة ' || v_invoice_number
    );
  end if;

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
    tax_total,
    delivery_fee,
    delivery_expense_id,
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
    v_tax,
    v_fee,
    v_expense,
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

create or replace function public.quick_sale(target_company uuid, target_trader uuid, items_payload jsonb, target_cashbox uuid, target_paid_amount numeric, target_cash_amount numeric, target_method text DEFAULT 'cash'::text, target_notes text DEFAULT NULL::text, target_delivery_fee numeric DEFAULT 0, target_delivery_cost numeric DEFAULT 0, target_cost_cashbox uuid DEFAULT NULL::uuid)
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
  v_paid numeric(18,2);
  v_due numeric(18,2);
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
  v_invoice := public.complete_order_delivery(
    target_company, v_order, 'بيع سريع',
    target_delivery_fee, target_delivery_cost, target_cost_cashbox
  );

  select total, currency into v_total, v_currency from public.sales_invoices where id = v_invoice;

  -- بدون مبلغ محدد = دفع كامل (مع الضريبة إذا في).
  v_paid := round(coalesce(target_paid_amount, v_total), 2);

  if v_paid > v_total then
    raise exception 'Paid amount exceeds invoice total';
  end if;

  -- إذا الزبون إلو رصيد عنا (مثلًا من مرتجع)، بيتخصم لحالو من الفاتورة،
  -- فمنقبض بس الباقي، والمبلغ بعملة الصندوق بينزل بنفس النسبة.
  select balance_due into v_due from public.sales_invoices where id = v_invoice;
  if v_paid > v_due then
    if target_cash_amount is not null and v_paid > 0 then
      target_cash_amount := round(target_cash_amount * v_due / v_paid, 2);
    end if;
    v_paid := v_due;
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
    'paid', v_paid,
    'credit_used', v_total - v_due
  );
end;
$function$;

create or replace function public.correct_sales_invoice(target_company uuid, target_invoice uuid, target_reason text, items_payload jsonb, target_delivery_fee numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reason text := nullif(trim(coalesce(target_reason, '')), '');
  v_old public.sales_invoices%rowtype;
  v_order_status text;
  v_item jsonb;
  v_needs_approval boolean := false;
  v_result jsonb;
  v_order uuid;
  v_status text;
  v_delivery_items jsonb;
  v_invoice uuid;
  v_alloc record;
  v_moves jsonb := '[]'::jsonb;
  v_move jsonb;
  v_release uuid;
  v_ar uuid;
  v_advance uuid;
  v_balance numeric(14,2);
  v_unallocated numeric(20,2);
  v_apply numeric(14,2);
  v_apply_pay numeric(20,2);
  v_label text;
  v_today date := (now() at time zone 'Asia/Damascus')::date;
begin
  if not public.has_permission(target_company, 'sales_invoices.cancel')
     and not public.use_owner_override(target_company, 'cancel_invoice')
  then
    raise exception 'Not allowed';
  end if;

  if v_reason is null then
    raise exception 'Correction reason required';
  end if;

  if items_payload is null or jsonb_typeof(items_payload) <> 'array' or jsonb_array_length(items_payload) = 0 then
    raise exception 'Correction requires items';
  end if;

  if coalesce(target_delivery_fee, 0) < 0 then
    raise exception 'Invalid delivery fee';
  end if;

  select * into v_old
  from public.sales_invoices
  where id = target_invoice
    and company_id = target_company
  for update;

  if v_old.id is null then
    raise exception 'Sales invoice not found';
  end if;

  if v_old.status <> 'posted' then
    raise exception 'Only posted invoices can be corrected';
  end if;

  -- بس فاتورة طلبية مسلّمة كلها بفاتورة وحدة (البيع العادي والبيع السريع).
  select status into v_order_status
  from public.sales_orders
  where id = v_old.order_id
  for update;

  if v_order_status <> 'delivered'
     or exists (
       select 1 from public.sales_invoices si
       where si.order_id = v_old.order_id
         and si.id <> target_invoice
         and si.status = 'posted'
     )
  then
    raise exception 'Order has other invoices';
  end if;

  -- أي سعر تحت الكلفة أو أقل سعر: بدها صلاحية الخصم أو رمز المالك (متل البيع السريع).
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

  v_label := 'تصحيح الفاتورة ' || v_old.invoice_number;

  -- ١. الدفعات اللي عالفاتورة القديمة بتتحرّر (متل المرتجع) لحتى تنتقل عالجديدة.
  v_ar := public.finance_system_account(target_company, 'accounts_receivable');
  v_advance := public.finance_system_account(target_company, 'customer_advances');

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
    join public.customer_payments p on p.id = a.payment_id
    where a.sales_invoice_id = target_invoice
      and p.status = 'posted'
    order by p.payment_date, p.created_at
    for update of a
  loop
    insert into public.customer_payment_releases(
      company_id, payment_id, allocation_id, sales_return_id, sales_invoice_id,
      amount, payment_amount, payment_currency
    )
    values(
      target_company, v_alloc.payment_id, v_alloc.id, null, target_invoice,
      v_alloc.amount,
      coalesce(v_alloc.payment_amount, v_alloc.amount),
      coalesce(v_alloc.payment_currency, v_old.currency)
    )
    returning id into v_release;

    perform public.post_system_journal(
      target_company,
      v_today,
      'تحرير دفعة لـ' || v_label,
      coalesce(v_alloc.payment_currency, v_old.currency),
      v_alloc.journal_rate,
      'customer_payment_release',
      v_release,
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_ar,
          'debit', coalesce(v_alloc.payment_amount, v_alloc.amount),
          'credit', 0,
          'party_type', 'trader',
          'party_id', v_old.trader_id,
          'memo', 'تحرير دفعة'
        ),
        jsonb_build_object(
          'account_id', v_advance,
          'debit', 0,
          'credit', coalesce(v_alloc.payment_amount, v_alloc.amount),
          'party_type', 'trader',
          'party_id', v_old.trader_id,
          'memo', 'رصيد دائن للعميل'
        )
      )
    );

    v_moves := v_moves || jsonb_build_array(jsonb_build_object(
      'payment_id', v_alloc.payment_id,
      'amount', v_alloc.amount,
      'payment_amount', coalesce(v_alloc.payment_amount, v_alloc.amount),
      'payment_currency', v_alloc.payment_currency,
      'invoice_currency', v_alloc.invoice_currency,
      'rate', v_alloc.payment_rate_to_base
    ));

    delete from public.customer_payment_allocations where id = v_alloc.id;
  end loop;

  -- ٢. الفاتورة القديمة بتنلغى (البضاعة بترجع للمستودع والقيد بينعكس) وطلبيتها بتتسكّر.
  perform public.cancel_sales_invoice(target_company, target_invoice, 'تصحيح: ' || v_reason);

  update public.sales_orders
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    cancellation_reason = v_label || ': ' || v_reason
  where id = v_old.order_id;

  -- ٣. الفاتورة الجديدة: طلبية وتسليم وفاتورة لنفس الزبون، بدون طلعة توصيل جديدة.
  perform set_config('app.elevated_company', target_company::text, true);
  perform set_config(
    'app.elevated_permissions',
    'orders.create,deliveries.update'
      || case when v_needs_approval then ',orders.approve_discount' else '' end,
    true
  );

  v_result := public.create_sales_order_v2(target_company, v_old.trader_id, v_label, items_payload, null);
  v_order := nullif(v_result->>'order_id', '')::uuid;

  if v_order is null then
    raise exception 'Correction could not create the order';
  end if;

  select status into v_status from public.sales_orders where id = v_order;

  if v_status <> 'ready' then
    raise exception 'Not enough stock for corrected invoice';
  end if;

  select jsonb_agg(jsonb_build_object('sales_order_item_id', soi.id, 'quantity', soi.quantity))
  into v_delivery_items
  from public.sales_order_items soi
  where soi.order_id = v_order;

  perform public.create_order_delivery(target_company, v_order, v_delivery_items);
  v_invoice := public.complete_order_delivery(target_company, v_order, v_label, target_delivery_fee, 0, null);

  update public.sales_invoices
  set corrected_from_id = target_invoice
  where id = v_invoice;

  -- ٤. الدفعات المحرّرة بترجع عالفاتورة الجديدة (بنفس عملتها وسعرها). اللي بيزيد بيضل رصيد للزبون.
  for v_move in select value from jsonb_array_elements(v_moves) loop
    select balance_due into v_balance from public.sales_invoices where id = v_invoice for update;
    exit when coalesce(v_balance, 0) <= 0;

    select unallocated_total into v_unallocated
    from public.customer_payments
    where id = (v_move->>'payment_id')::uuid
    for update;

    v_apply_pay := least((v_move->>'payment_amount')::numeric, coalesce(v_unallocated, 0));
    continue when v_apply_pay <= 0;

    v_apply := round((v_move->>'amount')::numeric * v_apply_pay / (v_move->>'payment_amount')::numeric, 2);

    if v_apply > v_balance then
      v_apply := v_balance;
      v_apply_pay := round((v_move->>'payment_amount')::numeric * v_apply / (v_move->>'amount')::numeric, 2);
    end if;

    continue when v_apply <= 0;

    insert into public.customer_payment_allocations(
      company_id, payment_id, sales_invoice_id, amount, payment_amount,
      payment_currency, invoice_currency, payment_rate_to_base
    )
    values(
      target_company,
      (v_move->>'payment_id')::uuid,
      v_invoice,
      v_apply,
      v_apply_pay,
      v_move->>'payment_currency',
      v_move->>'invoice_currency',
      nullif(v_move->>'rate', '')::numeric
    )
    on conflict(payment_id, sales_invoice_id) do nothing;
  end loop;

  return (
    select jsonb_build_object(
      'invoice_id', si.id,
      'invoice_number', si.invoice_number,
      'order_id', si.order_id,
      'total', si.total,
      'balance_due', si.balance_due,
      'currency', si.currency
    )
    from public.sales_invoices si
    where si.id = v_invoice
  );
end;
$function$;

create or replace function public.gl_sales_invoice_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ar uuid;
  v_sales uuid;
  v_discount uuid;
  v_lines jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'sales_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة بيع ' ||
        new.invoice_number
      );

    return new;
  end if;

  if new.status <> 'posted' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = new.status
  then
    return new;
  end if;

  if new.total <= 0
     and new.subtotal <= 0
  then
    return new;
  end if;

  v_ar :=
    public.finance_system_account(
      new.company_id,
      'accounts_receivable'
    );

  v_sales :=
    public.finance_system_account(
      new.company_id,
      'sales_revenue'
    );

  v_discount :=
    public.finance_system_account(
      new.company_id,
      'sales_discounts'
    );

  if new.total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          new.total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'ذمة فاتورة بيع'
        )
      );
  end if;

  if new.discount_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_discount,
          'debit',
          new.discount_total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'خصم مبيعات'
        )
      );
  end if;

  if coalesce(new.tax_total, 0) > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          public.finance_system_account(new.company_id, 'tax_payable'),
          'debit',
          0,
          'credit',
          new.tax_total,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'ضريبة مبيعات'
        )
      );
  end if;

  if coalesce(new.delivery_fee, 0) > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          public.finance_system_account(new.company_id, 'delivery_revenue'),
          'debit',
          0,
          'credit',
          new.delivery_fee,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'أجرة توصيل'
        )
      );
  end if;

  if new.subtotal > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_sales,
          'debit',
          0,
          'credit',
          new.subtotal,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'إيراد مبيعات'
        )
      );
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      new.invoice_date,
      'فاتورة بيع ' ||
      new.invoice_number,
      new.currency,
      null,
      'sales_invoice',
      new.id,
      v_lines
    );

  return new;
end;
$function$;

create or replace function public.gl_expense_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_expense uuid;
begin
  if new.cashbox_id is null then
    raise exception
      'Expense requires cashbox for automatic accounting';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  -- مصروف التوصيل بحساب لحالو، لحتى يبين قديش عم يكلّفنا التوصيل.
  v_expense :=
    public.finance_system_account(
      new.company_id,
      case when new.category = 'توصيل' then 'delivery_expense' else 'operating_expense' end
    );

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'مصروف - ' ||
      new.category,
      v_currency,
      null,
      'expense',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_expense,
          'debit',
          new.amount,
          'credit',
          0,
          'memo',
          new.category
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'memo',
          new.category
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.ensure_default_chart_of_accounts(target_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  -- Main groups
  insert into public.finance_accounts(
    company_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    allow_posting,
    is_system
  )
  values
  (
    target_company,
    '1000',
    'الأصول',
    'asset',
    'assets',
    'debit',
    false,
    true
  ),
  (
    target_company,
    '2000',
    'الالتزامات',
    'liability',
    'liabilities',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '3000',
    'حقوق الملكية',
    'equity',
    'equity',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '4000',
    'الإيرادات',
    'revenue',
    'revenue',
    'credit',
    false,
    true
  ),
  (
    target_company,
    '5000',
    'تكلفة المبيعات',
    'expense',
    'cost_of_sales',
    'debit',
    false,
    true
  ),
  (
    target_company,
    '6000',
    'المصاريف',
    'expense',
    'expenses',
    'debit',
    false,
    true
  )
  on conflict(
    company_id,
    code
  )
  do nothing;


  -- Assets
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1100',
    'الصندوق والبنوك',
    'asset',
    'cash_bank',
    'debit',
    null,
    false,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1110',
    'الصندوق الرئيسي',
    'asset',
    'cash_bank',
    'debit',
    'cash_default',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1100'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1200',
    'ذمم العملاء',
    'asset',
    'receivables',
    'debit',
    'accounts_receivable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1300',
    'المخزون',
    'asset',
    'inventory',
    'debit',
    'inventory',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1400',
    'سلف وقروض الموظفين',
    'asset',
    'employee_receivables',
    'debit',
    'employee_advances',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1500',
    'الأصول الثابتة',
    'asset',
    'fixed_assets',
    'debit',
    'fixed_assets',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '1590',
    'مجمع إهلاك الأصول',
    'asset',
    'fixed_assets',
    'credit',
    'accumulated_depreciation',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '1000'
  on conflict(company_id,code)
  do nothing;


  -- Liabilities
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2100',
    'ذمم الموردين',
    'liability',
    'payables',
    'credit',
    'accounts_payable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2200',
    'رواتب وأجور مستحقة',
    'liability',
    'payroll',
    'credit',
    'payroll_payable',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '2300',
    'اقتطاعات وضرائب رواتب مستحقة',
    'liability',
    'payroll',
    'credit',
    'payroll_withholdings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '2000'
  on conflict(company_id,code)
  do nothing;


  -- Equity
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3100',
    'رأس المال',
    'equity',
    'capital',
    'credit',
    'capital',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3200',
    'مسحوبات وجاري الشركاء',
    'equity',
    'partner_drawings',
    'debit',
    'partner_drawings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '3300',
    'الأرباح المحتجزة',
    'equity',
    'retained_earnings',
    'credit',
    'retained_earnings',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '3000'
  on conflict(company_id,code)
  do nothing;


  -- Revenue
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '4100',
    'إيرادات المبيعات',
    'revenue',
    'sales',
    'credit',
    'sales_revenue',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '4000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '4200',
    'مردودات ومسموحات المبيعات',
    'revenue',
    'sales_returns',
    'debit',
    'sales_returns',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '4000'
  on conflict(company_id,code)
  do nothing;


  -- Cost of sales
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '5100',
    'تكلفة البضاعة المباعة',
    'expense',
    'cost_of_sales',
    'debit',
    'cogs',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '5000'
  on conflict(company_id,code)
  do nothing;


  -- Expenses
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6100',
    'الرواتب والأجور',
    'expense',
    'payroll',
    'debit',
    'salary_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6110',
    'بدلات ومكافآت الموظفين',
    'expense',
    'payroll',
    'debit',
    'payroll_benefits_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6120',
    'مساهمات صاحب العمل',
    'expense',
    'payroll',
    'debit',
    'employer_contribution_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6200',
    'مصاريف تشغيلية عامة',
    'expense',
    'operating_expense',
    'debit',
    'operating_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6300',
    'مصروف الإهلاك',
    'expense',
    'depreciation',
    'debit',
    'depreciation_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;


  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    '6400',
    'فروقات وتسويات المخزون',
    'expense',
    'inventory_adjustments',
    'debit',
    'inventory_adjustment_expense',
    true,
    true
  from public.finance_accounts p
  where p.company_id = target_company
    and p.code = '6000'
  on conflict(company_id,code)
  do nothing;

  -- حسابات بتطلبها القيود التلقائية. بدونها بيفشل القبض والدفع وفواتير البيع والشراء.
  insert into public.finance_accounts(
    company_id,
    parent_id,
    code,
    name,
    account_type,
    account_group,
    normal_balance,
    system_key,
    allow_posting,
    is_system
  )
  select
    target_company,
    p.id,
    v.code,
    v.name,
    v.account_type,
    v.system_key,
    v.normal_balance,
    v.system_key,
    true,
    true
  from (
    values
      ('1600', '1000', 'دفعات مقدمة للموردين', 'asset', 'debit', 'supplier_advances'),
      ('2400', '2000', 'قروض الشركاء', 'liability', 'credit', 'partner_loans'),
      ('2500', '2000', 'دفعات مقدمة من العملاء', 'liability', 'credit', 'customer_advances'),
      ('2600', '2000', 'بضاعة مستلمة بانتظار الفاتورة', 'liability', 'credit', 'inventory_clearing'),
      ('3400', '3000', 'أرباح موزعة مستحقة', 'equity', 'debit', 'profit_distributions'),
      ('3500', '3000', 'أرصدة افتتاحية', 'equity', 'credit', 'opening_balance_equity'),
      ('4300', '4000', 'خصومات المبيعات', 'revenue', 'debit', 'sales_discounts'),
      ('5200', '5000', 'فروقات أسعار الشراء', 'expense', 'debit', 'purchase_variance'),
      ('4400', '4000', 'أرباح بيع أصول', 'revenue', 'credit', 'asset_disposal_gain'),
      ('6500', '6000', 'خسائر بيع وشطب أصول', 'expense', 'debit', 'asset_disposal_loss'),
      ('6600', '6000', 'خسائر بضاعة تالفة', 'expense', 'debit', 'damaged_goods_expense'),
      ('2700', '2000', 'ضريبة مبيعات مستحقة', 'liability', 'credit', 'tax_payable'),
      ('1700', '1000', 'تكاليف استيراد بانتظار التوزيع', 'asset', 'debit', 'import_costs_pending'),
      ('4500', '4000', 'إيرادات أجور التوصيل', 'revenue', 'credit', 'delivery_revenue'),
      ('6700', '6000', 'مصاريف التوصيل', 'expense', 'debit', 'delivery_expense')
  ) as v(code, parent_code, name, account_type, normal_balance, system_key)
  join public.finance_accounts p
    on p.company_id = target_company
   and p.code = v.parent_code
  on conflict do nothing;

end;
$function$;

-- الحسابين الجداد لكل الشركات الموجودة (ما بيلمس الحسابات الموجودة).
select public.ensure_default_chart_of_accounts(id) from public.companies;
