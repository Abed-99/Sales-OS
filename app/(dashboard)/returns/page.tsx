import {
  ReturnsClient,
  type PurchaseReturnCandidate,
  type ReturnHistoryRow,
  type ReturnsStats,
  type ReturnWarehouse,
  type SalesReturnCandidate,
  type ReturnsTab,
  type ReturnHistoryKindFilter,
  type ReturnHistoryStatusFilter,
} from "@/components/returns/returns-client";

import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { cleanSearch, firstParam } from "@/lib/search";

function cleanTab(value: string): ReturnsTab {
  if (value === "purchases" || value === "history") {
    return value;
  }

  return "sales";
}

function cleanKind(value: string): ReturnHistoryKindFilter {
  if (value === "sales" || value === "purchases") {
    return value;
  }

  return "all";
}

function cleanStatus(value: string): ReturnHistoryStatusFilter {
  if (value === "posted" || value === "reversed" || value === "cancelled") {
    return value;
  }

  return "all";
}

function parseRpcObject(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function parseRows<T>(value: unknown): T[] {
  const object = parseRpcObject(value);

  return Array.isArray(object?.rows) ? (object.rows as T[]) : [];
}

function parseCount(value: unknown) {
  const object = parseRpcObject(value);

  const count = Number(object?.total_count ?? 0);

  return Number.isFinite(count) ? count : 0;
}

export default async function ReturnsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const context = await getCurrentContext();

  const params = await searchParams;

  const canView = hasAnyPermission(
    context.permissions,
    ["returns.view", "returns.create", "inventory.returns", "returns.reverse"],
    context.isOwner,
  );

  const canCreate = hasAnyPermission(
    context.permissions,
    ["returns.create", "inventory.returns"],
    context.isOwner,
  );

  const canReverse = hasPermission(context.permissions, "returns.reverse", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar
          title="المرتجعات"
          subtitle="مرتجعات البيع والشراء"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <h3>لا تملك صلاحية عرض المرتجعات</h3>

              <p>تحتاج إلى إحدى صلاحيات المرتجعات للوصول لهذه الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const requestedTab = cleanTab(firstParam(params.tab));

  const tab: ReturnsTab = canCreate ? requestedTab : "history";

  const searchQuery = cleanSearch(firstParam(params.q));

  const historyKind = cleanKind(firstParam(params.kind));

  const historyStatus = cleanStatus(firstParam(params.status));

  const page = Math.max(1, Number.parseInt(firstParam(params.page), 10) || 1);

  const pageSize = 50;

  const offset = (page - 1) * pageSize;

  const supabase = await createClient();

  let initialError: string | null = null;

  let warehouses: ReturnWarehouse[] = [];

  let salesCandidates: SalesReturnCandidate[] = [];

  let purchaseCandidates: PurchaseReturnCandidate[] = [];

  let historyRows: ReturnHistoryRow[] = [];

  let totalCount = 0;

  const summaryPromise = supabase.rpc("get_returns_summary", {
    target_company: context.companyId,
  });

  const warehousesPromise = canCreate
    ? supabase.rpc("get_return_warehouses", {
        target_company: context.companyId,
      })
    : Promise.resolve({
        data: [],
        error: null,
      });

  const dataPromise =
    tab === "sales"
      ? supabase.rpc("get_sales_return_candidates", {
          target_company: context.companyId,

          target_search: searchQuery || null,

          target_limit: pageSize,

          target_offset: offset,
        })
      : tab === "purchases"
        ? supabase.rpc("get_purchase_return_candidates", {
            target_company: context.companyId,

            target_search: searchQuery || null,

            target_limit: pageSize,

            target_offset: offset,
          })
        : supabase.rpc("get_returns_history", {
            target_company: context.companyId,

            target_search: searchQuery || null,

            target_kind: historyKind === "all" ? null : historyKind,

            target_status: historyStatus === "all" ? null : historyStatus,

            target_limit: pageSize,

            target_offset: offset,
          });

  const [summaryResult, warehousesResult, dataResult] = await Promise.all([
    summaryPromise,
    warehousesPromise,
    dataPromise,
  ]);

  if (summaryResult.error) {
    initialError = "تعذر تحميل ملخص المرتجعات.";
  }

  if (warehousesResult.error) {
    initialError ??= "تعذر تحميل المستودعات.";
  } else if (Array.isArray(warehousesResult.data)) {
    warehouses = warehousesResult.data as ReturnWarehouse[];
  }

  if (dataResult.error) {
    initialError ??=
      tab === "history" ? "تعذر تحميل سجل المرتجعات." : "تعذر تحميل الفواتير القابلة للإرجاع.";
  } else {
    totalCount = parseCount(dataResult.data);

    if (tab === "sales") {
      salesCandidates = parseRows<SalesReturnCandidate>(dataResult.data);
    }

    if (tab === "purchases") {
      purchaseCandidates = parseRows<PurchaseReturnCandidate>(dataResult.data);
    }

    if (tab === "history") {
      historyRows = parseRows<ReturnHistoryRow>(dataResult.data);
    }
  }

  const summary = parseRpcObject(summaryResult.data);

  const stats: ReturnsStats = {
    salesCount: Number(summary?.sales_count ?? 0),

    salesPostedCount: Number(summary?.sales_posted_count ?? 0),

    salesReversedCount: Number(summary?.sales_reversed_count ?? 0),

    purchaseCount: Number(summary?.purchase_count ?? 0),

    purchasePostedCount: Number(summary?.purchase_posted_count ?? 0),

    purchaseReversedCount: Number(summary?.purchase_reversed_count ?? 0),

    salesTotals: Array.isArray(summary?.sales_totals)
      ? (summary.sales_totals as {
          currency: string;
          total: number;
        }[])
      : [],

    purchaseTotals: Array.isArray(summary?.purchase_totals)
      ? (summary.purchase_totals as {
          currency: string;
          total: number;
        }[])
      : [],
  };

  return (
    <>
      <Topbar
        title="المرتجعات"
        subtitle="إرجاع بضاعة من العميل أو إلى المورد مع المخزون والمحاسبة"
        companyName={context.companyName}
      />

      <ReturnsClient
        companyId={context.companyId}
        initialTab={tab}
        initialStats={stats}
        warehouses={warehouses}
        salesCandidates={salesCandidates}
        purchaseCandidates={purchaseCandidates}
        historyRows={historyRows}
        totalCount={totalCount}
        page={page}
        pageSize={pageSize}
        searchQuery={searchQuery}
        historyKind={historyKind}
        historyStatus={historyStatus}
        canCreate={canCreate}
        canReverse={canReverse}
        initialError={initialError}
      />
    </>
  );
}
