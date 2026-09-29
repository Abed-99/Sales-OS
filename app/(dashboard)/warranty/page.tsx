import { WarrantyClient, type OpenClaim } from "@/components/warranty/warranty-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function WarrantyPage() {
  const context = await getCurrentContext();
  const canView = hasAnyPermission(
    context.permissions,
    ["orders.view", "products.view"],
    context.isOwner,
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="الضمان"
          subtitle="الأرقام التسلسلية والصيانة"
          companyName={context.companyName}
        />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const { data } = await supabase
    .from("warranty_claims")
    .select(
      "id,claim_date,issue,status,in_warranty,product_serials(serial,warranty_until,products(name),traders(name))",
    )
    .eq("company_id", context.companyId)
    .eq("status", "open")
    .order("claim_date", { ascending: false })
    .limit(100);

  return (
    <>
      <Topbar
        title="الضمان"
        subtitle="ابحث برقم القطعة: مين اشتراها، إيمتى، وإذا لسا بالضمان"
        companyName={context.companyName}
      />
      <WarrantyClient
        companyId={context.companyId}
        openClaims={(data ?? []) as unknown as OpenClaim[]}
        canEdit={hasAnyPermission(
          context.permissions,
          ["orders.update", "orders.create"],
          context.isOwner,
        )}
      />
    </>
  );
}
