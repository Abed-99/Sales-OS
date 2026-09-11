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

commit;
