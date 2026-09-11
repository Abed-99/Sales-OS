begin;

-- ============================================================
-- CUSTOMER / SUPPLIER CREDIT TERMS
-- ============================================================

alter table public.traders
add column if not exists credit_limit numeric(14,2)
check (
  credit_limit is null
  or credit_limit >= 0
);

alter table public.traders
add column if not exists payment_terms_days integer
not null default 0
check (
  payment_terms_days >= 0
  and payment_terms_days <= 3650
);

alter table public.suppliers
add column if not exists payment_terms_days integer
not null default 0
check (
  payment_terms_days >= 0
  and payment_terms_days <= 3650
);


-- ============================================================
-- CREDIT OVERRIDE PERMISSION
-- ============================================================

insert into public.permissions(
  code,
  module,
  action,
  label,
  sort_order
)
values(
  'orders.override_credit_limit',
  'orders',
  'override_credit_limit',
  'تجاوز حد ائتمان العميل',
  75
)
on conflict (code)
do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  sort_order = excluded.sort_order;

insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  'orders.override_credit_limit'
from public.company_roles r
where r.is_owner = true
on conflict do nothing;


-- ============================================================
-- CUSTOMER CREDIT EXPOSURE
-- Outstanding invoices + not-yet-invoiced sales
-- ============================================================

create or replace function public.trader_credit_exposure(
  target_company uuid,
  target_trader uuid
)
returns table(
  open_receivables numeric,
  open_orders numeric,
  total_exposure numeric,
  credit_limit numeric,
  available_credit numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit numeric(14,2);
  v_receivables numeric(14,2);
  v_orders numeric(14,2);
begin
  if not public.has_any_permission(
    target_company,
    array[
      'orders.view',
      'orders.create',
      'traders.view_balance',
      'payments.sales_view',
      'reports.sales',
      'reports.finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select t.credit_limit
  into v_limit
  from public.traders t
  where t.id = target_trader
    and t.company_id = target_company;

  if not found then
    raise exception 'العميل غير موجود';
  end if;

  select
    round(
      coalesce(
        sum(si.balance_due),
        0
      ),
      2
    )
  into v_receivables
  from public.sales_invoices si
  where si.company_id = target_company
    and si.trader_id = target_trader
    and si.status = 'posted'
    and si.balance_due > 0;

  select
    round(
      coalesce(
        sum(
          greatest(
            so.total -
            coalesce(
              (
                select sum(si.total)
                from public.sales_invoices si
                where si.company_id = target_company
                  and si.order_id = so.id
                  and si.status = 'posted'
              ),
              0
            ),
            0
          )
        ),
        0
      ),
      2
    )
  into v_orders
  from public.sales_orders so
  where so.company_id = target_company
    and so.trader_id = target_trader
    and so.status <> 'cancelled';

  return query
  select
    v_receivables,
    v_orders,
    round(
      v_receivables +
      v_orders,
      2
    ),
    v_limit,
    case
      when v_limit is null
        then null
      else round(
        v_limit -
        v_receivables -
        v_orders,
        2
      )
    end;
end;
$$;

revoke all
on function public.trader_credit_exposure(
  uuid,
  uuid
)
from public;

grant execute
on function public.trader_credit_exposure(
  uuid,
  uuid
)
to authenticated;


-- ============================================================
-- ENFORCE CUSTOMER CREDIT LIMIT
-- Checks when order value / customer changes.
-- Owner may override through permission.
-- ============================================================

create or replace function public.enforce_sales_order_credit_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
  then
    raise exception
      'تم تجاوز حد ائتمان العميل. الحد: %، الانكشاف بعد الطلب: %',
      round(v_limit,2),
      round(v_exposure,2);
  end if;

  return new;
end;
$$;

drop trigger if exists
sales_orders_credit_limit_guard
on public.sales_orders;

create trigger
sales_orders_credit_limit_guard
before insert
or update of trader_id,total
on public.sales_orders
for each row
execute function
public.enforce_sales_order_credit_limit();


-- ============================================================
-- AUTOMATIC CUSTOMER DUE DATE
-- Existing delivery workflow creates same-day due date.
-- Replace it with the customer's payment terms.
-- ============================================================

create or replace function public.apply_customer_payment_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists
sales_invoice_payment_terms
on public.sales_invoices;

create trigger
sales_invoice_payment_terms
before insert
on public.sales_invoices
for each row
execute function
public.apply_customer_payment_terms();


-- ============================================================
-- AUTOMATIC SUPPLIER DUE DATE
-- ============================================================

create or replace function public.apply_supplier_payment_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists
purchase_invoice_payment_terms
on public.purchase_invoices;

create trigger
purchase_invoice_payment_terms
before insert
on public.purchase_invoices
for each row
execute function
public.apply_supplier_payment_terms();


-- ============================================================
-- RECEIVABLE AGING
-- Aging is based on DUE DATE, not invoice date.
-- ============================================================

create or replace function public.get_receivables_aging(
  target_company uuid,
  target_as_of date
)
returns table(
  trader_id uuid,
  trader_name text,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  over_90 numeric,
  total_due numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'reports.sales',
      'payments.sales_view',
      'traders.view_balance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    t.id,
    t.name,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) <= 0
            then si.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 1 and 30
            then si.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 31 and 60
            then si.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) between 61 and 90
            then si.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                si.due_date,
                si.invoice_date
              )
            ) > 90
            then si.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(si.balance_due),
        0
      ),
      2
    )

  from public.traders t

  join public.sales_invoices si
    on si.trader_id = t.id
   and si.company_id =
       target_company
   and si.status = 'posted'
   and si.invoice_date <=
       coalesce(
         target_as_of,
         current_date
       )
   and si.balance_due > 0

  where t.company_id =
        target_company

  group by
    t.id,
    t.name

  having
    sum(si.balance_due) > 0

  order by
    total_due desc,
    t.name;
end;
$$;


-- ============================================================
-- PAYABLE AGING
-- ============================================================

create or replace function public.get_payables_aging(
  target_company uuid,
  target_as_of date
)
returns table(
  supplier_id uuid,
  supplier_name text,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  over_90 numeric,
  total_due numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'purchases.view',
      'payments.supplier_view',
      'suppliers.view_finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    s.id,
    s.name,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) <= 0
            then pi.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 1 and 30
            then pi.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 31 and 60
            then pi.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) between 61 and 90
            then pi.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                current_date
              ) -
              coalesce(
                pi.due_date,
                pi.invoice_date
              )
            ) > 90
            then pi.balance_due
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(pi.balance_due),
        0
      ),
      2
    )

  from public.suppliers s

  join public.purchase_invoices pi
    on pi.supplier_id = s.id
   and pi.company_id =
       target_company
   and pi.status = 'posted'
   and pi.invoice_date <=
       coalesce(
         target_as_of,
         current_date
       )
   and pi.balance_due > 0

  where s.company_id =
        target_company

  group by
    s.id,
    s.name

  having
    sum(pi.balance_due) > 0

  order by
    total_due desc,
    s.name;
end;
$$;


create index if not exists
purchase_invoices_due_idx
on public.purchase_invoices(
  company_id,
  due_date
)
where
  status = 'posted'
  and payment_status <> 'paid';

commit;
