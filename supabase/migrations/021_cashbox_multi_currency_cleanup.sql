begin;

drop function if exists public.record_expense(uuid,text,numeric,text);

create function public.record_expense(
  target_company uuid,
  target_cashbox uuid,
  expense_category text,
  expense_amount numeric,
  expense_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense uuid;
begin
  if not public.has_permission(target_company,'finance.expenses_write') then
    raise exception 'Not allowed';
  end if;

  if expense_amount is null or expense_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if nullif(trim(expense_category),'') is null then
    raise exception 'Category required';
  end if;

  if not exists(
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true
  ) then
    raise exception 'Invalid active cashbox';
  end if;

  insert into public.expenses(
    company_id,cashbox_id,category,amount,notes
  )
  values(
    target_company,
    target_cashbox,
    trim(expense_category),
    round(expense_amount,2),
    nullif(trim(expense_notes),'')
  )
  returning id into v_expense;

  insert into public.cash_transactions(
    company_id,cashbox_id,direction,type,amount,expense_id,notes
  )
  values(
    target_company,
    target_cashbox,
    'out',
    'expense',
    round(expense_amount,2),
    v_expense,
    nullif(trim(expense_notes),'')
  );

  return v_expense;
end;
$$;

revoke all on function public.record_expense(uuid,uuid,text,numeric,text) from public;
grant execute on function public.record_expense(uuid,uuid,text,numeric,text) to authenticated;

drop function if exists public.record_cash_movement(uuid,text,numeric,text);

create function public.record_cash_movement(
  target_company uuid,
  target_cashbox uuid,
  movement_type text,
  movement_amount numeric,
  movement_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_direction text;
begin
  if not public.has_permission(target_company,'finance.cashbox_write') then
    raise exception 'Not allowed';
  end if;

  if movement_amount is null or movement_amount <= 0 then
    raise exception 'Invalid amount';
  end if;

  if movement_type not in ('adjustment_in','adjustment_out') then
    raise exception 'Manual cash movement only supports adjustments';
  end if;

  if not exists(
    select 1
    from public.cashboxes
    where id = target_cashbox
      and company_id = target_company
      and active = true
  ) then
    raise exception 'Invalid active cashbox';
  end if;

  v_direction = case when movement_type='adjustment_in' then 'in' else 'out' end;

  insert into public.cash_transactions(
    company_id,cashbox_id,direction,type,amount,notes
  )
  values(
    target_company,
    target_cashbox,
    v_direction,
    movement_type,
    round(movement_amount,2),
    nullif(trim(movement_notes),'')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.record_cash_movement(uuid,uuid,text,numeric,text) from public;
grant execute on function public.record_cash_movement(uuid,uuid,text,numeric,text) to authenticated;

commit;
