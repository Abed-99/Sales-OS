begin;

-- ============================================================
-- SAVE / UPDATE FINANCE ACCOUNT
-- ============================================================

create or replace function public.save_finance_account(
  target_company uuid,
  target_account uuid,
  target_parent uuid,
  target_code text,
  target_name text,
  target_type text,
  target_group text,
  target_normal_balance text,
  target_allow_posting boolean,
  target_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.save_finance_account(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  boolean,
  boolean
)
from public;

grant execute
on function public.save_finance_account(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  boolean,
  boolean
)
to authenticated;


-- ============================================================
-- SAVE / UPDATE EMPLOYEE
-- ============================================================

create or replace function public.save_employee(
  target_company uuid,
  target_employee uuid,
  target_employee_number text,
  target_name text,
  target_phone text,
  target_job_title text,
  target_department text,
  target_hire_date date,
  target_salary_currency text,
  target_base_salary numeric,
  target_fixed_allowances numeric,
  target_overtime_rate numeric,
  target_employee_social_rate numeric,
  target_employer_social_rate numeric,
  target_income_tax_rate numeric,
  target_cashbox uuid,
  target_notes text,
  target_status text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.save_employee(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  uuid,
  text,
  text
)
from public;

grant execute
on function public.save_employee(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  uuid,
  text,
  text
)
to authenticated;


-- ============================================================
-- EMPLOYEE ADVANCE / LOAN
-- ============================================================

create or replace function public.create_employee_loan(
  target_company uuid,
  target_employee uuid,
  target_type text,
  target_amount numeric,
  target_installment numeric,
  target_start_date date,
  target_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.create_employee_loan(
  uuid,
  uuid,
  text,
  numeric,
  numeric,
  date,
  text
)
from public;

grant execute
on function public.create_employee_loan(
  uuid,
  uuid,
  text,
  numeric,
  numeric,
  date,
  text
)
to authenticated;


-- ============================================================
-- SETTLE EMPLOYEE LOAN DEDUCTION WHEN PAYROLL POSTS
-- ============================================================

create table if not exists public.employee_loan_repayments(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  employee_loan_id uuid not null
    references public.employee_loans(id)
    on delete restrict,

  payroll_item_id uuid
    references public.payroll_items(id)
    on delete restrict,

  amount numeric(18,2) not null
    check(amount > 0),

  repayment_date date not null,

  created_at timestamptz not null default now(),

  unique(
    employee_loan_id,
    payroll_item_id
  )
);


create or replace function
public.apply_payroll_loan_deductions(
  target_run uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.apply_payroll_loan_deductions(uuid)
from public, authenticated;


-- Add loan settlement to payroll posting.
create or replace function public.payroll_after_post_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists
payroll_apply_loan_deductions
on public.payroll_runs;

create trigger
payroll_apply_loan_deductions
after update of status
on public.payroll_runs
for each row
execute function
public.payroll_after_post_trigger();


-- ============================================================
-- GENERAL LEDGER VIEW
-- ============================================================

create or replace view public.finance_general_ledger
with (security_invoker = true)
as
select
  je.company_id,

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

join public.journal_lines jl
  on jl.journal_entry_id =
     je.id

join public.finance_accounts a
  on a.id =
     jl.account_id;


grant select
on public.finance_general_ledger
to authenticated;


-- ============================================================
-- PAYROLL SUMMARY VIEW
-- ============================================================

create or replace view public.payroll_employee_summary
with (security_invoker = true)
as
select
  e.company_id,
  e.id as employee_id,
  e.employee_number,
  e.full_name,
  e.job_title,
  e.department,
  e.status,
  e.salary_currency,
  e.base_salary,
  e.fixed_allowances,

  coalesce(
    loans.active_loan_balance,
    0
  )::numeric(18,2)
  as active_loan_balance,

  coalesce(
    payroll.total_net,
    0
  )::numeric(18,2)
  as payroll_net_total,

  coalesce(
    payroll.total_paid,
    0
  )::numeric(18,2)
  as payroll_paid_total,

  coalesce(
    payroll.total_due,
    0
  )::numeric(18,2)
  as payroll_due_total

from public.employees e

left join lateral (
  select
    coalesce(
      sum(balance_due),
      0
    ) as active_loan_balance
  from public.employee_loans
  where employee_id =
        e.id
    and status =
        'active'
) loans on true

left join lateral (
  select
    coalesce(
      sum(pi.net_pay),
      0
    ) as total_net,

    coalesce(
      sum(pi.paid_total),
      0
    ) as total_paid,

    coalesce(
      sum(pi.balance_due),
      0
    ) as total_due

  from public.payroll_items pi

  join public.payroll_runs pr
    on pr.id =
       pi.payroll_run_id

  where pi.employee_id =
        e.id

    and pr.status in (
      'posted',
      'partial',
      'paid'
    )
) payroll on true;


grant select
on public.payroll_employee_summary
to authenticated;


-- ============================================================
-- RLS EMPLOYEE LOAN REPAYMENTS
-- ============================================================

alter table public.employee_loan_repayments
enable row level security;

drop policy if exists
employee_loan_repayments_read
on public.employee_loan_repayments;

create policy employee_loan_repayments_read
on public.employee_loan_repayments
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'payroll.view'
  )
);

revoke insert, update, delete
on public.employee_loan_repayments
from authenticated;

grant select
on public.employee_loan_repayments
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists
audit_employee_loan_repayments
on public.employee_loan_repayments;

create trigger
audit_employee_loan_repayments
after insert or update or delete
on public.employee_loan_repayments
for each row
execute function public.write_audit_log();

commit;