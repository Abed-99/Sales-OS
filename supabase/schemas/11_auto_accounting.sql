-- ======================================================================
-- القيود التلقائية
-- كل عملية بيع أو شراء أو دفع أو حركة مخزون بتعمل قيدها المحاسبي لحالها
-- ======================================================================

set check_function_bodies = off;


-- ----------------------------------------------------------------------
-- الدوال
-- ----------------------------------------------------------------------

create or replace function public.gl_cash_movement_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cash uuid;
  v_other uuid;
  v_currency text;
  v_lines jsonb;
begin
  if new.partner_transaction_id is not null then
    return new;
  end if;

  if new.type not in (
    'partner_deposit',
    'partner_withdrawal',
    'adjustment_in',
    'adjustment_out'
  ) then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id = new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  if new.type = 'partner_deposit' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'capital'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'partner_withdrawal' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'partner_drawings'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  elsif new.type = 'adjustment_in' then

    v_other :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cash,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_other,
          'debit', 0,
          'credit', new.amount
        )
      );

  else

    v_other :=
      public.finance_system_account(
        new.company_id,
        'operating_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_other,
          'debit', new.amount,
          'credit', 0
        ),
        jsonb_build_object(
          'account_id', v_cash,
          'debit', 0,
          'credit', new.amount
        )
      );

  end if;

  perform public.post_system_journal(
    new.company_id,
    (new.occurred_at at time zone 'Asia/Damascus')::date,
    'حركة صندوق - ' || new.type,
    v_currency,
    null,
    'cash_transaction',
    new.id,
    v_lines
  );

  return new;
end;
$function$;

create or replace function public.gl_customer_allocation_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_trader uuid;
  v_payment_date date;
  v_cashbox uuid;
  v_currency text;
  v_payment_status text;

  v_advance uuid;
  v_ar uuid;
begin
  select
    company_id,
    trader_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_trader,
    v_payment_date,
    v_cashbox,
    v_payment_status
  from public.customer_payments
  where id =
        new.payment_id;

  if v_payment_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'customer_advances'
    );

  v_ar :=
    public.finance_system_account(
      v_company,
      'accounts_receivable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_payment_date,
      'تخصيص قبض على فاتورة بيع',
      -- الدفعة ممكن تكون بعملة غير عملة الفاتورة (مثلًا ليرة على فاتورة دولار)،
      -- فالقيد لازم ينكتب بمبلغ الدفعة وعملتها وسعر صرفها، مش بمبلغ الفاتورة.
      coalesce(new.payment_currency, v_currency),
      new.payment_rate_to_base,
      'customer_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          coalesce(new.payment_amount, new.amount),
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          v_trader
        ),
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          0,
          'credit',
          coalesce(new.payment_amount, new.amount),
          'party_type',
          'trader',
          'party_id',
          v_trader
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_customer_payment_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'customer_payment',
        new.id,
        new.payment_date,
        'عكس قبض عميل ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.customer_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'customer_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص قبض عميل'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'customer_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'قبض من عميل ' ||
      new.payment_number,
      v_currency,
      null,
      'customer_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'trader',
          'party_id',
          new.trader_id
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_expense_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_expense uuid;
begin
  if new.cashbox_id is null then
    raise exception
      'Expense requires cashbox for automatic accounting';
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_expense :=
    public.finance_system_account(
      new.company_id,
      'operating_expense'
    );

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'مصروف - ' ||
      new.category,
      v_currency,
      null,
      'expense',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_expense,
          'debit',
          new.amount,
          'credit',
          0,
          'memo',
          new.category
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'memo',
          new.category
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_inventory_movement_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_amount numeric(18,2);

  v_inventory uuid;
  v_clearing uuid;
  v_cogs uuid;
  v_adjustment uuid;
  v_opening uuid;

  v_lines jsonb;
  v_currency text;
begin
  if new.movement_type in (
    'transfer_in',
    'transfer_out'
  ) then
    return new;
  end if;

  v_amount :=
    round(
      abs(new.quantity) *
      coalesce(
        new.unit_cost,
        0
      ),
      2
    );

  if v_amount <= 0 then
    return new;
  end if;

  select default_currency
  into v_currency
  from public.companies
  where id =
        new.company_id;

  v_inventory :=
    public.finance_system_account(
      new.company_id,
      'inventory'
    );

  if new.movement_type =
     'purchase_receipt'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_delivery'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'sales_return'
  then
    v_cogs :=
      public.finance_system_account(
        new.company_id,
        'cogs'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_cogs,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'purchase_return'
  then
    v_clearing :=
      public.finance_system_account(
        new.company_id,
        'inventory_clearing'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_in'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'adjustment_out'
  then
    v_adjustment :=
      public.finance_system_account(
        new.company_id,
        'inventory_adjustment_expense'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_adjustment,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  elsif new.movement_type =
        'opening'
  then
    v_opening :=
      public.finance_system_account(
        new.company_id,
        'opening_balance_equity'
      );

    v_lines :=
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_inventory,
          'debit',
          v_amount,
          'credit',
          0
        ),
        jsonb_build_object(
          'account_id',
          v_opening,
          'debit',
          0,
          'credit',
          v_amount
        )
      );

  else
    return new;
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      (new.occurred_at at time zone 'Asia/Damascus')::date,
      'حركة مخزون - ' ||
      new.movement_type,
      v_currency,
      1,
      'inventory_movement',
      new.id,
      v_lines
    );

  return new;
end;
$function$;

create or replace function public.gl_purchase_invoice_status_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'purchase_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة شراء ' ||
        new.invoice_number
      );

  elsif old.status <> 'posted'
        and new.status = 'posted'
  then
    perform
      public.sync_purchase_invoice_journal(
        new.id
      );
  end if;

  return new;
end;
$function$;

create or replace function public.gl_purchase_item_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform
    public.sync_purchase_invoice_journal(
      case
        when tg_op = 'DELETE'
          then old.invoice_id
        else new.invoice_id
      end
    );

  return coalesce(new,old);
end;
$function$;

create or replace function public.gl_sales_invoice_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ar uuid;
  v_sales uuid;
  v_discount uuid;
  v_lines jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'cancelled'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'sales_invoice',
        new.id,
        (now() at time zone 'Asia/Damascus')::date,
        'عكس فاتورة بيع ' ||
        new.invoice_number
      );

    return new;
  end if;

  if new.status <> 'posted' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = new.status
  then
    return new;
  end if;

  if new.total <= 0
     and new.subtotal <= 0
  then
    return new;
  end if;

  v_ar :=
    public.finance_system_account(
      new.company_id,
      'accounts_receivable'
    );

  v_sales :=
    public.finance_system_account(
      new.company_id,
      'sales_revenue'
    );

  v_discount :=
    public.finance_system_account(
      new.company_id,
      'sales_discounts'
    );

  if new.total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ar,
          'debit',
          new.total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'ذمة فاتورة بيع'
        )
      );
  end if;

  if new.discount_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_discount,
          'debit',
          new.discount_total,
          'credit',
          0,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'خصم مبيعات'
        )
      );
  end if;

  if new.subtotal > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_sales,
          'debit',
          0,
          'credit',
          new.subtotal,
          'party_type',
          'trader',
          'party_id',
          new.trader_id,
          'memo',
          'إيراد مبيعات'
        )
      );
  end if;

  perform
    public.post_system_journal(
      new.company_id,
      new.invoice_date,
      'فاتورة بيع ' ||
      new.invoice_number,
      new.currency,
      null,
      'sales_invoice',
      new.id,
      v_lines
    );

  return new;
end;
$function$;

create or replace function public.gl_supplier_allocation_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_supplier uuid;
  v_date date;
  v_cashbox uuid;
  v_currency text;
  v_status text;

  v_advance uuid;
  v_ap uuid;
begin
  select
    company_id,
    supplier_id,
    payment_date,
    cashbox_id,
    status
  into
    v_company,
    v_supplier,
    v_date,
    v_cashbox,
    v_status
  from public.supplier_payments
  where id =
        new.payment_id;

  if v_status <>
     'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        v_cashbox;

  v_advance :=
    public.finance_system_account(
      v_company,
      'supplier_advances'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'تخصيص دفعة على فاتورة شراء',
      -- الدفعة ممكن تكون بعملة غير عملة الفاتورة (مثلًا ليرة على فاتورة دولار)،
      -- فالقيد لازم ينكتب بمبلغ الدفعة وعملتها وسعر صرفها، مش بمبلغ الفاتورة.
      coalesce(new.payment_currency, v_currency),
      new.payment_rate_to_base,
      'supplier_payment_allocation',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          coalesce(new.payment_amount, new.amount),
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        ),
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          0,
          'credit',
          coalesce(new.payment_amount, new.amount),
          'party_type',
          'supplier',
          'party_id',
          v_supplier
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.gl_supplier_payment_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_currency text;
  v_cash uuid;
  v_advance uuid;
  v_alloc record;
begin
  if tg_op = 'UPDATE'
     and old.status = 'posted'
     and new.status = 'reversed'
  then
    perform
      public.reverse_system_journal(
        new.company_id,
        'supplier_payment',
        new.id,
        new.payment_date,
        'عكس دفعة مورد ' ||
        new.payment_number
      );

    for v_alloc in
      select id
      from public.supplier_payment_allocations
      where payment_id = new.id
    loop
      perform
        public.reverse_system_journal(
          new.company_id,
          'supplier_payment_allocation',
          v_alloc.id,
          new.payment_date,
          'عكس تخصيص دفعة مورد'
        );
    end loop;

    return new;
  end if;

  if tg_op <> 'INSERT'
     or new.status <> 'posted'
  then
    return new;
  end if;

  select currency
  into v_currency
  from public.cashboxes
  where id =
        new.cashbox_id;

  v_cash :=
    public.finance_cashbox_account(
      new.company_id,
      new.cashbox_id
    );

  v_advance :=
    public.finance_system_account(
      new.company_id,
      'supplier_advances'
    );

  perform
    public.post_system_journal(
      new.company_id,
      new.payment_date,
      'دفعة إلى مورد ' ||
      new.payment_number,
      v_currency,
      null,
      'supplier_payment',
      new.id,

      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_advance,
          'debit',
          new.amount,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        ),
        jsonb_build_object(
          'account_id',
          v_cash,
          'debit',
          0,
          'credit',
          new.amount,
          'party_type',
          'supplier',
          'party_id',
          new.supplier_id
        )
      )
    );

  return new;
end;
$function$;

create or replace function public.sync_purchase_invoice_journal(target_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company uuid;
  v_supplier uuid;
  v_number text;
  v_currency text;
  v_date date;
  v_status text;

  v_cost numeric(18,2);
  v_total numeric(18,2);
  v_variance numeric(18,2);

  v_clearing uuid;
  v_ap uuid;
  v_variance_account uuid;

  v_lines jsonb := '[]'::jsonb;
begin
  select
    company_id,
    supplier_id,
    invoice_number,
    currency,
    invoice_date,
    status
  into
    v_company,
    v_supplier,
    v_number,
    v_currency,
    v_date,
    v_status
  from public.purchase_invoices
  where id = target_invoice;

  if v_company is null
     or v_status <> 'posted'
  then
    return;
  end if;

  select
    round(
      coalesce(
        sum(
          quantity *
          unit_cost
        ),
        0
      ),
      2
    ),

    round(
      coalesce(
        sum(line_total),
        0
      ),
      2
    )
  into
    v_cost,
    v_total
  from public.purchase_invoice_items
  where invoice_id =
        target_invoice;

  if v_total <= 0
     and v_cost <= 0
  then
    return;
  end if;

  delete from public.journal_entries
  where company_id =
        v_company
    and source_type =
        'purchase_invoice'
    and source_id =
        target_invoice
    and reversed_from_id
        is null
    and status =
        'posted';

  v_clearing :=
    public.finance_system_account(
      v_company,
      'inventory_clearing'
    );

  v_ap :=
    public.finance_system_account(
      v_company,
      'accounts_payable'
    );

  v_variance_account :=
    public.finance_system_account(
      v_company,
      'purchase_variance'
    );

  if v_cost > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_clearing,
          'debit',
          v_cost,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'قيمة بضاعة مشتراة'
        )
      );
  end if;

  v_variance :=
    round(
      v_total -
      v_cost,
      2
    );

  if v_variance > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          v_variance,
          'credit',
          0,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'فروقات وتكاليف شراء'
        )
      );

  elsif v_variance < 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_variance_account,
          'debit',
          0,
          'credit',
          abs(v_variance),
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'خصم شراء'
        )
      );
  end if;

  if v_total > 0 then
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'account_id',
          v_ap,
          'debit',
          0,
          'credit',
          v_total,
          'party_type',
          'supplier',
          'party_id',
          v_supplier,
          'memo',
          'ذمة مورد'
        )
      );
  end if;

  perform
    public.post_system_journal(
      v_company,
      v_date,
      'فاتورة شراء ' ||
      v_number,
      v_currency,
      null,
      'purchase_invoice',
      target_invoice,
      v_lines
    );
end;
$function$;


-- ----------------------------------------------------------------------
-- المشغّلات (Triggers)
-- ----------------------------------------------------------------------

create trigger gl_cash_movement after insert on public.cash_transactions for each row execute function public.gl_cash_movement_trigger();

create trigger gl_customer_payment_allocation after insert on public.customer_payment_allocations for each row execute function public.gl_customer_allocation_trigger();

create trigger gl_customer_payment after insert or update of status on public.customer_payments for each row execute function public.gl_customer_payment_trigger();

create trigger gl_expense after insert on public.expenses for each row execute function public.gl_expense_trigger();

create trigger gl_inventory_movement after insert on public.inventory_movements for each row execute function public.gl_inventory_movement_trigger();

create trigger gl_purchase_invoice_item after insert or delete or update on public.purchase_invoice_items for each row execute function public.gl_purchase_item_trigger();

create trigger gl_purchase_invoice_status after update of status on public.purchase_invoices for each row execute function public.gl_purchase_invoice_status_trigger();

create trigger gl_sales_invoice after insert or update of status on public.sales_invoices for each row execute function public.gl_sales_invoice_trigger();

create trigger gl_supplier_payment_allocation after insert on public.supplier_payment_allocations for each row execute function public.gl_supplier_allocation_trigger();

create trigger gl_supplier_payment after insert or update of status on public.supplier_payments for each row execute function public.gl_supplier_payment_trigger();


-- ----------------------------------------------------------------------
-- الصلاحيات
-- ----------------------------------------------------------------------

revoke execute on function public.sync_purchase_invoice_journal(uuid) from authenticated;
