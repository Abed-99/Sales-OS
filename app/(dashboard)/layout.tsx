import { MobileNav } from "@/components/mobile-nav";
import { Sidebar } from "@/components/sidebar";

import { getCurrentContext } from "@/lib/current-context";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const {
    userName,
    email,

    roleName,
    isOwner,
    permissions,

    companyId,
    memberships,
  } = await getCurrentContext();

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
      />

      <main className="mainShell">
        {children}
      </main>

      <MobileNav
        permissions={permissions}
        isOwner={isOwner}
      />
    </div>
  );
}
