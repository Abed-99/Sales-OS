import {
  QuotesClient,
  type QuoteProduct,
  type QuoteRow,
  type QuotesStats,
  type QuoteTrader,
  type QuoteStatusFilter,
} from "@/components/quotes/quotes-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

function firstParam(
  value:
    | string
    | string[]
    | undefined
) {
  return Array.isArray(value)
    ? value[0] ?? ""
    : value ?? "";
}

function cleanSearch(
  value: string
) {
  return value
    .replace(
      /[%_(),"'\\]/g,
      " "
    )
    .replace(
      /\s+/g,
      " "
    )
    .trim()
    .slice(
      0,
      100
    );
}

function cleanStatus(
  value: string
): QuoteStatusFilter {
  const allowed:
    QuoteStatusFilter[] = [
      "all",
      "draft",
      "sent",
      "accepted",
      "rejected",
      "cancelled",
      "converted",
      "expired",
    ];

  return allowed.includes(
    value as QuoteStatusFilter
  )
    ? (
        value as QuoteStatusFilter
      )
    : "all";
}

export default async function QuotesPage({
  searchParams,
}: {
  searchParams: Promise<
    Record<
      string,
      | string
      | string[]
      | undefined
    >
  >;
}) {
  const context =
    await getCurrentContext();

  const params =
    await searchParams;

  const canView =
    hasPermission(
      context.permissions,
      "orders.view",
      context.isOwner
    );

  const canCreate =
    hasPermission(
      context.permissions,
      "orders.create",
      context.isOwner
    );

  const canUpdate =
    hasPermission(
      context.permissions,
      "orders.update",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="عروض الأسعار"
          subtitle="إدارة عروض الأسعار قبل تحويلها لطلبات"
          companyName={
            context.companyName
          }
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <h3>
                لا تملك صلاحية عرض عروض الأسعار
              </h3>

              <p>
                تحتاج إلى صلاحية عرض الطلبات للوصول لعروض الأسعار.
              </p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const searchQuery =
    cleanSearch(
      firstParam(
        params.q
      )
    );

  const statusFilter =
    cleanStatus(
      firstParam(
        params.status
      ) || "all"
    );

  const page =
    Math.max(
      1,
      Number.parseInt(
        firstParam(
          params.page
        ),
        10
      ) || 1
    );

  const pageSize =
    50;

  const offset =
    (page - 1) *
    pageSize;

  const supabase =
    await createClient();

  const [
    queueResult,
    summaryResult,
  ] =
    await Promise.all([
      supabase.rpc(
        "get_quotes_queue",
        {
          target_company:
            context.companyId,

          target_search:
            searchQuery ||
            null,

          target_status:
            statusFilter ===
            "all"
              ? null
              : statusFilter,

          target_limit:
            pageSize,

          target_offset:
            offset,
        }
      ),

      supabase.rpc(
        "get_quotes_summary",
        {
          target_company:
            context.companyId,
        }
      ),
    ]);

  let initialError:
    string | null =
      null;

  if (queueResult.error) {
    initialError =
      "تعذر تحميل عروض الأسعار.";
  }

  if (summaryResult.error) {
    initialError ??=
      "تعذر تحميل ملخص عروض الأسعار.";
  }

  const queueData =
    queueResult.data &&
    typeof queueResult.data ===
      "object" &&
    !Array.isArray(
      queueResult.data
    )
      ? (
          queueResult.data as {
            rows?: unknown;
            total_count?: unknown;
          }
        )
      : null;

  const initialQuotes =
    Array.isArray(
      queueData?.rows
    )
      ? (
          queueData.rows as QuoteRow[]
        )
      : [];

  const totalCountRaw =
    Number(
      queueData?.total_count ??
        0
    );

  const totalCount =
    Number.isFinite(
      totalCountRaw
    )
      ? totalCountRaw
      : 0;

  const summaryRaw =
    Array.isArray(
      summaryResult.data
    )
      ? summaryResult.data[0]
      : summaryResult.data;

  const summary =
    summaryRaw &&
    typeof summaryRaw ===
      "object"
      ? (
          summaryRaw as Record<
            string,
            unknown
          >
        )
      : null;

  const stats:
    QuotesStats = {
      allCount:
        Number(
          summary?.all_count ??
            0
        ),

      openCount:
        Number(
          summary?.open_count ??
            0
        ),

      acceptedCount:
        Number(
          summary?.accepted_count ??
            0
        ),

      convertedCount:
        Number(
          summary?.converted_count ??
            0
        ),

      expiredOpenCount:
        Number(
          summary?.expired_open_count ??
            0
        ),
  };

  let traders:
    QuoteTrader[] =
      [];

  let products:
    QuoteProduct[] =
      [];

  if (canCreate) {
    const [
      tradersResult,
      productsResult,
    ] =
      await Promise.all([
        supabase
          .from(
            "traders"
          )
          .select(
            "id,name,area,status"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .neq(
            "status",
            "inactive"
          )
          .order(
            "name"
          ),

        supabase
          .from(
            "products"
          )
          .select(
            "id,name,sku,sale_price,unit,active"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .eq(
            "active",
            true
          )
          .order(
            "name"
          ),
      ]);

    if (
      tradersResult.error
    ) {
      initialError ??=
        "تعذر تحميل قائمة العملاء.";
    } else {
      traders =
        (tradersResult.data ??
          []) as QuoteTrader[];
    }

    if (
      productsResult.error
    ) {
      initialError ??=
        "تعذر تحميل قائمة الأصناف.";
    } else {
      products =
        (productsResult.data ??
          []) as QuoteProduct[];
    }
  }

  return (
    <>
      <Topbar
        title="عروض الأسعار"
        subtitle="أنشئ العرض، تابع حالته وحوّله لطلبية عند الاعتماد"
        companyName={
          context.companyName
        }
      />

      <QuotesClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        initialQuotes={
          initialQuotes
        }
        initialStats={
          stats
        }
        totalCount={
          totalCount
        }
        page={
          page
        }
        pageSize={
          pageSize
        }
        searchQuery={
          searchQuery
        }
        statusFilter={
          statusFilter
        }
        traders={
          traders
        }
        products={
          products
        }
        canCreate={
          canCreate
        }
        canUpdate={
          canUpdate
        }
        initialError={
          initialError
        }
      />
    </>
  );
}