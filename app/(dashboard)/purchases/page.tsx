import { Topbar } from "@/components/topbar";
import {
  PurchasesClient,
  type CashboxOption,
  type ProductOption,
  type PurchaseInvoiceRow,
  type PurchaseNeed,
  type SupplierOption,
  type SupplierPaymentRow,
  type SupplierPriceOption,
} from "@/components/purchases/purchases-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

export default async function PurchasesPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const [
    needsResult,
    suppliersResult,
    productsResult,
    pricesResult,
    invoicesResult,
    cashboxesResult,
    paymentsResult,
  ] = await Promise.all([
    supabase.rpc("get_purchase_needs", {
      target_company: context.companyId,
    }),
    supabase
      .from("suppliers")
      .select("id,name,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
    supabase
      .from("products")
      .select("id,name,sku,unit,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
    supabase
      .from("supplier_prices")
      .select("supplier_id,product_id,purchase_price,available")
      .eq("company_id", context.companyId)
      .eq("available", true),
    supabase
      .from("purchase_invoices")
      .select(
        "id,invoice_number,supplier_invoice_number,status,payment_status,currency,invoice_date,due_date,total,paid_total,balance_due,created_at,suppliers(id,name)"
      )
      .eq("company_id", context.companyId)
      .order("invoice_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("cashboxes")
      .select("id,name,currency,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("created_at"),
    supabase
      .from("supplier_payments")
      .select(
        "id,supplier_id,cashbox_id,payment_number,status,payment_date,amount,allocated_total,unallocated_total,payment_currency,exchange_rate_to_base,base_amount,payment_method,reference_number,notes,reversal_reason,created_at,suppliers(id,name),cashboxes(id,name,currency)"
      )
      .eq("company_id", context.companyId)
      .order("payment_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  const initialError =
    needsResult.error?.message ||
    suppliersResult.error?.message ||
    productsResult.error?.message ||
    pricesResult.error?.message ||
    invoicesResult.error?.message ||
    cashboxesResult.error?.message ||
    paymentsResult.error?.message ||
    null;

  return (
    <>
      <Topbar
        title="المشتريات"
        subtitle="احتياجات الشراء، فواتير الموردين والدفعات"
        companyName={context.companyName}
      />
      <PurchasesClient
        companyId={context.companyId}
        currency={context.currency}
        needs={(needsResult.data ?? []) as PurchaseNeed[]}
        suppliers={(suppliersResult.data ?? []) as SupplierOption[]}
        products={(productsResult.data ?? []) as ProductOption[]}
        supplierPrices={(pricesResult.data ?? []) as SupplierPriceOption[]}
        initialInvoices={(invoicesResult.data ?? []) as PurchaseInvoiceRow[]}
        cashboxes={(cashboxesResult.data ?? []) as CashboxOption[]}
        initialPayments={(paymentsResult.data ?? []) as SupplierPaymentRow[]}
        initialError={initialError}
      />
    </>
  );
}
