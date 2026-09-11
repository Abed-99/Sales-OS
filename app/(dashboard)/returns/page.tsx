import { Topbar } from "@/components/topbar";
import {
  ReturnsClient,
  type ReturnWarehouse,
  type ReturnSalesInvoice,
  type ReturnPurchaseInvoice,
  type SalesReturnRecord,
  type PurchaseReturnRecord,
} from "@/components/returns/returns-client";

import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function ReturnsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "returns.view",
      "returns.create",
      "inventory.returns",
    ],
    context.isOwner
  );

  const canCreate = hasAnyPermission(
    context.permissions,
    [
      "returns.create",
      "inventory.returns",
    ],
    context.isOwner
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="المرتجعات"
          subtitle="مرتجعات البيع والشراء"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض المرتجعات.
          </section>
        </div>
      </>
    );
  }

  const [
    warehousesResult,
    salesInvoicesResult,
    purchaseInvoicesResult,
    salesReturnsResult,
    purchaseReturnsResult,
  ] = await Promise.all([
    supabase
      .from("warehouses")
      .select("id,name,code,is_default,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("is_default", { ascending: false })
      .order("name"),

    supabase
      .from("sales_invoices")
      .select(`
        id,
        invoice_number,
        trader_id,
        invoice_date,
        currency,
        subtotal,
        discount_total,
        total,
        status,
        traders(
          id,
          name
        ),
        sales_invoice_items(
          id,
          product_id,
          description,
          unit,
          quantity,
          unit_price,
          line_total,
          products(
            id,
            name,
            sku
          )
        )
      `)
      .eq("company_id", context.companyId)
      .eq("status", "posted")
      .order("invoice_date", { ascending: false })
      .limit(100),

    supabase
      .from("purchase_invoices")
      .select(`
        id,
        invoice_number,
        supplier_invoice_number,
        supplier_id,
        invoice_date,
        currency,
        total,
        status,
        suppliers(
          id,
          name
        ),
        purchase_invoice_items(
          id,
          product_id,
          description,
          quantity,
          unit_cost,
          line_total,
          products(
            id,
            name,
            sku
          )
        )
      `)
      .eq("company_id", context.companyId)
      .eq("status", "posted")
      .order("invoice_date", { ascending: false })
      .limit(100),

    supabase
      .from("sales_returns")
      .select(
        "id,return_number,sales_invoice_id,trader_id,warehouse_id,return_date,status,currency,subtotal,discount_total,total,notes,created_at"
      )
      .eq("company_id", context.companyId)
      .order("return_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(100),

    supabase
      .from("purchase_returns")
      .select(
        "id,return_number,purchase_invoice_id,supplier_id,warehouse_id,return_date,status,currency,inventory_cost_total,total,notes,created_at"
      )
      .eq("company_id", context.companyId)
      .order("return_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  const results = [
    warehousesResult,
    salesInvoicesResult,
    purchaseInvoicesResult,
    salesReturnsResult,
    purchaseReturnsResult,
  ];

  for (const result of results) {
    if (result.error) {
      throw new Error(result.error.message);
    }
  }

  const [
    salesReturnItemsResult,
    purchaseReturnItemsResult,
  ] = await Promise.all([
    supabase
      .from("sales_return_items")
      .select(
        "id,sales_return_id,sales_invoice_item_id,quantity"
      )
      .eq("company_id", context.companyId),

    supabase
      .from("purchase_return_items")
      .select(
        "id,purchase_return_id,purchase_invoice_item_id,quantity"
      )
      .eq("company_id", context.companyId),
  ]);

  if (salesReturnItemsResult.error) {
    throw new Error(
      salesReturnItemsResult.error.message
    );
  }

  if (purchaseReturnItemsResult.error) {
    throw new Error(
      purchaseReturnItemsResult.error.message
    );
  }

  return (
    <>
      <Topbar
        title="المرتجعات"
        subtitle="إرجاع بضاعة من العميل أو إلى المورد"
        companyName={context.companyName}
      />

      <ReturnsClient
        companyId={context.companyId}
        baseCurrency={context.currency}
        warehouses={
          (warehousesResult.data ?? []) as unknown as ReturnWarehouse[]
        }
        salesInvoices={
          (salesInvoicesResult.data ?? []) as unknown as ReturnSalesInvoice[]
        }
        purchaseInvoices={
          (purchaseInvoicesResult.data ?? []) as unknown as ReturnPurchaseInvoice[]
        }
        salesReturns={
          (salesReturnsResult.data ?? []) as unknown as SalesReturnRecord[]
        }
        purchaseReturns={
          (purchaseReturnsResult.data ?? []) as unknown as PurchaseReturnRecord[]
        }
        salesReturnItems={
          (salesReturnItemsResult.data ?? []) as unknown as {
            id: string;
            sales_return_id: string;
            sales_invoice_item_id: string;
            quantity: number;
          }[]
        }
        purchaseReturnItems={
          (purchaseReturnItemsResult.data ?? []) as unknown as {
            id: string;
            purchase_return_id: string;
            purchase_invoice_item_id: string;
            quantity: number;
          }[]
        }
        canCreate={canCreate}
        canReverse={hasPermission(
          context.permissions,
          "returns.reverse",
          context.isOwner
        )}
      />
    </>
  );
}