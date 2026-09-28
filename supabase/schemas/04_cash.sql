-- ======================================================================
-- الصناديق
-- الصناديق، المصاريف، حركات المصاري
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.cashboxes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text default 'الصندوق الرئيسي'::text not null,
  currency text default 'USD'::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create unique index cashboxes_company_name_unique on public.cashboxes using btree (company_id, name);

create table public.cashbox_gl_accounts (
  cashbox_id uuid primary key references public.cashboxes(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  account_id uuid not null references public.finance_accounts(id) on delete restrict,
  created_at timestamp with time zone default now() not null,
  constraint cashbox_gl_accounts_account_id_key unique (account_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid references public.cashboxes(id) on delete set null,
  category text not null,
  amount numeric(14,2) not null,
  notes text,
  occurred_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint expenses_amount_check check ((amount > (0)::numeric))
);
create index expenses_company_idx on public.expenses using btree (company_id, occurred_at desc);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashbox_id uuid not null references public.cashboxes(id) on delete restrict,
  direction text not null,
  type text not null,
  amount numeric(14,2) not null,
  order_id uuid,
  trader_id uuid references public.traders(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  expense_id uuid references public.expenses(id) on delete set null,
  supplier_payment_id uuid,
  customer_payment_id uuid,
  notes text,
  occurred_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  employee_id uuid,
  payroll_payment_id uuid,
  partner_transaction_id uuid,
  constraint cash_transactions_amount_check check ((amount > (0)::numeric)),
  constraint cash_transactions_direction_check check ((direction = any (array['in'::text, 'out'::text]))),
  constraint cash_transactions_type_check check ((type = any (array['sale_receipt'::text, 'supplier_payment'::text, 'expense'::text, 'partner_deposit'::text, 'partner_withdrawal'::text, 'adjustment_in'::text, 'adjustment_out'::text, 'customer_payment_reversal'::text, 'supplier_payment_reversal'::text, 'payroll_payment'::text, 'employee_advance'::text, 'employee_loan'::text, 'partner_distribution'::text, 'asset_purchase'::text, 'asset_sale'::text])))
);
create index cash_transactions_company_idx on public.cash_transactions using btree (company_id, occurred_at desc);
create index cash_transactions_customer_payment_idx on public.cash_transactions using btree (customer_payment_id) where (customer_payment_id is not null);
create unique index cash_transactions_customer_payment_type_unique on public.cash_transactions using btree (customer_payment_id, type) where ((customer_payment_id is not null) and (type = any (array['sale_receipt'::text, 'adjustment_out'::text])));
create unique index cash_transactions_partner_transaction_unique on public.cash_transactions using btree (partner_transaction_id) where (partner_transaction_id is not null);
create unique index cash_transactions_payroll_payment_unique on public.cash_transactions using btree (payroll_payment_id, type) where ((payroll_payment_id is not null) and (type = 'payroll_payment'::text));
create index cash_transactions_supplier_payment_idx on public.cash_transactions using btree (supplier_payment_id) where (supplier_payment_id is not null);
create unique index cash_transactions_supplier_payment_type_unique on public.cash_transactions using btree (supplier_payment_id, type) where ((supplier_payment_id is not null) and (type = any (array['supplier_payment'::text, 'adjustment_in'::text])));
create index cash_transactions_trader_idx on public.cash_transactions using btree (trader_id, occurred_at desc) where (trader_id is not null);


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.cashbox_gl_account_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.ensure_cashbox_gl_account(
      new.id
    );

  return new;
end;
$function$;

create or replace function public.enforce_cashbox_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.cashbox_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.cashboxes c
    where c.id = new.cashbox_id
      and c.company_id = new.company_id
  ) then
    raise exception 'Cashbox belongs to another company or does not exist';
  end if;

  return new;
end;
$function$;

create or replace function public.ensure_cashbox_gl_account(target_cashbox uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_name text;
  v_account uuid;
  v_parent uuid;
  v_currency text;
  v_code text;
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
    name,
    upper(currency)
  into
    v_company,
    v_name,
    v_currency
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

    -- رقم مرتب تحت "الصندوق والبنوك": 1120، 1130، ...
    perform pg_advisory_xact_lock(hashtext('cashbox_code:' || v_company::text));

    select coalesce(max(code::integer), 1110) + 10
    into v_code
    from public.finance_accounts
    where company_id = v_company
      and code ~ '^11[1-9][0-9]$';

    if v_code::integer > 1199 then
      select coalesce(max(code::integer), 1100) + 1
      into v_code
      from public.finance_accounts
      where company_id = v_company
        and code ~ '^11[0-9][0-9]$';
    end if;

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
      v_code,
      coalesce(v_name, 'صندوق') || ' (' || coalesce(v_currency, '') || ')',
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
$function$;

create or replace function public.finance_cashbox_account(target_company uuid, target_cashbox uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_account uuid;
begin
  if not exists(
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id =
          target_company
  ) then
    raise exception
      'Invalid cashbox';
  end if;

  perform
    public.ensure_cashbox_gl_account(
      target_cashbox
    );

  select account_id
  into v_account
  from public.cashbox_gl_accounts
  where cashbox_id =
        target_cashbox
    and company_id =
        target_company;

  if v_account is null then
    raise exception
      'Cashbox GL account not found';
  end if;

  return v_account;
end;
$function$;

create or replace function public.get_cashbox_balances(target_company uuid)
 RETURNS TABLE(id uuid, name text, currency text, active boolean, balance numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- رصيد كل صندوق لحاله (الملخص فوق بيجمع حسب العملة).
  select
    cb.id,
    cb.name,
    upper(cb.currency),
    cb.active,
    coalesce(
      (
        select sum(case when ct.direction = 'in' then ct.amount else -ct.amount end)
        from public.cash_transactions ct
        where ct.cashbox_id = cb.id
      ),
      0
    )
  from public.cashboxes cb
  where cb.company_id = target_company
    and public.has_any_permission(
      target_company,
      array['finance.cashbox_view', 'finance.cashbox_write', 'finance.expenses_view', 'finance.expenses_write']
    )
  order by cb.active desc, cb.created_at
$function$;

create or replace function public.get_cashbox_summary(target_company uuid, target_date date)
 RETURNS TABLE(currency text, balance numeric, today_in numeric, today_out numeric, month_expense numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(
    target_company,
    array[
      'finance.cashbox_view',
      'finance.cashbox_write',
      'finance.expenses_view',
      'finance.expenses_write'
    ]
  ) then
    raise exception 'Not allowed';
  end if;

  return query
  with currency_list as (
    select distinct upper(cb.currency) as currency
    from public.cashboxes cb
    where cb.company_id = target_company

    union

    select upper(coalesce(c.default_currency,'USD'))
    from public.companies c
    where c.id = target_company
  ),
  transaction_totals as (
    select
      upper(cb.currency) as currency,
      coalesce(
        sum(
          case
            when ct.direction = 'in' then ct.amount
            else -ct.amount
          end
        ),
        0
      ) as balance,
      coalesce(
        sum(
          case
            when ct.direction = 'in'
             and (ct.occurred_at at time zone 'Asia/Damascus')::date = target_date
              then ct.amount
            else 0
          end
        ),
        0
      ) as today_in,
      coalesce(
        sum(
          case
            when ct.direction = 'out'
             and (ct.occurred_at at time zone 'Asia/Damascus')::date = target_date
              then ct.amount
            else 0
          end
        ),
        0
      ) as today_out
    from public.cash_transactions ct
    join public.cashboxes cb
      on cb.id = ct.cashbox_id
     and cb.company_id = target_company
    where ct.company_id = target_company
    group by upper(cb.currency)
  ),
  expense_totals as (
    select
      upper(cb.currency) as currency,
      coalesce(sum(e.amount),0) as month_expense
    from public.expenses e
    join public.cashboxes cb
      on cb.id = e.cashbox_id
     and cb.company_id = target_company
    where e.company_id = target_company
      and (e.occurred_at at time zone 'Asia/Damascus')::date >=
          date_trunc('month',target_date::timestamp)::date
      and (e.occurred_at at time zone 'Asia/Damascus')::date <
          (
            date_trunc('month',target_date::timestamp)
            + interval '1 month'
          )::date
    group by upper(cb.currency)
  )
  select
    cl.currency,
    coalesce(tt.balance,0)::numeric,
    coalesce(tt.today_in,0)::numeric,
    coalesce(tt.today_out,0)::numeric,
    coalesce(et.month_expense,0)::numeric
  from currency_list cl
  left join transaction_totals tt
    on tt.currency = cl.currency
  left join expense_totals et
    on et.currency = cl.currency
  order by cl.currency;
end;
$function$;

create or replace function public.handle_company_default_cashbox()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.cashboxes(company_id,name,currency)
  values(new.id,'الصندوق الرئيسي',coalesce(new.default_currency,'USD'))
  on conflict do nothing;
  return new;
end;
$function$;

create or replace function public.protect_cashbox_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.currency := upper(trim(coalesce(new.currency,'')));

  if new.currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid cashbox currency';
  end if;

  if tg_op = 'UPDATE'
     and old.active = true
     and new.active = false
     and coalesce((
       select sum(case when ct.direction = 'in' then ct.amount else -ct.amount end)
       from public.cash_transactions ct
       where ct.cashbox_id = old.id
     ), 0) <> 0
  then
    -- ما منوقّف صندوق فيه مصاري، مشان رصيده ما يختفي من الشاشات.
    raise exception 'Cashbox still has a balance';
  end if;

  if tg_op = 'UPDATE' then
    if new.company_id is distinct from old.company_id then
      raise exception 'Cashbox company cannot be changed';
    end if;

    if new.currency is distinct from old.currency
       and (
         exists (
           select 1
           from public.cash_transactions ct
           where ct.cashbox_id = old.id
         )
         or exists (
           select 1
           from public.expenses e
           where e.cashbox_id = old.id
         )
       )
    then
      raise exception 'Cashbox currency cannot change after financial activity';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.record_cash_movement(target_company uuid, target_cashbox uuid, movement_type text, movement_amount numeric, movement_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cashbox uuid;
  v_id uuid;
  v_direction text;
  v_now timestamptz := now();
begin
  if not public.has_permission(
    target_company,
    'finance.cashbox_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_cashbox is null then
    raise exception 'Cashbox required';
  end if;

  if movement_amount is null or movement_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if movement_type not in (
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out'
  ) then
    raise exception 'Invalid movement';
  end if;

  v_direction :=
    case
      when movement_type in (
        'partner_deposit',
        'adjustment_in'
      ) then 'in'
      else 'out'
    end;

  select id
  into v_cashbox
  from public.cashboxes
  where id = target_cashbox
    and company_id = target_company
    and active = true
  for update;

  if v_cashbox is null then
    raise exception 'Invalid or inactive cashbox';
  end if;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    v_direction,
    movement_type,
    round(movement_amount,2),
    nullif(trim(coalesce(movement_notes,'')),''),
    v_now
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.record_expense(target_company uuid, target_cashbox uuid, expense_category text, expense_amount numeric, expense_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cashbox uuid;
  v_expense uuid;
  v_now timestamptz := now();
begin
  if not public.has_permission(
    target_company,
    'finance.expenses_write'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_cashbox is null then
    raise exception 'Cashbox required';
  end if;

  if expense_amount is null or expense_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if nullif(trim(coalesce(expense_category,'')),'') is null then
    raise exception 'Category required';
  end if;

  select id
  into v_cashbox
  from public.cashboxes
  where id = target_cashbox
    and company_id = target_company
    and active = true
  for update;

  if v_cashbox is null then
    raise exception 'Invalid or inactive cashbox';
  end if;

  insert into public.expenses(
    company_id,
    cashbox_id,
    category,
    amount,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    trim(expense_category),
    round(expense_amount,2),
    nullif(trim(coalesce(expense_notes,'')),''),
    v_now
  )
  returning id into v_expense;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    expense_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    v_cashbox,
    'out',
    'expense',
    round(expense_amount,2),
    v_expense,
    nullif(trim(coalesce(expense_notes,'')),''),
    v_now
  );

  return v_expense;
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_cash_transactions after insert or delete or update on public.cash_transactions for each row execute function public.write_audit_log();

create trigger cash_transactions_cashbox_company_guard before insert or update of company_id, cashbox_id on public.cash_transactions for each row execute function public.enforce_cashbox_company();

create trigger cashbox_gl_account_after_insert after insert on public.cashboxes for each row execute function public.cashbox_gl_account_trigger();

create trigger protect_cashbox_identity_trigger before insert or update on public.cashboxes for each row execute function public.protect_cashbox_identity();

create trigger on_company_default_cashbox after insert on public.companies for each row execute function public.handle_company_default_cashbox();

create trigger audit_expenses after insert or delete or update on public.expenses for each row execute function public.write_audit_log();

create trigger expenses_cashbox_company_guard before insert or update of company_id, cashbox_id on public.expenses for each row execute function public.enforce_cashbox_company();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.cashboxes enable row level security;
alter table public.cashbox_gl_accounts enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_transactions enable row level security;
create policy cash_transactions_read on public.cash_transactions
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.cashbox_view'::text, 'finance.accounts_view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'payments.supplier_view'::text, 'payments.supplier_create'::text, 'reports.finance'::text]));
create policy cashbox_gl_accounts_read on public.cashbox_gl_accounts
  for select to authenticated
  using ((public.has_permission(company_id, 'finance.cashbox_view'::text) or public.has_permission(company_id, 'finance.accounts_view'::text)));
create policy cashboxes_read on public.cashboxes
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.cashbox_view'::text, 'finance.accounts_view'::text, 'payments.sales_view'::text, 'payments.sales_create'::text, 'payments.supplier_view'::text, 'payments.supplier_create'::text, 'reports.finance'::text]));
create policy cashboxes_write on public.cashboxes
  for all to authenticated
  using (public.has_permission(company_id, 'finance.cashbox_write'::text))
  with check (public.has_permission(company_id, 'finance.cashbox_write'::text));
create policy expenses_read on public.expenses
  for select to authenticated
  using (public.has_any_permission(company_id, array['finance.expenses_view'::text, 'reports.finance'::text, 'reports.profit'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.cashbox_gl_accounts from authenticated;
revoke insert, update, delete on public.expenses from authenticated;
revoke insert, update, delete on public.cash_transactions from authenticated;
revoke execute on function public.ensure_cashbox_gl_account(uuid) from authenticated;
revoke execute on function public.finance_cashbox_account(uuid,uuid) from authenticated;
