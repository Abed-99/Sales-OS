import {
  DeliveriesClient,
  type DeliveryQueueRow,
  type DeliveryStats,
} from "@/components/deliveries/deliveries-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { cleanSearch, firstParam } from "@/lib/search";

type DeliveryStatusFilter = "all" | "ready" | "out_for_delivery";

export default async function DeliveriesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const context = await getCurrentContext();

  const params = await searchParams;

  const canAccess = hasAnyPermission(
    context.permissions,
    ["deliveries.view", "deliveries.update"],
    context.isOwner,
  );

  if (!canAccess) {
    return (
      <>
        <Topbar
          title="التوصيل"
          subtitle="تجهيز وتسليم طلبيات العملاء"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <h3>لا تملك صلاحية عرض التوصيلات</h3>

              <p>تحتاج إلى صلاحية التوصيلات للوصول لهذه الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canUpdate = hasPermission(context.permissions, "deliveries.update", context.isOwner);

  const canViewMap = hasPermission(context.permissions, "map.view", context.isOwner);

  const searchQuery = cleanSearch(firstParam(params.q));

  const rawStatus = firstParam(params.status);

  const statusFilter: DeliveryStatusFilter =
    rawStatus === "ready" || rawStatus === "out_for_delivery" ? rawStatus : "all";

  const page = Math.max(1, Number.parseInt(firstParam(params.page), 10) || 1);

  const pageSize = 50;

  const offset = (page - 1) * pageSize;

  const supabase = await createClient();

  // أجرة توصيل علينا بتطلع من صندوق، فبدها صلاحية المصاريف.
  const canPayDelivery =
    canUpdate && hasPermission(context.permissions, "finance.expenses_write", context.isOwner);

  const [queueResult, summaryResult, cashboxResult] = await Promise.all([
    supabase.rpc("get_delivery_queue", {
      target_company: context.companyId,

      target_search: searchQuery || null,

      target_status: statusFilter === "all" ? null : statusFilter,

      target_limit: pageSize,

      target_offset: offset,
    }),

    supabase.rpc("get_deliveries_summary", {
      target_company: context.companyId,
    }),

    canPayDelivery
      ? supabase
          .from("cashboxes")
          .select("id,name,currency")
          .eq("company_id", context.companyId)
          .eq("active", true)
          .order("created_at")
      : Promise.resolve({ data: [] as { id: string; name: string; currency: string }[] }),
  ]);

  let initialError: string | null = null;

  if (queueResult.error) {
    initialError = "تعذر تحميل قائمة التوصيلات.";
  }

  if (summaryResult.error) {
    initialError ??= "تعذر تحميل ملخص التوصيلات.";
  }

  const queueData =
    queueResult.data && typeof queueResult.data === "object" && !Array.isArray(queueResult.data)
      ? (queueResult.data as {
          rows?: unknown;
          total_count?: unknown;
        })
      : null;

  const initialRows = Array.isArray(queueData?.rows) ? (queueData?.rows as DeliveryQueueRow[]) : [];

  const totalCount = Number(queueData?.total_count ?? 0);

  const summaryRaw = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;

  const summary =
    summaryRaw && typeof summaryRaw === "object" ? (summaryRaw as Record<string, unknown>) : null;

  const stats: DeliveryStats = {
    readyCount: Number(summary?.ready_count ?? 0),

    roadCount: Number(summary?.road_count ?? 0),

    roadUnits: Number(summary?.road_units ?? 0),

    remainingUnits: Number(summary?.remaining_units ?? 0),
  };

  return (
    <>
      <Topbar
        title="التوصيل"
        subtitle="جهّز التسليمات الكاملة أو الجزئية وتابعها حتى التسليم"
        companyName={context.companyName}
      />

      <DeliveriesClient
        companyId={context.companyId}
        currency={context.currency}
        initialRows={initialRows}
        initialStats={stats}
        totalCount={Number.isFinite(totalCount) ? totalCount : 0}
        page={page}
        pageSize={pageSize}
        searchQuery={searchQuery}
        statusFilter={statusFilter}
        canUpdate={canUpdate}
        canViewMap={canViewMap}
        canPayDelivery={canPayDelivery}
        cashboxes={cashboxResult.data ?? []}
        initialError={initialError}
      />
    </>
  );
}
