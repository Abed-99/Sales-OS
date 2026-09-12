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
  v_reversal_date date;
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


  v_reversal_date :=
    (
      now()
      at time zone
      'Asia/Damascus'
    )::date;

  perform
    public.assert_finance_period_open(
      target_company,
      v_reversal_date
    );


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
    v_reversal_date,
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



-- ============================================================
-- RETURNS READ MODELS
-- Secure return-specific reads. These functions prevent the UI
-- from depending on sales/purchase invoice table permissions and
-- never expose purchase/inventory cost data.
-- ============================================================


-- ------------------------------------------------------------
-- Permission helper for return history / reporting.
-- ------------------------------------------------------------

create or replace function public.can_view_returns(
  target_company uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.has_any_permission(
      target_company,
      array[
        'returns.view',
        'returns.create',
        'inventory.returns',
        'returns.reverse'
      ]::text[]
    );
$$;

revoke all
on function public.can_view_returns(uuid)
from public, authenticated;


-- ------------------------------------------------------------
-- Exact summary.
-- Monetary totals stay grouped by their real currency.
-- Never add USD/SYP/etc together.
-- ------------------------------------------------------------

create or replace function public.get_returns_summary(
  target_company uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sales_count bigint;
  v_purchase_count bigint;

  v_sales_posted bigint;
  v_purchase_posted bigint;

  v_sales_reversed bigint;
  v_purchase_reversed bigint;

  v_sales_totals jsonb;
  v_purchase_totals jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_sales_count,
    v_sales_posted,
    v_sales_reversed
  from public.sales_returns
  where company_id =
        target_company;

  select
    count(*)::bigint,
    count(*) filter (
      where status = 'posted'
    )::bigint,
    count(*) filter (
      where status = 'reversed'
    )::bigint
  into
    v_purchase_count,
    v_purchase_posted,
    v_purchase_reversed
  from public.purchase_returns
  where company_id =
        target_company;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_sales_totals
  from (
    select
      upper(sr.currency)
        as currency,

      round(
        sum(sr.total),
        2
      ) as total

    from public.sales_returns sr

    where sr.company_id =
          target_company

      and sr.status =
          'posted'

    group by
      upper(sr.currency)
  ) x;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'currency',
          x.currency,

          'total',
          x.total
        )
        order by
          x.currency
      ),
      '[]'::jsonb
    )
  into
    v_purchase_totals
  from (
    select
      upper(pr.currency)
        as currency,

      round(
        sum(pr.total),
        2
      ) as total

    from public.purchase_returns pr

    where pr.company_id =
          target_company

      and pr.status =
          'posted'

    group by
      upper(pr.currency)
  ) x;

  return
    jsonb_build_object(
      'sales_count',
        v_sales_count,

      'sales_posted_count',
        v_sales_posted,

      'sales_reversed_count',
        v_sales_reversed,

      'purchase_count',
        v_purchase_count,

      'purchase_posted_count',
        v_purchase_posted,

      'purchase_reversed_count',
        v_purchase_reversed,

      'sales_totals',
        v_sales_totals,

      'purchase_totals',
        v_purchase_totals
    );
end;
$$;

revoke all
on function public.get_returns_summary(uuid)
from public;

grant execute
on function public.get_returns_summary(uuid)
to authenticated;


-- ------------------------------------------------------------
-- Warehouses available for return posting.
-- ------------------------------------------------------------

create or replace function public.get_return_warehouses(
  target_company uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            w.id,

          'name',
            w.name,

          'code',
            w.code,

          'is_default',
            w.is_default
        )
        order by
          w.is_default desc,
          w.name
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from public.warehouses w
  where w.company_id =
        target_company
    and w.active = true;

  return v_rows;
end;
$$;

revoke all
on function public.get_return_warehouses(uuid)
from public;

grant execute
on function public.get_return_warehouses(uuid)
to authenticated;


-- ------------------------------------------------------------
-- Sales invoices with quantities still eligible for return.
-- No cost fields are returned.
-- ------------------------------------------------------------

create or replace function public.get_sales_return_candidates(
  target_company uuid,
  target_search text default null,
  target_limit integer default 50,
  target_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.sales_invoices si

  join public.traders t
    on t.id =
       si.trader_id

  where si.company_id =
        target_company

    and si.status =
        'posted'

    and (
      v_search is null

      or si.invoice_number
         ilike
         '%' || v_search || '%'

      or t.name
         ilike
         '%' || v_search || '%'
    )

    and exists (
      select 1
      from public.sales_invoice_items sii
      where sii.invoice_id =
            si.id
        and sii.company_id =
            target_company

        and round(
              sii.quantity -
              coalesce(
                (
                  select
                    sum(sri.quantity)

                  from public.sales_return_items sri

                  join public.sales_returns sr
                    on sr.id =
                       sri.sales_return_id

                  where sri.sales_invoice_item_id =
                        sii.id

                    and sr.company_id =
                        target_company

                    and sr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      si.invoice_date
        as sort_date,

      si.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          si.id,

        'invoice_number',
          si.invoice_number,

        'invoice_date',
          si.invoice_date,

        'currency',
          si.currency,

        'total',
          si.total,

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_invoices si

    join public.traders t
      on t.id =
         si.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'unit',
              x.unit,

            'invoiced_quantity',
              x.invoiced_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.invoiced_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.invoiced_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          sii.id,
          sii.product_id,
          sii.description,
          sii.unit,
          sii.quantity
            as invoiced_quantity,
          sii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(sri.quantity)

              from public.sales_return_items sri

              join public.sales_returns sr
                on sr.id =
                   sri.sales_return_id

              where sri.sales_invoice_item_id =
                    sii.id

                and sr.company_id =
                    target_company

                and sr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.sales_invoice_items sii

        join public.products p
          on p.id =
             sii.product_id

        where sii.invoice_id =
              si.id

          and sii.company_id =
              target_company
      ) x
    ) items
      on true

    where si.company_id =
          target_company

      and si.status =
          'posted'

      and (
        v_search is null

        or si.invoice_number
           ilike
           '%' || v_search || '%'

        or t.name
           ilike
           '%' || v_search || '%'
      )

      and exists (
        select 1
        from public.sales_invoice_items sii
        where sii.invoice_id =
              si.id
          and sii.company_id =
              target_company

          and round(
                sii.quantity -
                coalesce(
                  (
                    select
                      sum(sri.quantity)

                    from public.sales_return_items sri

                    join public.sales_returns sr
                      on sr.id =
                         sri.sales_return_id

                    where sri.sales_invoice_item_id =
                          sii.id

                      and sr.company_id =
                          target_company

                      and sr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      si.invoice_date desc,
      si.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$$;

revoke all
on function public.get_sales_return_candidates(
  uuid,
  text,
  integer,
  integer
)
from public;

grant execute
on function public.get_sales_return_candidates(
  uuid,
  text,
  integer,
  integer
)
to authenticated;


-- ------------------------------------------------------------
-- Purchase invoices with physically RECEIVED quantity available
-- to return. Invoice quantity alone is not sufficient.
-- Purchase price / inventory cost are intentionally not exposed.
-- ------------------------------------------------------------

create or replace function public.get_purchase_return_candidates(
  target_company uuid,
  target_search text default null,
  target_limit integer default 50,
  target_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'returns.create',
      'inventory.returns'
    ]::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  select
    count(*)::bigint
  into
    v_total
  from public.purchase_invoices pi

  join public.suppliers s
    on s.id =
       pi.supplier_id

  where pi.company_id =
        target_company

    and pi.status =
        'posted'

    and (
      v_search is null

      or pi.invoice_number
         ilike
         '%' || v_search || '%'

      or coalesce(
           pi.supplier_invoice_number,
           ''
         )
         ilike
         '%' || v_search || '%'

      or s.name
         ilike
         '%' || v_search || '%'
    )

    and exists (
      select 1
      from public.purchase_invoice_items pii

      where pii.invoice_id =
            pi.id

        and pii.company_id =
            target_company

        and round(
              coalesce(
                (
                  select
                    sum(gri.quantity)

                  from public.goods_receipt_items gri

                  join public.goods_receipts gr
                    on gr.id =
                       gri.goods_receipt_id

                  where gri.purchase_invoice_item_id =
                        pii.id

                    and gr.company_id =
                        target_company

                    and gr.purchase_invoice_id =
                        pi.id

                    and gr.status =
                        'posted'
                ),
                0
              )
              -
              coalesce(
                (
                  select
                    sum(pri.quantity)

                  from public.purchase_return_items pri

                  join public.purchase_returns pr
                    on pr.id =
                       pri.purchase_return_id

                  where pri.purchase_invoice_item_id =
                        pii.id

                    and pr.company_id =
                        target_company

                    and pr.status =
                        'posted'
                ),
                0
              ),
              3
            ) > 0
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date desc,
          sort_created desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select
      pi.invoice_date
        as sort_date,

      pi.created_at
        as sort_created,

      jsonb_build_object(
        'id',
          pi.id,

        'invoice_number',
          pi.invoice_number,

        'supplier_invoice_number',
          pi.supplier_invoice_number,

        'invoice_date',
          pi.invoice_date,

        'currency',
          pi.currency,

        'total',
          pi.total,

        'supplier',
          jsonb_build_object(
            'id',
              s.id,

            'name',
              s.name
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.purchase_invoices pi

    join public.suppliers s
      on s.id =
         pi.supplier_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              x.id,

            'product_id',
              x.product_id,

            'product_name',
              x.product_name,

            'sku',
              x.sku,

            'description',
              x.description,

            'invoiced_quantity',
              x.invoiced_quantity,

            'received_quantity',
              x.received_quantity,

            'returned_quantity',
              x.returned_quantity,

            'available_quantity',
              greatest(
                round(
                  x.received_quantity -
                  x.returned_quantity,
                  3
                ),
                0
              )
          )
          order by
            x.created_at
        ) filter (
          where
            round(
              x.received_quantity -
              x.returned_quantity,
              3
            ) > 0
        ) as payload

      from (
        select
          pii.id,
          pii.product_id,
          pii.description,
          pii.quantity
            as invoiced_quantity,
          pii.created_at,

          p.name
            as product_name,

          p.sku,

          coalesce(
            (
              select
                sum(gri.quantity)

              from public.goods_receipt_items gri

              join public.goods_receipts gr
                on gr.id =
                   gri.goods_receipt_id

              where gri.purchase_invoice_item_id =
                    pii.id

                and gr.company_id =
                    target_company

                and gr.purchase_invoice_id =
                    pi.id

                and gr.status =
                    'posted'
            ),
            0
          ) as received_quantity,

          coalesce(
            (
              select
                sum(pri.quantity)

              from public.purchase_return_items pri

              join public.purchase_returns pr
                on pr.id =
                   pri.purchase_return_id

              where pri.purchase_invoice_item_id =
                    pii.id

                and pr.company_id =
                    target_company

                and pr.status =
                    'posted'
            ),
            0
          ) as returned_quantity

        from public.purchase_invoice_items pii

        join public.products p
          on p.id =
             pii.product_id

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company
      ) x
    ) items
      on true

    where pi.company_id =
          target_company

      and pi.status =
          'posted'

      and (
        v_search is null

        or pi.invoice_number
           ilike
           '%' || v_search || '%'

        or coalesce(
             pi.supplier_invoice_number,
             ''
           )
           ilike
           '%' || v_search || '%'

        or s.name
           ilike
           '%' || v_search || '%'
      )

      and exists (
        select 1
        from public.purchase_invoice_items pii

        where pii.invoice_id =
              pi.id

          and pii.company_id =
              target_company

          and round(
                coalesce(
                  (
                    select
                      sum(gri.quantity)

                    from public.goods_receipt_items gri

                    join public.goods_receipts gr
                      on gr.id =
                         gri.goods_receipt_id

                    where gri.purchase_invoice_item_id =
                          pii.id

                      and gr.company_id =
                          target_company

                      and gr.purchase_invoice_id =
                          pi.id

                      and gr.status =
                          'posted'
                  ),
                  0
                )
                -
                coalesce(
                  (
                    select
                      sum(pri.quantity)

                    from public.purchase_return_items pri

                    join public.purchase_returns pr
                      on pr.id =
                         pri.purchase_return_id

                    where pri.purchase_invoice_item_id =
                          pii.id

                      and pr.company_id =
                          target_company

                      and pr.status =
                          'posted'
                  ),
                  0
                ),
                3
              ) > 0
      )

    order by
      pi.invoice_date desc,
      pi.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$$;

revoke all
on function public.get_purchase_return_candidates(
  uuid,
  text,
  integer,
  integer
)
from public;

grant execute
on function public.get_purchase_return_candidates(
  uuid,
  text,
  integer,
  integer
)
to authenticated;


-- ------------------------------------------------------------
-- Unified return history.
-- ------------------------------------------------------------

create or replace function public.get_returns_history(
  target_company uuid,
  target_search text default null,
  target_kind text default null,
  target_status text default null,
  target_limit integer default 50,
  target_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text;
  v_kind text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.can_view_returns(
    target_company
  ) then
    raise exception 'Not allowed';
  end if;

  v_search :=
    nullif(
      trim(
        coalesce(
          target_search,
          ''
        )
      ),
      ''
    );

  v_kind :=
    case
      when target_kind in (
        'sales',
        'purchases'
      )
      then target_kind
      else null
    end;

  v_status :=
    case
      when target_status in (
        'posted',
        'reversed',
        'cancelled'
      )
      then target_status
      else null
    end;

  v_limit :=
    least(
      greatest(
        coalesce(
          target_limit,
          50
        ),
        1
      ),
      100
    );

  v_offset :=
    greatest(
      coalesce(
        target_offset,
        0
      ),
      0
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    count(*)::bigint
  into
    v_total
  from history h
  where (
      v_kind is null
      or h.kind =
         v_kind
    )
    and (
      v_status is null
      or h.status =
         v_status
    )
    and (
      v_search is null

      or h.return_number
         ilike
         '%' || v_search || '%'

      or h.invoice_number
         ilike
         '%' || v_search || '%'

      or h.party_name
         ilike
         '%' || v_search || '%'
    );

  with history as (
    select
      sr.id,
      'sales'::text
        as kind,
      sr.return_number,
      si.invoice_number,
      t.name
        as party_name,
      w.name
        as warehouse_name,
      sr.return_date,
      sr.status,
      sr.currency,
      sr.total,
      sr.notes,
      sr.created_at,
      sr.reversed_at,
      sr.reversal_reason

    from public.sales_returns sr

    join public.sales_invoices si
      on si.id =
         sr.sales_invoice_id

    join public.traders t
      on t.id =
         sr.trader_id

    join public.warehouses w
      on w.id =
         sr.warehouse_id

    where sr.company_id =
          target_company

    union all

    select
      pr.id,
      'purchases'::text
        as kind,
      pr.return_number,
      pi.invoice_number,
      s.name
        as party_name,
      w.name
        as warehouse_name,
      pr.return_date,
      pr.status,
      pr.currency,
      pr.total,
      pr.notes,
      pr.created_at,
      pr.reversed_at,
      pr.reversal_reason

    from public.purchase_returns pr

    join public.purchase_invoices pi
      on pi.id =
         pr.purchase_invoice_id

    join public.suppliers s
      on s.id =
         pr.supplier_id

    join public.warehouses w
      on w.id =
         pr.warehouse_id

    where pr.company_id =
          target_company
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',
            q.id,

          'kind',
            q.kind,

          'return_number',
            q.return_number,

          'invoice_number',
            q.invoice_number,

          'party_name',
            q.party_name,

          'warehouse_name',
            q.warehouse_name,

          'return_date',
            q.return_date,

          'status',
            q.status,

          'currency',
            q.currency,

          'total',
            q.total,

          'notes',
            q.notes,

          'created_at',
            q.created_at,

          'reversed_at',
            q.reversed_at,

          'reversal_reason',
            q.reversal_reason
        )
        order by
          q.return_date desc,
          q.created_at desc
      ),
      '[]'::jsonb
    )
  into
    v_rows
  from (
    select *
    from history h
    where (
        v_kind is null
        or h.kind =
           v_kind
      )
      and (
        v_status is null
        or h.status =
           v_status
      )
      and (
        v_search is null

        or h.return_number
           ilike
           '%' || v_search || '%'

        or h.invoice_number
           ilike
           '%' || v_search || '%'

        or h.party_name
           ilike
           '%' || v_search || '%'
      )

    order by
      h.return_date desc,
      h.created_at desc

    limit v_limit
    offset v_offset
  ) q;

  return
    jsonb_build_object(
      'total_count',
        v_total,

      'rows',
        v_rows
    );
end;
$$;

revoke all
on function public.get_returns_history(
  uuid,
  text,
  text,
  text,
  integer,
  integer
)
from public;

grant execute
on function public.get_returns_history(
  uuid,
  text,
  text,
  text,
  integer,
  integer
)
to authenticated;
commit;