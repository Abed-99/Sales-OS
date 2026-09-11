import { Topbar } from "@/components/topbar";
import {
  OrdersClient,
  type OrderCashbox,
  type OrderProduct,
  type OrderRow,
  type OrderSalesInvoice,
  type OrderTrader,
} from "@/components/orders/orders-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";

export default async function OrdersPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canCreate = hasPermission(
    context.permissions,
    "orders.create",
    context.isOwner
  );

  const canCancel = hasPermission(
    context.permissions,
    "orders.cancel",
    context.isOwner
  );

  const canCollect = hasPermission(
    context.permissions,
    "payments.sales_create",
    context.isOwner
  );

  const [ordersResult, tradersResult, productsResult] = await Promise.all([
    supabase
      .from("sales_orders")
      .select(`
        id,
        trader_id,
        status,
        payment_status,
        subtotal,
        total,
        notes,
        created_at,
        delivered_at,
        traders(name,area,phone,whatsapp),
        sales_order_items(
          id,
          product_id,
          quantity,
          sale_unit_price,
          line_total,
          products(name,sku)
        )
      `)
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false })
      .limit(150),

    supabase
      .from("traders")
      .select("id,name,area,status")
      .eq("company_id", context.companyId)
      .neq("status", "inactive")
      .order("name"),

    supabase
      .from("products")
      .select("id,name,sku,sale_price,minimum_sale_price,unit,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
  ]);

  if (ordersResult.error) throw new Error(ordersResult.error.message);
  if (tradersResult.error) throw new Error(tradersResult.error.message);
  if (productsResult.error) throw new Error(productsResult.error.message);

  let invoices: OrderSalesInvoice[] = [];
  let cashboxes: OrderCashbox[] = [];

  if (canCollect) {
    const [invoiceResult, cashboxResult] = await Promise.all([
      supabase
        .from("sales_invoices")
        .select(
          "id,order_id,trader_id,invoice_number,currency,total,paid_total,balance_due,payment_status,status"
        )
        .eq("company_id", context.companyId)
        .eq("status", "posted"),

      supabase
        .from("cashboxes")
        .select("id,name,currency,active")
        .eq("company_id", context.companyId)
        .eq("active", true)
        .order("created_at"),
    ]);

    if (invoiceResult.error) throw new Error(invoiceResult.error.message);
    if (cashboxResult.error) throw new Error(cashboxResult.error.message);

    invoices = (invoiceResult.data ?? []) as OrderSalesInvoice[];
    cashboxes = (cashboxResult.data ?? []) as OrderCashbox[];
  }

  return (
    <>
      <Topbar
        title="المبيعات"
        subtitle="الطلبات، الفواتير والتحصيل من العملاء"
        companyName={context.companyName}
      />
      <OrdersClient
        companyId={context.companyId}
        currency={context.currency}
        initialOrders={(ordersResult.data ?? []) as unknown as OrderRow[]}
        traders={(tradersResult.data ?? []) as OrderTrader[]}
        products={(productsResult.data ?? []) as OrderProduct[]}
        invoices={invoices}
        cashboxes={cashboxes}
        canCreate={canCreate}
        canCancel={canCancel}
        canCollect={canCollect}
      />
    </>
  );
}
