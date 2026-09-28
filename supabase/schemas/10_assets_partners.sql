-- ======================================================================
-- الأصول والشركاء
-- الأصول الثابتة والإهلاك، الشركاء وحركاتهم
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  asset_number text not null,
  name text not null,
  category text,
  description text,
  purchase_date date not null,
  in_service_date date not null,
  currency text default 'USD'::text not null,
  purchase_cost numeric(18,2) not null,
  salvage_value numeric(18,2) default 0 not null,
  useful_life_months integer not null,
  depreciation_method text default 'straight_line'::text not null,
  accumulated_depreciation numeric(18,2) default 0 not null,
  status text default 'active'::text not null,
  disposal_date date,
  disposal_amount numeric(18,2),
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint fixed_assets_company_id_asset_number_key unique (company_id, asset_number),
  constraint fixed_assets_accumulated_depreciation_check check ((accumulated_depreciation >= (0)::numeric)),
  constraint fixed_assets_check check ((salvage_value <= purchase_cost)),
  constraint fixed_assets_depreciation_method_check check ((depreciation_method = 'straight_line'::text)),
  constraint fixed_assets_purchase_cost_check check ((purchase_cost >= (0)::numeric)),
  constraint fixed_assets_salvage_value_check check ((salvage_value >= (0)::numeric)),
  constraint fixed_assets_status_check check ((status = any (array['active'::text, 'fully_depreciated'::text, 'disposed'::text]))),
  constraint fixed_assets_useful_life_months_check check ((useful_life_months > 0))
);
create index fixed_assets_company_status_idx on public.fixed_assets using btree (company_id, status, in_service_date);

create table public.asset_depreciation_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  asset_id uuid not null references public.fixed_assets(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  amount numeric(18,2) not null,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  posted_at timestamp with time zone default now() not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  constraint asset_depreciation_entries_asset_id_period_start_period_end_key unique (asset_id, period_start, period_end),
  constraint asset_depreciation_entries_amount_check check ((amount > (0)::numeric))
);
create index asset_depreciation_entries_asset_idx on public.asset_depreciation_entries using btree (asset_id, period_end desc);

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_number text,
  name text not null,
  phone text,
  ownership_percent numeric(9,4) default 0 not null,
  profit_share_percent numeric(9,4) default 0 not null,
  active boolean default true not null,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint partners_ownership_percent_check check (((ownership_percent >= (0)::numeric) and (ownership_percent <= (100)::numeric))),
  constraint partners_profit_share_percent_check check (((profit_share_percent >= (0)::numeric) and (profit_share_percent <= (100)::numeric)))
);
create index partners_company_idx on public.partners using btree (company_id, active, name);
create unique index partners_number_unique on public.partners using btree (company_id, partner_number) where (partner_number is not null);

create table public.partner_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete restrict,
  transaction_type text not null,
  amount numeric(18,2) not null,
  currency text not null,
  cashbox_id uuid references public.cashboxes(id) on delete restrict,
  transaction_date date default ((now() at time zone 'Asia/Damascus'::text))::date not null,
  notes text,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  constraint partner_transactions_amount_check check ((amount > (0)::numeric)),
  constraint partner_transactions_transaction_type_check check ((transaction_type = any (array['capital_contribution'::text, 'drawing'::text, 'partner_loan_in'::text, 'partner_loan_repayment'::text, 'profit_distribution'::text])))
);
create index partner_transactions_partner_idx on public.partner_transactions using btree (company_id, partner_id, transaction_date desc);


-- ----------------------------------------------------------------------
-- ربط جداول من أقسام سابقة بجداول هالقسم
-- ----------------------------------------------------------------------

alter table public.cash_transactions
  add constraint cash_transactions_partner_transaction_id_fkey foreign key (partner_transaction_id) references public.partner_transactions(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.create_fixed_asset(target_company uuid, target_name text, target_category text, target_description text, target_purchase_date date, target_in_service_date date, target_currency text, target_purchase_cost numeric, target_salvage_value numeric, target_useful_life_months integer, target_notes text, target_cashbox uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_number text;
  v_date date;
  v_currency text;
  v_cost numeric(18,2);
  v_credit uuid;
begin
  if not public.has_permission(
    target_company,
    'assets.manage'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(trim(target_name),'') is null then
    raise exception 'Asset name is required';
  end if;

  if target_purchase_cost is null
     or target_purchase_cost <= 0
  then
    raise exception 'Invalid purchase cost';
  end if;

  if coalesce(
       target_salvage_value,
       0
     ) < 0
  then
    raise exception
      'Invalid salvage value';
  end if;

  if upper(
       trim(
         coalesce(
           target_currency,
           ''
         )
       )
     ) !~ '^[A-Z]{3}$'
  then
    raise exception
      'Invalid asset currency';
  end if;

  if target_purchase_date is not null
     and target_in_service_date is not null
     and target_in_service_date <
         target_purchase_date
  then
    raise exception
      'In-service date cannot be before purchase date';
  end if;

  if target_useful_life_months is null
     or target_useful_life_months <= 0
  then
    raise exception 'Invalid useful life';
  end if;

  if coalesce(
       target_salvage_value,
       0
     ) >
     target_purchase_cost
  then
    raise exception
      'Salvage value cannot exceed cost';
  end if;

  perform
    public.assert_finance_period_open(
      target_company,
      coalesce(
        target_purchase_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  v_number :=
    public.next_asset_number(
      target_company,
      coalesce(
        target_purchase_date,
        (now() at time zone 'Asia/Damascus')::date
      )
    );

  insert into public.fixed_assets(
    company_id,
    asset_number,
    name,
    category,
    description,
    purchase_date,
    in_service_date,
    currency,
    purchase_cost,
    salvage_value,
    useful_life_months,
    notes
  )
  values(
    target_company,
    v_number,
    trim(target_name),
    nullif(trim(target_category),''),
    nullif(trim(target_description),''),
    coalesce(
      target_purchase_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    coalesce(
      target_in_service_date,
      target_purchase_date,
      (now() at time zone 'Asia/Damascus')::date
    ),
    upper(
      coalesce(
        nullif(
          trim(target_currency),
          ''
        ),
        'USD'
      )
    ),
    round(target_purchase_cost,2),
    round(
      coalesce(
        target_salvage_value,
        0
      ),
      2
    ),
    target_useful_life_months,
    nullif(trim(target_notes),'')
  )
  returning id
  into v_id;

  -- قيد الشراء: الأصل بيدخل الحسابات، ومقابله يا صندوق (دفعنا هلق)
  -- يا أرصدة افتتاحية (أصل كان عنا قبل ما نبلّش بالنظام).
  select purchase_date, currency, purchase_cost
  into v_date, v_currency, v_cost
  from public.fixed_assets
  where id = v_id;

  if target_cashbox is not null then
    if not exists (
      select 1
      from public.cashboxes cb
      where cb.id = target_cashbox
        and cb.company_id = target_company
        and cb.active = true
        and upper(cb.currency) = v_currency
    ) then
      raise exception 'Cashbox must be active and in the asset currency';
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
      target_cashbox,
      'out',
      'asset_purchase',
      v_cost,
      'شراء أصل ' || v_number || ' - ' || trim(target_name),
      (v_date::timestamp + time '12:00') at time zone 'Asia/Damascus'
    );

    v_credit := public.finance_cashbox_account(target_company, target_cashbox);
  else
    v_credit := public.finance_system_account(target_company, 'opening_balance_equity');
  end if;

  if v_cost > 0 then
    perform public.post_system_journal(
      target_company,
      v_date,
      'شراء أصل ثابت ' || v_number,
      v_currency,
      null,
      'fixed_asset',
      v_id,
      jsonb_build_array(
        jsonb_build_object(
          'account_id', public.finance_system_account(target_company, 'fixed_assets'),
          'debit', v_cost,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_credit,
          'debit', 0,
          'credit', v_cost
        )
      )
    );
  end if;

  return v_id;
end;
$function$;

-- بيع أصل (بمبلغ لصندوق) أو شطبو (مبلغ صفر، مثلًا انسرق أو خرب).
-- القيد: من مجمع الإهلاك + الصندوق، إلى الأصول الثابتة (بالكلفة)، والفرق ربح أو خسارة.
create or replace function public.dispose_fixed_asset(target_company uuid, target_asset uuid, target_date date, target_amount numeric, target_cashbox uuid, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_asset public.fixed_assets%rowtype;
  v_date date := coalesce(target_date, (now() at time zone 'Asia/Damascus')::date);
  v_amount numeric(18,2) := round(coalesce(target_amount, 0), 2);
  v_book numeric(18,2);
  v_diff numeric(18,2);
  v_lines jsonb;
begin
  if not public.has_permission(target_company, 'assets.manage') then
    raise exception 'Not allowed';
  end if;

  select * into v_asset
  from public.fixed_assets
  where id = target_asset and company_id = target_company
  for update;

  if v_asset.id is null then
    raise exception 'Asset not found';
  end if;

  if v_asset.status = 'disposed' then
    raise exception 'Asset already disposed';
  end if;

  if v_amount < 0 then
    raise exception 'Invalid amount';
  end if;

  if v_date < v_asset.purchase_date then
    raise exception 'Disposal date cannot be before purchase date';
  end if;

  if v_amount > 0 and not exists (
    select 1 from public.cashboxes
    where id = target_cashbox and company_id = target_company and active
      and upper(currency) = upper(v_asset.currency)
  ) then
    raise exception 'Cashbox must be active and in the asset currency';
  end if;

  perform public.assert_finance_period_open(target_company, v_date);

  v_book := round(v_asset.purchase_cost - v_asset.accumulated_depreciation, 2);
  v_diff := v_amount - v_book;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.finance_system_account(target_company, 'fixed_assets'),
      'debit', 0,
      'credit', v_asset.purchase_cost
    )
  );

  if v_asset.accumulated_depreciation > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.finance_system_account(target_company, 'accumulated_depreciation'),
      'debit', v_asset.accumulated_depreciation,
      'credit', 0
    ));
  end if;

  if v_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.finance_cashbox_account(target_company, target_cashbox),
      'debit', v_amount,
      'credit', 0
    ));

    insert into public.cash_transactions(company_id, cashbox_id, direction, type, amount, notes, occurred_at)
    values (
      target_company, target_cashbox, 'in', 'asset_sale', v_amount,
      'بيع أصل ' || v_asset.asset_number || ' - ' || v_asset.name,
      (v_date::timestamp + time '12:00') at time zone 'Asia/Damascus'
    );
  end if;

  if v_diff > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.finance_system_account(target_company, 'asset_disposal_gain'),
      'debit', 0,
      'credit', v_diff
    ));
  elsif v_diff < 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.finance_system_account(target_company, 'asset_disposal_loss'),
      'debit', -v_diff,
      'credit', 0
    ));
  end if;

  perform public.post_system_journal(
    target_company,
    v_date,
    case when v_amount > 0 then 'بيع أصل ' else 'شطب أصل ' end || v_asset.asset_number || ' - ' || v_asset.name,
    v_asset.currency,
    null,
    'asset_disposal',
    v_asset.id,
    v_lines
  );

  update public.fixed_assets
  set status = 'disposed',
      disposal_date = v_date,
      disposal_amount = v_amount,
      notes = coalesce(nullif(trim(target_notes), ''), notes)
  where id = v_asset.id;
end;
$function$;

create or replace function public.next_asset_number(target_company uuid, target_date date)
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
    'fixed_asset',
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
  where company_id = target_company
    and document_type = 'fixed_asset'
    and sequence_year = v_year
  for update;

  update public.document_sequences
  set next_value = next_value + 1
  where company_id = target_company
    and document_type = 'fixed_asset'
    and sequence_year = v_year;

  return
    'AST-' ||
    v_year::text ||
    '-' ||
    lpad(
      v_value::text,
      5,
      '0'
    );
end;
$function$;

create or replace function public.post_asset_depreciation_month(target_company uuid, target_year integer, target_month integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date;
  v_end date;

  v_asset record;

  v_depreciable numeric(18,2);
  v_monthly numeric(18,2);
  v_remaining numeric(18,2);
  v_amount numeric(18,2);

  v_expense uuid;
  v_accum uuid;

  v_entry uuid;
  v_count integer := 0;
begin
  if not public.has_permission(
    target_company,
    'assets.depreciate'
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

  perform
    public.assert_finance_period_open(
      target_company,
      v_end
    );

  v_expense :=
    public.finance_system_account(
      target_company,
      'depreciation_expense'
    );

  v_accum :=
    public.finance_system_account(
      target_company,
      'accumulated_depreciation'
    );

  for v_asset in
    select *
    from public.fixed_assets
    where company_id =
          target_company
      and status =
          'active'
      and in_service_date <=
          v_end
    order by in_service_date,
             created_at
    for update
  loop
    if exists(
      select 1
      from public.asset_depreciation_entries
      where asset_id =
            v_asset.id
        and period_start =
            v_start
        and period_end =
            v_end
    ) then
      continue;
    end if;

    v_depreciable :=
      round(
        v_asset.purchase_cost -
        v_asset.salvage_value,
        2
      );

    v_remaining :=
      greatest(
        v_depreciable -
        v_asset.accumulated_depreciation,
        0
      );

    if v_remaining <= 0 then
      update public.fixed_assets
      set status =
          'fully_depreciated'
      where id =
            v_asset.id;

      continue;
    end if;

    v_monthly :=
      round(
        v_depreciable /
        v_asset.useful_life_months,
        2
      );

    v_amount :=
      least(
        v_monthly,
        v_remaining
      );

    if v_amount <= 0 then
      continue;
    end if;

    v_entry :=
      public.post_system_journal(
        target_company,
        v_end,
        'إهلاك أصل ' ||
        v_asset.asset_number ||
        ' - ' ||
        v_asset.name,
        v_asset.currency,
        null,
        'asset_depreciation',
        gen_random_uuid(),
        jsonb_build_array(
          jsonb_build_object(
            'account_id',
            v_expense,
            'debit',
            v_amount,
            'credit',
            0,
            'memo',
            v_asset.name
          ),
          jsonb_build_object(
            'account_id',
            v_accum,
            'debit',
            0,
            'credit',
            v_amount,
            'memo',
            v_asset.name
          )
        )
      );

    insert into public.asset_depreciation_entries(
      company_id,
      asset_id,
      period_start,
      period_end,
      amount,
      journal_entry_id
    )
    values(
      target_company,
      v_asset.id,
      v_start,
      v_end,
      v_amount,
      v_entry
    );

    update public.fixed_assets
    set
      accumulated_depreciation =
        round(
          accumulated_depreciation +
          v_amount,
          2
        ),

      status =
        case
          when round(
                 accumulated_depreciation +
                 v_amount,
                 2
               ) >=
               v_depreciable
            then 'fully_depreciated'
          else status
        end

    where id =
          v_asset.id;

    v_count :=
      v_count + 1;
  end loop;

  return v_count;
end;
$function$;

create or replace function public.record_partner_transaction(target_company uuid, target_partner uuid, target_type text, target_amount numeric, target_currency text, target_cashbox uuid, target_date date, target_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.save_partner(target_company uuid, target_partner uuid, target_number text, target_name text, target_phone text, target_ownership_percent numeric, target_profit_share_percent numeric, target_notes text, target_active boolean)
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
    'partners.manage'
  ) then
    raise exception 'Not allowed';
  end if;

  if nullif(
       trim(target_name),
       ''
     ) is null
  then
    raise exception
      'Partner name is required';
  end if;

  if coalesce(
       target_ownership_percent,
       0
     ) < 0
     or coalesce(
       target_ownership_percent,
       0
     ) > 100
  then
    raise exception
      'Invalid ownership percent';
  end if;

  if coalesce(
       target_profit_share_percent,
       0
     ) < 0
     or coalesce(
       target_profit_share_percent,
       0
     ) > 100
  then
    raise exception
      'Invalid profit share percent';
  end if;

  if target_partner is null then

    insert into public.partners(
      company_id,
      partner_number,
      name,
      phone,
      ownership_percent,
      profit_share_percent,
      notes,
      active
    )
    values(
      target_company,
      nullif(
        trim(target_number),
        ''
      ),
      trim(target_name),
      nullif(
        trim(target_phone),
        ''
      ),
      coalesce(
        target_ownership_percent,
        0
      ),
      coalesce(
        target_profit_share_percent,
        0
      ),
      nullif(
        trim(target_notes),
        ''
      ),
      coalesce(
        target_active,
        true
      )
    )
    returning id
    into v_id;

  else

    update public.partners
    set
      partner_number =
        nullif(
          trim(target_number),
          ''
        ),
      name =
        trim(target_name),
      phone =
        nullif(
          trim(target_phone),
          ''
        ),
      ownership_percent =
        coalesce(
          target_ownership_percent,
          0
        ),
      profit_share_percent =
        coalesce(
          target_profit_share_percent,
          0
        ),
      notes =
        nullif(
          trim(target_notes),
          ''
        ),
      active =
        coalesce(
          target_active,
          true
        )
    where id =
          target_partner
      and company_id =
          target_company
    returning id
    into v_id;

    if v_id is null then
      raise exception
        'Partner not found';
    end if;

  end if;

  return v_id;
end;
$function$;


-- ----------------------------------------------------------------------
-- العروض (Views)
-- ----------------------------------------------------------------------

create view public.fixed_asset_summary with (security_invoker=true) as
 select id,
    company_id,
    asset_number,
    name,
    category,
    description,
    purchase_date,
    in_service_date,
    currency,
    purchase_cost,
    salvage_value,
    useful_life_months,
    depreciation_method,
    accumulated_depreciation,
    status,
    disposal_date,
    disposal_amount,
    notes,
    created_by,
    created_at,
    updated_at,
    round(greatest(purchase_cost - accumulated_depreciation, salvage_value), 2) as book_value,
    round((purchase_cost - salvage_value) / useful_life_months::numeric, 2) as monthly_depreciation
   from public.fixed_assets a;

create view public.partner_summary with (security_invoker=true) as
 select p.id,
    p.company_id,
    p.partner_number,
    p.name,
    p.phone,
    p.ownership_percent,
    p.profit_share_percent,
    p.active,
    p.notes,
    p.created_by,
    p.created_at,
    p.updated_at,
    coalesce(sum(
        case
            when pt.transaction_type = 'capital_contribution'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as capital_contributions,
    coalesce(sum(
        case
            when pt.transaction_type = 'drawing'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as drawings,
    coalesce(sum(
        case
            when pt.transaction_type = 'partner_loan_in'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            when pt.transaction_type = 'partner_loan_repayment'::text then - (pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date))
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as partner_loan_balance,
    coalesce(sum(
        case
            when pt.transaction_type = 'profit_distribution'::text then pt.amount * public.finance_rate_to_base(p.company_id, pt.currency, pt.transaction_date)
            else 0::numeric
        end), 0::numeric)::numeric(18,2) as profit_distributions
   from public.partners p
     left join public.partner_transactions pt on pt.partner_id = p.id
  group by p.id;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger audit_asset_depreciation_entries after insert or delete or update on public.asset_depreciation_entries for each row execute function public.write_audit_log();

create trigger audit_fixed_assets after insert or delete or update on public.fixed_assets for each row execute function public.write_audit_log();

create trigger fixed_assets_updated_at before update on public.fixed_assets for each row execute function public.set_updated_at();

create trigger audit_partner_transactions after insert or delete or update on public.partner_transactions for each row execute function public.write_audit_log();

create trigger audit_partners after insert or delete or update on public.partners for each row execute function public.write_audit_log();

create trigger partners_updated_at before update on public.partners for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.fixed_assets enable row level security;
alter table public.asset_depreciation_entries enable row level security;
alter table public.partners enable row level security;
alter table public.partner_transactions enable row level security;
create policy asset_depreciation_entries_read on public.asset_depreciation_entries
  for select to authenticated
  using (public.has_permission(company_id, 'assets.view'::text));
create policy fixed_assets_read on public.fixed_assets
  for select to authenticated
  using (public.has_permission(company_id, 'assets.view'::text));
create policy partner_transactions_read on public.partner_transactions
  for select to authenticated
  using (public.has_permission(company_id, 'partners.view'::text));
create policy partners_read on public.partners
  for select to authenticated
  using (public.has_permission(company_id, 'partners.view'::text));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke insert, update, delete on public.fixed_assets from authenticated;
revoke insert, update, delete on public.asset_depreciation_entries from authenticated;
revoke insert, update, delete on public.partners from authenticated;
revoke insert, update, delete on public.partner_transactions from authenticated;
revoke execute on function public.next_asset_number(uuid,date) from authenticated;
