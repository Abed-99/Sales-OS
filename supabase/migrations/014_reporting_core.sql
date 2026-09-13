begin;

-- ============================================================
-- FINANCIAL REPORT
-- P&L + BALANCE SHEET + CASH FLOW + AR/AP
-- All monetary results are in company base currency.
-- ============================================================

create or replace function public.get_financial_report(
  target_company uuid,
  target_start date,
  target_end date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start date;
  v_end date;

  v_revenue numeric(18,2);
  v_cogs numeric(18,2);
  v_operating_expenses numeric(18,2);

  v_gross_profit numeric(18,2);
  v_net_profit numeric(18,2);

  v_assets numeric(18,2);
  v_liabilities numeric(18,2);
  v_equity numeric(18,2);

  v_lifetime_revenue numeric(18,2);
  v_lifetime_expenses numeric(18,2);
  v_current_earnings numeric(18,2);

  v_cash_in numeric(18,2);
  v_cash_out numeric(18,2);
  v_cash_net numeric(18,2);

  v_ar numeric(18,2);
  v_ap numeric(18,2);

  v_inventory_value numeric(18,2);

  v_base_currency text;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.finance',
      'reports.profit',
      'finance.accounts_view'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_start :=
    coalesce(
      target_start,
      date_trunc(
        'year',
        (now() at time zone 'Asia/Damascus')::date
      )::date
    );

  v_end :=
    coalesce(
      target_end,
      (now() at time zone 'Asia/Damascus')::date
    );

  if v_end < v_start then
    raise exception
      'Invalid report date range';
  end if;

  select default_currency
  into v_base_currency
  from public.companies
  where id = target_company;

  if v_base_currency is null then
    raise exception
      'Company not found';
  end if;


  -- ----------------------------------------------------------
  -- REVENUE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_revenue
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_type =
        'revenue';


  -- ----------------------------------------------------------
  -- COST OF GOODS SOLD
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_cogs
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and (
      a.system_key =
        'cogs'

      or a.account_group =
         'cost_of_sales'
    );


  -- ----------------------------------------------------------
  -- OTHER EXPENSES
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_operating_expenses
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_type =
        'expense'

    and coalesce(
          a.system_key,
          ''
        ) <>
        'cogs'

    and coalesce(
          a.account_group,
          ''
        ) <>
        'cost_of_sales';


  v_gross_profit :=
    round(
      v_revenue -
      v_cogs,
      2
    );

  v_net_profit :=
    round(
      v_revenue -
      v_cogs -
      v_operating_expenses,
      2
    );


  -- ----------------------------------------------------------
  -- BALANCE SHEET AS OF END DATE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit -
          jl.base_credit
        ),
        0
      ),
      2
    )
  into v_assets
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'asset';


  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_liabilities
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'liability';


  select
    round(
      coalesce(
        sum(
          jl.base_credit -
          jl.base_debit
        ),
        0
      ),
      2
    )
  into v_equity
  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end

    and a.account_type =
        'equity';


  -- ----------------------------------------------------------
  -- CURRENT EARNINGS THROUGH END DATE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          case
            when a.account_type =
                 'revenue'
              then
                jl.base_credit -
                jl.base_debit

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
            when a.account_type =
                 'expense'
              then
                jl.base_debit -
                jl.base_credit

            else 0
          end
        ),
        0
      ),
      2
    )

  into
    v_lifetime_revenue,
    v_lifetime_expenses

  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date <=
        v_end;


  v_current_earnings :=
    round(
      v_lifetime_revenue -
      v_lifetime_expenses,
      2
    );


  -- ----------------------------------------------------------
  -- CASH FLOW
  -- Debit to cash = cash in
  -- Credit from cash = cash out
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          jl.base_debit
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          jl.base_credit
        ),
        0
      ),
      2
    )

  into
    v_cash_in,
    v_cash_out

  from public.journal_lines jl

  join public.journal_entries je
    on je.id =
       jl.journal_entry_id

  join public.finance_accounts a
    on a.id =
       jl.account_id

  where je.company_id =
        target_company

    and je.entry_date between
        v_start and v_end

    and a.account_group =
        'cash_bank';


  v_cash_net :=
    round(
      v_cash_in -
      v_cash_out,
      2
    );


  -- ----------------------------------------------------------
  -- ACCOUNTS RECEIVABLE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(balance_due),
        0
      ),
      2
    )
  into v_ar
  from public.sales_invoices
  where company_id =
        target_company

    and status =
        'posted'

    and invoice_date <=
        v_end;


  -- ----------------------------------------------------------
  -- ACCOUNTS PAYABLE
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(balance_due),
        0
      ),
      2
    )
  into v_ap
  from public.purchase_invoices
  where company_id =
        target_company

    and status =
        'posted'

    and invoice_date <=
        v_end;


  -- ----------------------------------------------------------
  -- INVENTORY VALUE - weighted average
  -- ----------------------------------------------------------

  select
    round(
      coalesce(
        sum(
          on_hand *
          average_cost
        ),
        0
      ),
      2
    )
  into v_inventory_value
  from public.inventory_stock
  where company_id =
        target_company;


  return jsonb_build_object(
    'currency',
      v_base_currency,

    'start_date',
      v_start,

    'end_date',
      v_end,

    'profit_loss',
      jsonb_build_object(
        'revenue',
          v_revenue,

        'cost_of_goods_sold',
          v_cogs,

        'gross_profit',
          v_gross_profit,

        'operating_expenses',
          v_operating_expenses,

        'net_profit',
          v_net_profit
      ),

    'balance_sheet',
      jsonb_build_object(
        'assets',
          v_assets,

        'liabilities',
          v_liabilities,

        'equity_posted',
          v_equity,

        'current_earnings',
          v_current_earnings,

        'equity_with_current_earnings',
          round(
            v_equity +
            v_current_earnings,
            2
          )
      ),

    'cash_flow',
      jsonb_build_object(
        'cash_in',
          v_cash_in,

        'cash_out',
          v_cash_out,

        'net_cash_flow',
          v_cash_net
      ),

    'working_capital',
      jsonb_build_object(
        'accounts_receivable',
          v_ar,

        'accounts_payable',
          v_ap,

        'inventory_value',
          v_inventory_value
      )
  );
end;
$$;

revoke all
on function public.get_financial_report(
  uuid,
  date,
  date
)
from public;

grant execute
on function public.get_financial_report(
  uuid,
  date,
  date
)
to authenticated;


-- ============================================================
-- CUSTOMER RECEIVABLE AGING
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
                (now() at time zone 'Asia/Damascus')::date
              ) -
              si.invoice_date
            ) <= 0
              then (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as current_amount,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              si.invoice_date
            ) between 1 and 30
              then (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_1_30,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              si.invoice_date
            ) between 31 and 60
              then (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_31_60,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              si.invoice_date
            ) between 61 and 90
              then (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_61_90,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              si.invoice_date
            ) > 90
              then (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as over_90,

    round(
      coalesce(
        sum(
          (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
        ),
        0
      ),
      2
    ) as total_due

  from public.traders t

  join public.sales_invoices si
    on si.trader_id =
       t.id

   and si.company_id =
       target_company

   and si.status =
       'posted'

   and si.invoice_date <=
       coalesce(
         target_as_of,
         (now() at time zone 'Asia/Damascus')::date
       )

   and (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date)) >
       0

  where t.company_id =
        target_company

  group by
    t.id,
    t.name

  having
    sum(
      (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))
    ) > 0

  order by
    total_due desc,
    t.name;
end;
$$;

revoke all
on function public.get_receivables_aging(
  uuid,
  date
)
from public;

grant execute
on function public.get_receivables_aging(
  uuid,
  date
)
to authenticated;


-- ============================================================
-- SUPPLIER PAYABLE AGING
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
                (now() at time zone 'Asia/Damascus')::date
              ) -
              pi.invoice_date
            ) <= 0
              then (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as current_amount,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              pi.invoice_date
            ) between 1 and 30
              then (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_1_30,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              pi.invoice_date
            ) between 31 and 60
              then (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_31_60,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              pi.invoice_date
            ) between 61 and 90
              then (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as days_61_90,

    round(
      coalesce(
        sum(
          case
            when (
              coalesce(
                target_as_of,
                (now() at time zone 'Asia/Damascus')::date
              ) -
              pi.invoice_date
            ) > 90
              then (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
            else 0
          end
        ),
        0
      ),
      2
    ) as over_90,

    round(
      coalesce(
        sum(
          (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
        ),
        0
      ),
      2
    ) as total_due

  from public.suppliers s

  join public.purchase_invoices pi
    on pi.supplier_id =
       s.id

   and pi.company_id =
       target_company

   and pi.status =
       'posted'

   and pi.invoice_date <=
       coalesce(
         target_as_of,
         (now() at time zone 'Asia/Damascus')::date
       )

   and (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date)) >
       0

  where s.company_id =
        target_company

  group by
    s.id,
    s.name

  having
    sum(
      (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))
    ) > 0

  order by
    total_due desc,
    s.name;
end;
$$;

revoke all
on function public.get_payables_aging(
  uuid,
  date
)
from public;

grant execute
on function public.get_payables_aging(
  uuid,
  date
)
to authenticated;


-- ============================================================
-- INVENTORY VALUATION REPORT
-- Cost is protected by cost/report permissions.
-- ============================================================

create or replace function public.get_inventory_valuation(
  target_company uuid
)
returns table(
  warehouse_id uuid,
  warehouse_name text,

  product_id uuid,
  product_name text,
  sku text,

  on_hand numeric,
  reserved numeric,
  available numeric,

  average_cost numeric,
  stock_value numeric
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
      'reports.profit',
      'products.view_cost',
      'suppliers.view_finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  select
    w.id,
    w.name,

    p.id,
    p.name,
    p.sku,

    round(
      s.on_hand,
      3
    ),

    round(
      coalesce(
        (
          select
            sum(r.quantity)
          from public.inventory_reservations r
          where r.company_id =
                target_company

            and r.warehouse_id =
                s.warehouse_id

            and r.product_id =
                s.product_id

            and r.status =
                'active'
        ),
        0
      ),
      3
    ),

    round(
      greatest(
        s.on_hand -
        coalesce(
          (
            select
              sum(r.quantity)
            from public.inventory_reservations r
            where r.company_id =
                  target_company

              and r.warehouse_id =
                  s.warehouse_id

              and r.product_id =
                  s.product_id

              and r.status =
                  'active'
          ),
          0
        ),
        0
      ),
      3
    ),

    round(
      s.average_cost,
      4
    ),

    round(
      s.on_hand *
      s.average_cost,
      2
    )

  from public.inventory_stock s

  join public.warehouses w
    on w.id =
       s.warehouse_id

  join public.products p
    on p.id =
       s.product_id

  where s.company_id =
        target_company

  order by
    w.name,
    p.name;
end;
$$;

revoke all
on function public.get_inventory_valuation(uuid)
from public;

grant execute
on function public.get_inventory_valuation(uuid)
to authenticated;


-- ============================================================
-- SALES REPORT BY MONTH
-- ============================================================

create or replace function public.get_sales_monthly_report(
  target_company uuid,
  target_start date,
  target_end date
)
returns table(
  month_start date,
  invoice_count bigint,
  gross_sales numeric,
  sales_returns numeric,
  net_sales numeric,
  collected numeric,
  outstanding numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'reports.sales',
      'reports.profit',
      'reports.finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with invoice_data as (
    select
      date_trunc(
        'month',
        si.invoice_date
      )::date as month_start,

      count(*) as invoice_count,

      coalesce(
        sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as gross_sales,

      coalesce(
        sum((si.paid_total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as collected,

      coalesce(
        sum((si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))),
        0
      ) as outstanding

    from public.sales_invoices si

    where si.company_id =
          target_company

      and si.status =
          'posted'

      and si.invoice_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  ),

  return_data as (
    select
      date_trunc(
        'month',
        sr.return_date
      )::date as month_start,

      coalesce(
        sum((sr.total * public.finance_rate_to_base(target_company, sr.currency, sr.return_date))),
        0
      ) as return_total

    from public.sales_returns sr

    where sr.company_id =
          target_company

      and sr.status =
          'posted'

      and sr.return_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  )

  select
    i.month_start,
    i.invoice_count,

    round(
      i.gross_sales,
      2
    ),

    round(
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.gross_sales -
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.collected,
      2
    ),

    round(
      i.outstanding,
      2
    )

  from invoice_data i

  left join return_data r
    on r.month_start =
       i.month_start

  order by
    i.month_start;
end;
$$;

revoke all
on function public.get_sales_monthly_report(
  uuid,
  date,
  date
)
from public;

grant execute
on function public.get_sales_monthly_report(
  uuid,
  date,
  date
)
to authenticated;


-- ============================================================
-- PURCHASE REPORT BY MONTH
-- ============================================================

create or replace function public.get_purchase_monthly_report(
  target_company uuid,
  target_start date,
  target_end date
)
returns table(
  month_start date,
  invoice_count bigint,
  gross_purchases numeric,
  purchase_returns numeric,
  net_purchases numeric,
  paid numeric,
  outstanding numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'purchases.view',
      'reports.profit',
      'reports.finance'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with invoice_data as (
    select
      date_trunc(
        'month',
        pi.invoice_date
      )::date as month_start,

      count(*) as invoice_count,

      coalesce(
        sum((pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as gross_purchases,

      coalesce(
        sum((pi.paid_total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as paid,

      coalesce(
        sum((pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date))),
        0
      ) as outstanding

    from public.purchase_invoices pi

    where pi.company_id =
          target_company

      and pi.status =
          'posted'

      and pi.invoice_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  ),

  return_data as (
    select
      date_trunc(
        'month',
        pr.return_date
      )::date as month_start,

      coalesce(
        sum((pr.total * public.finance_rate_to_base(target_company, pr.currency, pr.return_date))),
        0
      ) as return_total

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.status =
          'posted'

      and pr.return_date between
          coalesce(
            target_start,
            date_trunc(
              'year',
              (now() at time zone 'Asia/Damascus')::date
            )::date
          )
          and
          coalesce(
            target_end,
            (now() at time zone 'Asia/Damascus')::date
          )

    group by 1
  )

  select
    i.month_start,
    i.invoice_count,

    round(
      i.gross_purchases,
      2
    ),

    round(
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.gross_purchases -
      coalesce(
        r.return_total,
        0
      ),
      2
    ),

    round(
      i.paid,
      2
    ),

    round(
      i.outstanding,
      2
    )

  from invoice_data i

  left join return_data r
    on r.month_start =
       i.month_start

  order by
    i.month_start;
end;
$$;

revoke all
on function public.get_purchase_monthly_report(
  uuid,
  date,
  date
)
from public;

grant execute
on function public.get_purchase_monthly_report(
  uuid,
  date,
  date
)
to authenticated;



-- ============================================================
-- DASHBOARD SUMMARY
-- ============================================================

-- ============================================================
-- DASHBOARD SUMMARY
-- Secure aggregate-only access for dashboard.view.
-- Business timezone: Asia/Damascus.
-- ============================================================

create index if not exists dashboard_sales_orders_status_idx
on public.sales_orders(company_id, status);

create index if not exists dashboard_sales_orders_delivered_idx
on public.sales_orders(company_id, delivered_at)
where status = 'delivered';

create index if not exists dashboard_sales_invoices_posted_idx
on public.sales_invoices(company_id, posted_at)
where status = 'posted';

create index if not exists dashboard_traders_customer_idx
on public.traders(company_id, status, created_at desc);

create index if not exists dashboard_products_active_idx
on public.products(company_id, active);

create index if not exists dashboard_suppliers_active_idx
on public.suppliers(company_id, active);


create or replace function public.get_dashboard_summary(
  target_company uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_business_date date;
  v_day_start timestamptz;
  v_day_end timestamptz;

  v_currency text;

  v_today_sales numeric(18,2) := 0;
  v_today_invoice_count bigint := 0;

  v_open_orders bigint := 0;
  v_purchasing_orders bigint := 0;
  v_ready_orders bigint := 0;
  v_delivery_orders bigint := 0;
  v_delivered_today bigint := 0;

  v_unpaid_invoices bigint := 0;

  v_customer_count bigint := 0;
  v_product_count bigint := 0;
  v_supplier_count bigint := 0;
  v_order_count bigint := 0;

  v_recent_customers jsonb := '[]'::jsonb;
  v_can_view_traders boolean := false;
begin
  -- Dashboard access is checked here, not only in the UI.
  if not public.has_permission(
    target_company,
    'dashboard.view'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    upper(coalesce(c.default_currency, 'USD'))
  into
    v_currency
  from public.companies c
  where c.id = target_company;

  if v_currency is null then
    raise exception 'Company not found';
  end if;

  -- One canonical business day for Syria/Lebanon operations.
  v_business_date :=
    (now() at time zone 'Asia/Damascus')::date;

  v_day_start :=
    (
      v_business_date::timestamp
      at time zone 'Asia/Damascus'
    );

  v_day_end :=
    (
      (v_business_date + 1)::timestamp
      at time zone 'Asia/Damascus'
    );

  -- ----------------------------------------------------------
  -- TODAY'S ACTUAL INVOICED SALES
  -- Uses posted sales invoices, not newly-created orders.
  -- Cancelled invoices are excluded.
  -- ----------------------------------------------------------

  select
    round(
      coalesce(sum((si.total * public.finance_rate_to_base(target_company, si.currency, si.invoice_date))), 0),
      2
    ),
    count(*)
  into
    v_today_sales,
    v_today_invoice_count
  from public.sales_invoices si
  where si.company_id = target_company
    and si.status = 'posted'
    and si.posted_at >= v_day_start
    and si.posted_at < v_day_end;

  -- ----------------------------------------------------------
  -- ORDER WORKFLOW
  -- No LIMIT: counts the complete company dataset.
  -- Drafts are not considered active execution.
  -- ----------------------------------------------------------

  select
    count(*) filter (
      where so.status in (
        'new',
        'to_purchase',
        'purchasing',
        'ready',
        'out_for_delivery'
      )
    ),

    count(*) filter (
      where so.status in (
        'to_purchase',
        'purchasing'
      )
    ),

    count(*) filter (
      where so.status = 'ready'
    ),

    count(*) filter (
      where so.status = 'out_for_delivery'
    ),

    count(*) filter (
      where so.status <> 'cancelled'
    )
  into
    v_open_orders,
    v_purchasing_orders,
    v_ready_orders,
    v_delivery_orders,
    v_order_count
  from public.sales_orders so
  where so.company_id = target_company;

  -- Delivered TODAY, not lifetime delivered orders.
  select
    count(*)
  into
    v_delivered_today
  from public.sales_orders so
  where so.company_id = target_company
    and so.status = 'delivered'
    and so.delivered_at >= v_day_start
    and so.delivered_at < v_day_end;

  -- Actual posted invoices that still have money due.
  select
    count(*)
  into
    v_unpaid_invoices
  from public.sales_invoices si
  where si.company_id = target_company
    and si.status = 'posted'
    and (si.balance_due * public.finance_rate_to_base(target_company, si.currency, si.invoice_date)) > 0;

  -- "Customers" means actual customer status, not leads/inactive.
  select
    count(*)
  into
    v_customer_count
  from public.traders t
  where t.company_id = target_company
    and t.status = 'customer';

  -- Active catalog records only.
  select
    count(*)
  into
    v_product_count
  from public.products p
  where p.company_id = target_company
    and p.active = true;

  select
    count(*)
  into
    v_supplier_count
  from public.suppliers s
  where s.company_id = target_company
    and s.active = true;

  -- Customer names/phones are only returned when the user
  -- actually has traders.view. dashboard.view alone exposes
  -- aggregate numbers, not customer details.
  v_can_view_traders :=
    public.has_permission(
      target_company,
      'traders.view'
    );

  if v_can_view_traders then
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'name', r.name,
            'area', r.area,
            'phone', r.phone,
            'created_at', r.created_at
          )
          order by r.created_at desc
        ),
        '[]'::jsonb
      )
    into
      v_recent_customers
    from (
      select
        t.id,
        t.name,
        t.area,
        t.phone,
        t.created_at
      from public.traders t
      where t.company_id = target_company
        and t.status = 'customer'
      order by t.created_at desc
      limit 5
    ) r;
  end if;

  return jsonb_build_object(
    'business_date', v_business_date,
    'currency', v_currency,

    'today_sales', v_today_sales,
    'today_invoice_count', v_today_invoice_count,

    'open_orders', v_open_orders,
    'purchasing_orders', v_purchasing_orders,
    'ready_orders', v_ready_orders,
    'delivery_orders', v_delivery_orders,
    'delivered_today', v_delivered_today,

    'unpaid_invoices', v_unpaid_invoices,

    'customer_count', v_customer_count,
    'active_product_count', v_product_count,
    'active_supplier_count', v_supplier_count,
    'order_count', v_order_count,

    'recent_customers', v_recent_customers
  );
end;
$$;


revoke all
on function public.get_dashboard_summary(uuid)
from public;

grant execute
on function public.get_dashboard_summary(uuid)
to authenticated;


-- ============================================================
-- CUSTOMER SALES SUMMARY
-- ============================================================

create or replace function public.get_trader_sales_summary(
  target_company uuid,
  target_trader uuid
)
returns table(
  invoice_count bigint,
  total_invoiced numeric,
  outstanding numeric,
  currency text
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_trader_sales_summary(uuid,uuid)
from public;

grant execute
on function public.get_trader_sales_summary(uuid,uuid)
to authenticated;

-- ============================================================
-- SUPPLIER FINANCIAL SUMMARY
-- ============================================================

create or replace function public.get_supplier_financial_summary(
  target_company uuid,
  target_supplier uuid
)
returns table(
  total_purchases numeric,
  total_payments numeric,
  invoice_balance numeric,
  advance_credit numeric,
  net_balance numeric,
  invoice_count bigint,
  payment_count bigint,
  available_products bigint,
  currency text
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
      (pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date)),
      (pi.balance_due * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date)),

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
$$;

revoke all
on function public.get_supplier_financial_summary(
  uuid,
  uuid
)
from public;

grant execute
on function public.get_supplier_financial_summary(
  uuid,
  uuid
)
to authenticated;


-- ============================================================
-- SUPPLIER LEDGER
--
-- Running balance is calculated over ALL posted history.
-- Only the latest requested rows are returned to the UI.
-- ============================================================

create or replace function public.get_supplier_ledger(
  target_company uuid,
  target_supplier uuid,
  target_limit integer default 100
)
returns table(
  source_id uuid,
  event_date date,
  event_created_at timestamptz,
  row_type text,
  reference text,
  description text,
  debit numeric,
  credit numeric,
  balance numeric,
  total_count bigint,
  currency text
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
        (pi.total * public.finance_rate_to_base(target_company, pi.currency, pi.invoice_date)) *
        case
          when upper(pi.currency) = v_currency
            then 1::numeric
          else public.finance_rate_to_base(
            target_company,
            pi.currency,
            pi.invoice_date
          )
        end,
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
$$;

revoke all
on function public.get_supplier_ledger(
  uuid,
  uuid,
  integer
)
from public;

grant execute
on function public.get_supplier_ledger(
  uuid,
  uuid,
  integer
)
to authenticated;

-- ============================================================
-- ORDERS SUMMARY
-- Exact values over the full company history.
-- ============================================================

create or replace function public.get_orders_summary(
  target_company uuid
)
returns table(
  total_count bigint,
  active_count bigint,
  new_count bigint,
  ready_delivery_count bigint,
  total_active_value numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_orders_summary(
  uuid
)
from public;

grant execute
on function public.get_orders_summary(
  uuid
)
to authenticated;

-- ============================================================
-- PURCHASES SUMMARY
-- Exact financial values over the full company history.
-- Purchase invoices are currently posted in company base currency.
-- ============================================================

create or replace function public.get_purchases_summary(
  target_company uuid
)
returns table(
  invoice_count bigint,
  outstanding_total numeric,
  supplier_credit_total numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_purchases_summary(
  uuid
)
from public;

grant execute
on function public.get_purchases_summary(
  uuid
)
to authenticated;

-- ============================================================
-- DELIVERIES SUMMARY
-- Exact operational delivery totals.
-- ============================================================

create or replace function public.get_deliveries_summary(
  target_company uuid
)
returns table(
  ready_count bigint,
  road_count bigint,
  road_units numeric,
  remaining_units numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_deliveries_summary(
  uuid
)
from public;

grant execute
on function public.get_deliveries_summary(
  uuid
)
to authenticated;


-- ============================================================
-- DELIVERY QUEUE
-- Server-side search/filter/pagination with quantities already
-- aggregated. Prevents loading every delivery item in browser.
-- ============================================================

create or replace function public.get_delivery_queue(
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
$$;

revoke all
on function public.get_delivery_queue(
  uuid,
  text,
  text,
  integer,
  integer
)
from public;

grant execute
on function public.get_delivery_queue(
  uuid,
  text,
  text,
  integer,
  integer
)
to authenticated;
commit;