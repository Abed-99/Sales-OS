begin;

-- ============================================================
-- PAYMENT CURRENCY SNAPSHOTS
-- amount / allocated_total / unallocated_total on payment
-- are always in PAYMENT / CASHBOX currency.
--
-- allocation.amount remains in INVOICE currency.
-- allocation.payment_amount is the equivalent amount taken
-- from the cashbox currency.
-- ============================================================

alter table public.customer_payments
  add column if not exists payment_currency text,
  add column if not exists exchange_rate_to_base numeric(24,10),
  add column if not exists base_amount numeric(20,4);

alter table public.supplier_payments
  add column if not exists payment_currency text,
  add column if not exists exchange_rate_to_base numeric(24,10),
  add column if not exists base_amount numeric(20,4);


alter table public.customer_payment_allocations
  add column if not exists payment_amount numeric(20,2),
  add column if not exists payment_currency text,
  add column if not exists invoice_currency text,
  add column if not exists payment_rate_to_base numeric(24,10);

alter table public.supplier_payment_allocations
  add column if not exists payment_amount numeric(20,2),
  add column if not exists payment_currency text,
  add column if not exists invoice_currency text,
  add column if not exists payment_rate_to_base numeric(24,10);


-- ============================================================
-- BACKFILL OLD SAME-CURRENCY DATA
-- Old system assumed payment currency = invoice currency.
-- ============================================================

update public.customer_payments cp
set payment_currency =
      upper(cb.currency)
from public.cashboxes cb
where cb.id = cp.cashbox_id
  and cp.payment_currency is null;


update public.supplier_payments sp
set payment_currency =
      upper(cb.currency)
from public.cashboxes cb
where cb.id = sp.cashbox_id
  and sp.payment_currency is null;


update public.customer_payment_allocations
set payment_amount = amount
where payment_amount is null;


update public.supplier_payment_allocations
set payment_amount = amount
where payment_amount is null;


update public.customer_payment_allocations a
set
  payment_currency =
    upper(
      coalesce(
        p.payment_currency,
        cb.currency
      )
    ),

  invoice_currency =
    upper(si.currency)

from public.customer_payments p,
     public.cashboxes cb,
     public.sales_invoices si

where a.payment_id =
      p.id

  and cb.id =
      p.cashbox_id

  and si.id =
      a.sales_invoice_id

  and (
    a.payment_currency is null
    or
    a.invoice_currency is null
  );


update public.supplier_payment_allocations a
set
  payment_currency =
    upper(
      coalesce(
        p.payment_currency,
        cb.currency
      )
    ),

  invoice_currency =
    upper(pi.currency)

from public.supplier_payments p,
     public.cashboxes cb,
     public.purchase_invoices pi

where a.payment_id =
      p.id

  and cb.id =
      p.cashbox_id

  and pi.id =
      a.purchase_invoice_id

  and (
    a.payment_currency is null
    or
    a.invoice_currency is null
  );


-- ============================================================
-- PAYMENT TOTALS
-- IMPORTANT:
-- allocation.amount = invoice currency
-- payment_amount = cashbox currency
-- ============================================================

create or replace function public.refresh_customer_payment_totals(
  target_payment uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.refresh_customer_payment_totals(uuid)
from public, authenticated;


create or replace function public.refresh_supplier_payment_totals(
  target_payment uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.refresh_supplier_payment_totals(uuid)
from public, authenticated;


-- ============================================================
-- CONVERSION PREVIEW
--
-- Example:
-- Company base = USD
-- Invoice = USD 100
-- Payment currency = SYP
-- rate_to_base = USD value of 1 SYP
--
-- payment amount = 100 / rate_to_base
-- ============================================================

create or replace function public.payment_currency_quote(
  target_company uuid,
  target_invoice_currency text,
  target_payment_currency text,
  target_invoice_amount numeric,
  target_payment_date date
)
returns table(
  invoice_currency text,
  payment_currency text,
  invoice_amount numeric,
  payment_amount numeric,
  payment_rate_to_base numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_invoice_currency text;
  v_payment_currency text;
  v_rate numeric(24,10);
begin
  if not public.has_any_permission(
    target_company,
    array[
      'payments.sales_view',
      'payments.sales_create',
      'payments.supplier_view',
      'payments.supplier_create',
      'finance.accounts_view'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if target_invoice_amount is null
     or target_invoice_amount <= 0
  then
    raise exception
      'Invalid amount';
  end if;

  select upper(default_currency)
  into v_base
  from public.companies
  where id =
        target_company;

  if v_base is null then
    raise exception
      'Company not found';
  end if;

  v_invoice_currency :=
    upper(
      trim(
        target_invoice_currency
      )
    );

  v_payment_currency :=
    upper(
      trim(
        target_payment_currency
      )
    );

  if v_invoice_currency =
     v_payment_currency
  then
    return query
    select
      v_invoice_currency,
      v_payment_currency,
      round(
        target_invoice_amount,
        2
      ),
      round(
        target_invoice_amount,
        2
      ),
      1::numeric;

    return;
  end if;

  -- Current professional rule:
  -- cross-currency settlement is allowed when the debt
  -- itself is in the company's base currency.
  if v_invoice_currency <>
     v_base
  then
    raise exception
      'Cross-currency settlement currently requires invoice currency to be company base currency';
  end if;

  v_rate :=
    public.finance_rate_to_base(
      target_company,
      v_payment_currency,
      coalesce(
        target_payment_date,
        current_date
      )
    );

  return query
  select
    v_invoice_currency,
    v_payment_currency,
    round(
      target_invoice_amount,
      2
    ),
    round(
      target_invoice_amount /
      v_rate,
      2
    ),
    v_rate;
end;
$$;

revoke all
on function public.payment_currency_quote(
  uuid,
  text,
  text,
  numeric,
  date
)
from public;

grant execute
on function public.payment_currency_quote(
  uuid,
  text,
  text,
  numeric,
  date
)
to authenticated;


-- ============================================================
-- CUSTOMER PAYMENT
--
-- target_amount:
--   physical amount received in CASHBOX currency.
--
-- allocations_payload.amount:
--   amount clearing the invoice in INVOICE currency.
-- ============================================================

create or replace function public.record_customer_payment(
  target_company uuid,
  target_trader uuid,
  target_cashbox uuid,
  target_amount numeric,
  target_payment_date date,
  target_method text,
  target_reference text,
  target_notes text,
  allocations_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;

  v_method text;

  v_base_currency text;
  v_payment_currency text;
  v_payment_rate numeric(24,10);
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
$$;

revoke all
on function public.record_customer_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  jsonb
)
from public;

grant execute
on function public.record_customer_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- SUPPLIER PAYMENT
-- Same currency model as customer payment.
-- ============================================================

create or replace function public.record_supplier_payment(
  target_company uuid,
  target_supplier uuid,
  target_cashbox uuid,
  target_amount numeric,
  target_payment_date date,
  target_method text,
  target_reference text,
  target_notes text,
  allocations_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment uuid;
  v_number text;
  v_cashbox uuid;

  v_method text;

  v_base_currency text;
  v_payment_currency text;
  v_payment_rate numeric(24,10);
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
$$;

revoke all
on function public.record_supplier_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  jsonb
)
from public;

grant execute
on function public.record_supplier_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- AUTO CUSTOMER ADVANCE
--
-- For safety, automatic credit application only uses advances
-- in the SAME currency as the invoice.
--
-- Cross-currency credit must be allocated explicitly so the
-- payment-day FX rate is visible and intentional.
-- ============================================================

create or replace function public.apply_customer_credit_to_invoice(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
        1
      )
      on conflict(
        payment_id,
        sales_invoice_id
      )
      do nothing;

    end if;

  end loop;
end;
$$;

revoke all
on function public.apply_customer_credit_to_invoice(uuid)
from public, authenticated;


-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists
customer_payments_currency_idx
on public.customer_payments(
  company_id,
  payment_currency,
  payment_date desc
);

create index if not exists
supplier_payments_currency_idx
on public.supplier_payments(
  company_id,
  payment_currency,
  payment_date desc
);

commit;