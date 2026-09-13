begin;

-- ============================================================
-- LINK CASH MOVEMENT TO PARTNER TRANSACTION
-- Avoid duplicate automatic journal entries.
-- ============================================================

alter table public.cash_transactions
add column if not exists partner_transaction_id uuid
references public.partner_transactions(id)
on delete set null;

create unique index if not exists
cash_transactions_partner_transaction_unique
on public.cash_transactions(
  partner_transaction_id
)
where partner_transaction_id is not null;


-- ============================================================
-- GENERIC CASH GL MUST IGNORE PARTNER TRANSACTIONS
-- They already create their exact accounting journal.
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
  if new.partner_transaction_id is not null then
    return new;
  end if;

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
  where id = new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  if new.type = 'partner_deposit' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'capital'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'partner_withdrawal' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'partner_drawings'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'adjustment_in' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
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
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  end if;

  perform public.post_system_journal(
    new.company_id,
    (new.occurred_at at time zone 'Asia/Damascus')::date,
    'حركة صندوق - ' || new.type,
    v_currency,
    null,
    'cash_transaction',
    new.id,
    v_lines
  );

  return new;
end;
$$;


-- ============================================================
-- REPLACE PARTNER TRANSACTION RPC
-- ============================================================

create or replace function public.record_partner_transaction(
  target_company uuid,
  target_partner uuid,
  target_type text,
  target_amount numeric,
  target_currency text,
  target_cashbox uuid,
  target_date date,
  target_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;

  v_cash uuid;
  v_other uuid;

  v_entry uuid;
  v_lines jsonb;

  v_direction text;
  v_cash_type text;
  v_currency text;
begin
  if not public.has_permission(
    target_company,
    'partners.transactions'
  ) then
    raise exception 'Not allowed';
  end if;

  if target_type not in (
    'capital_contribution',
    'drawing',
    'partner_loan_in',
    'partner_loan_repayment',
    'profit_distribution'
  ) then
    raise exception
      'Invalid partner transaction';
  end if;

  if target_amount is null
     or target_amount <= 0
  then
    raise exception
      'Invalid amount';
  end if;

  if not exists (
    select 1
    from public.partners
    where id = target_partner
      and company_id = target_company
      and active = true
  ) then
    raise exception
      'Invalid partner';
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
    raise exception
      'Invalid partner transaction currency';
  end if;

  if target_cashbox is null then
    raise exception
      'Cashbox is required';
  end if;

  if not exists (
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true
      and upper(trim(currency)) =
          v_currency
  ) then
    raise exception
      'Invalid cashbox or currency';
  end if;

  perform public.assert_finance_period_open(
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

  if target_type = 'capital_contribution' then

    v_other :=
      public.finance_system_account(
        target_company,
        'capital'
      );

    v_direction := 'in';
    v_cash_type := 'partner_deposit';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'drawing' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_drawings'
      );

    v_direction := 'out';
    v_cash_type := 'partner_withdrawal';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'partner_loan_in' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_loans'
      );

    v_direction := 'in';
    v_cash_type := 'partner_deposit';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  elsif target_type = 'partner_loan_repayment' then

    v_other :=
      public.finance_system_account(
        target_company,
        'partner_loans'
      );

    v_direction := 'out';
    v_cash_type := 'partner_withdrawal';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  else

    v_other :=
      public.finance_system_account(
        target_company,
        'profit_distributions'
      );

    v_direction := 'out';
    v_cash_type := 'partner_distribution';

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', target_amount,
          'credit', 0,
          'party_type', 'partner',
          'party_id', target_partner
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', target_amount,
          'party_type', 'partner',
          'party_id', target_partner
        )
      );

  end if;

  insert into public.partner_transactions(
    company_id,
    partner_id,
    transaction_type,
    amount,
    currency,
    cashbox_id,
    transaction_date,
    notes
  )
  values(
    target_company,
    target_partner,
    target_type,
    round(target_amount,2),
    v_currency,
    target_cashbox,
    coalesce(
      target_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    nullif(
      trim(target_notes),
      ''
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
      'حركة شريك',
      v_currency,
      null,
      'partner_transaction',
      v_id,
      v_lines
    );

  update public.partner_transactions
  set journal_entry_id =
      v_entry
  where id = v_id;

  insert into public.cash_transactions(
    company_id,
    cashbox_id,
    direction,
    type,
    amount,
    partner_transaction_id,
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    v_direction,
    v_cash_type,
    round(target_amount,2),
    v_id,
    coalesce(
      nullif(
        trim(target_notes),
        ''
      ),
      'حركة شريك'
    ),
    (
      coalesce(
        target_date,
        (
          now()
          at time zone 'Asia/Damascus'
        )::date
      )::timestamp
      at time zone 'Asia/Damascus'
    )
  );

  return v_id;
end;
$$;

revoke all
on function public.record_partner_transaction(
  uuid,
  uuid,
  text,
  numeric,
  text,
  uuid,
  date,
  text
)
from public;

grant execute
on function public.record_partner_transaction(
  uuid,
  uuid,
  text,
  numeric,
  text,
  uuid,
  date,
  text
)
to authenticated;

commit;