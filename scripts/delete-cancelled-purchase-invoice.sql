-- مسح فاتورة شراء ملغية نهائيًا (مع استلامها وقيودها)، ورجوع الترقيم إذا كانت آخر فاتورة.
--
-- قبل: الغي الفاتورة من الشاشة (المشتريات ← إلغاء). إذا انستلمت بضاعتها، اعكس الاستلام أول.
-- التشغيل: غيّر الرقم تحت، وبعدين Supabase → SQL Editor → الصق → Run.

begin;

do $$
declare
  v_number text := 'PI-2026-000002';   -- ← رقم الفاتورة
  v_company uuid := null;              -- (للتجربة بس: شركة معيّنة)
  v_invoice record;
  v_receipts uuid[];
  v_movements uuid[];
  v_journals uuid[];
  v_seq_number bigint;
  v_last boolean;
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
  if v_invoice.status <> 'cancelled' then
    raise exception 'الفاتورة % مش ملغية. الغيها من الشاشة أول.', v_number;
  end if;
  if exists (select 1 from public.supplier_payment_allocations where purchase_invoice_id = v_invoice.id) then
    raise exception 'في دفعات مورد كانت موزّعة على هالفاتورة، ما رح امسحها';
  end if;
  if exists (select 1 from public.purchase_returns where purchase_invoice_id = v_invoice.id) then
    raise exception 'في مرتجع شراء على هالفاتورة، ما رح امسحها';
  end if;

  select coalesce(array_agg(id), '{}') into v_receipts
  from public.goods_receipts where purchase_invoice_id = v_invoice.id;
  if exists (select 1 from public.goods_receipts where id = any(v_receipts) and status <> 'cancelled') then
    raise exception 'في استلام بضاعة لهالفاتورة لسا ما انعكس';
  end if;

  -- حركات المخزون (الاستلام وعكسه)، والقيود تبعها وتبع الفاتورة، والقيود العاكسة.
  select coalesce(array_agg(id), '{}') into v_movements
  from public.inventory_movements
  where source_table in ('goods_receipts', 'goods_receipt_reversals') and source_id = any(v_receipts);

  select coalesce(array_agg(id), '{}') into v_journals
  from public.journal_entries
  where (source_type = 'purchase_invoice' and source_id = v_invoice.id)
     or (source_type = 'inventory_movement' and source_id = any(v_movements));

  delete from public.journal_entries where reversed_from_id = any(v_journals);
  delete from public.journal_entries where id = any(v_journals);
  delete from public.inventory_movements where id = any(v_movements);
  delete from public.goods_receipts where id = any(v_receipts);
  delete from public.purchase_invoices where id = v_invoice.id;

  -- الترقيم: إذا هي آخر فاتورة بسنتها، الفاتورة الجاية بتاخد رقمها.
  v_seq_number := split_part(v_number, '-', 3)::bigint;
  select not exists (
    select 1 from public.purchase_invoices
    where company_id = v_invoice.company_id
      and invoice_number like split_part(v_number, '-', 1) || '-' || split_part(v_number, '-', 2) || '-%'
      and split_part(invoice_number, '-', 3)::bigint > v_seq_number
  ) into v_last;

  if v_last then
    update public.document_sequences
    set next_value = v_seq_number
    where company_id = v_invoice.company_id
      and document_type = 'purchase_invoice'
      and sequence_year = split_part(v_number, '-', 2)::integer;
    raise notice 'انمسحت %، والفاتورة الجاية رح تاخد نفس الرقم.', v_number;
  else
    raise notice 'انمسحت %. في فواتير بعدها، فالترقيم ما تغيّر.', v_number;
  end if;
end;
$$;

-- تأكيد: القيود لازم تضل متوازنة (المدين = الدائن).
select round(sum(base_debit), 2) as "المدين", round(sum(base_credit), 2) as "الدائن" from public.journal_lines;

commit;
