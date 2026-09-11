begin;

-- ============================================================
-- 017 RETURN REVERSALS
-- Sales returns + purchase returns
-- Inventory reversal + financial reversal + audit-safe status.
-- ============================================================


-- ============================================================
-- PERMISSION
-- ============================================================

insert into public.permissions(
  code,
  module,
  action,
  label,
  description,
  sort_order
)
values(
  'returns.reverse',
  'returns',
  'reverse',
  'عكس مرتجع',
  'عكس مرتجع بيع أو شراء مع المخزون والمحاسبة',
  183
)
on conflict(code)
do update set
  module = excluded.module,
  action = excluded.action,
  label = excluded.label,
  description = excluded.description;


insert into public.role_permissions(
  role_id,
  permission_code
)
select
  r.id,
  'returns.reverse'
from public.company_roles r
where
  r.is_owner = true
  or r.name = 'محاسب'
on conflict do nothing;


-- ============================================================
-- REVERSAL METADATA
-- ============================================================

alter table public.sales_returns
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid
    references auth.users(id)
    on delete set null,
  add column if not exists reversal_reason text,
  add column if not exists reversal_journal_entry_id uuid
    references public.journal_entries(id)
    on delete set null;


alter table public.purchase_returns
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid
    references auth.users(id)
    on delete set null,
  add column if not exists reversal_reason text,
  add column if not exists reversal_journal_entry_id uuid
    references public.journal_entries(id)
    on delete set null;


-- ============================================================
-- STATUS CONSTRAINTS
-- Preserve posted/cancelled compatibility and add reversed.
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid =
          'public.sales_returns'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid)
          ilike '%status%'
  loop
    execute format(
      'alter table public.sales_returns drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;

alter table public.sales_returns
add constraint sales_returns_status_check
check(
  status in (
    'posted',
    'cancelled',
    'reversed'
  )
);


do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid =
          'public.purchase_returns'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid)
          ilike '%status%'
  loop
    execute format(
      'alter table public.purchase_returns drop constraint %I',
      r.conname
    );
  end loop;
end;
$$;

alter table public.purchase_returns
add constraint purchase_returns_status_check
check(
  status in (
    'posted',
    'cancelled',
    'reversed'
  )
);


-- ============================================================
-- VERIFY ACCOUNTING ENGINE
-- Current post_system_journal is expected to have 8 arguments.
-- ============================================================

do $$
begin
  if not exists(
    select 1
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname =
          'post_system_journal'
      and p.pronargs = 8
  ) then
    raise exception
      'Expected 8-argument post_system_journal was not found';
  end if;
end;
$$;


-- ============================================================
-- INTERNAL FINANCIAL REVERSAL
--
-- Reads the original journal lines as JSON, therefore it does
-- not depend on users having direct access to journal tables.
--
-- Original:
--   debit  -> reversal credit
--   credit -> reversal debit
-- ============================================================

create or replace function public.reverse_return_financial_journal(
  target_company uuid,
  target_original_journal uuid,
  target_currency text,
  target_description text,
  target_source_type text,
  target_source_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lines jsonb;
  v_entry uuid;
begin
  if target_original_journal is null then
    raise exception
      'Return financial journal is missing';
  end if;


  select
    coalesce(
      jsonb_agg(
        jsonb_strip_nulls(
          jsonb_build_object(
            'account_id',
            coalesce(
              nullif(
                x->>'account_id',
                ''
              ),
              nullif(
                x->>'finance_account_id',
                ''
              )
            ),

            'debit',
            coalesce(
              nullif(
                x->>'credit',
                ''
              )::numeric,
              nullif(
                x->>'credit_amount',
                ''
              )::numeric,
              0
            ),

            'credit',
            coalesce(
              nullif(
                x->>'debit',
                ''
              )::numeric,
              nullif(
                x->>'debit_amount',
                ''
              )::numeric,
              0
            ),

            'party_type',
            nullif(
              x->>'party_type',
              ''
            ),

            'party_id',
            nullif(
              x->>'party_id',
              ''
            ),

            'memo',
            case
              when nullif(
                     x->>'memo',
                     ''
                   ) is not null
              then
                'عكس - ' ||
                (x->>'memo')
              else
                target_description
            end
          )
        )
      ),
      '[]'::jsonb
    )
  into v_lines
  from (
    select
      to_jsonb(jl) as x
    from public.journal_lines jl
    where
      coalesce(
        to_jsonb(jl)
          ->>'journal_entry_id',

        to_jsonb(jl)
          ->>'entry_id'
      ) =
      target_original_journal::text
  ) q;


  if jsonb_array_length(
       v_lines
     ) = 0
  then
    raise exception
      'Original journal lines not found';
  end if;


  if exists(
    select 1
    from jsonb_array_elements(
      v_lines
    ) line
    where nullif(
            line->>'account_id',
            ''
          ) is null
  ) then
    raise exception
      'Original journal contains an invalid account';
  end if;


  -- Signature used by the current accounting engine:
  --
  -- post_system_journal(
  --   company,
  --   entry_date,
  --   description,
  --   currency,
  --   exchange_rate,
  --   source_type,
  --   source_id,
  --   lines
  -- )

  execute
    'select public.post_system_journal(
       $1,$2,$3,$4,$5,$6,$7,$8
     )'
  into v_entry
  using
    target_company,
    current_date,
    target_description,
    upper(target_currency),
    null::numeric,
    target_source_type,
    target_source_id,
    v_lines;


  if v_entry is null then
    raise exception
      'Financial reversal journal was not created';
  end if;

  return v_entry;
end;
$$;

revoke all
on function public.reverse_return_financial_journal(
  uuid,
  uuid,
  text,
  text,
  text,
  uuid
)
from public, authenticated;


-- ============================================================
-- REVERSE SALES RETURN
--
-- Original sales return:
--   inventory quantity +
--
-- Reversal:
--   inventory quantity -
--   using original return movement cost.
-- ============================================================

create or replace function public.reverse_sales_return(
  target_company uuid,
  target_return uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_product record;
  v_item record;

  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;


  select
    status,
    sales_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.sales_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Sales return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted sales returns can be reversed';
  end if;


  -- ----------------------------------------------------------
  -- Validate the total quantity by product BEFORE changing
  -- anything.
  --
  -- We only remove AVAILABLE stock, never active reservations.
  -- ----------------------------------------------------------

  for v_product in

    select
      sri.product_id,
      sum(
        sri.quantity
      ) as quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    group by
      sri.product_id

  loop

    select
      coalesce(
        s.on_hand,
        0
      ),

      coalesce(
        (
          select
            sum(r.quantity)

          from public.inventory_reservations r

          where r.company_id =
                target_company

            and r.warehouse_id =
                v_warehouse

            and r.product_id =
                v_product.product_id

            and r.status =
                'active'
        ),
        0
      )

    into
      v_on_hand,
      v_reserved

    from public.inventory_stock s

    where s.company_id =
          target_company

      and s.warehouse_id =
          v_warehouse

      and s.product_id =
          v_product.product_id;


    if
      coalesce(
        v_on_hand,
        0
      ) -
      coalesce(
        v_reserved,
        0
      )
      <
      v_product.quantity
    then
      raise exception
        'Cannot reverse sales return: returned stock was already reserved, transferred or used';
    end if;

  end loop;


  -- ----------------------------------------------------------
  -- Reverse every original return stock movement.
  -- ----------------------------------------------------------

  for v_item in

    select
      sri.id,
      sri.product_id,
      sri.quantity

    from public.sales_return_items sri

    where sri.sales_return_id =
          target_return

    order by sri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'sales_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'sales_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for sales return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'sales_delivery',
        -v_item.quantity,
        v_cost,
        'sales_return_reversals',
        target_return,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );

  end loop;


  -- ----------------------------------------------------------
  -- Reverse financial credit-note journal.
  -- Inventory accounting is already reversed by the inventory
  -- movements above.
  -- ----------------------------------------------------------

  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مبيعات ' ||
      v_number,
      'sales_return_reversal',
      target_return
    );


  update public.sales_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_sales_invoice_payment(
      v_invoice
    );

end;
$$;


revoke all
on function public.reverse_sales_return(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.reverse_sales_return(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- REVERSE PURCHASE RETURN
--
-- Original purchase return:
--   inventory quantity -
--
-- Reversal:
--   inventory quantity +
--   using the exact original movement cost.
-- ============================================================

create or replace function public.reverse_purchase_return(
  target_company uuid,
  target_return uuid,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;

  v_invoice uuid;
  v_warehouse uuid;

  v_number text;
  v_currency text;

  v_original_journal uuid;
  v_reversal_journal uuid;

  v_item record;
  v_cost numeric(18,4);
begin

  if not public.has_permission(
    target_company,
    'returns.reverse'
  ) then
    raise exception 'Not allowed';
  end if;


  if nullif(
       trim(target_reason),
       ''
     ) is null
  then
    raise exception
      'Reversal reason required';
  end if;


  select
    status,
    purchase_invoice_id,
    warehouse_id,
    return_number,
    currency,
    journal_entry_id

  into
    v_status,
    v_invoice,
    v_warehouse,
    v_number,
    v_currency,
    v_original_journal

  from public.purchase_returns

  where id =
        target_return

    and company_id =
        target_company

  for update;


  if v_status is null then
    raise exception
      'Purchase return not found';
  end if;


  if v_status = 'reversed' then
    return;
  end if;


  if v_status <> 'posted' then
    raise exception
      'Only posted purchase returns can be reversed';
  end if;


  for v_item in

    select
      pri.id,
      pri.product_id,
      pri.quantity

    from public.purchase_return_items pri

    where pri.purchase_return_id =
          target_return

    order by pri.id

  loop

    select
      im.unit_cost

    into v_cost

    from public.inventory_movements im

    where im.company_id =
          target_company

      and im.source_table =
          'purchase_returns'

      and im.source_id =
          target_return

      and im.source_line_id =
          v_item.id

      and im.movement_type =
          'purchase_return'

    order by
      im.created_at desc

    limit 1;


    if v_cost is null then
      raise exception
        'Original inventory cost for purchase return line was not found';
    end if;


    perform
      public.post_inventory_movement(
        target_company,
        v_warehouse,
        v_item.product_id,
        'purchase_receipt',
        v_item.quantity,
        v_cost,
        'purchase_return_reversals',
        target_return,
        v_item.id,
        v_number || '-REV',
        trim(target_reason),
        now()
      );


    perform
      public.reserve_pending_orders_for_product(
        target_company,
        v_warehouse,
        v_item.product_id
      );

  end loop;


  v_reversal_journal :=
    public.reverse_return_financial_journal(
      target_company,
      v_original_journal,
      v_currency,
      'عكس مرتجع مشتريات ' ||
      v_number,
      'purchase_return_reversal',
      target_return
    );


  update public.purchase_returns
  set
    status =
      'reversed',

    reversed_at =
      now(),

    reversed_by =
      auth.uid(),

    reversal_reason =
      trim(target_reason),

    reversal_journal_entry_id =
      v_reversal_journal

  where id =
        target_return;


  perform
    public.recalc_purchase_invoice_payment(
      v_invoice
    );

end;
$$;


revoke all
on function public.reverse_purchase_return(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.reverse_purchase_return(
  uuid,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- INVOICE CANCELLATION SAFETY
-- A posted return must always be reversed first.
-- ============================================================

create or replace function public.block_invoice_cancel_with_posted_return()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  if old.status = 'posted'
     and new.status = 'cancelled'
  then

    if tg_table_name =
       'sales_invoices'
    then

      if exists(
        select 1
        from public.sales_returns sr
        where sr.company_id =
              new.company_id
          and sr.sales_invoice_id =
              new.id
          and sr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted sales returns before cancelling sales invoice';
      end if;


    elsif tg_table_name =
          'purchase_invoices'
    then

      if exists(
        select 1
        from public.purchase_returns pr
        where pr.company_id =
              new.company_id
          and pr.purchase_invoice_id =
              new.id
          and pr.status =
              'posted'
      ) then
        raise exception
          'Reverse posted purchase returns before cancelling purchase invoice';
      end if;

    end if;

  end if;

  return new;
end;
$$;


drop trigger if exists
block_sales_invoice_cancel_with_return
on public.sales_invoices;

create trigger
block_sales_invoice_cancel_with_return
before update of status
on public.sales_invoices
for each row
execute function
public.block_invoice_cancel_with_posted_return();


drop trigger if exists
block_purchase_invoice_cancel_with_return
on public.purchase_invoices;

create trigger
block_purchase_invoice_cancel_with_return
before update of status
on public.purchase_invoices
for each row
execute function
public.block_invoice_cancel_with_posted_return();


-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists
sales_returns_company_status_idx
on public.sales_returns(
  company_id,
  status,
  return_date desc
);


create index if not exists
purchase_returns_company_status_idx
on public.purchase_returns(
  company_id,
  status,
  return_date desc
);


commit;