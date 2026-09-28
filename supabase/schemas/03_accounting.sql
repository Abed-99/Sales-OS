-- ======================================================================
-- المحاسبة
-- دليل الحسابات، الفترات المالية، أسعار الصرف، القيود اليومية
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  parent_id uuid references public.finance_accounts(id) on delete restrict,
  code text not null,
  name text not null,
  account_type text not null,
  account_group text,
  normal_balance text not null,
  system_key text,
  allow_posting boolean default true not null,
  is_system boolean default false not null,
  active boolean default true not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint finance_accounts_company_id_code_key unique (company_id, code),
  constraint finance_accounts_account_type_check check ((account_type = any (array['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text]))),
  constraint finance_accounts_normal_balance_check check ((normal_balance = any (array['debit'::text, 'credit'::text])))
);
create index finance_accounts_company_idx on public.finance_accounts using btree (company_id, account_type, active, code);
create unique index finance_accounts_system_key_unique on public.finance_accounts using btree (company_id, system_key) where (system_key is not null);

create table public.finance_periods (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text default 'open'::text not null,
  closed_at timestamp with time zone,
  closed_by uuid references auth.users(id) on delete set null,
  reopened_at timestamp with time zone,
  reopened_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint finance_periods_company_id_period_start_key unique (company_id, period_start),
  constraint finance_periods_check check ((period_end >= period_start)),
  constraint finance_periods_status_check check ((status = any (array['open'::text, 'closed'::text])))
);

create table public.finance_exchange_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  currency text not null,
  rate_date date not null,
  rate_to_base numeric(30,18) not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint finance_exchange_rates_company_id_currency_rate_date_key unique (company_id, currency, rate_date),
  constraint finance_exchange_rates_currency_check check ((upper(trim(both from currency)) ~ '^[A-Z]{3}$'::text)),
  constraint finance_exchange_rates_rate_to_base_check check ((rate_to_base > (0)::numeric))
);
create index finance_exchange_rates_lookup_idx on public.finance_exchange_rates using btree (company_id, currency, rate_date desc);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entry_number text not null,
  entry_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  description text not null,
  status text default 'posted'::text not null,
  currency text default 'USD'::text not null,
  exchange_rate_to_base numeric(30,18) default 1 not null,
  source_type text,
  source_id uuid,
  reversed_from_id uuid references public.journal_entries(id) on delete restrict,
  posted_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint journal_entries_company_id_entry_number_key unique (company_id, entry_number),
  constraint journal_entries_exchange_rate_to_base_check check ((exchange_rate_to_base > (0)::numeric)),
  constraint journal_entries_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index journal_entries_company_date_idx on public.journal_entries using btree (company_id, entry_date desc, created_at desc);
create unique index journal_entries_reversal_unique on public.journal_entries using btree (reversed_from_id) where (reversed_from_id is not null);
create index journal_entries_source_idx on public.journal_entries using btree (company_id, source_type, source_id);
create unique index journal_entries_source_unique on public.journal_entries using btree (company_id, source_type, source_id) where ((source_id is not null) and (reversed_from_id is null));

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid not null references public.finance_accounts(id) on delete restrict,
  debit numeric(18,2) default 0 not null,
  credit numeric(18,2) default 0 not null,
  base_debit numeric(18,2) default 0 not null,
  base_credit numeric(18,2) default 0 not null,
  party_type text,
  party_id uuid,
  memo text,
  created_at timestamp with time zone default now() not null,
  constraint journal_lines_base_credit_check check ((base_credit >= (0)::numeric)),
  constraint journal_lines_base_debit_check check ((base_debit >= (0)::numeric)),
  constraint journal_lines_check check ((((debit > (0)::numeric) and (credit = (0)::numeric)) or ((credit > (0)::numeric) and (debit = (0)::numeric)))),
  constraint journal_lines_credit_check check ((credit >= (0)::numeric)),
  constraint journal_lines_debit_check check ((debit >= (0)::numeric)),
  constraint journal_lines_party_type_check check (((party_type is null) or (party_type = any (array['trader'::text, 'supplier'::text, 'employee'::text, 'partner'::text, 'other'::text]))))
);
create index journal_lines_account_idx on public.journal_lines using btree (company_id, account_id);
create index journal_lines_entry_idx on public.journal_lines using btree (journal_entry_id);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.assert_finance_period_open(target_company uuid, target_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (
    select 1
    from public.finance_periods fp
    where fp.company_id =
          target_company
      and fp.status =
          'closed'
      and target_date
          between
          fp.period_start
          and
          fp.period_end
  ) then
    raise exception
      'Financial period is closed';
  end if;
end;
$function$;

create or replace function public.balance_journal_base_rounding(target_entry uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_diff numeric(18,2);
  v_line uuid;
begin
  select
    round(
      coalesce(
        sum(base_debit),
        0
      ),
      2
    ),
    round(
      coalesce(
        sum(base_credit),
        0
      ),
      2
    )
  into
    v_debit,
    v_credit
  from public.journal_lines
  where journal_entry_id =
        target_entry;

  v_diff :=
    round(
      v_debit -
      v_credit,
      2
    );

  if abs(v_diff) <= 0.009 then
    return;
  end if;

  if v_diff > 0 then

    select id
    into v_line
    from public.journal_lines
    where journal_entry_id =
          target_entry
      and credit > 0
    order by
      base_credit desc,
      id
    limit 1
    for update;

    if v_line is null then
      raise exception
        'Cannot balance journal base rounding';
    end if;

    update public.journal_lines
    set base_credit =
        round(
          base_credit +
          v_diff,
          2
        )
    where id = v_line;

  else

    select id
    into v_line
    from public.journal_lines
    where journal_entry_id =
          target_entry
      and debit > 0
    order by
      base_debit desc,
      id
    limit 1
    for update;

    if v_line is null then
      raise exception
        'Cannot balance journal base rounding';
    end if;

    update public.journal_lines
    set base_debit =
        round(
          base_debit +
          abs(v_diff),
          2
        )
    where id = v_line;

  end if;

  select
    round(
      coalesce(
        sum(base_debit),
        0
      ),
      2
    ),
    round(
      coalesce(
        sum(base_credit),
        0
      ),
      2
    )
  into
    v_debit,
    v_credit
  from public.journal_lines
  where journal_entry_id =
        target_entry;

  if v_debit <> v_credit then
    raise exception
      'Journal base currency is not balanced';
  end if;
end;
$function$;

create or replace function public.close_finance_month(target_company uuid, target_year integer, target_month integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
  v_end date;
begin
  if not public.has_permission(
    target_company,
    'finance.month_close'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_month < 1
     or target_month > 12
  then
    raise exception 'Invalid month';
  end if;

  v_start :=
    make_date(
      target_year,
      target_month,
      1
    );

  v_end :=
    (
      v_start +
      interval '1 month' -
      interval '1 day'
    )::date;

  insert into public.finance_periods(
    company_id,
    period_start,
    period_end,
    status,
    closed_at,
    closed_by
  )
  values(
    target_company,
    v_start,
    v_end,
    'closed',
    now(),
    auth.uid()
  )
  on conflict(
    company_id,
    period_start
  )
  do update set
    period_end =
      excluded.period_end,

    status =
      'closed',

    closed_at =
      now(),

    closed_by =
      auth.uid(),

    reopened_at =
      null,

    reopened_by =
      null;
end;
$function$;

create or replace function public.company_default_chart_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.ensure_default_chart_of_accounts(
      new.id
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
      ('6500', '6000', 'خسائر بيع وشطب أصول', 'expense', 'debit', 'asset_disposal_loss')
  ) as v(code, parent_code, name, account_type, normal_balance, system_key)
  join public.finance_accounts p
    on p.company_id = target_company
   and p.code = v.parent_code
  on conflict do nothing;

end;
$function$;

create or replace function public.finance_rate_to_base(target_company uuid, target_currency text, target_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base text;
  v_currency text;
  v_rate numeric(30,18);
  v_effective_date date;
begin
  select upper(trim(default_currency))
  into v_base
  from public.companies
  where id = target_company;

  if v_base is null then
    raise exception 'Company not found';
  end if;

  v_currency :=
    upper(
      trim(
        coalesce(
          target_currency,
          v_base
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid currency';
  end if;

  if v_currency = v_base then
    return 1;
  end if;

  v_effective_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone 'Asia/Damascus'
      )::date
    );

  select rate_to_base
  into v_rate
  from public.finance_exchange_rates
  where company_id = target_company
    and upper(currency) = v_currency
    and rate_date <= v_effective_date
  order by rate_date desc
  limit 1;

  if v_rate is null then
    raise exception
      'Missing exchange rate for % on %',
      v_currency,
      v_effective_date;
  end if;

  return v_rate;
end;
$function$;

create or replace function public.finance_to_base(target_company uuid, target_currency text, target_amount numeric, target_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- تحويل مبلغ لعملة الشركة للتقارير: آخر سعر لحد التاريخ، وإذا ما في، أقدم سعر مسجّل.
  -- ما بترمي خطأ متل finance_rate_to_base، فالتقرير ما بيوقف إذا ناقص سعر.
  select target_amount * coalesce(
    case
      when upper(target_currency) = (
        select upper(c.default_currency) from public.companies c where c.id = target_company
      ) then 1::numeric
    end,
    (
      select r.rate_to_base
      from public.finance_exchange_rates r
      where r.company_id = target_company
        and upper(r.currency) = upper(target_currency)
        and r.rate_date <= coalesce(target_date, current_date)
      order by r.rate_date desc
      limit 1
    ),
    (
      select r.rate_to_base
      from public.finance_exchange_rates r
      where r.company_id = target_company
        and upper(r.currency) = upper(target_currency)
      order by r.rate_date
      limit 1
    )
  )
$function$;
create or replace function public.finance_system_account(target_company uuid, target_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  select id
  into v_id
  from public.finance_accounts
  where company_id = target_company
    and system_key = target_key
    and active = true
    and allow_posting = true
  limit 1;

  if v_id is null then
    raise exception
      'Missing system account: %',
      target_key;
  end if;

  return v_id;
end;
$function$;

create or replace function public.next_journal_number(target_company uuid, target_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year integer;
  v_value bigint;
begin
  v_year :=
    extract(
      year from coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.document_sequences(
    company_id,
    document_type,
    sequence_year,
    next_value
  )
  values(
    target_company,
    'journal_entry',
    v_year,
    1
  )
  on conflict(
    company_id,
    document_type,
    sequence_year
  )
  do nothing;

  select next_value
  into v_value
  from public.document_sequences
  where company_id =
        target_company
    and document_type =
        'journal_entry'
    and sequence_year =
        v_year
  for update;

  update public.document_sequences
  set next_value =
      next_value + 1
  where company_id =
        target_company
    and document_type =
        'journal_entry'
    and sequence_year =
        v_year;

  return
    'JE-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      6,
      '0'
    );
end;
$function$;

create or replace function public.payment_currency_quote(target_company uuid, target_invoice_currency text, target_payment_currency text, target_invoice_amount numeric, target_payment_date date)
 RETURNS TABLE(invoice_currency text, payment_currency text, invoice_amount numeric, payment_amount numeric, payment_rate_to_base numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base text;
  v_invoice_currency text;
  v_payment_currency text;
  v_rate numeric(30,18);
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
$function$;

create or replace function public.post_manual_journal_entry(target_company uuid, target_date date, target_description text, target_currency text, target_exchange_rate numeric, lines_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_entry uuid;
  v_number text;

  v_base_currency text;
  v_currency text;
  v_rate numeric(30,18);
  v_business_date date;

  v_line jsonb;
  v_account uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);

  v_total_debit numeric(18,2) := 0;
  v_total_credit numeric(18,2) := 0;

  v_base_debit numeric(18,2);
  v_base_credit numeric(18,2);

  v_party_type text;
  v_party_id uuid;
  v_memo text;
begin
  if not public.has_permission(
    target_company,
    'finance.manual_journal'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_description),
       ''
     ) is null
  then
    raise exception
      'Description is required';
  end if;

  if lines_payload is null
     or jsonb_typeof(
          lines_payload
        ) <> 'array'
     or jsonb_array_length(
          lines_payload
        ) < 2
  then
    raise exception
      'Journal needs at least two lines';
  end if;

  v_business_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone
        'Asia/Damascus'
      )::date
    );

  perform
    public.assert_finance_period_open(
      target_company,
      v_business_date
    );

  select
    upper(default_currency)
  into
    v_base_currency
  from public.companies
  where id =
        target_company;

  if v_base_currency is null then
    raise exception
      'Company not found';
  end if;

  v_currency :=
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        v_base_currency
      )
    );

  if v_currency =
     v_base_currency
  then
    v_rate := 1;
  else
    -- Never trust a browser-supplied accounting FX rate.
    -- Use the approved company rate snapshot for this date.
    v_rate :=
      public.finance_rate_to_base(
        target_company,
        v_currency,
        v_business_date
      );
  end if;

  -- Validate and total first.
  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    begin
      v_account :=
        (
          v_line->>'account_id'
        )::uuid;

      v_debit :=
        coalesce(
          nullif(
            v_line->>'debit',
            ''
          )::numeric,
          0
        );

      v_credit :=
        coalesce(
          nullif(
            v_line->>'credit',
            ''
          )::numeric,
          0
        );
    exception
      when others then
        raise exception
          'Invalid journal line';
    end;

    if not exists (
      select 1
      from public.finance_accounts a
      where a.id =
            v_account
        and a.company_id =
            target_company
        and a.active = true
        and a.allow_posting = true
    ) then
      raise exception
        'Invalid posting account';
    end if;

    if v_debit < 0
       or v_credit < 0
       or (
         v_debit = 0
         and v_credit = 0
       )
       or (
         v_debit > 0
         and v_credit > 0
       )
    then
      raise exception
        'Invalid debit or credit';
    end if;

    v_total_debit :=
      v_total_debit +
      v_debit;

    v_total_credit :=
      v_total_credit +
      v_credit;
  end loop;

  if round(
       v_total_debit,
       2
     ) <>
     round(
       v_total_credit,
       2
     )
  then
    raise exception
      'Journal entry is not balanced';
  end if;

  v_number :=
    public.next_journal_number(
      target_company,
      v_business_date
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    posted_at
  )
  values(
    target_company,
    v_number,
    v_business_date,
    trim(
      target_description
    ),
    'posted',
    v_currency,
    v_rate,
    'manual',
    now()
  )
  returning id
  into v_entry;

  -- Manual entries use their own id as immutable source identity.
  -- This lets the generic reversal engine reverse them safely.
  update public.journal_entries
  set source_id =
      v_entry
  where id =
        v_entry;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    v_account :=
      (
        v_line->>'account_id'
      )::uuid;

    v_debit :=
      coalesce(
        nullif(
          v_line->>'debit',
          ''
        )::numeric,
        0
      );

    v_credit :=
      coalesce(
        nullif(
          v_line->>'credit',
          ''
        )::numeric,
        0
      );

    v_base_debit :=
      round(
        v_debit *
        v_rate,
        2
      );

    v_base_credit :=
      round(
        v_credit *
        v_rate,
        2
      );

    v_party_type :=
      nullif(
        trim(
          v_line->>'party_type'
        ),
        ''
      );

    v_party_id :=
      nullif(
        v_line->>'party_id',
        ''
      )::uuid;

    v_memo :=
      nullif(
        trim(
          v_line->>'memo'
        ),
        ''
      );

    insert into public.journal_lines(
      company_id,
      journal_entry_id,
      account_id,
      debit,
      credit,
      base_debit,
      base_credit,
      party_type,
      party_id,
      memo
    )
    values(
      target_company,
      v_entry,
      v_account,
      v_debit,
      v_credit,
      v_base_debit,
      v_base_credit,
      v_party_type,
      v_party_id,
      v_memo
    );
  end loop;

  perform
    public.balance_journal_base_rounding(
      v_entry
    );

  return v_entry;
end;
$function$;

create or replace function public.post_system_journal(target_company uuid, target_date date, target_description text, target_currency text, target_rate numeric, target_source_type text, target_source_id uuid, lines_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_existing uuid;
  v_entry uuid;
  v_number text;
  v_currency text;
  v_base_currency text;
  v_rate numeric(30,18);
  v_business_date date;

  v_line jsonb;
  v_account uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);

  v_total_debit numeric(18,2) := 0;
  v_total_credit numeric(18,2) := 0;

  v_party_type text;
  v_party_id uuid;
  v_memo text;
begin
  if target_source_id is not null then
    select id
    into v_existing
    from public.journal_entries
    where company_id =
          target_company
      and source_type =
          target_source_type
      and source_id =
          target_source_id
      and reversed_from_id
          is null
    limit 1;

    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  if lines_payload is null
     or jsonb_typeof(
          lines_payload
        ) <> 'array'
     or jsonb_array_length(
          lines_payload
        ) < 2
  then
    raise exception
      'Automatic journal requires at least two lines';
  end if;

  v_business_date :=
    coalesce(
      target_date,
      (
        now()
        at time zone
        'Asia/Damascus'
      )::date
    );

  perform
    public.assert_finance_period_open(
      target_company,
      v_business_date
    );

  select
    upper(default_currency),
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        default_currency
      )
    )
  into
    v_base_currency,
    v_currency
  from public.companies
  where id =
        target_company;

  if v_currency is null
     or v_base_currency is null
  then
    raise exception
      'Company not found';
  end if;

  if v_currency =
     v_base_currency
  then
    v_rate := 1;
  else

    if target_rate is not null
       and target_rate <= 0
    then
      raise exception
        'Invalid exchange rate';
    end if;

    v_rate :=
      coalesce(
        target_rate,
        public.finance_rate_to_base(
          target_company,
          v_currency,
          v_business_date
        )
      );

  end if;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    begin
      v_account :=
        (
          v_line->>'account_id'
        )::uuid;

      v_debit :=
        coalesce(
          nullif(
            v_line->>'debit',
            ''
          )::numeric,
          0
        );

      v_credit :=
        coalesce(
          nullif(
            v_line->>'credit',
            ''
          )::numeric,
          0
        );
    exception
      when others then
        raise exception
          'Invalid automatic journal line';
    end;

    if not exists(
      select 1
      from public.finance_accounts
      where id = v_account
        and company_id =
            target_company
        and active = true
        and allow_posting = true
    ) then
      raise exception
        'Invalid automatic journal account';
    end if;

    if (
      v_debit <= 0
      and v_credit <= 0
    )
    or (
      v_debit > 0
      and v_credit > 0
    )
    then
      raise exception
        'Invalid automatic debit or credit';
    end if;

    v_total_debit :=
      v_total_debit +
      v_debit;

    v_total_credit :=
      v_total_credit +
      v_credit;
  end loop;

  if round(
       v_total_debit,
       2
     ) <>
     round(
       v_total_credit,
       2
     )
  then
    raise exception
      'Automatic journal is not balanced: debit %, credit %',
      v_total_debit,
      v_total_credit;
  end if;

  v_number :=
    public.next_journal_number(
      target_company,
      v_business_date
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    source_id,
    posted_at
  )
  values(
    target_company,
    v_number,
    v_business_date,
    target_description,
    'posted',
    upper(v_currency),
    v_rate,
    target_source_type,
    target_source_id,
    now()
  )
  returning id
  into v_entry;

  for v_line in
    select value
    from jsonb_array_elements(
      lines_payload
    )
  loop
    v_account :=
      (
        v_line->>'account_id'
      )::uuid;

    v_debit :=
      coalesce(
        nullif(
          v_line->>'debit',
          ''
        )::numeric,
        0
      );

    v_credit :=
      coalesce(
        nullif(
          v_line->>'credit',
          ''
        )::numeric,
        0
      );

    v_party_type :=
      nullif(
        trim(
          v_line->>'party_type'
        ),
        ''
      );

    v_party_id :=
      nullif(
        v_line->>'party_id',
        ''
      )::uuid;

    v_memo :=
      nullif(
        trim(
          v_line->>'memo'
        ),
        ''
      );

    insert into public.journal_lines(
      company_id,
      journal_entry_id,
      account_id,
      debit,
      credit,
      base_debit,
      base_credit,
      party_type,
      party_id,
      memo
    )
    values(
      target_company,
      v_entry,
      v_account,
      round(v_debit,2),
      round(v_credit,2),

      round(
        v_debit *
        v_rate,
        2
      ),

      round(
        v_credit *
        v_rate,
        2
      ),

      v_party_type,
      v_party_id,
      v_memo
    );
  end loop;

  perform
    public.balance_journal_base_rounding(
      v_entry
    );

  return v_entry;
end;
$function$;

create or replace function public.reopen_finance_month(target_company uuid, target_year integer, target_month integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
begin
  if not public.has_permission(
    target_company,
    'finance.month_reopen'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_month < 1
     or target_month > 12
  then
    raise exception 'Invalid month';
  end if;

  v_start :=
    make_date(
      target_year,
      target_month,
      1
    );

  update public.finance_periods
  set
    status = 'open',
    reopened_at = now(),
    reopened_by = auth.uid()
  where company_id =
        target_company
    and period_start =
        v_start
    and status = 'closed';

  if not found then
    raise exception 'Closed financial period not found';
  end if;
end;
$function$;

create or replace function public.reverse_manual_journal_entry(target_company uuid, target_entry uuid, target_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_source_type text;
  v_source_id uuid;
  v_status text;
  v_reversed_from uuid;

  v_reversal uuid;
  v_business_date date;
begin

  if not public.has_permission(
    target_company,
    'finance.manual_journal_reverse'
  ) then
    raise exception
      'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason is required';
  end if;


  select
    source_type,
    source_id,
    status,
    reversed_from_id

  into
    v_source_type,
    v_source_id,
    v_status,
    v_reversed_from

  from public.journal_entries

  where id =
        target_entry

    and company_id =
        target_company

  for update;


  if not found then
    raise exception
      'Journal entry not found';
  end if;


  if v_source_type <>
     'manual'
     or v_reversed_from
        is not null
  then
    raise exception
      'Only original manual journals can be reversed';
  end if;


  -- Compatibility guard for manual entries created before
  -- source_id became the entry's own id.
  if v_source_id is null then

    update public.journal_entries
    set source_id =
        id

    where id =
          target_entry

      and company_id =
          target_company;

  elsif v_source_id <>
        target_entry
  then

    raise exception
      'Invalid manual journal source identity';

  end if;


  -- Idempotent retry: return the existing reversal.
  select id
  into v_reversal

  from public.journal_entries

  where reversed_from_id =
        target_entry

  limit 1;


  if v_reversal is not null then
    return v_reversal;
  end if;


  v_business_date :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;


  -- reverse_system_journal itself verifies that the reversal
  -- date is inside an open financial period.
  v_reversal :=
    public.reverse_system_journal(
      target_company,
      'manual',
      target_entry,
      v_business_date,
      'عكس قيد يدوي: ' ||
      trim(target_reason)
    );


  if v_reversal is null then
    raise exception
      'Manual journal reversal failed';
  end if;


  return v_reversal;
end;
$function$;

create or replace function public.reverse_system_journal(target_company uuid, target_source_type text, target_source_id uuid, target_date date, target_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_original public.journal_entries%rowtype;
  v_reversal uuid;
  v_number text;
begin
  select *
  into v_original
  from public.journal_entries
  where company_id =
        target_company
    and source_type =
        target_source_type
    and source_id =
        target_source_id
    and reversed_from_id
        is null
  limit 1
  for update;

  if v_original.id is null then
    return null;
  end if;

  select id
  into v_reversal
  from public.journal_entries
  where reversed_from_id =
        v_original.id
  limit 1;

  if v_reversal is not null then
    return v_reversal;
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_number :=
    public.next_journal_number(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.journal_entries(
    company_id,
    entry_number,
    entry_date,
    description,
    status,
    currency,
    exchange_rate_to_base,
    source_type,
    source_id,
    reversed_from_id,
    posted_at
  )
  values(
    target_company,
    v_number,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      nullif(
        trim(target_description),
        ''
      ),
      'عكس ' ||
      v_original.description
    ),
    'posted',
    v_original.currency,
    v_original.exchange_rate_to_base,
    'reversal',
    v_original.id,
    v_original.id,
    now()
  )
  returning id
  into v_reversal;

  insert into public.journal_lines(
    company_id,
    journal_entry_id,
    account_id,
    debit,
    credit,
    base_debit,
    base_credit,
    party_type,
    party_id,
    memo
  )
  select
    company_id,
    v_reversal,
    account_id,
    credit,
    debit,
    base_credit,
    base_debit,
    party_type,
    party_id,
    coalesce(
      memo,
      'عكس القيد'
    )
  from public.journal_lines
  where journal_entry_id =
        v_original.id;

  update public.journal_entries
  set status = 'reversed'
  where id =
        v_original.id;

  return v_reversal;
end;
$function$;

create or replace function public.save_finance_account(target_company uuid, target_account uuid, target_parent uuid, target_code text, target_name text, target_type text, target_group text, target_normal_balance text, target_allow_posting boolean, target_active boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;

  v_is_system boolean;
  v_old_type text;
  v_old_group text;
  v_old_normal_balance text;
  v_old_allow_posting boolean;

  v_target_group text;
begin

  if not public.has_permission(
    target_company,
    'finance.accounts_write'
  ) then
    raise exception
      'Not allowed';
  end if;


  if nullif(
       trim(target_code),
       ''
     ) is null
  then
    raise exception
      'Account code is required';
  end if;


  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Account name is required';
  end if;


  if target_type not in (
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense'
  ) then
    raise exception
      'Invalid account type';
  end if;


  if target_normal_balance not in (
    'debit',
    'credit'
  ) then
    raise exception
      'Invalid normal balance';
  end if;


  v_target_group :=
    nullif(
      trim(target_group),
      ''
    );


  -- Parent must belong to this company.
  if target_parent is not null
     and not exists (
       select 1
       from public.finance_accounts
       where id =
             target_parent
         and company_id =
             target_company
     )
  then
    raise exception
      'Invalid parent account';
  end if;


  if target_account is null then

    insert into public.finance_accounts(
      company_id,
      parent_id,
      code,
      name,
      account_type,
      account_group,
      normal_balance,
      allow_posting,
      is_system,
      active
    )
    values(
      target_company,
      target_parent,
      trim(target_code),
      trim(target_name),
      target_type,
      v_target_group,
      target_normal_balance,
      coalesce(
        target_allow_posting,
        true
      ),
      false,
      coalesce(
        target_active,
        true
      )
    )
    returning id
    into v_id;


  else

    -- Lock the account while validating structural changes.
    select
      is_system,
      account_type,
      account_group,
      normal_balance,
      allow_posting
    into
      v_is_system,
      v_old_type,
      v_old_group,
      v_old_normal_balance,
      v_old_allow_posting
    from public.finance_accounts
    where id =
          target_account
      and company_id =
          target_company
    for update;


    if not found then
      raise exception
        'Account not found';
    end if;


    if v_is_system then
      raise exception
        'System account cannot be structurally modified';
    end if;


    if target_parent =
       target_account
    then
      raise exception
        'Account cannot be its own parent';
    end if;


    -- Prevent A -> B -> C -> A style cycles.
    if target_parent is not null
       and exists (
         with recursive descendants(id)
         as (
           select
             a.id
           from public.finance_accounts a
           where a.company_id =
                 target_company
             and a.parent_id =
                 target_account

           union

           select
             a.id
           from public.finance_accounts a

           join descendants d
             on a.parent_id =
                d.id

           where a.company_id =
                 target_company
         )

         select 1
         from descendants
         where id =
               target_parent
       )
    then
      raise exception
        'Account hierarchy cycle is not allowed';
    end if;


    -- Once accounting history exists, classification must remain
    -- immutable. Changing it would rewrite historical reports.
    if exists (
         select 1
         from public.journal_lines jl
         where jl.company_id =
               target_company
           and jl.account_id =
               target_account
       )
       and (
         target_type
           is distinct from
           v_old_type

         or v_target_group
           is distinct from
           v_old_group

         or target_normal_balance
           is distinct from
           v_old_normal_balance

         or coalesce(
              target_allow_posting,
              true
            )
            is distinct from
            v_old_allow_posting
       )
    then
      raise exception
        'Posted account classification cannot be changed';
    end if;


    update public.finance_accounts
    set
      parent_id =
        target_parent,

      code =
        trim(target_code),

      name =
        trim(target_name),

      account_type =
        target_type,

      account_group =
        v_target_group,

      normal_balance =
        target_normal_balance,

      allow_posting =
        coalesce(
          target_allow_posting,
          true
        ),

      active =
        coalesce(
          target_active,
          true
        )

    where id =
          target_account

      and company_id =
          target_company

    returning id
    into v_id;

  end if;


  return v_id;
end;
$function$;

-- سعر الصرف لحظة العملية: الموظف اللي عم يقبض أو يدفع بالليرة بيكتب السعر الحالي،
-- وبينسجّل كسعر هاليوم (القيد بياخدو وبيحفظو معه، فتغيير السعر بعدين ما بيأثر على القيود القديمة).
create or replace function public.set_transaction_rate(target_company uuid, target_currency text, target_date date, target_units_per_base numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base text;
  v_currency text := upper(trim(coalesce(target_currency, '')));
  v_date date := coalesce(target_date, (now() at time zone 'Asia/Damascus')::date);
  v_rate numeric(30,18);
begin
  if not public.has_any_permission(target_company, array[
    'finance.accounts_write', 'finance.cashbox_write', 'finance.expenses_write',
    'payments.sales_create', 'payments.supplier_create', 'payroll.pay',
    'assets.manage', 'partners.transactions'
  ]) then
    raise exception 'Not allowed';
  end if;

  select upper(trim(default_currency)) into v_base from public.companies where id = target_company;

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid currency';
  end if;

  if v_currency = v_base then
    return 1;
  end if;

  if target_units_per_base is null or target_units_per_base <= 0 then
    raise exception 'Invalid exchange rate';
  end if;

  if v_date > (now() at time zone 'Asia/Damascus')::date then
    raise exception 'Future exchange rate date is not allowed';
  end if;

  v_rate := round(1 / target_units_per_base, 18);

  insert into public.finance_exchange_rates(company_id, currency, rate_date, rate_to_base, notes)
  values (target_company, v_currency, v_date, v_rate, 'من عملية')
  on conflict (company_id, currency, rate_date)
  do update set rate_to_base = excluded.rate_to_base, notes = excluded.notes;

  return v_rate;
end;
$function$;

-- آخر سعر مسجّل لحد هالتاريخ، بصيغة "كم ليرة بالدولار" لتعبئة الخانة.
create or replace function public.get_units_per_base(target_company uuid, target_currency text, target_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- الليرة (رقم كبير) بدون فواصل، والعملات الصغيرة بـ 4 خانات.
  select case when 1 / r.rate_to_base >= 100 then round(1 / r.rate_to_base, 0) else round(1 / r.rate_to_base, 4) end
  from public.finance_exchange_rates r
  where r.company_id = target_company
    and upper(r.currency) = upper(target_currency)
    and r.rate_date <= coalesce(target_date, (now() at time zone 'Asia/Damascus')::date)
    and public.is_company_member(target_company)
  order by r.rate_date desc
  limit 1;
$function$;

create or replace function public.save_finance_exchange_rate(target_company uuid, target_currency text, target_date date, target_rate numeric, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_base_currency text;
  v_currency text;
  v_business_date date;
  v_rate_date date;
begin
  if not public.has_permission(
    target_company,
    'finance.accounts_write'
  ) then
    raise exception 'Not allowed';
  end if;

  select upper(trim(default_currency))
  into v_base_currency
  from public.companies
  where id = target_company;

  if v_base_currency is null then
    raise exception 'Company not found';
  end if;

  v_currency :=
    upper(
      trim(
        coalesce(
          target_currency,
          ''
        )
      )
    );

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid currency';
  end if;

  if v_currency = v_base_currency then
    raise exception 'Base currency does not need exchange rate';
  end if;

  if target_rate is null
     or target_rate <= 0
  then
    raise exception 'Invalid exchange rate';
  end if;

  v_business_date :=
    (
      now()
      at time zone 'Asia/Damascus'
    )::date;

  v_rate_date :=
    coalesce(
      target_date,
      v_business_date
    );

  if v_rate_date > v_business_date then
    raise exception 'Future exchange rate date is not allowed';
  end if;

  insert into public.finance_exchange_rates(
    company_id,
    currency,
    rate_date,
    rate_to_base,
    notes
  )
  values(
    target_company,
    v_currency,
    v_rate_date,
    target_rate,
    nullif(
      trim(target_notes),
      ''
    )
  )
  on conflict(
    company_id,
    currency,
    rate_date
  )
  do update set
    rate_to_base =
      excluded.rate_to_base,

    notes =
      excluded.notes

  returning id
  into v_id;

  return v_id;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.finance_general_ledger with (security_invoker=true) as
 select je.company_id,
    je.id as journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.status,
    je.currency,
    je.exchange_rate_to_base,
    je.source_type,
    je.source_id,
    jl.id as journal_line_id,
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.account_type,
    a.account_group,
    jl.debit,
    jl.credit,
    jl.base_debit,
    jl.base_credit,
    jl.party_type,
    jl.party_id,
    jl.memo,
    je.created_at
   from public.journal_entries je
     join public.journal_lines jl on jl.journal_entry_id = je.id
     join public.finance_accounts a on a.id = jl.account_id;

create view public.finance_trial_balance with (security_invoker=true) as
 select a.company_id,
    a.id as account_id,
    a.code,
    a.name,
    a.account_type,
    a.account_group,
    a.normal_balance,
    coalesce(sum(jl.base_debit), 0::numeric)::numeric(18,2) as debit,
    coalesce(sum(jl.base_credit), 0::numeric)::numeric(18,2) as credit,
    (coalesce(sum(jl.base_debit), 0::numeric) - coalesce(sum(jl.base_credit), 0::numeric))::numeric(18,2) as balance
   from public.finance_accounts a
     left join public.journal_lines jl on jl.account_id = a.id
     left join public.journal_entries je on je.id = jl.journal_entry_id
  where a.allow_posting = true
  group by a.company_id, a.id, a.code, a.name, a.account_type, a.account_group, a.normal_balance;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger company_default_chart after insert on public.companies for each row execute function public.company_default_chart_trigger();

create trigger audit_finance_accounts after insert or delete or update on public.finance_accounts for each row execute function public.write_audit_log();

create trigger finance_accounts_updated_at before update on public.finance_accounts for each row execute function public.set_updated_at();

create trigger audit_finance_exchange_rates after insert or delete or update on public.finance_exchange_rates for each row execute function public.write_audit_log();

create trigger finance_exchange_rates_updated_at before update on public.finance_exchange_rates for each row execute function public.set_updated_at();

create trigger audit_journal_entries after insert or update on public.journal_entries for each row execute function public.write_audit_log();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.finance_accounts enable row level security;
alter table public.finance_periods enable row level security;
alter table public.finance_exchange_rates enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
create policy finance_accounts_read on public.finance_accounts
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy finance_exchange_rates_read on public.finance_exchange_rates
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy finance_periods_read on public.finance_periods
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.accounts_view'::text, 'reports.finance'::text, 'finance.month_close'::text, 'finance.month_reopen'::text]));
create policy journal_entries_read on public.journal_entries
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));
create policy journal_lines_read on public.journal_lines
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.accounts_view'::text) or public.has_permission(company_id, 'reports.finance'::text)));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.finance_accounts from authenticated;
revoke insert, update, delete on public.finance_periods from authenticated;
revoke insert, update, delete on public.finance_exchange_rates from authenticated;
revoke insert, update, delete on public.journal_entries from authenticated;
revoke insert, update, delete on public.journal_lines from authenticated;
revoke execute on function public.assert_finance_period_open(uuid,date) from authenticated;
revoke execute on function public.balance_journal_base_rounding(uuid) from authenticated;
revoke execute on function public.ensure_default_chart_of_accounts(uuid) from authenticated;
revoke execute on function public.finance_rate_to_base(uuid,text,date) from authenticated;
revoke execute on function public.finance_system_account(uuid,text) from authenticated;
revoke execute on function public.finance_to_base(uuid,text,numeric,date) from authenticated;
revoke execute on function public.next_journal_number(uuid,date) from authenticated;
revoke execute on function public.post_system_journal(uuid,date,text,text,numeric,text,uuid,jsonb) from authenticated;
revoke execute on function public.reverse_system_journal(uuid,text,uuid,date,text) from authenticated;
