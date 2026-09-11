begin;

create or replace function public.get_cashbox_summary(
  target_company uuid,
  target_date date
)
returns table(
  currency text,
  balance numeric,
  today_in numeric,
  today_out numeric,
  month_expense numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all
on function public.get_cashbox_summary(uuid,date)
from public;

grant execute
on function public.get_cashbox_summary(uuid,date)
to authenticated;

commit;
