-- أكتر من مالك للشركة: أي عضو صفتو "المالك" صار مالك كامل (متل يلي عمل الشركة).
-- صفة المالك بيعطيها أو بيشيلها مالك بس؛ المالك الأساسي محمي دايمًا.

create or replace function public.is_company_owner(target_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- المالك الأول (يلي عمل الشركة) أو أي شريك أعطاه مالك صفة "المالك".
  select exists(
    select 1
    from public.companies c
    where c.id = target_company
      and c.owner_user_id = auth.uid()
  )
  or exists(
    select 1
    from public.company_members m
    join public.company_roles r on r.id = m.role_id
    where m.company_id = target_company
      and m.user_id = auth.uid()
      and r.is_owner
      and r.active
  );
$function$;

create or replace function public.assign_company_member_role(target_company uuid, target_user uuid, target_role uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_role_owner boolean;
begin

  if not public.has_permission(
    target_company,
    'team.manage_members'
  ) then
    raise exception 'Not allowed';
  end if;


  select
    c.owner_user_id

  into
    v_owner

  from public.companies c

  where c.id =
        target_company;


  if v_owner is null then
    raise exception 'Company not found';
  end if;


  if target_user =
     v_owner
  then
    raise exception
      'Company owner role cannot be changed';
  end if;


  select
    r.is_owner

  into
    v_role_owner

  from public.company_roles r

  where r.id =
        target_role

    and r.company_id =
        target_company

    and r.active =
        true;


  if not found then
    raise exception 'Invalid team role';
  end if;


  -- صفة المالك (أو تغيير صفة شريك مالك) بيعملها مالك بس، مش المدير.
  if (
       coalesce(v_role_owner, false)
       or exists(
         select 1
         from public.company_members m
         join public.company_roles r on r.id = m.role_id
         where m.company_id = target_company
           and m.user_id = target_user
           and r.is_owner
       )
     )
     and not public.is_company_owner(target_company)
  then
    raise exception
      'Only an owner can manage owners';
  end if;


  insert into public.company_members(
    company_id,
    user_id,
    role_id
  )
  values(
    target_company,
    target_user,
    target_role
  )

  on conflict(
    company_id,
    user_id
  )
  do update
  set role_id =
      excluded.role_id;

end;
$function$;

create or replace function public.protect_owner_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_role_owner boolean;
  v_company uuid;
begin
  if tg_op = 'DELETE' then
    v_company := old.company_id;
  else
    v_company := new.company_id;
  end if;

  select owner_user_id
  into v_owner
  from public.companies
  where id = v_company;

  if tg_op = 'DELETE' and old.user_id = v_owner then
    raise exception 'Company owner membership cannot be deleted';
  end if;

  -- شريك مالك ما بيشيلو ولا بيغيّر صفتو غير مالك.
  if tg_op in ('DELETE','UPDATE')
     and auth.uid() is not null
     and exists(select 1 from public.company_roles r where r.id = old.role_id and r.is_owner)
     and not public.is_company_owner(old.company_id)
  then
    raise exception 'Only an owner can manage owners';
  end if;

  if tg_op in ('INSERT','UPDATE') then
    select is_owner
    into v_role_owner
    from public.company_roles
    where id = new.role_id
      and company_id = new.company_id;

    if coalesce(v_role_owner,false)
       and new.user_id <> v_owner
       and auth.uid() is not null
       and not public.is_company_owner(new.company_id)
    then
      raise exception 'Only an owner can manage owners';
    end if;

    if tg_op = 'UPDATE' and old.user_id = v_owner then
      if new.user_id <> old.user_id
         or new.company_id <> old.company_id
         or coalesce(v_role_owner,false) = false
      then
        raise exception 'Company owner membership is protected';
      end if;
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;
