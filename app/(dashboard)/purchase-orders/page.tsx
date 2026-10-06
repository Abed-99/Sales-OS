import {
  PurchaseOrdersClient,
  type PurchaseOrderRow,
} from "@/components/purchase-orders/purchase-orders-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, quickAddRights } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function PurchaseOrdersPage() {
  const context = await getCurrentContext();
  const canView = hasAnyPermission(
    context.permissions,
    ["purchases.view", "purchase_invoices.view"],
    context.isOwner,
  );
  const canCreate = hasAnyPermission(
    context.permissions,
    ["purchases.create", "purchase_invoices.create"],
    context.isOwner,
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="أوامر الشراء"
          subtitle="الطلبات للموردين"
          companyName={context.companyName}
        />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض أوامر الشراء.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const [ordersResult, suppliersResult] = await Promise.all([
    supabase
      .from("purchase_orders")
      .select(
        "id,po_number,order_date,expected_date,status,currency,total,notes,converted_invoice_id,suppliers(name),purchase_order_items(id,quantity,unit_cost,line_total,products(name,unit,pack_size,pack_unit))",
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("suppliers")
      .select("id,name")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
  ]);

  return (
    <>
      <Topbar
        title="أوامر الشراء"
        subtitle="اطلب من المورد، ابعتلو الأمر، ولما توصل الفاتورة حوّلو بكبسة"
        companyName={context.companyName}
      />
      <PurchaseOrdersClient
        canAdd={quickAddRights(context.permissions, context.isOwner)}
        companyId={context.companyId}
        currency={context.currency}
        orders={(ordersResult.data ?? []) as unknown as PurchaseOrderRow[]}
        suppliers={suppliersResult.data ?? []}
        canCreate={canCreate}
      />
    </>
  );
}
