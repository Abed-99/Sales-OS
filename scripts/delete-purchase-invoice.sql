-- مسح فاتورة شراء نهائيًا بخطوة وحدة: بيعكس استلام بضاعتها (إذا انستلمت)، بيلغيها،
-- وبيمسحها هي واستلامها وحركات مخزونها وقيودها، وبيرجّع رقمها إذا كانت آخر فاتورة.
-- ما بيمسح إذا في دفعة أو مرتجع عليها، أو إذا بضاعتها انباعت أو انحجزت.
--
-- التشغيل: غيّر الرقم تحت، وبعدين Supabase → SQL Editor → الصق الملف كلّو → Run.

begin;

do $$
declare
  v_number text := 'PI-2026-000002';   -- ← رقم الفاتورة
  v_company uuid := null;              -- (للتجربة بس: شركة معيّنة)
  v_invoice record;
  v_receipts uuid[];
  v_movements uuid[];
  v_journals uuid[];
  v_last boolean;
  v_receipt uuid;
  v_receipt_numbers text[];
  v_journal_numbers text[];
  v_doc record;
  v_min bigint;
begin
  select * into v_invoice from public.purchase_invoices
  where invoice_number = v_number and (v_company is null or company_id = v_company);
  if not found then
    raise exception 'ما لقيت فاتورة بالرقم %', v_number;
  end if;
  if (select count(*) from public.purchase_invoices
      where invoice_number = v_number and (v_company is null or company_id = v_company)) > 1 then
    raise exception 'في أكتر من شركة فيها هالرقم، ما رح امسح شي';
  end if;
  if exists (select 1 from public.supplier_payment_allocations where purchase_invoice_id = v_invoice.id) then
    raise exception 'في دفعات مورد كانت موزّعة على هالفاتورة، ما رح امسحها';
  end if;
  if exists (select 1 from public.purchase_returns where purchase_invoice_id = v_invoice.id) then
    raise exception 'في مرتجع شراء على هالفاتورة، ما رح امسحها';
  end if;

  -- منشتغل باسم مالك الشركة، مشان دوال العكس والإلغاء تعدّي فحص الصلاحيات.
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', (select owner_user_id from public.companies where id = v_invoice.company_id), 'role', 'authenticated')::text,
    true
  );

  -- 1) عكس استلام البضاعة (بيرجّع المخزون متل ما كان).
  for v_receipt in
    select id from public.goods_receipts where purchase_invoice_id = v_invoice.id and status = 'posted'
  loop
    perform public.reverse_goods_receipt(v_invoice.company_id, v_receipt, 'مسح فاتورة شراء ' || v_number);
  end loop;

  -- 2) إلغاء الفاتورة (بيعكس قيدها ودين المورد).
  if v_invoice.status <> 'cancelled' then
    perform public.cancel_purchase_invoice(v_invoice.company_id, v_invoice.id, 'مسح فاتورة شراء ' || v_number);
  end if;

  -- 3) المسح النهائي.
  select coalesce(array_agg(id), '{}') into v_receipts
  from public.goods_receipts where purchase_invoice_id = v_invoice.id;

  -- حركات المخزون (الاستلام وعكسه)، والقيود تبعها وتبع الفاتورة، والقيود العاكسة.
  select coalesce(array_agg(id), '{}') into v_movements
  from public.inventory_movements
  where source_table in ('goods_receipts', 'goods_receipt_reversals') and source_id = any(v_receipts);

  select coalesce(array_agg(id), '{}') into v_journals
  from public.journal_entries
  where (source_type = 'purchase_invoice' and source_id = v_invoice.id)
     or (source_type = 'inventory_movement' and source_id = any(v_movements));

  select coalesce(array_agg(receipt_number), '{}') into v_receipt_numbers
  from public.goods_receipts where id = any(v_receipts);
  select coalesce(array_agg(entry_number), '{}') into v_journal_numbers
  from public.journal_entries where id = any(v_journals) or reversed_from_id = any(v_journals);

  delete from public.journal_entries where reversed_from_id = any(v_journals);
  delete from public.journal_entries where id = any(v_journals);
  delete from public.inventory_movements where id = any(v_movements);
  delete from public.goods_receipts where id = any(v_receipts);
  delete from public.purchase_invoices where id = v_invoice.id;

  -- الترقيم: إذا المحذوف كان آخر رقم (فاتورة، استلام، قيد)، الجاي بياخد رقمو.
  for v_doc in
    select * from (values
      ('purchase_invoice', 'purchase_invoices', 'invoice_number', array[v_number]),
      ('goods_receipt', 'goods_receipts', 'receipt_number', v_receipt_numbers),
      ('journal_entry', 'journal_entries', 'entry_number', v_journal_numbers)
    ) as t(doc_type, table_name, column_name, numbers)
  loop
    continue when coalesce(array_length(v_doc.numbers, 1), 0) = 0;
    select min(split_part(n, '-', 3)::bigint) into v_min from unnest(v_doc.numbers) as n;
    execute format(
      'select not exists (select 1 from public.%I where company_id = $1 and split_part(%I, ''-'', 2) = $2 and split_part(%I, ''-'', 3)::bigint >= $3)',
      v_doc.table_name, v_doc.column_name, v_doc.column_name
    ) into v_last using v_invoice.company_id, split_part(v_doc.numbers[1], '-', 2), v_min;
    if v_last then
      update public.document_sequences
      set next_value = v_min
      where company_id = v_invoice.company_id
        and document_type = v_doc.doc_type
        and sequence_year = split_part(v_doc.numbers[1], '-', 2)::integer;
    end if;
  end loop;

  raise notice 'انمسحت %.', v_number;
end;
$$;

-- تأكيد: القيود لازم تضل متوازنة (المدين = الدائن).
select round(sum(base_debit), 2) as "المدين", round(sum(base_credit), 2) as "الدائن" from public.journal_lines;

commit;
