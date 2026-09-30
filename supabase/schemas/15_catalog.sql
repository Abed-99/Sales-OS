-- ======================================================================
-- كتالوج البضاعة للتجار: رابط بينبعت للتاجر، بيفتحو بدون تسجيل دخول.
-- كل رابط إلو إعداداته: مع سعر أو بلا، أي مستوى سعر، مع شرح وصور، وكيف يبين المخزون.
-- الكلفة ما بتطلع أبدًا. الطلب من الكتالوج خيار (مطفي افتراضيًا): التاجر بيحط رقمو،
-- ولازم يكون مسجّل عنا، وبينزل الطلب كعرض سعر مسودة لنراجعو.
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الجداول
-- ----------------------------------------------------------------------

create table public.catalog_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  -- الرمز اللي بالرابط. عشوائي وطويل، ما بينخمّن.
  token text default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') not null,
  title text not null,
  -- رابط خاص لتاجر معيّن (اختياري). إذا موجود، الطلب بيقبل رقمو بس.
  trader_id uuid references public.traders(id) on delete cascade,
  show_prices boolean default true not null,
  -- فاضي = سعر البيع العادي.
  price_level_id uuid references public.price_levels(id) on delete set null,
  show_description boolean default true not null,
  show_images boolean default true not null,
  -- hidden: ما بيبين شي، available: متوفر/غير متوفر، quantity: مع الكمية.
  stock_mode text default 'available'::text not null,
  hide_out_of_stock boolean default false not null,
  -- فاضي = كل التصنيفات.
  category_ids uuid[],
  allow_orders boolean default false not null,
  active boolean default true not null,
  expires_at timestamp with time zone,
  view_count integer default 0 not null,
  last_viewed_at timestamp with time zone,
  -- حماية من تجريب أرقام تلفونات كتير على نفس الرابط.
  failed_attempts integer default 0 not null,
  failed_window_start timestamp with time zone,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint catalog_links_token_key unique (token),
  constraint catalog_links_stock_mode_check check (stock_mode in ('hidden','available','quantity')),
  constraint catalog_links_title_check check (length(btrim(title)) between 1 and 120)
);
create index catalog_links_company_idx on public.catalog_links using btree (company_id, created_at desc);

alter table public.sales_quotes
  add constraint sales_quotes_catalog_link_fk foreign key (catalog_link_id) references public.catalog_links(id) on delete set null;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

-- إنشاء أو تعديل رابط كتالوج.
create or replace function public.save_catalog_link(target_company uuid, target_link uuid, settings jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_link uuid;
  v_trader uuid := nullif(settings->>'trader_id', '')::uuid;
  v_level uuid := nullif(settings->>'price_level_id', '')::uuid;
  v_categories uuid[];
  v_title text := nullif(btrim(settings->>'title'), '');
  v_stock text := coalesce(nullif(settings->>'stock_mode', ''), 'available');
  v_expires timestamptz := nullif(settings->>'expires_at', '')::timestamptz;
begin
  if not public.has_any_permission(target_company, array['orders.create','products.update']) then
    raise exception 'Not allowed';
  end if;

  if v_trader is not null and not exists (
    select 1 from public.traders where id = v_trader and company_id = target_company
  ) then
    raise exception 'Invalid trader';
  end if;

  if v_level is not null and not exists (
    select 1 from public.price_levels where id = v_level and company_id = target_company
  ) then
    raise exception 'Invalid price level';
  end if;

  if jsonb_typeof(settings->'category_ids') = 'array' and jsonb_array_length(settings->'category_ids') > 0 then
    select array_agg(c.id) into v_categories
    from public.categories c
    where c.company_id = target_company
      and c.id in (select (x #>> '{}')::uuid from jsonb_array_elements(settings->'category_ids') x);
  end if;

  if v_title is null then
    v_title := coalesce((select 'كتالوج ' || name from public.traders where id = v_trader), 'كتالوج البضاعة');
  end if;

  if target_link is null then
    insert into public.catalog_links(
      company_id, title, trader_id, show_prices, price_level_id, show_description, show_images,
      stock_mode, hide_out_of_stock, category_ids, allow_orders, expires_at
    ) values (
      target_company, left(v_title, 120), v_trader,
      coalesce((settings->>'show_prices')::boolean, true), v_level,
      coalesce((settings->>'show_description')::boolean, true),
      coalesce((settings->>'show_images')::boolean, true),
      v_stock, coalesce((settings->>'hide_out_of_stock')::boolean, false), v_categories,
      coalesce((settings->>'allow_orders')::boolean, false), v_expires
    ) returning id into v_link;
  else
    update public.catalog_links
    set title = left(v_title, 120),
        trader_id = v_trader,
        show_prices = coalesce((settings->>'show_prices')::boolean, true),
        price_level_id = v_level,
        show_description = coalesce((settings->>'show_description')::boolean, true),
        show_images = coalesce((settings->>'show_images')::boolean, true),
        stock_mode = v_stock,
        hide_out_of_stock = coalesce((settings->>'hide_out_of_stock')::boolean, false),
        category_ids = v_categories,
        allow_orders = coalesce((settings->>'allow_orders')::boolean, false),
        expires_at = v_expires,
        updated_at = now()
    where id = target_link and company_id = target_company
    returning id into v_link;

    if v_link is null then
      raise exception 'Catalog link not found';
    end if;
  end if;

  return v_link;
end;
$function$;

create or replace function public.set_catalog_link_active(target_company uuid, target_link uuid, target_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_any_permission(target_company, array['orders.create','products.update']) then
    raise exception 'Not allowed';
  end if;

  update public.catalog_links
  set active = coalesce(target_active, false), updated_at = now()
  where id = target_link and company_id = target_company;

  if not found then
    raise exception 'Catalog link not found';
  end if;
end;
$function$;

-- الأصناف اللي بتطلع برابط معيّن، مع السعر والمخزون حسب إعداداته. داخلية (ما بتنادى من برّا).
create or replace function public.catalog_link_products(target_link uuid)
 RETURNS TABLE(product_id uuid, name text, brand text, sku text, unit text, pack_size numeric, pack_unit text,
               category_id uuid, image_url text, description text, price numeric, available numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with l as (
    select * from public.catalog_links where id = target_link
  ),
  stock as (
    select s.product_id, sum(s.on_hand) as on_hand
    from public.inventory_stock s
    join public.warehouses w on w.id = s.warehouse_id and w.active
    where s.company_id = (select company_id from l)
    group by s.product_id
  ),
  reserved as (
    select r.product_id, sum(r.quantity) as quantity
    from public.inventory_reservations r
    where r.company_id = (select company_id from l) and r.status = 'active'
    group by r.product_id
  )
  select p.id, p.name, p.brand, p.sku, p.unit, p.pack_size, p.pack_unit, p.category_id,
         case when l.show_images then p.image_url end,
         case when l.show_description then p.description end,
         case when l.show_prices then coalesce(lp.price, p.sale_price) end,
         greatest(coalesce(st.on_hand, 0) - coalesce(rs.quantity, 0), 0)
  from l
  join public.products p on p.company_id = l.company_id and p.active
  left join public.product_level_prices lp on lp.product_id = p.id and lp.price_level_id = l.price_level_id
  left join stock st on st.product_id = p.id
  left join reserved rs on rs.product_id = p.id
  where (l.category_ids is null or p.category_id = any(l.category_ids))
    and (not l.hide_out_of_stock or coalesce(st.on_hand, 0) - coalesce(rs.quantity, 0) > 0);
$function$;

-- الكتالوج للزائر (بدون تسجيل دخول). الرمز غلط أو الرابط موقوف = null.
create or replace function public.get_public_catalog(target_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_link public.catalog_links;
  v_company public.companies;
  v_result jsonb;
begin
  if target_token is null or length(target_token) < 32 or length(target_token) > 80 then
    return null;
  end if;

  select * into v_link from public.catalog_links
  where token = target_token and active and (expires_at is null or expires_at > now());

  if not found then
    return null;
  end if;

  select * into v_company from public.companies where id = v_link.company_id;

  update public.catalog_links
  set view_count = view_count + 1, last_viewed_at = now()
  where id = v_link.id;

  select jsonb_build_object(
    'company', jsonb_build_object(
      'name', v_company.name, 'logo_url', v_company.logo_url, 'phone', v_company.phone,
      'whatsapp', v_company.whatsapp, 'address', v_company.address, 'currency', v_company.default_currency
    ),
    'link', jsonb_build_object(
      'title', v_link.title,
      'trader_name', (select name from public.traders where id = v_link.trader_id),
      'show_prices', v_link.show_prices, 'show_description', v_link.show_description,
      'show_images', v_link.show_images, 'stock_mode', v_link.stock_mode,
      'allow_orders', v_link.allow_orders
    ),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.categories c
      where c.company_id = v_link.company_id
        and exists (select 1 from public.catalog_link_products(v_link.id) x where x.category_id = c.id)
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.product_id, 'name', x.name, 'brand', x.brand, 'sku', x.sku, 'unit', x.unit,
        'pack_size', x.pack_size, 'pack_unit', x.pack_unit, 'category_id', x.category_id,
        'image_url', x.image_url, 'description', x.description, 'price', x.price,
        'in_stock', case when v_link.stock_mode = 'hidden' then null else x.available > 0 end,
        'quantity', case when v_link.stock_mode = 'quantity' then x.available end
      ) order by x.name)
      from public.catalog_link_products(v_link.id) x
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- التاجر بيطلب من الكتالوج: لازم رقمو يكون مسجّل عنا. الطلب بينزل عرض سعر مسودة.
create or replace function public.submit_catalog_order(target_token text, target_phone text, items_payload jsonb, target_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_link public.catalog_links;
  v_phone text := regexp_replace(coalesce(target_phone, ''), '[\s\-()]', '', 'g');
  v_trader public.traders;
  v_quote uuid;
  v_number text;
  v_currency text;
  v_item jsonb;
  v_product uuid;
  v_quantity numeric(18,3);
  v_price numeric(18,4);
  v_total numeric(18,2) := 0;
  v_today date := (now() at time zone 'Asia/Damascus')::date;
begin
  select * into v_link from public.catalog_links
  where token = target_token and active and allow_orders and (expires_at is null or expires_at > now())
  for update;

  if not found then
    raise exception 'Catalog ordering is not available';
  end if;

  -- أكتر من 10 محاولات غلط بالساعة على نفس الرابط = وقف مؤقت.
  if v_link.failed_window_start is not null
     and v_link.failed_window_start > now() - interval '1 hour'
     and v_link.failed_attempts >= 10 then
    raise exception 'Too many attempts';
  end if;

  -- نفس توحيد الأرقام اللي بالبرنامج: 09xxxxxxxx أو 00963 بتصير +963.
  if v_phone ~ '^09\d{8}$' then
    v_phone := '+963' || substr(v_phone, 2);
  elsif v_phone ~ '^00\d+$' then
    v_phone := '+' || substr(v_phone, 3);
  end if;

  select * into v_trader from public.traders t
  where t.company_id = v_link.company_id
    and t.status <> 'inactive'
    and v_phone <> ''
    and (t.phone = v_phone or t.whatsapp = v_phone)
    and (v_link.trader_id is null or t.id = v_link.trader_id)
  limit 1;

  if not found then
    update public.catalog_links
    set failed_attempts = case when failed_window_start is null or failed_window_start <= now() - interval '1 hour'
                               then 1 else failed_attempts + 1 end,
        failed_window_start = case when failed_window_start is null or failed_window_start <= now() - interval '1 hour'
                                   then now() else failed_window_start end
    where id = v_link.id;
    -- الرد بيرجع عادي (مش خطأ) مشان تنحفظ المحاولة الغلط.
    return jsonb_build_object('ok', false, 'reason', 'unknown_phone');
  end if;

  if (select count(*) from public.sales_quotes
      where company_id = v_link.company_id and trader_id = v_trader.id
        and source = 'catalog' and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Too many catalog orders today';
  end if;

  if items_payload is null or jsonb_typeof(items_payload) <> 'array'
     or jsonb_array_length(items_payload) = 0 or jsonb_array_length(items_payload) > 200 then
    raise exception 'Order must contain items';
  end if;

  if exists (
    select 1 from jsonb_array_elements(items_payload) x group by x->>'product_id' having count(*) > 1
  ) then
    raise exception 'Duplicate products are not allowed';
  end if;

  select coalesce(default_currency, 'USD') into v_currency from public.companies where id = v_link.company_id;
  v_number := public.next_sales_quote_number(v_link.company_id, v_today);

  insert into public.sales_quotes(
    company_id, trader_id, quote_number, quote_date, status, currency, notes, source, catalog_link_id, created_by
  ) values (
    v_link.company_id, v_trader.id, v_number, v_today, 'draft', v_currency,
    nullif(left(btrim(coalesce(target_notes, '')), 500), ''), 'catalog', v_link.id, null
  ) returning id into v_quote;

  for v_item in select value from jsonb_array_elements(items_payload) loop
    begin
      v_product := (v_item->>'product_id')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
    exception when others then
      raise exception 'Invalid order item';
    end;

    if v_quantity is null or v_quantity <= 0 or v_quantity > 1000000 then
      raise exception 'Invalid order quantity';
    end if;

    -- لازم الصنف يكون من أصناف هاد الرابط.
    if not exists (select 1 from public.catalog_link_products(v_link.id) x where x.product_id = v_product) then
      raise exception 'Invalid product';
    end if;

    -- السعر: سعر الرابط إذا بيبين أسعار، وإلا سعر مستوى التاجر.
    select coalesce(lp.price, p.sale_price, 0) into v_price
    from public.products p
    left join public.product_level_prices lp
      on lp.product_id = p.id
     and lp.price_level_id = case when v_link.show_prices then v_link.price_level_id else v_trader.price_level_id end
    where p.id = v_product;

    insert into public.sales_quote_items(
      quote_id, product_id, quantity, sale_unit_price, line_total, minimum_sale_price_snapshot, reference_cost_snapshot
    )
    select v_quote, p.id, v_quantity, v_price, round(v_quantity * v_price, 2), p.minimum_sale_price,
           public.product_reference_cost(v_link.company_id, p.id)
    from public.products p where p.id = v_product;

    v_total := v_total + round(v_quantity * v_price, 2);
  end loop;

  update public.sales_quotes set subtotal = v_total, total = v_total where id = v_quote;

  return jsonb_build_object('ok', true, 'quote_number', v_number, 'trader_name', v_trader.name);
end;
$function$;


-- ----------------------------------------------------------------------
-- الحماية (RLS)
-- ----------------------------------------------------------------------

alter table public.catalog_links enable row level security;

create policy catalog_links_read on public.catalog_links
  for select to authenticated
  using (public.has_any_permission(company_id, array['orders.create'::text, 'products.update'::text]));


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

-- التعديل بس عن طريق الدوال.
revoke insert, update, delete on public.catalog_links from authenticated;

revoke execute on function public.catalog_link_products(uuid) from authenticated;

-- الزائر (anon) بيقدر يشوف الكتالوج ويطلب منو، وبس.
grant execute on function public.get_public_catalog(text) to anon;
grant execute on function public.submit_catalog_order(text, text, jsonb, text) to anon;
