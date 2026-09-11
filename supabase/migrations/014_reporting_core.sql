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
        current_date
      )::date
    );

  v_end :=
    coalesce(
      target_end,
      current_date
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
                current_date
              ) -
              si.invoice_date
            ) <= 0
              then si.balance_due
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
                current_date
              ) -
              si.invoice_date
            ) between 1 and 30
              then si.balance_due
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
                current_date
              ) -
              si.invoice_date
            ) between 31 and 60
              then si.balance_due
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
                current_date
              ) -
              si.invoice_date
            ) between 61 and 90
              then si.balance_due
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
                current_date
              ) -
              si.invoice_date
            ) > 90
              then si.balance_due
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
          si.balance_due
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
         current_date
       )

   and si.balance_due >
       0

  where t.company_id =
        target_company

  group by
    t.id,
    t.name

  having
    sum(
      si.balance_due
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
                current_date
              ) -
              pi.invoice_date
            ) <= 0
              then pi.balance_due
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
                current_date
              ) -
              pi.invoice_date
            ) between 1 and 30
              then pi.balance_due
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
                current_date
              ) -
              pi.invoice_date
            ) between 31 and 60
              then pi.balance_due
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
                current_date
              ) -
              pi.invoice_date
            ) between 61 and 90
              then pi.balance_due
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
                current_date
              ) -
              pi.invoice_date
            ) > 90
              then pi.balance_due
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
          pi.balance_due
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
         current_date
       )

   and pi.balance_due >
       0

  where s.company_id =
        target_company

  group by
    s.id,
    s.name

  having
    sum(
      pi.balance_due
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
        sum(si.total),
        0
      ) as gross_sales,

      coalesce(
        sum(si.paid_total),
        0
      ) as collected,

      coalesce(
        sum(si.balance_due),
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
              current_date
            )::date
          )
          and
          coalesce(
            target_end,
            current_date
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
        sum(sr.total),
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
              current_date
            )::date
          )
          and
          coalesce(
            target_end,
            current_date
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
        sum(pi.total),
        0
      ) as gross_purchases,

      coalesce(
        sum(pi.paid_total),
        0
      ) as paid,

      coalesce(
        sum(pi.balance_due),
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
              current_date
            )::date
          )
          and
          coalesce(
            target_end,
            current_date
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
        sum(pr.total),
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
              current_date
            )::date
          )
          and
          coalesce(
            target_end,
            current_date
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

commit;