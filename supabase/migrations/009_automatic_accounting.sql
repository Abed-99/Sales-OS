create or replace function
public.finance_rate_to_base(
  target_company uuid,
  target_currency text,
  target_date date
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_currency text;
  v_rate numeric(24,10);
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
$$;

revoke all
on function public.finance_rate_to_base(
  uuid,
  text,
  date
)
from public, authenticated;


create or replace function
public.save_finance_exchange_rate(
  target_company uuid,
  target_currency text,
  target_date date,
  target_rate numeric,
  target_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.save_finance_exchange_rate(
  uuid,
  text,
  date,
  numeric,
  text
)
from public;

grant execute
on function public.save_finance_exchange_rate(
  uuid,
  text,
  date,
  numeric,
  text
)
to authenticated;


-- ============================================================
-- ACCOUNT HELPERS
-- ============================================================

create or replace function public.finance_system_account(
  target_company uuid,
  target_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.finance_system_account(
  uuid,
  text
)
from public, authenticated;


create or replace function public.finance_cashbox_account(
  target_company uuid,
  target_cashbox uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.finance_cashbox_account(
  uuid,
  uuid
)
from public, authenticated;


-- ============================================================
-- SYSTEM JOURNAL IDEMPOTENCY
-- ============================================================

create unique index if not exists
journal_entries_source_unique
on public.journal_entries(
  company_id,
  source_type,
  source_id
)
where source_id is not null
  and reversed_from_id is null;


create unique index if not exists
journal_entries_reversal_unique
on public.journal_entries(
  reversed_from_id
)
where reversed_from_id is not null;


-- ============================================================
-- GENERIC AUTOMATIC JOURNAL ENGINE
-- ============================================================

create or replace function public.post_system_journal(
  target_company uuid,
  target_date date,
  target_description text,
  target_currency text,
  target_rate numeric,
  target_source_type text,
  target_source_id uuid,
  lines_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing uuid;
  v_entry uuid;
  v_number text;
  v_currency text;
  v_base_currency text;
  v_rate numeric(24,10);
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
$$;

revoke all
on function public.post_system_journal(
  uuid,
  date,
  text,
  text,
  numeric,
  text,
  uuid,
  jsonb
)
from public, authenticated;


-- ============================================================
-- REVERSAL ENGINE
-- ============================================================

create or replace function public.reverse_system_journal(
  target_company uuid,
  target_source_type text,
  target_source_id uuid,
  target_date date,
  target_description text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.reverse_system_journal(
  uuid,
  text,
  uuid,
  date,
  text
)
from public, authenticated;


-- ============================================================
-- MANUAL JOURNAL REVERSAL
-- Never delete or rewrite posted accounting history.
-- ============================================================

create or replace function public.reverse_manual_journal_entry(
  target_company uuid,
  target_entry uuid,
  target_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;


revoke all
on function public.reverse_manual_journal_entry(
  uuid,
  uuid,
  text
)
from public;


grant execute
on function public.reverse_manual_journal_entry(
  uuid,
  uuid,
  text
)
to authenticated;

-- ============================================================
-- FIX TRIAL BALANCE
-- Reversed originals + reversal entries both remain history
-- and therefore both participate, netting to zero.
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
-- SALES INVOICE -> AR / SALES
-- ============================================================

create or replace function public.gl_sales_invoice_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ar uuid;
  v_sales uuid;
  v_discount uuid;
  v_lines jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'sales_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة بيع ' ||
        new.invoice_number
      );

    return new;
  end if;

  if new.status <> 'posted' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = new.status
  then
    return new;
  end if;

  if new.total <= 0
     and new.subtotal <= 0
  then
    return new;
  end if;

  v_ar :=
    public.finance_system_account(
      new.company_id,
      'accounts_receivable'
    );

  v_sales :=
    public.finance_system_account(
      new.company_id,
      'sales_revenue'
    );

  v_discount :=
    public.finance_system_account(
      new.company_id,
      'sales_discounts'
    );

  if new.total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          new.total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'ذمة فاتورة بيع'
        )
      );
  end if;

  if new.discount_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_discount,
          'debit',
          new.discount_total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'خصم مبيعات'
        )
      );
  end if;

  if new.subtotal > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_sales,
          'debit',
          0,
          'credit',
          new.subtotal,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'إيراد مبيعات'
        )
      );
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      new.invoice_date,
      'فاتورة بيع ' ||
      new.invoice_number,
      new.currency,
      null,
      'sales_invoice',
      new.id,
      v_lines
    );

  return new;
end;
$$;

drop trigger if exists
gl_sales_invoice
on public.sales_invoices;

create trigger gl_sales_invoice
after insert or update of status
on public.sales_invoices
for each row
execute function
public.gl_sales_invoice_trigger();


-- ============================================================
-- PURCHASE INVOICE -> INVENTORY CLEARING / AP
-- The journal is recalculated while invoice items are inserted.
-- ============================================================

create or replace function public.sync_purchase_invoice_journal(
  target_invoice uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_supplier uuid;
  v_number text;
  v_currency text;
  v_date date;
  v_status text;

  v_cost numeric(18,2);
  v_total numeric(18,2);
  v_variance numeric(18,2);

  v_clearing uuid;
  v_ap uuid;
  v_variance_account uuid;

  v_lines jsonb := '[]'::jsonb;
begin
  select
    company_id,
    supplier_id,
    invoice_number,
    currency,
    invoice_date,
    status
  into
    v_company,
    v_supplier,
    v_number,
    v_currency,
    v_date,
    v_status
  from public.purchase_invoices
  where id = target_invoice;

  if v_company is null
     or v_status <> 'posted'
  then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          quantity *
          unit_cost
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(line_total),
        0
      ),
      2
    )
  into
    v_cost,
    v_total
  from public.purchase_invoice_items
  where invoice_id =
        target_invoice;

  if v_total <= 0
     and v_cost <= 0
  then
    return;
  end if;

  delete from public.journal_entries
  where company_id =
        v_company
    and source_type =
        'purchase_invoice'
    and source_id =
        target_invoice
    and reversed_from_id
        is null
    and status =
        'posted';

  v_clearing :=
    public.finance_system_account(
      v_company,
      'inventory_clearing'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  v_variance_account :=
    public.finance_system_account(
      v_company,
      'purchase_variance'
    );

  if v_cost > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_cost,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'قيمة بضاعة مشتراة'
        )
      );
  end if;

  v_variance :=
    round(
      v_total -
      v_cost,
      2
    );

  if v_variance > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          v_variance,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'فروقات وتكاليف شراء'
        )
      );

  elsif v_variance < 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          0,
          'credit',
          abs(v_variance),
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'خصم شراء'
        )
      );
  end if;

  if v_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          0,
          'credit',
          v_total,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'ذمة مورد'
        )
      );
  end if;

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'فاتورة شراء ' ||
      v_number,
      v_currency,
      null,
      'purchase_invoice',
      target_invoice,
      v_lines
    );
end;
$$;

revoke all
on function public.sync_purchase_invoice_journal(uuid)
from public, authenticated;


create or replace function public.gl_purchase_item_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform
    public.sync_purchase_invoice_journal(
      case
        when tg_op = 'DELETE'
          then old.invoice_id
        else new.invoice_id
      end
    );

  return coalesce(new,old);
end;
$$;

drop trigger if exists
gl_purchase_invoice_item
on public.purchase_invoice_items;

create trigger gl_purchase_invoice_item
after insert or update or delete
on public.purchase_invoice_items
for each row
execute function
public.gl_purchase_item_trigger();


create or replace function public.gl_purchase_invoice_status_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'purchase_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة شراء ' ||
        new.invoice_number
      );

  elsif old.status <> 'posted'
        and new.status = 'posted'
  then
    perform
      public.sync_purchase_invoice_journal(
        new.id
      );
  end if;

  return new;
end;
$$;

drop trigger if exists
gl_purchase_invoice_status
on public.purchase_invoices;

create trigger gl_purchase_invoice_status
after update of status
on public.purchase_invoices
for each row
execute function
public.gl_purchase_invoice_status_trigger();


-- ============================================================
-- CUSTOMER PAYMENT
-- Cash first becomes customer advance.
-- Allocations move it from advance -> AR.
-- ============================================================

create or replace function public.gl_customer_payment_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'customer_payment',
        new.id,
        new.payment_date,
        'عكس قبض عميل ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.customer_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'customer_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص قبض عميل'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'customer_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'قبض من عميل ' ||
      new.payment_number,
      v_currency,
      null,
      'customer_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        )
      )
    );

  return new;
end;
$$;


drop trigger if exists
gl_customer_payment
on public.customer_payments;

create trigger gl_customer_payment
after insert or update of status
on public.customer_payments
for each row
execute function
public.gl_customer_payment_trigger();


create or replace function public.gl_customer_allocation_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_trader uuid;
  v_payment_date date;
  v_cashbox uuid;
  v_currency text;
  v_payment_status text;

  v_advance uuid;
  v_ar uuid;
begin
  select
    company_id,
    trader_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_trader,
    v_payment_date,
    v_cashbox,
    v_payment_status
  from public.customer_payments
  where id =
        new.payment_id;

  if v_payment_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'customer_advances'
    );

  v_ar :=
    public.finance_system_account(
      v_company,
      'accounts_receivable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_payment_date,
      'تخصيص قبض على فاتورة بيع',
      v_currency,
      null,
      'customer_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          v_trader
        ),
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'trader',
          'party_id',
          v_trader
        )
      )
    );

  return new;
end;
$$;


drop trigger if exists
gl_customer_payment_allocation
on public.customer_payment_allocations;

create trigger gl_customer_payment_allocation
after insert
on public.customer_payment_allocations
for each row
execute function
public.gl_customer_allocation_trigger();


-- ============================================================
-- SUPPLIER PAYMENT
-- Cash payment first becomes supplier advance.
-- Allocation moves AP -> supplier advance.
-- ============================================================

create or replace function public.gl_supplier_payment_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'supplier_payment',
        new.id,
        new.payment_date,
        'عكس دفعة مورد ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.supplier_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'supplier_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص دفعة مورد'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'supplier_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'دفعة إلى مورد ' ||
      new.payment_number,
      v_currency,
      null,
      'supplier_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        )
      )
    );

  return new;
end;
$$;


drop trigger if exists
gl_supplier_payment
on public.supplier_payments;

create trigger gl_supplier_payment
after insert or update of status
on public.supplier_payments
for each row
execute function
public.gl_supplier_payment_trigger();


create or replace function public.gl_supplier_allocation_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_supplier uuid;
  v_date date;
  v_cashbox uuid;
  v_currency text;
  v_status text;

  v_advance uuid;
  v_ap uuid;
begin
  select
    company_id,
    supplier_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_supplier,
    v_date,
    v_cashbox,
    v_status
  from public.supplier_payments
  where id =
        new.payment_id;

  if v_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'supplier_advances'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'تخصيص دفعة على فاتورة شراء',
      v_currency,
      null,
      'supplier_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        )
      )
    );

  return new;
end;
$$;


drop trigger if exists
gl_supplier_payment_allocation
on public.supplier_payment_allocations;

create trigger gl_supplier_payment_allocation
after insert
on public.supplier_payment_allocations
for each row
execute function
public.gl_supplier_allocation_trigger();


-- ============================================================
-- EXPENSE -> EXPENSE / CASH
-- ============================================================

create or replace function public.gl_expense_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
  v_cash uuid;
  v_expense uuid;
begin
  if new.cashbox_id is null then
    raise exception
      'Expense requires cashbox for automatic accounting';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_expense :=
    public.finance_system_account(
      new.company_id,
      'operating_expense'
    );

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'مصروف - ' ||
      new.category,
      v_currency,
      null,
      'expense',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_expense,
          'debit',
          new.amount,
          'credit',
          0,
          'memo',
          new.category
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'memo',
          new.category
        )
      )
    );

  return new;
end;
$$;


drop trigger if exists
gl_expense
on public.expenses;

create trigger gl_expense
after insert
on public.expenses
for each row
execute function
public.gl_expense_trigger();


-- ============================================================
-- INVENTORY MOVEMENTS
-- Purchase receipt: Inventory / Clearing
-- Sale: COGS / Inventory
-- Adjustment: Inventory variance
-- ============================================================

create or replace function public.gl_inventory_movement_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(18,2);

  v_inventory uuid;
  v_clearing uuid;
  v_cogs uuid;
  v_adjustment uuid;
  v_opening uuid;

  v_lines jsonb;
  v_currency text;
begin
  if new.movement_type in (
    'transfer_in',
    'transfer_out'
  ) then
    return new;
  end if;

  v_amount :=
    round(
      abs(new.quantity) *
      coalesce(
        new.unit_cost,
        0
      ),
      2
    );

  if v_amount <= 0 then
    return new;
  end if;

  select default_currency
  into v_currency
  from public.companies
  where id =
        new.company_id;

  v_inventory :=
    public.finance_system_account(
      new.company_id,
      'inventory'
    );

  if new.movement_type =
     'purchase_receipt'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_delivery'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_return'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'purchase_return'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_in'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_out'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'opening'
  then
    v_opening :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_opening,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  else
    return new;
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      new.occurred_at::date,
      'حركة مخزون - ' ||
      new.movement_type,
      v_currency,
      1,
      'inventory_movement',
      new.id,
      v_lines
    );

  return new;
end;
$$;


drop trigger if exists
gl_inventory_movement
on public.inventory_movements;

create trigger gl_inventory_movement
after insert
on public.inventory_movements
for each row
execute function
public.gl_inventory_movement_trigger();


-- ============================================================
-- CASH MOVEMENTS NOT ALREADY ACCOUNTED BY OTHER DOCUMENTS
-- ============================================================

create or replace function public.gl_cash_movement_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash uuid;
  v_other uuid;
  v_currency text;
  v_lines jsonb;
begin
  if new.type not in (
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out'
  ) then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  if new.type =
     'partner_deposit'
  then
    v_other :=
      public.finance_system_account(
        new.company_id,
        'capital'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          new.amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_other,
          'debit',
          0,
          'credit',
          new.amount
        )
      );

  elsif new.type =
        'partner_withdrawal'
  then
    v_other :=
      public.finance_system_account(
        new.company_id,
        'partner_drawings'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_other,
          'debit',
          new.amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount
        )
      );

  elsif new.type =
        'adjustment_in'
  then
    v_other :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          new.amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_other,
          'debit',
          0,
          'credit',
          new.amount
        )
      );

  else
    v_other :=
      public.finance_system_account(
        new.company_id,
        'operating_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_other,
          'debit',
          new.amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount
        )
      );
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'حركة صندوق - ' ||
      new.type,
      v_currency,
      null,
      'cash_transaction',
      new.id,
      v_lines
    );

  return new;
end;
$$;


drop trigger if exists
gl_cash_movement
on public.cash_transactions;

create trigger gl_cash_movement
after insert
on public.cash_transactions
for each row
execute function
public.gl_cash_movement_trigger();


-- ============================================================
-- CASH TRANSACTION SUPPORT FOR PAYROLL
-- ============================================================

alter table public.cash_transactions
add column if not exists employee_id uuid
references public.employees(id)
on delete set null;

alter table public.cash_transactions
add column if not exists payroll_payment_id uuid
references public.payroll_payments(id)
on delete set null;


do $$
declare
  r record;
begin
  for r in
    select
      c.conname
    from pg_constraint c
    where c.conrelid =
          'public.cash_transactions'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid)
          ilike '%type%'
  loop
    execute format(
      'alter table public.cash_transactions drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;


alter table public.cash_transactions
add constraint cash_transactions_type_check
check (
  type in (
    'sale_receipt',
    'supplier_payment',
    'expense',
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out',
    'customer_payment_reversal',
    'supplier_payment_reversal',
    'payroll_payment',
    'employee_advance',
    'employee_loan',
    'partner_distribution'
  )
);


create unique index if not exists
cash_transactions_payroll_payment_unique
on public.cash_transactions(
  payroll_payment_id,
  type
)
where payroll_payment_id is not null
  and type =
      'payroll_payment';


-- ============================================================
-- POST PAYROLL RUN
-- ============================================================

create or replace function public.post_payroll_run(
  target_company uuid,
  target_run uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.post_payroll_run(
  uuid,
  uuid
)
from public;

grant execute
on function public.post_payroll_run(
  uuid,
  uuid
)
to authenticated;


-- ============================================================
-- PAY ONE EMPLOYEE SALARY
-- ============================================================

create or replace function public.record_payroll_payment(
  target_company uuid,
  target_payroll_item uuid,
  target_cashbox uuid,
  target_amount numeric,
  target_payment_date date,
  target_method text,
  target_reference text,
  target_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.record_payroll_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text
)
from public;

grant execute
on function public.record_payroll_payment(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text
)
to authenticated;


-- ============================================================
-- FIX SALES INVOICE CANCELLATION PAYMENT STATUS
-- FOR MULTIPLE INVOICES PER ORDER
-- ============================================================

create or replace function public.cancel_sales_invoice(
  target_company uuid,
  target_invoice uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_order uuid;
begin
  if not public.has_permission(
    target_company,
    'sales_invoices.cancel'
  ) then
    raise exception 'Not allowed';
  end if;

  select
    status,
    order_id
  into
    v_status,
    v_order
  from public.sales_invoices
  where id = target_invoice
    and company_id =
        target_company
  for update;

  if v_status is null then
    raise exception
      'Sales invoice not found';
  end if;

  if v_status =
     'cancelled'
  then
    return;
  end if;

  if exists(
    select 1
    from public.customer_payment_allocations a

    join public.customer_payments p
      on p.id =
         a.payment_id

    where a.sales_invoice_id =
          target_invoice

      and p.status =
          'posted'

      and a.amount > 0
  ) then
    raise exception
      'Reverse allocated customer payments before cancelling invoice';
  end if;

  update public.sales_invoices
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),

    cancellation_reason =
      coalesce(
        nullif(
          trim(target_reason),
          ''
        ),
        'Cancelled'
      )

  where id =
        target_invoice;

  perform
    public.recalc_sales_order_payment(
      v_order
    );
end;
$$;

revoke all
on function public.cancel_sales_invoice(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.cancel_sales_invoice(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- EXCHANGE RATE RLS
-- ============================================================

alter table public.finance_exchange_rates
enable row level security;

drop policy if exists
finance_exchange_rates_read
on public.finance_exchange_rates;

create policy finance_exchange_rates_read
on public.finance_exchange_rates
for select
to authenticated
using(
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

revoke insert, update, delete
on public.finance_exchange_rates
from authenticated;

grant select
on public.finance_exchange_rates
to authenticated;


-- ============================================================
-- AUDIT EXCHANGE RATES
-- ============================================================

drop trigger if exists
audit_finance_exchange_rates
on public.finance_exchange_rates;

create trigger audit_finance_exchange_rates
after insert or update or delete
on public.finance_exchange_rates
for each row
execute function public.write_audit_log();

commit;
