import { MobileNav } from "@/components/mobile-nav";
import { Sidebar } from "@/components/sidebar";

import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
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

  const supabase = await createClient();

  // عدد رسائل واتساب الجاهزة للإرسال (مع تجهيز التذكير والكشوف الشهرية).
  async function countWhatsapp() {
    if (!hasAnyPermission(permissions, ["traders.view", "orders.view"], isOwner)) return 0;
    await supabase.rpc("refresh_whatsapp_outbox", { target_company: companyId });
    const { count } = await supabase
      .from("whatsapp_outbox")
      .select("id", { count: "exact", head: true })
      .eq("company_id", companyId)
      .eq("status", "pending");
    return count ?? 0;
  }

  // الطلبات الناطرة موافقة (بتبين رقم جنب "الإدارة" بالقائمة لحتى ما تضيع).
  async function countApprovals() {
    if (!hasPermission(permissions, "approvals.view", isOwner)) return 0;
    const { count } = await supabase
      .from("approval_requests")
      .select("id", { count: "exact", head: true })
      .eq("company_id", companyId)
      .eq("status", "pending");
    return count ?? 0;
  }

  const [waPending, approvalsPending] = await Promise.all([countWhatsapp(), countApprovals()]);

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
        approvalsPending={approvalsPending}
      />

      <main className="mainShell">{children}</main>

      <MobileNav permissions={permissions} isOwner={isOwner} waPending={waPending} />
    </div>
  );
}
