import { MobileNav } from "@/components/mobile-nav";
import { Sidebar } from "@/components/sidebar";

import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const {
    userName,
    email,

    roleName,
    isOwner,
    permissions,

    companyId,
    memberships,
  } = await getCurrentContext();

  // عدد رسائل واتساب الجاهزة للإرسال (مع تجهيز التذكير والكشوف الشهرية).
  let waPending = 0;
  if (hasAnyPermission(permissions, ["traders.view", "orders.view"], isOwner)) {
    const supabase = await createClient();
    await supabase.rpc("refresh_whatsapp_outbox", { target_company: companyId });
    const { count } = await supabase
      .from("whatsapp_outbox")
      .select("id", { count: "exact", head: true })
      .eq("company_id", companyId)
      .eq("status", "pending");
    waPending = count ?? 0;
  }

  return (
    <div className="appShell">
      <Sidebar
        userName={userName}
        email={email}
        roleName={roleName}
        isOwner={isOwner}
        permissions={permissions}
        companyId={companyId}
        memberships={memberships}
        waPending={waPending}
      />

      <main className="mainShell">{children}</main>

      <MobileNav permissions={permissions} isOwner={isOwner} waPending={waPending} />
    </div>
  );
}
