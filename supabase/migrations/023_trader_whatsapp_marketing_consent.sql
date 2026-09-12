begin;

alter table public.traders
  add column if not exists whatsapp_marketing_opt_in boolean not null default false;

alter table public.traders
  add column if not exists whatsapp_opt_in_at timestamptz;

alter table public.traders
  add column if not exists whatsapp_opt_out_at timestamptz;

comment on column public.traders.whatsapp_marketing_opt_in
  is 'Whether the trader has opted in to WhatsApp marketing messages.';

comment on column public.traders.whatsapp_opt_in_at
  is 'Timestamp of the latest WhatsApp marketing opt-in.';

comment on column public.traders.whatsapp_opt_out_at
  is 'Timestamp of the latest WhatsApp marketing opt-out.';


create or replace function public.set_trader_whatsapp_consent_timestamps()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.whatsapp_marketing_opt_in then
      new.whatsapp_opt_in_at := now();
      new.whatsapp_opt_out_at := null;
    else
      new.whatsapp_opt_in_at := null;
      new.whatsapp_opt_out_at := null;
    end if;

    return new;
  end if;

  -- Prevent ordinary customer edits from rewriting consent history.
  new.whatsapp_opt_in_at := old.whatsapp_opt_in_at;
  new.whatsapp_opt_out_at := old.whatsapp_opt_out_at;

  if new.whatsapp_marketing_opt_in
     is distinct from old.whatsapp_marketing_opt_in
  then
    if new.whatsapp_marketing_opt_in then
      new.whatsapp_opt_in_at := now();
    else
      new.whatsapp_opt_out_at := now();
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists
traders_whatsapp_consent_timestamps
on public.traders;

create trigger traders_whatsapp_consent_timestamps
before insert or update of whatsapp_marketing_opt_in,
  whatsapp_opt_in_at,
  whatsapp_opt_out_at
on public.traders
for each row
execute function public.set_trader_whatsapp_consent_timestamps();
commit;
