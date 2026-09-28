import { notFound } from "next/navigation";

import { TraderDetailClient } from "@/components/customers/trader-detail-client";
import type {
  TraderOrderRow,
  TraderSalesSummary,
  TraderVisitRow,
} from "@/components/customers/trader-detail-client";
import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function CustomerDetailPage({
  params,
}: {
  params: Promise<{
    id: string;
  }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();

  const canView = hasPermission(context.permissions, "traders.view", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar title="العميل" subtitle="ملف العميل" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />

              <h3>لا تملك صلاحية عرض العملاء</h3>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canViewVisits = hasAnyPermission(
    context.permissions,
    ["visits.view", "reports.team"],
    context.isOwner,
  );

  const canCreateVisit = hasPermission(context.permissions, "visits.create", context.isOwner);

  const canViewOrders = hasPermission(context.permissions, "orders.view", context.isOwner);

  const canViewFinancials = hasAnyPermission(
    context.permissions,
    [
      "sales_invoices.view",
      "payments.sales_view",
      "payments.sales_create",
      "traders.view_balance",
      "reports.sales",
      "reports.finance",
      "reports.profit",
    ],
    context.isOwner,
  );

  const canViewBalance = hasPermission(
    context.permissions,
    "traders.view_balance",
    context.isOwner,
  );

  const canViewMap = hasPermission(context.permissions, "map.view", context.isOwner);

  const supabase = await createClient();

  const traderResult = await supabase
    .from("traders")
    .select(
      "id,name,contact_name,phone,whatsapp,area,address,latitude,longitude,status,notes,whatsapp_marketing_opt_in,credit_limit,payment_terms_days,created_at,updated_at",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (traderResult.error) {
    return (
      <>
        <Topbar title="العميل" subtitle="ملف العميل" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.users size={30} />

              <h3>تعذر تحميل بيانات العميل</h3>

              <p>حاول تحديث الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  if (!traderResult.data) {
    notFound();
  }

  let visits: TraderVisitRow[] = [];

  let visitCount = 0;

  let orders: TraderOrderRow[] = [];

  let orderCount = 0;

  let salesSummary: TraderSalesSummary | null = null;

  let relatedError: string | null = null;

  if (canViewVisits) {
    const result = await supabase
      .from("trader_visits")
      .select("id,result,notes,contacted_at,next_follow_up_at", {
        count: "exact",
      })
      .eq("company_id", context.companyId)
      .eq("trader_id", id)
      .order("contacted_at", {
        ascending: false,
      })
      .limit(100);

    if (result.error) {
      relatedError = "تعذر تحميل بعض بيانات العميل.";

      visits = [];
      visitCount = 0;
    } else {
      visits = result.data ?? [];

      visitCount = result.count ?? 0;
    }
  }

  if (canViewOrders) {
    const result = await supabase
      .from("sales_orders")
      .select("id,status,total,created_at", {
        count: "exact",
      })
      .eq("company_id", context.companyId)
      .eq("trader_id", id)
      .neq("status", "cancelled")
      .order("created_at", {
        ascending: false,
      })
      .limit(5);

    if (result.error) {
      relatedError = "تعذر تحميل بعض بيانات العميل.";

      orders = [];
      orderCount = 0;
    } else {
      orders = result.data ?? [];

      orderCount = result.count ?? 0;
    }
  }

  if (canViewFinancials) {
    const result = await supabase.rpc("get_trader_sales_summary", {
      target_company: context.companyId,

      target_trader: id,
    });

    if (result.error) {
      relatedError = "تعذر تحميل بعض بيانات العميل.";
    } else {
      const raw = Array.isArray(result.data) ? result.data[0] : result.data;

      if (raw) {
        salesSummary = {
          invoice_count: Number(raw.invoice_count ?? 0),

          total_invoiced: Number(raw.total_invoiced ?? 0),

          outstanding: Number(raw.outstanding ?? 0),

          currency: String(raw.currency ?? context.currency),
        };
      }
    }
  }

  return (
    <>
      <Topbar
        title={traderResult.data.name}
        subtitle="ملف العميل، الزيارات والمتابعات والمبيعات"
        companyName={context.companyName}
      />

      <TraderDetailClient
        companyId={context.companyId}
        currency={context.currency}
        trader={traderResult.data}
        initialVisits={visits}
        visitCount={visitCount}
        orders={orders}
        orderCount={orderCount}
        salesSummary={salesSummary}
        canViewVisits={canViewVisits}
        canCreateVisit={canCreateVisit}
        canViewOrders={canViewOrders}
        canViewFinancials={canViewFinancials}
        canViewBalance={canViewBalance}
        canViewMap={canViewMap}
        initialError={relatedError}
      />
    </>
  );
}
