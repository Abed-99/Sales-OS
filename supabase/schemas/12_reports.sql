-- ======================================================================
-- التقارير
-- لوحة التحكم، التقارير المالية، أعمار الديون، التقارير الشهرية
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.get_dashboard_summary(target_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_financial_report(target_company uuid, target_start date, target_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_payables_aging(target_company uuid, target_as_of date)
 RETURNS TABLE(supplier_id uuid, supplier_name text, current_amount numeric, days_1_30 numeric, days_31_60 numeric, days_61_90 numeric, over_90 numeric, total_due numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))),
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
    sum(public.finance_to_base(target_company, pi.currency, pi.balance_due, coalesce(target_as_of, current_date))) > 0

  order by
    total_due desc,
    s.name;
end;
$function$;

create or replace function public.get_purchase_monthly_report(target_company uuid, target_start date, target_end date)
 RETURNS TABLE(month_start date, invoice_count bigint, gross_purchases numeric, purchase_returns numeric, net_purchases numeric, paid numeric, outstanding numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.get_receivables_aging(target_company uuid, target_as_of date)
 RETURNS TABLE(trader_id uuid, trader_name text, current_amount numeric, days_1_30 numeric, days_31_60 numeric, days_61_90 numeric, over_90 numeric, total_due numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
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
            then public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))
            else 0
          end
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))),
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
    sum(public.finance_to_base(target_company, si.currency, si.balance_due, coalesce(target_as_of, current_date))) > 0

  order by
    total_due desc,
    t.name;
end;
$function$;

create or replace function public.get_sales_monthly_report(target_company uuid, target_start date, target_end date)
 RETURNS TABLE(month_start date, invoice_count bigint, gross_sales numeric, sales_returns numeric, net_sales numeric, collected numeric, outstanding numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
