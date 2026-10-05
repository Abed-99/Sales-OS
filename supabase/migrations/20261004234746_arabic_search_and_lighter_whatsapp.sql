SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.get_delivery_queue (
  target_company uuid,
  target_search  text    DEFAULT NULL::text,
  target_status  text    DEFAULT NULL::text,
  target_limit   integer DEFAULT 50,
  target_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
declare
  v_search text;
  v_status text;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_rows jsonb;
begin
  if not public.has_any_permission(
    target_company,
    array[
      'deliveries.view',
      'deliveries.update'
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

  v_status :=
    case
      when target_status in (
        'ready',
        'out_for_delivery'
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

  select
    count(*)::bigint

  into
    v_total

  from public.sales_orders so

  join public.traders t
    on t.id =
       so.trader_id

  where so.company_id =
        target_company

    and so.status in (
      'ready',
      'out_for_delivery'
    )

    and (
      v_status is null
      or so.status =
         v_status
    )

    and (
      v_search is null

      or public.search_match(t.search_key, v_search)

      or coalesce(
           t.phone,
           ''
         ) ilike
         '%' || v_search || '%'

      or coalesce(
           t.whatsapp,
           ''
         ) ilike
         '%' || v_search || '%'

      or public.search_match(t.area, v_search)

      or so.id::text ilike
         '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
    );

  select
    coalesce(
      jsonb_agg(
        row_data
        order by
          sort_date,
          sort_created
      ),
      '[]'::jsonb
    )

  into
    v_rows

  from (
    select
      coalesce(
        so.ordered_at,
        so.created_at
      ) as sort_date,

      so.created_at as sort_created,

      jsonb_build_object(
        'id',
          so.id,

        'order_number',
          so.order_number,

        'status',
          so.status,

        'payment_status',
          so.payment_status,

        'total',
          so.total,

        'created_at',
          so.created_at,

        'ordered_at',
          so.ordered_at,

        -- التوصيلة المفتوحة وسائقها (إذا في).
        'delivery',
          (
            select jsonb_build_object('id', d.id, 'driver_id', d.driver_id)
            from public.deliveries d
            where d.order_id = so.id
              and d.status in ('pending', 'out_for_delivery')
            order by d.created_at desc
            limit 1
          ),

        'trader',
          jsonb_build_object(
            'id',
              t.id,

            'name',
              t.name,

            'area',
              t.area,

            'address',
              t.address,

            'phone',
              t.phone,

            'whatsapp',
              t.whatsapp,

            'latitude',
              t.latitude,

            'longitude',
              t.longitude
          ),

        'items',
          coalesce(
            items.payload,
            '[]'::jsonb
          )
      ) as row_data

    from public.sales_orders so

    join public.traders t
      on t.id =
         so.trader_id

    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'id',
              soi.id,

            'product_id',
              soi.product_id,

            'quantity',
              soi.quantity,

            'sale_unit_price',
              soi.sale_unit_price,

            'product_name',
              p.name,

            'sku',
              p.sku,

            'unit',
              p.unit,

            'delivered_quantity',
              coalesce(
                delivered.qty,
                0
              ),

            'active_quantity',
              coalesce(
                active.qty,
                0
              ),

            'remaining_quantity',
              greatest(
                soi.quantity -
                coalesce(
                  delivered.qty,
                  0
                ) -
                coalesce(
                  active.qty,
                  0
                ),
                0
              )
          )
          order by
            soi.created_at
        ) as payload

      from public.sales_order_items soi

      join public.products p
        on p.id =
           soi.product_id

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'delivered'
      ) delivered
        on true

      left join lateral (
        select
          coalesce(
            sum(di.quantity),
            0
          ) as qty

        from public.delivery_items di

        join public.deliveries d
          on d.id =
             di.delivery_id

        where di.sales_order_item_id =
              soi.id

          and d.status =
              'out_for_delivery'
      ) active
        on true

      where soi.order_id =
            so.id
    ) items
      on true

    where so.company_id =
          target_company

      and so.status in (
        'ready',
        'out_for_delivery'
      )

      and (
        v_status is null
        or so.status =
           v_status
      )

      and (
        v_search is null

        or public.search_match(t.search_key, v_search)

        or coalesce(
             t.phone,
             ''
           ) ilike
           '%' || v_search || '%'

        or coalesce(
             t.whatsapp,
             ''
           ) ilike
           '%' || v_search || '%'

        or public.search_match(t.area, v_search)

        or so.id::text ilike
           '%' || v_search || '%'
      or coalesce(so.order_number, '') ilike '%' || v_search || '%'
      )

    order by
      coalesce(
        so.ordered_at,
        so.created_at
      ),
      so.created_at

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
$function$;

CREATE OR REPLACE FUNCTION public.get_purchase_return_candidates (
  target_company uuid,
  target_search  text    DEFAULT NULL::text,
  target_limit   integer DEFAULT 50,
  target_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
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

      or public.search_match(s.search_key, v_search)

      or exists (
        select 1
        from public.purchase_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = pi.id
          and public.search_match(pr.search_key, v_search)
      )
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

        or public.search_match(s.search_key, v_search)

        or exists (
          select 1
          from public.purchase_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = pi.id
            and public.search_match(pr.search_key, v_search)
        )
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
$function$;

CREATE OR REPLACE FUNCTION public.get_returns_history (
  target_company uuid,
  target_search  text    DEFAULT NULL::text,
  target_kind    text    DEFAULT NULL::text,
  target_status  text    DEFAULT NULL::text,
  target_limit   integer DEFAULT 50,
  target_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
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

      or public.search_match(h.party_name, v_search)

      or exists (
        select 1
        from public.sales_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'sales'
          and x.sales_return_id = h.id
          and public.search_match(pr.search_key, v_search)
      )

      or exists (
        select 1
        from public.purchase_return_items x
        join public.products pr on pr.id = x.product_id
        where h.kind = 'purchases'
          and x.purchase_return_id = h.id
          and public.search_match(pr.search_key, v_search)
      )
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

        or public.search_match(h.party_name, v_search)

        or exists (
          select 1
          from public.sales_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'sales'
            and x.sales_return_id = h.id
            and public.search_match(pr.search_key, v_search)
        )

        or exists (
          select 1
          from public.purchase_return_items x
          join public.products pr on pr.id = x.product_id
          where h.kind = 'purchases'
            and x.purchase_return_id = h.id
            and public.search_match(pr.search_key, v_search)
        )
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
$function$;

CREATE OR REPLACE FUNCTION public.get_sales_return_candidates (
  target_company uuid,
  target_search  text    DEFAULT NULL::text,
  target_limit   integer DEFAULT 50,
  target_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
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

      or public.search_match(t.search_key, v_search)

      or exists (
        select 1
        from public.sales_orders so
        where so.id = si.order_id
          and so.order_number ilike '%' || v_search || '%'
      )

      or exists (
        select 1
        from public.sales_invoice_items x
        join public.products pr on pr.id = x.product_id
        where x.invoice_id = si.id
          and public.search_match(pr.search_key, v_search)
      )
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

        or public.search_match(t.search_key, v_search)

        or exists (
          select 1
          from public.sales_orders so
          where so.id = si.order_id
            and so.order_number ilike '%' || v_search || '%'
        )

        or exists (
          select 1
          from public.sales_invoice_items x
          join public.products pr on pr.id = x.product_id
          where x.invoice_id = si.id
            and public.search_match(pr.search_key, v_search)
        )
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
$function$;

CREATE OR REPLACE FUNCTION public.normalize_search (
  target_text text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO ''
  AS $function$
  select trim(regexp_replace(
    translate(
      lower(coalesce(target_text, '')),
      'أإآٱةىؤئًٌٍَُِّْـ',
      'ااااهيوي'
    ),
    '\s+', ' ', 'g'
  ));
$function$;

REVOKE ALL ON FUNCTION "public"."normalize_search"(text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.refresh_whatsapp_outbox (
  target_company uuid
)
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
      and coalesce((select (c.whatsapp_settings->>'reminder')::boolean from public.companies c where c.id = target_company), true)
      -- الزبون يلي رسالتو جاهزة من قبل ما منرجع نحسبلو (هالدالة بتشتغل مع كل فتحة صفحة).
      and not exists (
        select 1 from public.whatsapp_outbox o
        where o.company_id = target_company
          and o.dedupe_key = 'reminder:' || si.trader_id || ':' || ((v_today - date '2000-01-01') / greatest(v_days, 1))::text
      )
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
      and coalesce((select (c.whatsapp_settings->>'statement')::boolean from public.companies c where c.id = target_company), true)
      and not exists (
        select 1 from public.whatsapp_outbox o
        where o.company_id = target_company
          and o.dedupe_key = 'statement:' || si.trader_id || ':' || to_char(v_today, 'YYYY-MM')
      )
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

CREATE OR REPLACE FUNCTION public.sales_quote_matches (
  target_quote  uuid,
  target_search text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  -- البحث بعروض الأسعار بكل شي: رقم العرض، الزبون (اسم، منطقة، هاتف)، الملاحظات،
  -- المبلغ، أو اسم/كود/ماركة صنف موجود بالعرض.
  select exists (
    select 1
    from public.sales_quotes q
    join public.traders t on t.id = q.trader_id
    where q.id = target_quote
      and (
        q.quote_number ilike '%' || target_search || '%'
        or public.search_match(t.search_key, target_search)
        or public.search_match(t.area, target_search)
        or coalesce(t.phone, '') ilike '%' || target_search || '%'
        or coalesce(t.whatsapp, '') ilike '%' || target_search || '%'
        or coalesce(q.notes, '') ilike '%' || target_search || '%'
        or q.total = case
          when replace(target_search, ',', '') ~ '^[0-9]+([.][0-9]+)?$'
            then replace(target_search, ',', '')::numeric
        end
        or exists (
          select 1
          from public.sales_quote_items qi
          join public.products p on p.id = qi.product_id
          where qi.quote_id = q.id
            and (
              public.search_match(p.search_key, target_search)
              or public.search_match(p.sku, target_search)
              or public.search_match(p.brand, target_search)
            )
        )
      )
  )
$function$;

CREATE OR REPLACE FUNCTION public.search_match (
  target_text   text,
  target_search text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO ''
  AS $function$
  select coalesce(bool_and(strpos(public.normalize_search(target_text), word) > 0), true)
  from unnest(string_to_array(public.normalize_search(target_search), ' ')) as word
  where word <> '';
$function$;

REVOKE ALL ON FUNCTION "public"."search_match"(text, text) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."normalize_search"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."normalize_search"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."normalize_search"(text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."normalize_search"(text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."search_match"(text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."search_match"(text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_match"(text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_match"(text, text) TO "service_role";

ALTER TABLE "public"."products"
  ADD COLUMN "search_key" text GENERATED ALWAYS AS
    (public.normalize_search(((((((name || ' '::text) || COALESCE(sku, ''::text)) || ' '::text) || COALESCE(brand, ''::text)) || ' '::text) || COALESCE(barcode, ''::text)))) STORED;

ALTER TABLE "public"."suppliers"
  ADD COLUMN "search_key" text GENERATED ALWAYS AS
    (public.normalize_search(((((name || ' '::text) || COALESCE(contact_name, ''::text)) || ' '::text) || COALESCE(country, ''::text)))) STORED;

ALTER TABLE "public"."traders"
  ADD COLUMN "search_key" text GENERATED ALWAYS AS
    (public.normalize_search(((((((name || ' '::text) || COALESCE(contact_name, ''::text)) || ' '::text) || COALESCE(area, ''::text)) || ' '::text) || COALESCE(address,
    ''::text)))) STORED;
