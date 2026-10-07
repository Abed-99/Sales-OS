import { Topbar } from "@/components/topbar";
import { VisitsClient, type VisitShop } from "@/components/visits/visits-client";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

// المحلات اللي لسا ما صارت زبائن: جديد (ما انزار)، تواصلنا (انزار)، مهتم.
const VISIT_STATUSES = ["new", "contacted", "interested"];

export default async function VisitsPage() {
  const context = await getCurrentContext();
  const canView = hasPermission(context.permissions, "traders.view", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar title="جولة الزيارات" subtitle="محلات بدك تزورها" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية تشوف العملاء.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("traders")
    .select("id,name,area,address,phone,whatsapp,latitude,longitude,status,notes")
    .eq("company_id", context.companyId)
    .in("status", VISIT_STATUSES)
    .neq("name", "زبون نقدي")
    .order("created_at", { ascending: false })
    .limit(500);

  return (
    <>
      <Topbar
        title="جولة الزيارات"
        subtitle="محلات بدك تزورها، وأقصر طريق بيناتها"
        companyName={context.companyName}
      />
      <VisitsClient
        companyId={context.companyId}
        initialShops={(data ?? []) as VisitShop[]}
        loadError={error ? "ما قدرنا نحمّل المحلات. حدّث الصفحة." : null}
        canCreate={hasPermission(context.permissions, "traders.create", context.isOwner)}
        canEdit={hasPermission(context.permissions, "traders.update", context.isOwner)}
      />
    </>
  );
}
