import { Topbar } from "@/components/topbar";
import {
  ApprovalsClient,
  type ApprovalRequest,
} from "@/components/approvals/approvals-client";

import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function ApprovalsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "approvals.view",
      "approvals.resolve",
    ],
    context.isOwner
  );

  const canResolve = hasPermission(
    context.permissions,
    "approvals.resolve",
    context.isOwner
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="الموافقات"
          subtitle="طلبات الموافقة"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض الموافقات.
          </section>
        </div>
      </>
    );
  }

  const { data, error } = await supabase
    .from("approval_requests")
    .select(
      "id,request_type,reference_type,reference_id,title,description,payload,status,requested_at,resolved_at,resolution_notes,requested_by,resolved_by,created_at"
    )
    .eq("company_id", context.companyId)
    .order("requested_at", { ascending: false })
    .limit(200);

  if (error) {
    throw new Error(error.message);
  }

  return (
    <>
      <Topbar
        title="الموافقات"
        subtitle="الطلبات المعلقة والمقبولة والمرفوضة"
        companyName={context.companyName}
      />

      <ApprovalsClient
        companyId={context.companyId}
        requests={
          (data ?? []) as unknown as ApprovalRequest[]
        }
        canResolve={canResolve}
      />
    </>
  );
}