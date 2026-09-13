begin;

-- ============================================================
-- PERMISSIONS
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
  'assets.view',
  'assets',
  'view',
  'عرض الأصول',
  220
),
(
  'assets.manage',
  'assets',
  'manage',
  'إدارة الأصول',
  221
),
(
  'assets.depreciate',
  'assets',
  'depreciate',
  'ترحيل الإهلاك',
  222
),
(
  'partners.view',
  'partners',
  'view',
  'عرض الشركاء',
  230
),
(
  'partners.manage',
  'partners',
  'manage',
  'إدارة الشركاء',
  231
),
(
  'partners.transactions',
  'partners',
  'transactions',
  'حركات الشركاء',
  232
)
on conflict(code)
do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  sort_order = excluded.sort_order;


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
    'assets.view',
    'assets.manage',
    'assets.depreciate',
    'partners.view',
    'partners.manage',
    'partners.transactions'
  )
on conflict do nothing;


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
    'assets.view',
    'assets.manage',
    'assets.depreciate',
    'partners.view',
    'partners.manage',
    'partners.transactions'
  )
on conflict do nothing;


-- ============================================================
-- EXTRA GL ACCOUNTS
-- ============================================================

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
  c.id,
  p.id,
  '2400',
  'قروض الشركاء',
  'liability',
  'partner_loans',
  'credit',
  'partner_loans',
  true,
  true
from public.companies c
join public.finance_accounts p
  on p.company_id = c.id
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
  c.id,
  p.id,
  '3400',
  'أرباح موزعة مستحقة',
  'equity',
  'profit_distributions',
  'debit',
  'profit_distributions',
  true,
  true
from public.companies c
join public.finance_accounts p
  on p.company_id = c.id
 and p.code = '3000'
on conflict(company_id,code)
do nothing;


-- ============================================================
-- FIXED ASSETS
-- ============================================================

create table if not exists public.fixed_assets(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  asset_number text not null,

  name text not null,

  category text,

  description text,

  purchase_date date not null,

  in_service_date date not null,

  currency text not null default 'USD',

  purchase_cost numeric(18,2) not null
    check(purchase_cost >= 0),

  salvage_value numeric(18,2) not null default 0
    check(salvage_value >= 0),

  useful_life_months integer not null
    check(useful_life_months > 0),

  depreciation_method text not null default 'straight_line'
    check(
      depreciation_method in (
        'straight_line'
      )
    ),

  accumulated_depreciation numeric(18,2)
    not null default 0
    check(accumulated_depreciation >= 0),

  status text not null default 'active'
    check(
      status in (
        'active',
        'fully_depreciated',
        'disposed'
      )
    ),

  disposal_date date,

  disposal_amount numeric(18,2),

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  unique(
    company_id,
    asset_number
  ),

  check(
    salvage_value <= purchase_cost
  )
);

create index if not exists
fixed_assets_company_status_idx
on public.fixed_assets(
  company_id,
  status,
  in_service_date
);

drop trigger if exists
fixed_assets_updated_at
on public.fixed_assets;

create trigger
fixed_assets_updated_at
before update
on public.fixed_assets
for each row
execute function public.set_updated_at();


create table if not exists public.asset_depreciation_entries(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  asset_id uuid not null
    references public.fixed_assets(id)
    on delete restrict,

  period_start date not null,
  period_end date not null,

  amount numeric(18,2) not null
    check(amount > 0),

  journal_entry_id uuid
    references public.journal_entries(id)
    on delete restrict,

  posted_at timestamptz not null default now(),

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  unique(
    asset_id,
    period_start,
    period_end
  )
);

create index if not exists
asset_depreciation_entries_asset_idx
on public.asset_depreciation_entries(
  asset_id,
  period_end desc
);


-- ============================================================
-- ASSET NUMBER
-- ============================================================

create or replace function public.next_asset_number(
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
$$;

revoke all
on function public.next_asset_number(uuid,date)
from public, authenticated;


-- ============================================================
-- CREATE FIXED ASSET
-- ============================================================

create or replace function public.create_fixed_asset(
  target_company uuid,
  target_name text,
  target_category text,
  target_description text,
  target_purchase_date date,
  target_in_service_date date,
  target_currency text,
  target_purchase_cost numeric,
  target_salvage_value numeric,
  target_useful_life_months integer,
  target_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_number text;
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

  return v_id;
end;
$$;

revoke all
on function public.create_fixed_asset(
  uuid,
  text,
  text,
  text,
  date,
  date,
  text,
  numeric,
  numeric,
  integer,
  text
)
from public;

grant execute
on function public.create_fixed_asset(
  uuid,
  text,
  text,
  text,
  date,
  date,
  text,
  numeric,
  numeric,
  integer,
  text
)
to authenticated;


-- ============================================================
-- POST MONTHLY DEPRECIATION
-- ============================================================

create or replace function public.post_asset_depreciation_month(
  target_company uuid,
  target_year integer,
  target_month integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.post_asset_depreciation_month(
  uuid,
  integer,
  integer
)
from public;

grant execute
on function public.post_asset_depreciation_month(
  uuid,
  integer,
  integer
)
to authenticated;


-- ============================================================
-- PARTNERS
-- ============================================================

create table if not exists public.partners(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  partner_number text,

  name text not null,

  phone text,

  ownership_percent numeric(9,4)
    not null default 0
    check(
      ownership_percent >= 0
      and ownership_percent <= 100
    ),

  profit_share_percent numeric(9,4)
    not null default 0
    check(
      profit_share_percent >= 0
      and profit_share_percent <= 100
    ),

  active boolean not null default true,

  notes text,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create unique index if not exists
partners_number_unique
on public.partners(
  company_id,
  partner_number
)
where partner_number is not null;

create index if not exists
partners_company_idx
on public.partners(
  company_id,
  active,
  name
);

drop trigger if exists
partners_updated_at
on public.partners;

create trigger
partners_updated_at
before update
on public.partners
for each row
execute function public.set_updated_at();


create table if not exists public.partner_transactions(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  partner_id uuid not null
    references public.partners(id)
    on delete restrict,

  transaction_type text not null
    check(
      transaction_type in (
        'capital_contribution',
        'drawing',
        'partner_loan_in',
        'partner_loan_repayment',
        'profit_distribution'
      )
    ),

  amount numeric(18,2) not null
    check(amount > 0),

  currency text not null,

  cashbox_id uuid
    references public.cashboxes(id)
    on delete restrict,

  transaction_date date not null default (now() at time zone 'Asia/Damascus')::date,

  notes text,

  journal_entry_id uuid
    references public.journal_entries(id)
    on delete restrict,

  created_by uuid
    default auth.uid()
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index if not exists
partner_transactions_partner_idx
on public.partner_transactions(
  company_id,
  partner_id,
  transaction_date desc
);


-- ============================================================
-- SAVE PARTNER
-- ============================================================

create or replace function public.save_partner(
  target_company uuid,
  target_partner uuid,
  target_number text,
  target_name text,
  target_phone text,
  target_ownership_percent numeric,
  target_profit_share_percent numeric,
  target_notes text,
  target_active boolean
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
$$;

revoke all
on function public.save_partner(
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean
)
from public;

grant execute
on function public.save_partner(
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean
)
to authenticated;


-- ============================================================
-- RECORD PARTNER TRANSACTION
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

  if not exists(
    select 1
    from public.partners
    where id = target_partner
      and company_id =
          target_company
      and active = true
  ) then
    raise exception
      'Invalid partner';
  end if;

  if target_cashbox is null then
    raise exception
      'Cashbox is required';
  end if;

  if not exists(
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id =
          target_company
      and active = true
      and upper(currency) =
          upper(target_currency)
  ) then
    raise exception
      'Invalid cashbox or currency';
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

  if target_type =
     'capital_contribution'
  then
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

  elsif target_type =
        'drawing'
  then
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

  elsif target_type =
        'partner_loan_in'
  then
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

  elsif target_type =
        'partner_loan_repayment'
  then
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
    upper(target_currency),
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
      target_currency,
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
    notes,
    occurred_at
  )
  values(
    target_company,
    target_cashbox,
    v_direction,
    v_cash_type,
    round(target_amount,2),
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
        (now() at time zone 'Asia/Damascus')::date
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


-- ============================================================
-- EMPLOYEE ADVANCE / LOAN CASH ISSUE
-- ============================================================

create table if not exists public.employee_loan_disbursements(
  id uuid primary key default gen_random_uuid(),

  company_id uuid not null
    references public.companies(id)
    on delete cascade,

  employee_loan_id uuid not null unique
    references public.employee_loans(id)
    on delete restrict,

  employee_id uuid not null
    references public.employees(id)
    on delete restrict,

  cashbox_id uuid not null
    references public.cashboxes(id)
    on delete restrict,

  amount numeric(18,2) not null
    check(amount > 0),

  currency text not null,

  disbursement_date date not null,

  journal_entry_id uuid
    references public.journal_entries(id)
    on delete restrict,

  created_at timestamptz not null default now()
);


create or replace function public.disburse_employee_loan(
  target_company uuid,
  target_loan uuid,
  target_cashbox uuid,
  target_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.disburse_employee_loan(
  uuid,
  uuid,
  uuid,
  date
)
from public;

grant execute
on function public.disburse_employee_loan(
  uuid,
  uuid,
  uuid,
  date
)
to authenticated;


-- ============================================================
-- ASSET SUMMARY
-- ============================================================

create or replace view public.fixed_asset_summary
with (security_invoker = true)
as
select
  a.*,

  round(
    greatest(
      a.purchase_cost -
      a.accumulated_depreciation,
      a.salvage_value
    ),
    2
  ) as book_value,

  round(
    (
      a.purchase_cost -
      a.salvage_value
    ) /
    a.useful_life_months,
    2
  ) as monthly_depreciation

from public.fixed_assets a;


-- ============================================================
-- PARTNER SUMMARY
-- ============================================================

create or replace view public.partner_summary
with (security_invoker = true)
as
select
  p.*,

  coalesce(
    sum(
      case
        when pt.transaction_type =
             'capital_contribution'
          then (
            pt.amount *
            public.finance_rate_to_base(
              p.company_id,
              pt.currency,
              pt.transaction_date
            )
          )
        else 0
      end
    ),
    0
  )::numeric(18,2)
  as capital_contributions,

  coalesce(
    sum(
      case
        when pt.transaction_type =
             'drawing'
          then (
            pt.amount *
            public.finance_rate_to_base(
              p.company_id,
              pt.currency,
              pt.transaction_date
            )
          )
        else 0
      end
    ),
    0
  )::numeric(18,2)
  as drawings,

  coalesce(
    sum(
      case
        when pt.transaction_type =
             'partner_loan_in'
          then (
            pt.amount *
            public.finance_rate_to_base(
              p.company_id,
              pt.currency,
              pt.transaction_date
            )
          )

        when pt.transaction_type =
             'partner_loan_repayment'
          then -(
            pt.amount *
            public.finance_rate_to_base(
              p.company_id,
              pt.currency,
              pt.transaction_date
            )
          )

        else 0
      end
    ),
    0
  )::numeric(18,2)
  as partner_loan_balance,

  coalesce(
    sum(
      case
        when pt.transaction_type =
             'profit_distribution'
          then (
            pt.amount *
            public.finance_rate_to_base(
              p.company_id,
              pt.currency,
              pt.transaction_date
            )
          )
        else 0
      end
    ),
    0
  )::numeric(18,2)
  as profit_distributions

from public.partners p

left join public.partner_transactions pt
  on pt.partner_id =
     p.id

group by
  p.id;


-- ============================================================
-- RLS
-- ============================================================

alter table public.fixed_assets
enable row level security;

alter table public.asset_depreciation_entries
enable row level security;

alter table public.partners
enable row level security;

alter table public.partner_transactions
enable row level security;

alter table public.employee_loan_disbursements
enable row level security;


drop policy if exists
fixed_assets_read
on public.fixed_assets;

create policy fixed_assets_read
on public.fixed_assets
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'assets.view'
  )
);


drop policy if exists
asset_depreciation_entries_read
on public.asset_depreciation_entries;

create policy asset_depreciation_entries_read
on public.asset_depreciation_entries
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'assets.view'
  )
);


drop policy if exists
partners_read
on public.partners;

create policy partners_read
on public.partners
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'partners.view'
  )
);


drop policy if exists
partner_transactions_read
on public.partner_transactions;

create policy partner_transactions_read
on public.partner_transactions
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'partners.view'
  )
);


drop policy if exists
employee_loan_disbursements_read
on public.employee_loan_disbursements;

create policy employee_loan_disbursements_read
on public.employee_loan_disbursements
for select
to authenticated
using(
  public.has_permission(
    company_id,
    'payroll.view'
  )
);


revoke insert, update, delete
on public.fixed_assets,
   public.asset_depreciation_entries,
   public.partners,
   public.partner_transactions,
   public.employee_loan_disbursements
from authenticated;


grant select
on public.fixed_assets,
   public.asset_depreciation_entries,
   public.partners,
   public.partner_transactions,
   public.employee_loan_disbursements
to authenticated;


grant select
on public.fixed_asset_summary,
   public.partner_summary
to authenticated;


-- ============================================================
-- AUDIT
-- ============================================================

drop trigger if exists
audit_fixed_assets
on public.fixed_assets;

create trigger audit_fixed_assets
after insert or update or delete
on public.fixed_assets
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_asset_depreciation_entries
on public.asset_depreciation_entries;

create trigger audit_asset_depreciation_entries
after insert or update or delete
on public.asset_depreciation_entries
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_partners
on public.partners;

create trigger audit_partners
after insert or update or delete
on public.partners
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_partner_transactions
on public.partner_transactions;

create trigger audit_partner_transactions
after insert or update or delete
on public.partner_transactions
for each row
execute function public.write_audit_log();


drop trigger if exists
audit_employee_loan_disbursements
on public.employee_loan_disbursements;

create trigger audit_employee_loan_disbursements
after insert or update or delete
on public.employee_loan_disbursements
for each row
execute function public.write_audit_log();

commit;