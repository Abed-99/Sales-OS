import { ImportsClient, type ShipmentRow } from "@/components/imports/imports-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function ImportsPage() {
  const context = await getCurrentContext();
  const canView = hasAnyPermission(
    context.permissions,
    ["purchases.view", "purchase_invoices.view"],
    context.isOwner,
  );

  if (!canView) {
    return (
      <>
        <Topbar title="الاستيراد" subtitle="الكونتينرات" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const [shipments, invoices, cashboxes] = await Promise.all([
    supabase
      .from("import_shipments")
      .select(
        "id,shipment_number,container_number,origin_country,shipped_on,expected_on,arrived_on,status,notes,closed_at,import_shipment_costs(id,cost_type,amount,currency,base_amount,cost_date,notes,allocation_method),purchase_invoices(id,invoice_number,supplier_invoice_number,total,currency,suppliers(name))",
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false })
      .limit(60),
    supabase
      .from("purchase_invoices")
      .select(
        "id,invoice_number,supplier_invoice_number,total,currency,invoice_date,suppliers(name)",
      )
      .eq("company_id", context.companyId)
      .eq("status", "posted")
      .is("shipment_id", null)
      .order("invoice_date", { ascending: false })
      .limit(100),
    supabase
      .from("cashboxes")
      .select("id,name,currency")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("created_at"),
  ]);

  return (
    <>
      <Topbar
        title="الاستيراد"
        subtitle="الكونتينر: فواتيرو ومصاريفو، والكلفة الواصلة لكل صنف"
        companyName={context.companyName}
      />
      <ImportsClient
        companyId={context.companyId}
        currency={context.currency}
        shipments={(shipments.data ?? []) as unknown as ShipmentRow[]}
        freeInvoices={(invoices.data ?? []) as unknown as ShipmentRow["purchase_invoices"]}
        cashboxes={cashboxes.data ?? []}
        canManage={hasAnyPermission(
          context.permissions,
          ["purchases.create", "purchase_invoices.create"],
          context.isOwner,
        )}
      />
    </>
  );
}
