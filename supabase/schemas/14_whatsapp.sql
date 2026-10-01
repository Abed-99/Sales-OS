-- ======================================================================
-- صندوق رسائل واتساب الجاهزة: البرنامج بيجهّز الرسالة (والفاتورة أو الكشف)،
-- والمستخدم بيبعتها بإيدو من واتساب. ما في إرسال آلي، فما في خطر حظر.
-- ======================================================================

-- شو الرسائل اللي بتنجهّز، وقوالبها (فاضي = القالب الافتراضي).
alter table public.companies
  add column whatsapp_settings jsonb default '{"invoice": true, "receipt": true, "delivery": true, "reminder": true, "statement": true, "reminder_days": 7}'::jsonb not null,
  add column whatsapp_templates jsonb default '{}'::jsonb not null;

create table public.whatsapp_outbox (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null,
  trader_id uuid references public.traders(id) on delete cascade,
  phone text,
  message text not null,
  document_type text,
  document_id uuid,
  status text default 'pending'::text not null,
  dedupe_key text not null,
  created_at timestamp with time zone default now() not null,
  sent_at timestamp with time zone,
  sent_by uuid references auth.users(id) on delete set null,
  constraint whatsapp_outbox_kind_check check (kind in ('invoice','receipt','delivery','reminder','statement','custom')),
  constraint whatsapp_outbox_status_check check (status in ('pending','sent','skipped')),
  constraint whatsapp_outbox_document_check check (document_type is null or document_type in ('invoice','statement','receipt')),
  constraint whatsapp_outbox_dedupe_key unique (company_id, dedupe_key)
);

create index whatsapp_outbox_pending_idx on public.whatsapp_outbox using btree (company_id, status, created_at desc);

alter table public.whatsapp_outbox enable row level security;

create policy whatsapp_outbox_read on public.whatsapp_outbox
  for select to authenticated
  using (public.has_any_permission(company_id, array['traders.view'::text, 'orders.view'::text]));

-- القوالب الافتراضية. المتغيّرات: {الاسم} {الرقم} {المبلغ} {الباقي} {الشركة} {السائق} {الشهر}
create or replace function public.whatsapp_default_template(target_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case target_kind
    when 'invoice' then E'مرحبا {الاسم}،\nهي فاتورتك رقم {الرقم} بقيمة {المبلغ}.\nشكرًا لتعاملك معنا 🌷\n{الشركة}'
    when 'receipt' then E'مرحبا {الاسم}،\nاستلمنا منك {المبلغ}، شكرًا إلك.\nرصيدك الحالي: {الباقي}.\n{الشركة}'
    when 'delivery' then E'مرحبا {الاسم}،\nطلبيتك رقم {الرقم} طلعت بالطريق إليك{السائق}.\n{الشركة}'
    when 'reminder' then E'مرحبا {الاسم}،\nتذكير لطيف: عليك رصيد {الباقي}، منو {المبلغ} متأخر.\nمنشكر تعاونك 🌷\n{الشركة}'
    when 'statement' then E'مرحبا {الاسم}،\nهاد كشف حسابك لغاية {الشهر}. الرصيد: {الباقي}.\n{الشركة}'
    else '{الاسم}'
  end;
$function$;

create or replace function public.render_whatsapp_message(target_company uuid, target_kind text, vars jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_text text;
  v_key text;
begin
  select coalesce(nullif(trim(c.whatsapp_templates->>target_kind), ''), public.whatsapp_default_template(target_kind))
  into v_text
  from public.companies c
  where c.id = target_company;

  for v_key in select jsonb_object_keys(vars) loop
    v_text := replace(v_text, '{' || v_key || '}', coalesce(vars->>v_key, ''));
  end loop;

  return v_text;
end;
$function$;

-- بيحط رسالة بالصندوق (إذا نوعها مفعّل، ومرة وحدة لكل حدث).
create or replace function public.enqueue_whatsapp(target_company uuid, target_kind text, target_trader uuid, target_dedupe text, vars jsonb, target_document_type text DEFAULT NULL::text, target_document_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_trader record;
  v_enabled boolean;
begin
  select coalesce((whatsapp_settings->>target_kind)::boolean, true)
  into v_enabled
  from public.companies
  where id = target_company;

  if not coalesce(v_enabled, false) then
    return;
  end if;

  select id, name, coalesce(nullif(whatsapp, ''), phone) as phone
  into v_trader
  from public.traders
  where id = target_trader;

  -- زبون البيع السريع بدون اسم ما إلو محادثة.
  if v_trader.id is null or v_trader.name = 'زبون نقدي' then
    return;
  end if;

  insert into public.whatsapp_outbox(company_id, kind, trader_id, phone, message, document_type, document_id, dedupe_key)
  values (
    target_company, target_kind, v_trader.id, v_trader.phone,
    public.render_whatsapp_message(
      target_company, target_kind,
      jsonb_build_object('الاسم', v_trader.name, 'الشركة', (select name from public.companies where id = target_company)) || vars
    ),
    target_document_type, target_document_id, target_dedupe
  )
  on conflict (company_id, dedupe_key) do nothing;
end;
$function$;

create or replace function public.whatsapp_money(target_amount numeric, target_currency text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select to_char(round(coalesce(target_amount, 0), 2), 'FM999,999,999,990.00') || ' ' || coalesce(target_currency, '');
$function$;

-- رصيد الزبون الحالي (فواتير مفتوحة ناقص رصيدو الدائن) بعملة الشركة.
create or replace function public.trader_balance_text(target_company uuid, target_trader uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.whatsapp_money(
    coalesce((select sum(public.finance_to_base(target_company, si.currency, si.balance_due, si.invoice_date))
              from public.sales_invoices si
              where si.trader_id = target_trader and si.status = 'posted'), 0)
    - coalesce((select sum(p.unallocated_total) from public.customer_payments p
                where p.trader_id = target_trader and p.status = 'posted'), 0),
    (select default_currency from public.companies where id = target_company)
  );
$function$;

create or replace function public.whatsapp_on_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'posted' then
    perform public.enqueue_whatsapp(
      new.company_id, 'invoice', new.trader_id, 'invoice:' || new.id,
      jsonb_build_object('الرقم', new.invoice_number, 'المبلغ', public.whatsapp_money(new.total, new.currency)),
      'invoice', new.id
    );
  end if;
  return new;
end;
$function$;

create or replace function public.whatsapp_on_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'posted' then
    perform public.enqueue_whatsapp(
      new.company_id, 'receipt', new.trader_id, 'receipt:' || new.id,
      jsonb_build_object(
        'الرقم', new.payment_number,
        'المبلغ', public.whatsapp_money(new.amount, coalesce(new.payment_currency, (select currency from public.cashboxes where id = new.cashbox_id))),
        'الباقي', public.trader_balance_text(new.company_id, new.trader_id)
      ),
      'receipt', new.id
    );
  end if;
  return new;
end;
$function$;

create or replace function public.whatsapp_on_delivery()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order record;
  v_driver text;
begin
  if new.status <> 'out_for_delivery' then
    return new;
  end if;

  select so.trader_id, so.order_number into v_order from public.sales_orders so where so.id = new.order_id;
  select ' مع السائق ' || full_name into v_driver from public.employees where id = new.driver_id;

  if tg_op = 'INSERT' then
    perform public.enqueue_whatsapp(
      new.company_id, 'delivery', v_order.trader_id, 'delivery:' || new.id,
      jsonb_build_object('الرقم', coalesce(v_order.order_number, ''), 'السائق', coalesce(v_driver, ''))
    );
  elsif new.driver_id is distinct from old.driver_id then
    -- تعيّن السائق بعدين: منحدّث الرسالة إذا لسا ما انبعتت.
    update public.whatsapp_outbox
    set message = public.render_whatsapp_message(
          new.company_id, 'delivery',
          jsonb_build_object(
            'الاسم', (select name from public.traders where id = v_order.trader_id),
            'الشركة', (select name from public.companies where id = new.company_id),
            'الرقم', coalesce(v_order.order_number, ''),
            'السائق', coalesce(v_driver, '')
          )
        )
    where company_id = new.company_id and dedupe_key = 'delivery:' || new.id and status = 'pending';
  end if;

  return new;
end;
$function$;

create trigger whatsapp_on_invoice after insert on public.sales_invoices for each row execute function public.whatsapp_on_invoice();
create trigger whatsapp_on_payment after insert on public.customer_payments for each row execute function public.whatsapp_on_payment();
create trigger whatsapp_on_delivery after insert or update of driver_id on public.deliveries for each row execute function public.whatsapp_on_delivery();

-- التذكير بالديون وكشوف أول الشهر: بتنجهّز لما تنفتح صفحة الرسائل.
create or replace function public.refresh_whatsapp_outbox(target_company uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row record;
  v_today date := (now() at time zone 'Asia/Damascus')::date;
  v_days integer;
  v_before integer;
  v_after integer;
  v_currency text;
begin
  if not public.has_any_permission(target_company, array['traders.view','orders.view']) then
    raise exception 'Not allowed';
  end if;

  select count(*) into v_before from public.whatsapp_outbox where company_id = target_company;
  select default_currency, coalesce((whatsapp_settings->>'reminder_days')::integer, 7)
  into v_currency, v_days
  from public.companies where id = target_company;

  -- تذكير: زبون عندو فواتير متأخرة، مرة كل كم يوم.
  for v_row in
    select si.trader_id,
           sum(public.finance_to_base(target_company, si.currency, si.balance_due, si.invoice_date)) as overdue
    from public.sales_invoices si
    where si.company_id = target_company and si.status = 'posted'
      and si.balance_due > 0 and si.due_date < v_today
    group by si.trader_id
  loop
    perform public.enqueue_whatsapp(
      target_company, 'reminder', v_row.trader_id,
      'reminder:' || v_row.trader_id || ':' || ((v_today - date '2000-01-01') / greatest(v_days, 1))::text,
      jsonb_build_object('المبلغ', public.whatsapp_money(v_row.overdue, v_currency),
                         'الباقي', public.trader_balance_text(target_company, v_row.trader_id))
    );
  end loop;

  -- كشف حساب شهري لكل زبون عليه رصيد.
  for v_row in
    select distinct si.trader_id
    from public.sales_invoices si
    where si.company_id = target_company and si.status = 'posted' and si.balance_due > 0
  loop
    perform public.enqueue_whatsapp(
      target_company, 'statement', v_row.trader_id,
      'statement:' || v_row.trader_id || ':' || to_char(v_today, 'YYYY-MM'),
      jsonb_build_object('الشهر', to_char(v_today, 'YYYY-MM-DD'),
                         'الباقي', public.trader_balance_text(target_company, v_row.trader_id)),
      'statement', v_row.trader_id
    );
  end loop;

  select count(*) into v_after from public.whatsapp_outbox where company_id = target_company;
  return v_after - v_before;
end;
$function$;

create or replace function public.mark_whatsapp_outbox(target_company uuid, target_message uuid, target_status text, target_text text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(target_company, array['traders.view','orders.view']) then
    raise exception 'Not allowed';
  end if;

  if target_status not in ('pending','sent','skipped') then
    raise exception 'Invalid status';
  end if;

  update public.whatsapp_outbox
  set status = target_status,
      message = coalesce(nullif(trim(target_text), ''), message),
      sent_at = case when target_status = 'sent' then now() end,
      sent_by = case when target_status = 'sent' then auth.uid() end
  where id = target_message and company_id = target_company;
end;
$function$;

-- رسالة يدوية لأي زبون (من صفحة الزبون مثلًا).
create or replace function public.add_whatsapp_message(target_company uuid, target_trader uuid, target_text text, target_document_type text DEFAULT NULL::text, target_document_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.has_any_permission(target_company, array['traders.view','orders.view']) then
    raise exception 'Not allowed';
  end if;

  insert into public.whatsapp_outbox(company_id, kind, trader_id, phone, message, document_type, document_id, dedupe_key)
  select target_company, 'custom', t.id, coalesce(nullif(t.whatsapp, ''), t.phone), trim(target_text),
         target_document_type, target_document_id, 'custom:' || gen_random_uuid()
  from public.traders t
  where t.id = target_trader and t.company_id = target_company
  returning id into v_id;

  return v_id;
end;
$function$;


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

-- دوال داخلية: بتشتغل من المشغّلات بس. ما لازم أي مستخدم يناديها مباشرة
-- (وإلا بيقدر يحط رسائل بصندوق شركة تانية أو يعرف رصيد زبون عند شركة تانية).
revoke execute on function public.enqueue_whatsapp(uuid, text, uuid, text, jsonb, text, uuid) from authenticated;
revoke execute on function public.trader_balance_text(uuid, uuid) from authenticated;
revoke execute on function public.render_whatsapp_message(uuid, text, jsonb) from authenticated;
revoke execute on function public.whatsapp_money(numeric, text) from authenticated;
revoke execute on function public.whatsapp_default_template(text) from authenticated;
