-- ======================================================================
-- الرواتب
-- الموظفين، مسيرات الرواتب، السلف والقروض
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  employee_number text,
  full_name text not null,
  phone text,
  job_title text,
  department text,
  hire_date date,
  termination_date date,
  status text default 'active'::text not null,
  salary_currency text default 'USD'::text not null,
  base_salary numeric(18,2) default 0 not null,
  fixed_allowances numeric(18,2) default 0 not null,
  overtime_hour_rate numeric(18,4) default 0 not null,
  social_security_employee_rate numeric(9,4) default 0 not null,
  social_security_employer_rate numeric(9,4) default 0 not null,
  income_tax_rate numeric(9,4) default 0 not null,
  default_cashbox_id uuid references public.cashboxes(id) on delete set null,
  -- سائق توصيل / مندوب مبيعات (مع نسبة عمولة من صافي مبيعات زبائنو).
  is_driver boolean default false not null,
  is_sales_rep boolean default false not null,
  commission_rate numeric(5,2) default 0 not null check (commission_rate >= 0 and commission_rate <= 100),
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint employees_base_salary_check check ((base_salary >= (0)::numeric)),
  constraint employees_fixed_allowances_check check ((fixed_allowances >= (0)::numeric)),
  constraint employees_income_tax_rate_check check ((income_tax_rate >= (0)::numeric)),
  constraint employees_overtime_hour_rate_check check ((overtime_hour_rate >= (0)::numeric)),
  constraint employees_social_security_employee_rate_check check ((social_security_employee_rate >= (0)::numeric)),
  constraint employees_social_security_employer_rate_check check ((social_security_employer_rate >= (0)::numeric)),
  constraint employees_status_check check ((status = any (array['active'::text, 'inactive'::text, 'terminated'::text])))
);
create index employees_company_status_idx on public.employees using btree (company_id, status, full_name);
create unique index employees_number_unique on public.employees using btree (company_id, employee_number) where (employee_number is not null);

create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date,
  status text default 'draft'::text not null,
  currency text default 'USD'::text not null,
  total_gross numeric(18,2) default 0 not null,
  total_deductions numeric(18,2) default 0 not null,
  total_net numeric(18,2) default 0 not null,
  total_paid numeric(18,2) default 0 not null,
  notes text,
  posted_at timestamp with time zone,
  posted_by uuid references auth.users(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint payroll_runs_check check ((period_end >= period_start)),
  constraint payroll_runs_status_check check ((status = any (array['draft'::text, 'posted'::text, 'partial'::text, 'paid'::text, 'cancelled'::text])))
);
create unique index payroll_runs_period_unique on public.payroll_runs using btree (company_id, period_start, period_end) where (status <> 'cancelled'::text);

create table public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  base_salary numeric(18,2) default 0 not null,
  allowances numeric(18,2) default 0 not null,
  overtime_hours numeric(12,2) default 0 not null,
  overtime_amount numeric(18,2) default 0 not null,
  bonuses numeric(18,2) default 0 not null,
  absent_days numeric(12,2) default 0 not null,
  absence_deduction numeric(18,2) default 0 not null,
  loan_deduction numeric(18,2) default 0 not null,
  social_security_deduction numeric(18,2) default 0 not null,
  tax_deduction numeric(18,2) default 0 not null,
  other_deductions numeric(18,2) default 0 not null,
  employer_contribution numeric(18,2) default 0 not null,
  gross_pay numeric(18,2) default 0 not null,
  total_deductions numeric(18,2) default 0 not null,
  net_pay numeric(18,2) default 0 not null,
  paid_total numeric(18,2) default 0 not null,
  balance_due numeric(18,2) default 0 not null,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint payroll_items_payroll_run_id_employee_id_key unique (payroll_run_id, employee_id),
  constraint payroll_items_check check (((base_salary >= (0)::numeric) and (allowances >= (0)::numeric) and (overtime_hours >= (0)::numeric) and (overtime_amount >= (0)::numeric) and (bonuses >= (0)::numeric) and (absent_days >= (0)::numeric) and (absence_deduction >= (0)::numeric) and (loan_deduction >= (0)::numeric) and (social_security_deduction >= (0)::numeric) and (tax_deduction >= (0)::numeric) and (other_deductions >= (0)::numeric) and (employer_contribution >= (0)::numeric) and (gross_pay >= (0)::numeric) and (total_deductions >= (0)::numeric) and (net_pay >= (0)::numeric) and (paid_total >= (0)::numeric) and (balance_due >= (0)::numeric)))
);
create index payroll_items_employee_idx on public.payroll_items using btree (company_id, employee_id);

create table public.payroll_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payroll_item_id uuid not null references public.payroll_items(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  amount numeric(18,2) not null,
  currency text not null,
  payment_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  payment_method text default 'cash'::text not null,
  status text default 'posted'::text not null,
  reference_number text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint payroll_payments_amount_check check ((amount > (0)::numeric)),
  constraint payroll_payments_status_check check ((status = any (array['posted'::text, 'reversed'::text])))
);
create index payroll_payments_employee_idx on public.payroll_payments using btree (company_id, employee_id, payment_date desc);

create table public.employee_loans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  loan_type text not null,
  original_amount numeric(18,2) not null,
  balance_due numeric(18,2) not null,
  installment_amount numeric(18,2) default 0 not null,
  start_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  status text default 'active'::text not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint employee_loans_balance_due_check check ((balance_due >= (0)::numeric)),
  constraint employee_loans_installment_amount_check check ((installment_amount >= (0)::numeric)),
  constraint employee_loans_loan_type_check check ((loan_type = any (array['advance'::text, 'loan'::text]))),
  constraint employee_loans_original_amount_check check ((original_amount > (0)::numeric)),
  constraint employee_loans_status_check check ((status = any (array['active'::text, 'settled'::text, 'cancelled'::text])))
);
create index employee_loans_employee_idx on public.employee_loans using btree (company_id, employee_id, status);

create table public.employee_loan_disbursements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_loan_id uuid not null references public.employee_loans(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  amount numeric(18,2) not null,
  currency text not null,
  disbursement_date date not null,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint employee_loan_disbursements_employee_loan_id_key unique (employee_loan_id),
  constraint employee_loan_disbursements_amount_check check ((amount > (0)::numeric))
);

create table public.employee_loan_repayments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_loan_id uuid not null references public.employee_loans(id) on delete restrict,
  payroll_item_id uuid references public.payroll_items(id) on delete restrict,
  amount numeric(18,2) not null,
  repayment_date date not null,
  created_at timestamp with time zone default now() not null,
  constraint employee_loan_repayments_employee_loan_id_payroll_item_id_key unique (employee_loan_id, payroll_item_id),
  constraint employee_loan_repayments_amount_check check ((amount > (0)::numeric))
);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_employee_id_fkey foreign key (employee_id) references public.employees(id) on delete set null;
alter table public.cash_transactions
  add constraint cash_transactions_payroll_payment_id_fkey foreign key (payroll_payment_id) references public.payroll_payments(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

alter table public.traders
  add constraint traders_sales_rep_fk foreign key (sales_rep_id) references public.employees(id) on delete set null;

alter table public.deliveries
  add column driver_id uuid references public.employees(id) on delete set null;

create index deliveries_driver_idx on public.deliveries using btree (driver_id) where (driver_id is not null);
create index traders_sales_rep_idx on public.traders using btree (sales_rep_id) where (sales_rep_id is not null);

create or replace function public.apply_payroll_loan_deductions(target_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row record;
  v_loan record;

  v_remaining numeric(18,2);
  v_take numeric(18,2);

  v_existing numeric(18,2);
  v_repayment uuid;
begin
  for v_row in
    select
      pi.id as payroll_item_id,
      pi.company_id,
      pi.employee_id,
      pi.loan_deduction,
      pr.period_end

    from public.payroll_items pi

    join public.payroll_runs pr
      on pr.id =
         pi.payroll_run_id

    where pi.payroll_run_id =
          target_run

      and pi.loan_deduction >
          0
  loop

    select
      coalesce(
        sum(r.amount),
        0
      )

    into
      v_existing

    from public.employee_loan_repayments r

    where r.company_id =
          v_row.company_id

      and r.payroll_item_id =
          v_row.payroll_item_id;


    v_remaining :=
      greatest(
        round(
          v_row.loan_deduction -
          v_existing,
          2
        ),
        0
      );


    if v_remaining <= 0.01 then
      continue;
    end if;


    for v_loan in
      select
        el.id,
        el.balance_due

      from public.employee_loans el

      where el.company_id =
            v_row.company_id

        and el.employee_id =
            v_row.employee_id

        and el.status =
            'active'

        and el.balance_due >
            0

        -- السلفة اللي لسا ما انصرفت للموظف ما بتنخصم من راتبو.
        and exists (select 1 from public.employee_loan_disbursements d where d.employee_loan_id = el.id)

      order by
        el.start_date,
        el.created_at

      for update
    loop

      exit when
        v_remaining <= 0.01;


      v_take :=
        round(
          least(
            v_remaining,
            v_loan.balance_due
          ),
          2
        );


      v_repayment := null;


      insert into public.employee_loan_repayments(
        company_id,
        employee_loan_id,
        payroll_item_id,
        amount,
        repayment_date
      )
      values(
        v_row.company_id,
        v_loan.id,
        v_row.payroll_item_id,
        v_take,
        v_row.period_end
      )

      on conflict(
        employee_loan_id,
        payroll_item_id
      )
      do nothing

      returning id
      into v_repayment;


      if v_repayment is null then

        select
          r.amount

        into
          v_existing

        from public.employee_loan_repayments r

        where r.employee_loan_id =
              v_loan.id

          and r.payroll_item_id =
              v_row.payroll_item_id;


        v_remaining :=
          greatest(
            round(
              v_remaining -
              coalesce(
                v_existing,
                0
              ),
              2
            ),
            0
          );

        continue;
      end if;


      update public.employee_loans
      set
        balance_due =
          greatest(
            round(
              balance_due -
              v_take,
              2
            ),
            0
          ),

        status =
          case
            when round(
                   balance_due -
                   v_take,
                   2
                 ) <= 0
              then 'settled'

            else status
          end

      where id =
            v_loan.id;


      v_remaining :=
        greatest(
          round(
            v_remaining -
            v_take,
            2
          ),
          0
        );

    end loop;


    if v_remaining > 0.01 then
      raise exception
        'Payroll loan deduction exceeds employee loan balance';
    end if;

  end loop;
end;
$function$;

create or replace function public.create_employee_loan(target_company uuid, target_employee uuid, target_type text, target_amount numeric, target_installment numeric, target_start_date date, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_type not in (
    'advance',
    'loan'
  ) then
    raise exception
      'Invalid employee loan type';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid employee loan amount';
  end if;

  if coalesce(
       target_installment,
       0
     ) < 0
  then
    raise exception
      'Invalid installment';
  end if;

  if not exists (
    select 1
    from public.employees
    where id =
          target_employee

      and company_id =
          target_company

      and status =
          'active'
  ) then
    raise exception
      'Invalid employee';
  end if;

  insert into public.employee_loans(
    company_id,
    employee_id,
    loan_type,
    original_amount,
    balance_due,
    installment_amount,
    start_date,
    status,
    notes
  )
  values(
    target_company,
    target_employee,
    target_type,
    round(target_amount,2),
    round(target_amount,2),
    round(
      coalesce(
        target_installment,
        0
      ),
      2
    ),
    coalesce(
      target_start_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    'active',
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_id;

  return v_id;
end;
$function$;

-- إلغاء سلفة انعملت بالغلط، بس إذا لسا ما انصرفت (بعد الصرف الطريق هو خصمها أو تسديدها).
create or replace function public.cancel_employee_loan(target_company uuid, target_loan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(target_company, 'payroll.manage_employees') then
    raise exception 'Not allowed';
  end if;

  if exists (
    select 1 from public.employee_loan_disbursements
    where employee_loan_id = target_loan
  ) then
    raise exception 'Loan already disbursed';
  end if;

  update public.employee_loans
  set status = 'cancelled'
  where id = target_loan
    and company_id = target_company
    and status = 'active';

  if not found then
    raise exception 'Employee loan not found';
  end if;
end;
$function$;

-- سائق/مندوب ونسبة العمولة (بعد حفظ الموظف).
create or replace function public.set_employee_roles(target_company uuid, target_employee uuid, target_is_driver boolean, target_is_sales_rep boolean, target_commission_rate numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(target_company, 'payroll.manage_employees') then
    raise exception 'Not allowed';
  end if;

  update public.employees
  set is_driver = coalesce(target_is_driver, false),
      is_sales_rep = coalesce(target_is_sales_rep, false),
      commission_rate = case when coalesce(target_is_sales_rep, false)
                             then greatest(least(coalesce(target_commission_rate, 0), 100), 0) else 0 end,
      updated_at = now()
  where id = target_employee and company_id = target_company;

  if not found then
    raise exception 'Employee not found';
  end if;
end;
$function$;

-- أسماء السائقين والمندوبين الشغّالين (لقوائم الاختيار؛ بدون رواتب أو تفاصيل).
create or replace function public.get_staff_options(target_company uuid)
 RETURNS TABLE(id uuid, full_name text, is_driver boolean, is_sales_rep boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.id, e.full_name, e.is_driver, e.is_sales_rep
  from public.employees e
  where e.company_id = target_company
    and e.status = 'active'
    and (e.is_driver or e.is_sales_rep)
    and public.is_company_member(target_company)
  order by e.full_name;
$function$;

-- سائق التوصيلة.
create or replace function public.set_delivery_driver(target_company uuid, target_delivery uuid, target_driver uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_permission(target_company, 'deliveries.update') then
    raise exception 'Not allowed';
  end if;

  if target_driver is not null and not exists (
    select 1 from public.employees
    where id = target_driver and company_id = target_company and is_driver and status = 'active'
  ) then
    raise exception 'Invalid driver';
  end if;

  update public.deliveries
  set driver_id = target_driver, updated_at = now()
  where id = target_delivery and company_id = target_company;

  if not found then
    raise exception 'Delivery not found';
  end if;
end;
$function$;

-- أداء المندوبين (صافي مبيعات زبائنهن والعمولة) والسائقين (التوصيلات) بفترة.
create or replace function public.get_team_performance(target_company uuid, target_from date, target_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_from date := coalesce(target_from, date_trunc('month', (now() at time zone 'Asia/Damascus')::date)::date);
  v_to date := coalesce(target_to, (now() at time zone 'Asia/Damascus')::date);
begin
  if not public.has_any_permission(target_company, array['reports.sales','reports.team','reports.profit','payroll.view']) then
    raise exception 'Not allowed';
  end if;

  return jsonb_build_object(
    'reps', coalesce((
      select jsonb_agg(r order by r.net_sales desc)
      from (
        select
          e.id,
          e.full_name,
          e.commission_rate,
          (select count(*) from public.traders t where t.sales_rep_id = e.id) as customers,
          round(coalesce(inv.sales, 0), 2) as sales,
          round(coalesce(ret.returns, 0), 2) as returns,
          round(coalesce(inv.sales, 0) - coalesce(ret.returns, 0), 2) as net_sales,
          round(coalesce(pay.collected, 0), 2) as collected,
          round((coalesce(inv.sales, 0) - coalesce(ret.returns, 0)) * e.commission_rate / 100, 2) as commission
        from public.employees e
        left join lateral (
          select sum(public.finance_to_base(target_company, si.currency, si.total, si.invoice_date)) as sales
          from public.sales_invoices si
          join public.traders t on t.id = si.trader_id
          where t.sales_rep_id = e.id and si.status = 'posted'
            and si.invoice_date between v_from and v_to
        ) inv on true
        left join lateral (
          select sum(public.finance_to_base(target_company, sr.currency, sr.total, sr.return_date)) as returns
          from public.sales_returns sr
          join public.traders t on t.id = sr.trader_id
          where t.sales_rep_id = e.id and sr.status = 'posted'
            and sr.return_date between v_from and v_to
        ) ret on true
        left join lateral (
          select sum(coalesce(p.base_amount, p.amount)) as collected
          from public.customer_payments p
          join public.traders t on t.id = p.trader_id
          where t.sales_rep_id = e.id and p.status = 'posted'
            and p.payment_date between v_from and v_to
        ) pay on true
        where e.company_id = target_company and e.is_sales_rep
      ) r
    ), '[]'::jsonb),
    'drivers', coalesce((
      select jsonb_agg(d order by d.delivered desc)
      from (
        select
          e.id,
          e.full_name,
          count(*) filter (where dl.status = 'delivered') as delivered,
          count(*) filter (where dl.status = 'failed') as failed,
          count(*) filter (where dl.status in ('pending','out_for_delivery')) as open
        from public.employees e
        left join public.deliveries dl
          on dl.driver_id = e.id
         and (dl.status in ('pending','out_for_delivery')
              or (coalesce(dl.delivered_at, dl.failed_at) at time zone 'Asia/Damascus')::date between v_from and v_to)
        where e.company_id = target_company and e.is_driver
        group by e.id, e.full_name
      ) d
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.create_payroll_run(target_company uuid, target_period_start date, target_period_end date, target_pay_date date, target_currency text, target_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- قسط السلف بينخصم تلقائيًا: لكل موظف، مجموع أقساط سلفه المفتوحة
  -- (القسط أو الباقي من السلفة إذا أقل). بيضل قابل للتعديل من شاشة الرواتب.
  update public.payroll_items pi
  set loan_deduction = least(x.installments, pi.gross_pay)
  from (
    select
      el.employee_id,
      sum(least(el.installment_amount, el.balance_due)) as installments
    from public.employee_loans el
    where el.company_id = target_company
      and el.status = 'active'
      and el.balance_due > 0
      and el.installment_amount > 0
      and el.start_date <= target_period_end
      and exists (select 1 from public.employee_loan_disbursements d where d.employee_loan_id = el.id)
    group by el.employee_id
  ) x
  where pi.payroll_run_id = v_run
    and pi.employee_id = x.employee_id;

  perform public.recalculate_payroll_item(pi.id)
  from public.payroll_items pi
  where pi.payroll_run_id = v_run
    and pi.loan_deduction > 0;

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
$function$;

create or replace function public.disburse_employee_loan(target_company uuid, target_loan uuid, target_cashbox uuid, target_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_employee uuid;
  v_amount numeric(18,2);
  v_status text;
  v_currency text;

  v_id uuid;
  v_cash uuid;
  v_advance uuid;
  v_entry uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if exists(
    select 1
    from public.employee_loan_disbursements
    where employee_loan_id =
          target_loan
  ) then
    raise exception
      'Loan already disbursed';
  end if;

  select
    employee_id,
    original_amount,
    status
  into
    v_employee,
    v_amount,
    v_status
  from public.employee_loans
  where id = target_loan
    and company_id =
        target_company
  for update;

  if v_employee is null then
    raise exception
      'Employee loan not found';
  end if;

  if v_status <>
     'active'
  then
    raise exception
      'Loan is not active';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        target_cashbox
    and company_id =
        target_company
    and active = true;

  if v_currency is null then
    raise exception
      'Invalid cashbox';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_cash :=
    public.finance_cashbox_account(
      target_company,
      target_cashbox
    );

  v_advance :=
    public.finance_system_account(
      target_company,
      'employee_advances'
    );

  insert into public.employee_loan_disbursements(
    company_id,
    employee_loan_id,
    employee_id,
    cashbox_id,
    amount,
    currency,
    disbursement_date
  )
  values(
    target_company,
    target_loan,
    v_employee,
    target_cashbox,
    v_amount,
    v_currency,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    )
  )
  returning id
  into v_id;

  v_entry :=
    public.post_system_journal(
      target_company,
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      ),
      'صرف سلفة أو قرض موظف',
      v_currency,
      null,
      'employee_loan_disbursement',
      v_id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          v_amount,
          'credit',
          0,
          'party_type',
          'employee',
          'party_id',
          v_employee
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          v_amount,
          'party_type',
          'employee',
          'party_id',
          v_employee
        )
      )
    );

  update public.employee_loan_disbursements
  set journal_entry_id =
      v_entry
  where id =
        v_id;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    employee_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    'out',
    case
      when exists(
        select 1
        from public.employee_loans
        where id = target_loan
          and loan_type =
              'advance'
      )
        then 'employee_advance'
      else 'employee_loan'
    end,
    v_amount,
    v_employee,
    'صرف سلفة أو قرض موظف',
    (
      coalesce(
        target_date,
        (now() at time zone 'Asia/Damascus')::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  return v_id;
end;
$function$;

create or replace function public.payroll_after_post_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if old.status = 'draft'
     and new.status = 'posted'
  then
    perform
      public.apply_payroll_loan_deductions(
        new.id
      );
  end if;

  return new;
end;
$function$;

create or replace function public.post_payroll_run(target_company uuid, target_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  v_currency text;
  v_period_end date;
  v_pay_date date;

  v_gross numeric(18,2);
  v_employer numeric(18,2);
  v_net numeric(18,2);

  v_social numeric(18,2);
  v_tax numeric(18,2);
  v_loan numeric(18,2);
  v_absence_other numeric(18,2);

  v_salary_expense uuid;
  v_employer_expense uuid;
  v_payable uuid;
  v_withholdings uuid;
  v_employee_advances uuid;

  v_lines jsonb := '[]'::jsonb;
begin
  if not public.has_permission(
    target_company,
    'payroll.process'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    status,
    currency,
    period_end,
    pay_date
  into
    v_status,
    v_currency,
    v_period_end,
    v_pay_date
  from public.payroll_runs
  where id = target_run
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Payroll run not found';
  end if;

  if v_status <> 'draft' then
    raise exception
      'Only draft payroll can be posted';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      v_period_end
    );

  select
    round(
      coalesce(
        sum(gross_pay),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(employer_contribution),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(net_pay),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(social_security_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(tax_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(loan_deduction),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(
          absence_deduction +
          other_deductions
        ),
        0
      ),
      2
    )

  into
    v_gross,
    v_employer,
    v_net,
    v_social,
    v_tax,
    v_loan,
    v_absence_other

  from public.payroll_items
  where payroll_run_id =
        target_run;

  if v_gross <= 0 then
    raise exception
      'Payroll has no payable amounts';
  end if;

  v_salary_expense :=
    public.finance_system_account(
      target_company,
      'salary_expense'
    );

  v_employer_expense :=
    public.finance_system_account(
      target_company,
      'employer_contribution_expense'
    );

  v_payable :=
    public.finance_system_account(
      target_company,
      'payroll_payable'
    );

  v_withholdings :=
    public.finance_system_account(
      target_company,
      'payroll_withholdings'
    );

  v_employee_advances :=
    public.finance_system_account(
      target_company,
      'employee_advances'
    );

  v_lines :=
    v_lines ||
    jsonb_build_array(
      jsonb_build_object(
        'account_id',
        v_salary_expense,
        'debit',
        v_gross,
        'credit',
        0,
        'memo',
        'رواتب وأجور'
      )
    );

  if v_employer > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_employer_expense,
          'debit',
          v_employer,
          'credit',
          0,
          'memo',
          'مساهمات صاحب العمل'
        )
      );
  end if;

  if v_net > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_payable,
          'debit',
          0,
          'credit',
          v_net,
          'memo',
          'صافي رواتب مستحق'
        )
      );
  end if;

  if (
    v_social +
    v_tax +
    v_employer
  ) > 0
  then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_withholdings,
          'debit',
          0,
          'credit',
          round(
            v_social +
            v_tax +
            v_employer,
            2
          ),
          'memo',
          'اقتطاعات ومستحقات رواتب'
        )
      );
  end if;

  if v_loan > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_employee_advances,
          'debit',
          0,
          'credit',
          v_loan,
          'memo',
          'حسم سلفة أو قرض موظف'
        )
      );
  end if;

  if v_absence_other > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_salary_expense,
          'debit',
          0,
          'credit',
          v_absence_other,
          'memo',
          'حسم غياب وخصومات أخرى'
        )
      );
  end if;

  perform
    public.post_system_journal(
      target_company,
      v_period_end,
      'ترحيل رواتب حتى ' ||
      v_period_end::text,
      v_currency,
      null,
      'payroll_run',
      target_run,
      v_lines
    );

  update public.payroll_runs
  set
    status = 'posted',
    posted_at = now(),
    posted_by = auth.uid()
  where id = target_run;
end;
$function$;

create or replace function public.recalculate_payroll_item(target_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.record_payroll_payment(target_company uuid, target_payroll_item uuid, target_cashbox uuid, target_amount numeric, target_payment_date date, target_method text, target_reference text, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid;
  v_employee uuid;
  v_balance numeric(18,2);
  v_run_status text;
  v_currency text;

  v_cashbox_currency text;
  v_payment uuid;

  v_cash uuid;
  v_payable uuid;

  v_total_net numeric(18,2);
  v_total_paid numeric(18,2);
begin
  if not public.has_permission(
    target_company,
    'payroll.pay'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid payroll payment amount';
  end if;

  select
    pi.payroll_run_id,
    pi.employee_id,
    pi.balance_due,
    pr.status,
    pr.currency
  into
    v_run,
    v_employee,
    v_balance,
    v_run_status,
    v_currency
  from public.payroll_items pi

  join public.payroll_runs pr
    on pr.id =
       pi.payroll_run_id

  where pi.id =
        target_payroll_item

    and pi.company_id =
        target_company

  for update of pi, pr;

  if v_run is null then
    raise exception
      'Payroll item not found';
  end if;

  if v_run_status not in (
    'posted',
    'partial'
  ) then
    raise exception
      'Payroll is not ready for payment';
  end if;

  if round(
       target_amount,
       2
     ) >
     round(
       v_balance,
       2
     )
  then
    raise exception
      'Payment exceeds employee payroll balance';
  end if;

  select currency
  into v_cashbox_currency
  from public.cashboxes
  where id = target_cashbox
    and company_id =
        target_company
    and active = true;

  if v_cashbox_currency is null then
    raise exception
      'Invalid cashbox';
  end if;

  if upper(v_cashbox_currency) <>
     upper(v_currency)
  then
    raise exception
      'Payroll cashbox currency must match payroll currency';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.payroll_payments(
    company_id,
    payroll_item_id,
    employee_id,
    cashbox_id,
    amount,
    currency,
    payment_date,
    payment_method,
    status,
    reference_number,
    notes
  )
  values(
    target_company,
    target_payroll_item,
    v_employee,
    target_cashbox,
    round(
      target_amount,
      2
    ),
    upper(v_currency),
    coalesce(
      target_payment_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      nullif(
        trim(target_method),
        ''
      ),
      'cash'
    ),
    'posted',
    nullif(
      trim(target_reference),
      ''
    ),
    nullif(
      trim(target_notes),
      ''
    )
  )
  returning id
  into v_payment;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    employee_id,
    payroll_payment_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    'out',
    'payroll_payment',
    round(
      target_amount,
      2
    ),
    v_employee,
    v_payment,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'دفع راتب موظف'
    ),
    (
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  v_cash :=
    public.finance_cashbox_account(
      target_company,
      target_cashbox
    );

  v_payable :=
    public.finance_system_account(
      target_company,
      'payroll_payable'
    );

  perform
    public.post_system_journal(
      target_company,
      coalesce(
        target_payment_date,
        (now() at time zone 'Asia/Damascus')::date
      ),
      'دفع راتب موظف',
      v_currency,
      null,
      'payroll_payment',
      v_payment,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_payable,
          'debit',
          round(
            target_amount,
            2
          ),
          'credit',
          0,
          'party_type',
          'employee',
          'party_id',
          v_employee
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          round(
            target_amount,
            2
          ),
          'party_type',
          'employee',
          'party_id',
          v_employee
        )
      )
    );

  update public.payroll_items
  set
    paid_total =
      round(
        paid_total +
        target_amount,
        2
      ),

    balance_due =
      greatest(
        round(
          net_pay -
          (
            paid_total +
            target_amount
          ),
          2
        ),
        0
      )

  where id =
        target_payroll_item;

  select
    coalesce(
      sum(net_pay),
      0
    ),
    coalesce(
      sum(paid_total),
      0
    )
  into
    v_total_net,
    v_total_paid
  from public.payroll_items
  where payroll_run_id =
        v_run;

  update public.payroll_runs
  set
    total_paid =
      round(
        v_total_paid,
        2
      ),

    status =
      case
        when round(
               v_total_paid,
               2
             ) >=
             round(
               v_total_net,
               2
             )
          then 'paid'

        when v_total_paid > 0
          then 'partial'

        else 'posted'
      end

  where id =
        v_run;

  return v_payment;
end;
$function$;

create or replace function public.save_employee(target_company uuid, target_employee uuid, target_employee_number text, target_name text, target_phone text, target_job_title text, target_department text, target_hire_date date, target_salary_currency text, target_base_salary numeric, target_fixed_allowances numeric, target_overtime_rate numeric, target_employee_social_rate numeric, target_employer_social_rate numeric, target_income_tax_rate numeric, target_cashbox uuid, target_notes text, target_status text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_permission(
    target_company,
    'payroll.manage_employees'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Employee name is required';
  end if;

  if target_status not in (
    'active',
    'inactive',
    'terminated'
  ) then
    raise exception
      'Invalid employee status';
  end if;

  if upper(
       trim(
         coalesce(
           target_salary_currency,
           ''
         )
       )
     ) !~ '^[A-Z]{3}$'
  then
    raise exception
      'Invalid salary currency';
  end if;

  if coalesce(
       target_base_salary,
       0
     ) < 0
     or coalesce(
       target_fixed_allowances,
       0
     ) < 0
     or coalesce(
       target_overtime_rate,
       0
     ) < 0
     or coalesce(
       target_employee_social_rate,
       0
     ) < 0
     or coalesce(
       target_employer_social_rate,
       0
     ) < 0
     or coalesce(
       target_income_tax_rate,
       0
     ) < 0
  then
    raise exception
      'Payroll values cannot be negative';
  end if;

  if coalesce(
       target_employee_social_rate,
       0
     ) > 100
     or coalesce(
       target_employer_social_rate,
       0
     ) > 100
     or coalesce(
       target_income_tax_rate,
       0
     ) > 100
  then
    raise exception
      'Payroll percentage cannot exceed 100';
  end if;

  if target_cashbox is not null
     and not exists (
       select 1
       from public.cashboxes
       where id = target_cashbox
         and company_id =
             target_company
         and active = true
     )
  then
    raise exception
      'Invalid employee cashbox';
  end if;

  if target_employee is null then

    insert into public.employees(
      company_id,
      employee_number,
      full_name,
      phone,
      job_title,
      department,
      hire_date,
      status,
      salary_currency,
      base_salary,
      fixed_allowances,
      overtime_hour_rate,
      social_security_employee_rate,
      social_security_employer_rate,
      income_tax_rate,
      default_cashbox_id,
      notes
    )
    values(
      target_company,
      nullif(
        trim(target_employee_number),
        ''
      ),
      trim(target_name),
      nullif(trim(target_phone),''),
      nullif(trim(target_job_title),''),
      nullif(trim(target_department),''),
      target_hire_date,
      target_status,
      upper(
        coalesce(
          nullif(
            trim(target_salary_currency),
            ''
          ),
          'USD'
        )
      ),
      coalesce(target_base_salary,0),
      coalesce(target_fixed_allowances,0),
      coalesce(target_overtime_rate,0),
      coalesce(target_employee_social_rate,0),
      coalesce(target_employer_social_rate,0),
      coalesce(target_income_tax_rate,0),
      target_cashbox,
      nullif(trim(target_notes),'')
    )
    returning id
    into v_id;

  else

    update public.employees
    set
      employee_number =
        nullif(
          trim(target_employee_number),
          ''
        ),

      full_name =
        trim(target_name),

      phone =
        nullif(
          trim(target_phone),
          ''
        ),

      job_title =
        nullif(
          trim(target_job_title),
          ''
        ),

      department =
        nullif(
          trim(target_department),
          ''
        ),

      hire_date =
        target_hire_date,

      status =
        target_status,

      salary_currency =
        upper(
          coalesce(
            nullif(
              trim(target_salary_currency),
              ''
            ),
            salary_currency
          )
        ),

      base_salary =
        coalesce(
          target_base_salary,
          0
        ),

      fixed_allowances =
        coalesce(
          target_fixed_allowances,
          0
        ),

      overtime_hour_rate =
        coalesce(
          target_overtime_rate,
          0
        ),

      social_security_employee_rate =
        coalesce(
          target_employee_social_rate,
          0
        ),

      social_security_employer_rate =
        coalesce(
          target_employer_social_rate,
          0
        ),

      income_tax_rate =
        coalesce(
          target_income_tax_rate,
          0
        ),

      default_cashbox_id =
        target_cashbox,

      notes =
        nullif(
          trim(target_notes),
          ''
        )

    where id =
          target_employee

      and company_id =
          target_company

    returning id
    into v_id;

    if v_id is null then
      raise exception
        'Employee not found';
    end if;

  end if;

  return v_id;
end;
$function$;

create or replace function public.update_payroll_item(target_company uuid, target_item uuid, target_allowances numeric, target_overtime_hours numeric, target_overtime_amount numeric, target_bonuses numeric, target_absent_days numeric, target_absence_deduction numeric, target_loan_deduction numeric, target_social_security_deduction numeric, target_tax_deduction numeric, target_other_deductions numeric, target_employer_contribution numeric, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_employee_loan_disbursements after insert or delete or update on public.employee_loan_disbursements for each row execute function public.write_audit_log();

create trigger audit_employee_loan_repayments after insert or delete or update on public.employee_loan_repayments for each row execute function public.write_audit_log();

create trigger audit_employee_loans after insert or delete or update on public.employee_loans for each row execute function public.write_audit_log();

create trigger employee_loans_updated_at before update on public.employee_loans for each row execute function public.set_updated_at();

create trigger audit_employees after insert or delete or update on public.employees for each row execute function public.write_audit_log();

create trigger employees_updated_at before update on public.employees for each row execute function public.set_updated_at();

create trigger audit_payroll_items after insert or delete or update on public.payroll_items for each row execute function public.write_audit_log();

create trigger payroll_items_updated_at before update on public.payroll_items for each row execute function public.set_updated_at();

create trigger audit_payroll_payments after insert or update on public.payroll_payments for each row execute function public.write_audit_log();

create trigger audit_payroll_runs after insert or delete or update on public.payroll_runs for each row execute function public.write_audit_log();

create trigger payroll_apply_loan_deductions after update of status on public.payroll_runs for each row execute function public.payroll_after_post_trigger();

create trigger payroll_runs_updated_at before update on public.payroll_runs for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.employees enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
alter table public.payroll_payments enable row level security;
alter table public.employee_loans enable row level security;
alter table public.employee_loan_disbursements enable row level security;
alter table public.employee_loan_repayments enable row level security;
create policy employee_loan_disbursements_read on public.employee_loan_disbursements
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employee_loan_repayments_read on public.employee_loan_repayments
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employee_loans_read on public.employee_loans
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy employees_payroll_read on public.employees
  for select to authenticated
  using ((public.has_permission(company_id, 'payroll.view'::text) or public.has_permission(company_id, 'payroll.manage_employees'::text)));
create policy payroll_items_read on public.payroll_items
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));
create policy payroll_payments_read on public.payroll_payments
  for select to authenticated
  using ((public.has_permission(company_id, 'payroll.view'::text) or public.has_permission(company_id, 'payroll.pay'::text)));
create policy payroll_runs_read on public.payroll_runs
  for select to authenticated
  using (public.has_permission(company_id, 'payroll.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.employees from authenticated;
revoke insert, update, delete on public.payroll_runs from authenticated;
revoke insert, update, delete on public.payroll_items from authenticated;
revoke insert, update, delete on public.payroll_payments from authenticated;
revoke insert, update, delete on public.employee_loans from authenticated;
revoke insert, update, delete on public.employee_loan_disbursements from authenticated;
revoke insert, update, delete on public.employee_loan_repayments from authenticated;
revoke execute on function public.apply_payroll_loan_deductions(uuid) from authenticated;
revoke execute on function public.recalculate_payroll_item(uuid) from authenticated;
