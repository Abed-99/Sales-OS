begin;

-- ============================================================
-- NEW PERMISSIONS
-- ============================================================

insert into public.permissions(
  code,
  module,
  action,
  label,
  sort_order
)
values
(
  'finance.manual_journal',
  'finance',
  'manual_journal',
  'إدخال قيد يومية يدوي',
  149
),
(
  'finance.manual_journal_reverse',
  'finance',
  'manual_journal_reverse',
  'عكس قيد يومية يدوي',
  150
),
(
  'payroll.view',
  'payroll',
  'view',
  'عرض الرواتب',
  200
),
(
  'payroll.manage_employees',
  'payroll',
  'manage_employees',
  'إدارة الموظفين',
  201
),
(
  'payroll.process',
  'payroll',
  'process',
  'إعداد وترحيل الرواتب',
  202
),
(
  'payroll.pay',
  'payroll',
  'pay',
  'دفع الرواتب',
  203
),
(
  'payroll.reports',
  'payroll',
  'reports',
  'تقارير الرواتب',
  204
)
on conflict(code)
do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  sort_order = excluded.sort_order;


-- Owner gets everything.
insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  p.code
from public.company_roles r
cross join public.permissions p
where r.is_owner = true
  and p.code in (
    'finance.manual_journal',
    'finance.manual_journal_reverse',
    'payroll.view',
    'payroll.manage_employees',
    'payroll.process',
    'payroll.pay',
    'payroll.reports'
  )
on conflict do nothing;


-- Accountant gets payroll + manual journals.
insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  p.code
from public.company_roles r
cross join public.permissions p
where r.name = 'محاسب'
  and r.is_owner = false
  and p.code in (
    'finance.manual_journal',
    'finance.manual_journal_reverse',
    'payroll.view',
    'payroll.manage_employees',
    'payroll.process',
    'payroll.pay',
    'payroll.reports'
  )
on conflict do nothing;


-- ============================================================
-- FINANCE EXCHANGE RATES
-- ============================================================

create table if not exists public.finance_exchange_rates (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  currency text not null
    check (upper(trim(currency)) ~ '^[A-Z]{3}$'),

  rate_date date not null,

  rate_to_base numeric(24,10) not null
    check (rate_to_base > 0),

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  unique(company_id, currency, rate_date)
);

create index if not exists
finance_exchange_rates_lookup_idx
on public.finance_exchange_rates(
  company_id,
  currency,
  rate_date desc
);

drop trigger if exists
finance_exchange_rates_updated_at
on public.finance_exchange_rates;

create trigger finance_exchange_rates_updated_at
before update
on public.finance_exchange_rates
for each row
execute function public.set_updated_at();

-- ============================================================
-- CHART OF ACCOUNTS
-- ============================================================

create table if not exists public.finance_accounts (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  parent_id uuid
    references public.finance_accounts(id)
    on delete restrict,

  code text not null,

  name text not null,

  account_type text not null
    check (
      account_type in (
        'asset',
        'liability',
        'equity',
        'revenue',
        'expense'
      )
    ),

  account_group text,

  normal_balance text not null
    check (
      normal_balance in (
        'debit',
        'credit'
      )
    ),

  system_key text,

  allow_posting boolean not null default true,

  is_system boolean not null default false,

  active boolean not null default true,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  unique(
    company_id,
    code
  )
);

create unique index if not exists
finance_accounts_system_key_unique
on public.finance_accounts(
  company_id,
  system_key
)
where system_key is not null;

create index if not exists
finance_accounts_company_idx
on public.finance_accounts(
  company_id,
  account_type,
  active,
  code
);

drop trigger if exists finance_accounts_updated_at
on public.finance_accounts;

create trigger finance_accounts_updated_at
before update
on public.finance_accounts
for each row
execute function public.set_updated_at();


-- ============================================================
-- DEFAULT CHART OF ACCOUNTS
-- ============================================================

create or replace function
public.ensure_default_chart_of_accounts(
  target_company uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

end;
$$;

revoke all
on function public.ensure_default_chart_of_accounts(uuid)
from public, authenticated;


-- Existing companies
do $$
declare
  r record;
begin
  for r in
    select id
    from public.companies
  loop
    perform
      public.ensure_default_chart_of_accounts(
        r.id
      );
  end loop;
end;
$$;


create or replace function
public.company_default_chart_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform
    public.ensure_default_chart_of_accounts(
      new.id
    );

  return new;
end;
$$;

drop trigger if exists
company_default_chart
on public.companies;

create trigger
company_default_chart
after insert
on public.companies
for each row
execute function
public.company_default_chart_trigger();


-- ============================================================
-- CASHBOX -> GL ACCOUNT MAPPING
-- ============================================================

create table if not exists public.cashbox_gl_accounts (
  cashbox_id uuid primary key
    references public.cashboxes(id)
    on delete cascade,

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  account_id uuid not null unique
    references public.finance_accounts(id)
    on delete restrict,

  created_at timestamptz not null default now()
);


create or replace function
public.ensure_cashbox_gl_account(
  target_cashbox uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_name text;
  v_account uuid;
  v_parent uuid;
begin
  if exists (
    select 1
    from public.cashbox_gl_accounts
    where cashbox_id =
          target_cashbox
  ) then
    return;
  end if;

  select
    company_id,
    name
  into
    v_company,
    v_name
  from public.cashboxes
  where id =
        target_cashbox;

  if v_company is null then
    return;
  end if;

  perform
    public.ensure_default_chart_of_accounts(
      v_company
    );

  select a.id
  into v_account
  from public.finance_accounts a
  where a.company_id =
        v_company

    and a.system_key =
        'cash_default'

    and not exists (
      select 1
      from public.cashbox_gl_accounts m
      where m.account_id =
            a.id
    )
  limit 1;

  if v_account is null then

    select id
    into v_parent
    from public.finance_accounts
    where company_id =
          v_company
      and code = '1100'
    limit 1;

    insert into public.finance_accounts(
      company_id,
      parent_id,
      code,
      name,
      account_type,
      account_group,
      normal_balance,
      allow_posting,
      is_system
    )
    values(
      v_company,
      v_parent,

      'CB-' ||
      replace(
        target_cashbox::text,
        '-',
        ''
      ),

      'صندوق - ' ||
      coalesce(
        v_name,
        'بدون اسم'
      ),

      'asset',
      'cash_bank',
      'debit',
      true,
      true
    )
    returning id
    into v_account;

  end if;

  insert into public.cashbox_gl_accounts(
    cashbox_id,
    company_id,
    account_id
  )
  values(
    target_cashbox,
    v_company,
    v_account
  )
  on conflict(cashbox_id)
  do nothing;
end;
$$;

revoke all
on function public.ensure_cashbox_gl_account(uuid)
from public, authenticated;


do $$
declare
  r record;
begin
  for r in
    select id
    from public.cashboxes
  loop
    perform
      public.ensure_cashbox_gl_account(
        r.id
      );
  end loop;
end;
$$;


create or replace function
public.cashbox_gl_account_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform
    public.ensure_cashbox_gl_account(
      new.id
    );

  return new;
end;
$$;

drop trigger if exists
cashbox_gl_account_after_insert
on public.cashboxes;

create trigger
cashbox_gl_account_after_insert
after insert
on public.cashboxes
for each row
execute function
public.cashbox_gl_account_trigger();


-- ============================================================
-- FINANCIAL PERIOD LOCKS
-- ============================================================

create table if not exists public.finance_periods (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  period_start date not null,
  period_end date not null,

  status text not null default 'open'
    check (
      status in (
        'open',
        'closed'
      )
    ),

  closed_at timestamptz,

  closed_by uuid
    references auth.users(id)
    on delete set null,

  reopened_at timestamptz,

  reopened_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  unique(
    company_id,
    period_start
  ),

  check(
    period_end >=
    period_start
  )
);


create or replace function
public.assert_finance_period_open(
  target_company uuid,
  target_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.assert_finance_period_open(uuid,date)
from public, authenticated;


create or replace function
public.close_finance_month(
  target_company uuid,
  target_year integer,
  target_month integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;


create or replace function
public.reopen_finance_month(
  target_company uuid,
  target_year integer,
  target_month integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.close_finance_month(
  uuid,
  integer,
  integer
)
from public;

revoke all
on function public.reopen_finance_month(
  uuid,
  integer,
  integer
)
from public;

grant execute
on function public.close_finance_month(
  uuid,
  integer,
  integer
)
to authenticated;

grant execute
on function public.reopen_finance_month(
  uuid,
  integer,
  integer
)
to authenticated;


-- ============================================================
-- JOURNAL ENTRIES
-- ============================================================

create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  entry_number text not null,

  entry_date date not null default (now() at time zone 'Asia/Damascus')::date,

  description text not null,

  status text not null default 'posted'
    check (
      status in (
        'posted',
        'reversed'
      )
    ),

  currency text not null default 'USD',

  exchange_rate_to_base numeric(20,8)
    not null default 1
    check(
      exchange_rate_to_base > 0
    ),

  source_type text,

  source_id uuid,

  reversed_from_id uuid
    references public.journal_entries(id)
    on delete restrict,

  posted_at timestamptz not null default now(),

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  unique(
    company_id,
    entry_number
  )
);

create index if not exists
journal_entries_company_date_idx
on public.journal_entries(
  company_id,
  entry_date desc,
  created_at desc
);

create index if not exists
journal_entries_source_idx
on public.journal_entries(
  company_id,
  source_type,
  source_id
);


create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  journal_entry_id uuid not null
    references public.journal_entries(id)
    on delete cascade,

  account_id uuid not null
    references public.finance_accounts(id)
    on delete restrict,

  debit numeric(18,2)
    not null default 0
    check(debit >= 0),

  credit numeric(18,2)
    not null default 0
    check(credit >= 0),

  base_debit numeric(18,2)
    not null default 0
    check(base_debit >= 0),

  base_credit numeric(18,2)
    not null default 0
    check(base_credit >= 0),

  party_type text
    check (
      party_type is null
      or party_type in (
        'trader',
        'supplier',
        'employee',
        'partner',
        'other'
      )
    ),

  party_id uuid,

  memo text,

  created_at timestamptz not null default now(),

  check (
    (
      debit > 0
      and credit = 0
    )
    or
    (
      credit > 0
      and debit = 0
    )
  )
);

create index if not exists
journal_lines_entry_idx
on public.journal_lines(
  journal_entry_id
);

create index if not exists
journal_lines_account_idx
on public.journal_lines(
  company_id,
  account_id
);


-- ============================================================
-- JOURNAL NUMBER
-- ============================================================

create or replace function
public.next_journal_number(
  target_company uuid,
  target_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.next_journal_number(uuid,date)
from public, authenticated;



-- ============================================================
-- BASE-CURRENCY ROUNDING BALANCER
-- Source-currency debit/credit is already balanced before this
-- runs. This only removes cent-level differences introduced by
-- rounding each converted journal line independently.
-- ============================================================

create or replace function public.balance_journal_base_rounding(
  target_entry uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.balance_journal_base_rounding(uuid)
from public, authenticated;

-- ============================================================
-- MANUAL JOURNAL RPC
-- Manual accounting only for explicit permission.
-- ============================================================

create or replace function
public.post_manual_journal_entry(
  target_company uuid,
  target_date date,
  target_description text,
  target_currency text,
  target_exchange_rate numeric,
  lines_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry uuid;
  v_number text;

  v_base_currency text;
  v_currency text;
  v_rate numeric(20,8);
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
$$;

revoke all
on function public.post_manual_journal_entry(
  uuid,
  date,
  text,
  text,
  numeric,
  jsonb
)
from public;

grant execute
on function public.post_manual_journal_entry(
  uuid,
  date,
  text,
  text,
  numeric,
  jsonb
)
to authenticated;


-- ============================================================
-- TRIAL BALANCE
-- ============================================================

create or replace view public.finance_trial_balance
with (security_invoker = true)
as
select
  a.company_id,
  a.id as account_id,
  a.code,
  a.name,
  a.account_type,
  a.account_group,
  a.normal_balance,

  coalesce(
    sum(jl.base_debit),
    0
  )::numeric(18,2)
  as debit,

  coalesce(
    sum(jl.base_credit),
    0
  )::numeric(18,2)
  as credit,

  (
    coalesce(
      sum(jl.base_debit),
      0
    ) -
    coalesce(
      sum(jl.base_credit),
      0
    )
  )::numeric(18,2)
  as balance

from public.finance_accounts a

left join public.journal_lines jl
  on jl.account_id =
     a.id

left join public.journal_entries je
  on je.id =
     jl.journal_entry_id

 and je.status =
     'posted'

where a.allow_posting =
      true

group by
  a.company_id,
  a.id,
  a.code,
  a.name,
  a.account_type,
  a.account_group,
  a.normal_balance;


-- ============================================================
-- EMPLOYEES
-- Employees do not need login accounts.
-- ============================================================

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  user_id uuid
    references auth.users(id)
    on delete set null,

  employee_number text,

  full_name text not null,

  phone text,

  job_title text,

  department text,

  hire_date date,

  termination_date date,

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'terminated'
      )
    ),

  salary_currency text not null default 'USD',

  base_salary numeric(18,2)
    not null default 0
    check(base_salary >= 0),

  fixed_allowances numeric(18,2)
    not null default 0
    check(fixed_allowances >= 0),

  overtime_hour_rate numeric(18,4)
    not null default 0
    check(overtime_hour_rate >= 0),

  social_security_employee_rate numeric(9,4)
    not null default 0
    check(
      social_security_employee_rate >= 0
    ),

  social_security_employer_rate numeric(9,4)
    not null default 0
    check(
      social_security_employer_rate >= 0
    ),

  income_tax_rate numeric(9,4)
    not null default 0
    check(income_tax_rate >= 0),

  default_cashbox_id uuid
    references public.cashboxes(id)
    on delete set null,

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create unique index if not exists
employees_number_unique
on public.employees(
  company_id,
  employee_number
)
where employee_number is not null;

create index if not exists
employees_company_status_idx
on public.employees(
  company_id,
  status,
  full_name
);

drop trigger if exists employees_updated_at
on public.employees;

create trigger employees_updated_at
before update
on public.employees
for each row
execute function public.set_updated_at();


-- ============================================================
-- EMPLOYEE ADVANCES / LOANS
-- ============================================================

create table if not exists public.employee_loans (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  employee_id uuid not null
    references public.employees(id)
    on delete restrict,

  loan_type text not null
    check (
      loan_type in (
        'advance',
        'loan'
      )
    ),

  original_amount numeric(18,2)
    not null
    check(original_amount > 0),

  balance_due numeric(18,2)
    not null
    check(balance_due >= 0),

  installment_amount numeric(18,2)
    not null default 0
    check(installment_amount >= 0),

  start_date date not null default (now() at time zone 'Asia/Damascus')::date,

  status text not null default 'active'
    check (
      status in (
        'active',
        'settled',
        'cancelled'
      )
    ),

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index if not exists
employee_loans_employee_idx
on public.employee_loans(
  company_id,
  employee_id,
  status
);

drop trigger if exists employee_loans_updated_at
on public.employee_loans;

create trigger employee_loans_updated_at
before update
on public.employee_loans
for each row
execute function public.set_updated_at();


-- ============================================================
-- PAYROLL RUN
-- ============================================================

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  period_start date not null,

  period_end date not null,

  pay_date date,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'posted',
        'partial',
        'paid',
        'cancelled'
      )
    ),

  currency text not null default 'USD',

  total_gross numeric(18,2)
    not null default 0,

  total_deductions numeric(18,2)
    not null default 0,

  total_net numeric(18,2)
    not null default 0,

  total_paid numeric(18,2)
    not null default 0,

  notes text,

  posted_at timestamptz,

  posted_by uuid
    references auth.users(id)
    on delete set null,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  check(
    period_end >=
    period_start
  )
);

create unique index if not exists
payroll_runs_period_unique
on public.payroll_runs(
  company_id,
  period_start,
  period_end
)
where status <>
      'cancelled';

drop trigger if exists payroll_runs_updated_at
on public.payroll_runs;

create trigger payroll_runs_updated_at
before update
on public.payroll_runs
for each row
execute function public.set_updated_at();


-- ============================================================
-- PAYROLL ITEMS
-- ============================================================

create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  payroll_run_id uuid not null
    references public.payroll_runs(id)
    on delete cascade,

  employee_id uuid not null
    references public.employees(id)
    on delete restrict,

  base_salary numeric(18,2)
    not null default 0,

  allowances numeric(18,2)
    not null default 0,

  overtime_hours numeric(12,2)
    not null default 0,

  overtime_amount numeric(18,2)
    not null default 0,

  bonuses numeric(18,2)
    not null default 0,

  absent_days numeric(12,2)
    not null default 0,

  absence_deduction numeric(18,2)
    not null default 0,

  loan_deduction numeric(18,2)
    not null default 0,

  social_security_deduction numeric(18,2)
    not null default 0,

  tax_deduction numeric(18,2)
    not null default 0,

  other_deductions numeric(18,2)
    not null default 0,

  employer_contribution numeric(18,2)
    not null default 0,

  gross_pay numeric(18,2)
    not null default 0,

  total_deductions numeric(18,2)
    not null default 0,

  net_pay numeric(18,2)
    not null default 0,

  paid_total numeric(18,2)
    not null default 0,

  balance_due numeric(18,2)
    not null default 0,

  notes text,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  unique(
    payroll_run_id,
    employee_id
  ),

  check(
    base_salary >= 0
    and allowances >= 0
    and overtime_hours >= 0
    and overtime_amount >= 0
    and bonuses >= 0
    and absent_days >= 0
    and absence_deduction >= 0
    and loan_deduction >= 0
    and social_security_deduction >= 0
    and tax_deduction >= 0
    and other_deductions >= 0
    and employer_contribution >= 0
    and gross_pay >= 0
    and total_deductions >= 0
    and net_pay >= 0
    and paid_total >= 0
    and balance_due >= 0
  )
);

create index if not exists
payroll_items_employee_idx
on public.payroll_items(
  company_id,
  employee_id
);

drop trigger if exists payroll_items_updated_at
on public.payroll_items;

create trigger payroll_items_updated_at
before update
on public.payroll_items
for each row
execute function public.set_updated_at();


-- ============================================================
-- PAYROLL PAYMENTS
-- ============================================================

create table if not exists public.payroll_payments (
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  payroll_item_id uuid not null
    references public.payroll_items(id)
    on delete restrict,

  employee_id uuid not null
    references public.employees(id)
    on delete restrict,

  cashbox_id uuid not null
    references public.cashboxes(id)
    on delete restrict,

  amount numeric(18,2)
    not null
    check(amount > 0),

  currency text not null,

  payment_date date not null default (now() at time zone 'Asia/Damascus')::date,

  payment_method text not null default 'cash',

  status text not null default 'posted'
    check (
      status in (
        'posted',
        'reversed'
      )
    ),

  reference_number text,

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index if not exists
payroll_payments_employee_idx
on public.payroll_payments(
  company_id,
  employee_id,
  payment_date desc
);


-- ============================================================
-- CREATE PAYROLL RUN
-- ============================================================

create or replace function
public.create_payroll_run(
  target_company uuid,
  target_period_start date,
  target_period_end date,
  target_pay_date date,
  target_currency text,
  target_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run uuid;
  v_count integer;
  v_currency text;
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_period_start is null
     or target_period_end is null
     or target_period_end <
        target_period_start
  then
    raise exception
      'Invalid payroll period';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      target_period_end
    );

  select
    default_currency
  into
    v_currency
  from public.companies
  where id =
        target_company;

  if v_currency is null then
    raise exception
      'Company not found';
  end if;

  v_currency :=
    coalesce(
      nullif(
        trim(target_currency),
        ''
      ),
      v_currency
    );

  insert into public.payroll_runs(
    company_id,
    period_start,
    period_end,
    pay_date,
    status,
    currency,
    notes
  )
  values(
    target_company,
    target_period_start,
    target_period_end,
    target_pay_date,
    'draft',
    v_currency,
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_run;

  insert into public.payroll_items(
    company_id,
    payroll_run_id,
    employee_id,
    base_salary,
    allowances,
    overtime_hours,
    overtime_amount,
    bonuses,
    absent_days,
    absence_deduction,
    loan_deduction,
    social_security_deduction,
    tax_deduction,
    other_deductions,
    employer_contribution,
    gross_pay,
    total_deductions,
    net_pay,
    paid_total,
    balance_due
  )
  select
    target_company,
    v_run,
    e.id,
    e.base_salary,
    e.fixed_allowances,
    0,
    0,
    0,
    0,
    0,
    0,

    round(
      e.base_salary *
      e.social_security_employee_rate /
      100,
      2
    ),

    round(
      e.base_salary *
      e.income_tax_rate /
      100,
      2
    ),

    0,

    round(
      e.base_salary *
      e.social_security_employer_rate /
      100,
      2
    ),

    round(
      e.base_salary +
      e.fixed_allowances,
      2
    ),

    round(
      (
        e.base_salary *
        e.social_security_employee_rate /
        100
      ) +
      (
        e.base_salary *
        e.income_tax_rate /
        100
      ),
      2
    ),

    greatest(
      round(
        e.base_salary +
        e.fixed_allowances -
        (
          e.base_salary *
          e.social_security_employee_rate /
          100
        ) -
        (
          e.base_salary *
          e.income_tax_rate /
          100
        ),
        2
      ),
      0
    ),

    0,

    greatest(
      round(
        e.base_salary +
        e.fixed_allowances -
        (
          e.base_salary *
          e.social_security_employee_rate /
          100
        ) -
        (
          e.base_salary *
          e.income_tax_rate /
          100
        ),
        2
      ),
      0
    )

  from public.employees e

  where e.company_id =
        target_company

    and e.status =
        'active'

    and e.salary_currency =
        v_currency;

  get diagnostics
    v_count = row_count;

  if v_count = 0 then
    delete from public.payroll_runs
    where id = v_run;

    raise exception
      'No active employees for payroll currency';
  end if;

  update public.payroll_runs pr
  set
    total_gross =
      x.gross,

    total_deductions =
      x.deductions,

    total_net =
      x.net

  from (
    select
      payroll_run_id,

      coalesce(
        sum(gross_pay),
        0
      ) as gross,

      coalesce(
        sum(total_deductions),
        0
      ) as deductions,

      coalesce(
        sum(net_pay),
        0
      ) as net

    from public.payroll_items

    where payroll_run_id =
          v_run

    group by
      payroll_run_id
  ) x

  where pr.id =
        x.payroll_run_id;

  return v_run;
end;
$$;

revoke all
on function public.create_payroll_run(
  uuid,
  date,
  date,
  date,
  text,
  text
)
from public;

grant execute
on function public.create_payroll_run(
  uuid,
  date,
  date,
  date,
  text,
  text
)
to authenticated;


-- ============================================================
-- RECALCULATE ONE PAYROLL ITEM
-- ============================================================

create or replace function
public.recalculate_payroll_item(
  target_item uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gross numeric(18,2);
  v_deductions numeric(18,2);
  v_net numeric(18,2);
  v_run uuid;
begin
  select
    payroll_run_id,

    round(
      base_salary +
      allowances +
      overtime_amount +
      bonuses,
      2
    ),

    round(
      absence_deduction +
      loan_deduction +
      social_security_deduction +
      tax_deduction +
      other_deductions,
      2
    )

  into
    v_run,
    v_gross,
    v_deductions

  from public.payroll_items
  where id =
        target_item;

  if v_run is null then
    raise exception
      'Payroll item not found';
  end if;

  v_net :=
    greatest(
      v_gross -
      v_deductions,
      0
    );

  update public.payroll_items
  set
    gross_pay =
      v_gross,

    total_deductions =
      v_deductions,

    net_pay =
      v_net,

    balance_due =
      greatest(
        v_net -
        paid_total,
        0
      )

  where id =
        target_item;

  update public.payroll_runs pr
  set
    total_gross =
      x.gross,

    total_deductions =
      x.deductions,

    total_net =
      x.net,

    total_paid =
      x.paid

  from (
    select
      payroll_run_id,

      coalesce(
        sum(gross_pay),
        0
      ) as gross,

      coalesce(
        sum(total_deductions),
        0
      ) as deductions,

      coalesce(
        sum(net_pay),
        0
      ) as net,

      coalesce(
        sum(paid_total),
        0
      ) as paid

    from public.payroll_items
    where payroll_run_id =
          v_run

    group by payroll_run_id
  ) x

  where pr.id =
        x.payroll_run_id;
end;
$$;

revoke all
on function public.recalculate_payroll_item(uuid)
from public, authenticated;


-- ============================================================
-- EDIT PAYROLL ITEM
-- ============================================================

create or replace function
public.update_payroll_item(
  target_company uuid,
  target_item uuid,
  target_allowances numeric,
  target_overtime_hours numeric,
  target_overtime_amount numeric,
  target_bonuses numeric,
  target_absent_days numeric,
  target_absence_deduction numeric,
  target_loan_deduction numeric,
  target_social_security_deduction numeric,
  target_tax_deduction numeric,
  target_other_deductions numeric,
  target_employer_contribution numeric,
  target_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.payroll_items pi

    join public.payroll_runs pr
      on pr.id =
         pi.payroll_run_id

    where pi.id =
          target_item

      and pi.company_id =
          target_company

      and pr.status =
          'draft'
  ) then
    raise exception
      'Payroll item is not editable';
  end if;

  update public.payroll_items
  set
    allowances =
      greatest(
        coalesce(
          target_allowances,
          0
        ),
        0
      ),

    overtime_hours =
      greatest(
        coalesce(
          target_overtime_hours,
          0
        ),
        0
      ),

    overtime_amount =
      greatest(
        coalesce(
          target_overtime_amount,
          0
        ),
        0
      ),

    bonuses =
      greatest(
        coalesce(
          target_bonuses,
          0
        ),
        0
      ),

    absent_days =
      greatest(
        coalesce(
          target_absent_days,
          0
        ),
        0
      ),

    absence_deduction =
      greatest(
        coalesce(
          target_absence_deduction,
          0
        ),
        0
      ),

    loan_deduction =
      greatest(
        coalesce(
          target_loan_deduction,
          0
        ),
        0
      ),

    social_security_deduction =
      greatest(
        coalesce(
          target_social_security_deduction,
          0
        ),
        0
      ),

    tax_deduction =
      greatest(
        coalesce(
          target_tax_deduction,
          0
        ),
        0
      ),

    other_deductions =
      greatest(
        coalesce(
          target_other_deductions,
          0
        ),
        0
      ),

    employer_contribution =
      greatest(
        coalesce(
          target_employer_contribution,
          0
        ),
        0
      ),

    notes =
      nullif(
        trim(target_notes),
        ''
      )

  where id =
        target_item

    and company_id =
        target_company;

  perform
    public.recalculate_payroll_item(
      target_item
    );
end;
$$;

revoke all
on function public.update_payroll_item(
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text
)
from public;

grant execute
on function public.update_payroll_item(
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text
)
to authenticated;


-- ============================================================
-- RLS
-- ============================================================

alter table public.finance_accounts
enable row level security;

alter table public.cashbox_gl_accounts
enable row level security;

alter table public.finance_periods
enable row level security;

alter table public.journal_entries
enable row level security;

alter table public.journal_lines
enable row level security;

alter table public.employees
enable row level security;

alter table public.employee_loans
enable row level security;

alter table public.payroll_runs
enable row level security;

alter table public.payroll_items
enable row level security;

alter table public.payroll_payments
enable row level security;


drop policy if exists finance_accounts_read
on public.finance_accounts;

create policy finance_accounts_read
on public.finance_accounts
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'finance.accounts_view'
  )
  or
  public.has_permission(
    company_id,
    'reports.finance'
  )
);


drop policy if exists cashbox_gl_accounts_read
on public.cashbox_gl_accounts;

create policy cashbox_gl_accounts_read
on public.cashbox_gl_accounts
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'finance.cashbox_view'
  )
  or
  public.has_permission(
    company_id,
    'finance.accounts_view'
  )
);


drop policy if exists finance_periods_read
on public.finance_periods;

create policy finance_periods_read
on public.finance_periods
for select
to authenticated
using (
  public.has_any_permission(
    company_id,
    array[
      'finance.accounts_view',
      'reports.finance',
      'finance.month_close',
      'finance.month_reopen'
    ]::text[]
  )
);

drop policy if exists journal_entries_read
on public.journal_entries;

create policy journal_entries_read
on public.journal_entries
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'finance.accounts_view'
  )
  or
  public.has_permission(
    company_id,
    'reports.finance'
  )
);


drop policy if exists journal_lines_read
on public.journal_lines;

create policy journal_lines_read
on public.journal_lines
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'finance.accounts_view'
  )
  or
  public.has_permission(
    company_id,
    'reports.finance'
  )
);


drop policy if exists employees_payroll_read
on public.employees;

create policy employees_payroll_read
on public.employees
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'payroll.view'
  )
  or
  public.has_permission(
    company_id,
    'payroll.manage_employees'
  )
);


drop policy if exists employee_loans_read
on public.employee_loans;

create policy employee_loans_read
on public.employee_loans
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'payroll.view'
  )
);


drop policy if exists payroll_runs_read
on public.payroll_runs;

create policy payroll_runs_read
on public.payroll_runs
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'payroll.view'
  )
);


drop policy if exists payroll_items_read
on public.payroll_items;

create policy payroll_items_read
on public.payroll_items
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'payroll.view'
  )
);


drop policy if exists payroll_payments_read
on public.payroll_payments;

create policy payroll_payments_read
on public.payroll_payments
for select
to authenticated
using (
  public.has_permission(
    company_id,
    'payroll.view'
  )
  or
  public.has_permission(
    company_id,
    'payroll.pay'
  )
);


revoke insert, update, delete
on public.finance_accounts,
   public.cashbox_gl_accounts,
   public.finance_periods,
   public.journal_entries,
   public.journal_lines,
   public.employees,
   public.employee_loans,
   public.payroll_runs,
   public.payroll_items,
   public.payroll_payments
from authenticated;

grant select
on public.finance_accounts,
   public.cashbox_gl_accounts,
   public.finance_periods,
   public.journal_entries,
   public.journal_lines,
   public.employees,
   public.employee_loans,
   public.payroll_runs,
   public.payroll_items,
   public.payroll_payments
to authenticated;

grant select
on public.finance_trial_balance
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists audit_finance_accounts
on public.finance_accounts;

create trigger audit_finance_accounts
after insert or update or delete
on public.finance_accounts
for each row
execute function public.write_audit_log();


drop trigger if exists audit_journal_entries
on public.journal_entries;

create trigger audit_journal_entries
after insert or update
on public.journal_entries
for each row
execute function public.write_audit_log();


drop trigger if exists audit_employees
on public.employees;

create trigger audit_employees
after insert or update or delete
on public.employees
for each row
execute function public.write_audit_log();


drop trigger if exists audit_employee_loans
on public.employee_loans;

create trigger audit_employee_loans
after insert or update or delete
on public.employee_loans
for each row
execute function public.write_audit_log();


drop trigger if exists audit_payroll_runs
on public.payroll_runs;

create trigger audit_payroll_runs
after insert or update or delete
on public.payroll_runs
for each row
execute function public.write_audit_log();


drop trigger if exists audit_payroll_items
on public.payroll_items;

create trigger audit_payroll_items
after insert or update or delete
on public.payroll_items
for each row
execute function public.write_audit_log();


drop trigger if exists audit_payroll_payments
on public.payroll_payments;

create trigger audit_payroll_payments
after insert or update
on public.payroll_payments
for each row
execute function public.write_audit_log();

commit;