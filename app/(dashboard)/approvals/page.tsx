import { Topbar } from "@/components/topbar";
import {
  ApprovalsClient,
  type ApprovalLookups,
  type ApprovalRequest,
} from "@/components/approvals/approvals-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

function uuidList(values: unknown[]) {
  return [
    ...new Set(
      values.filter(
        (value): value is string => typeof value === "string" && /^[0-9a-f-]{36}$/i.test(value),
      ),
    ),
  ];
}

export default async function ApprovalsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    ["approvals.view", "approvals.resolve"],
    context.isOwner,
  );

  const canResolve = hasPermission(context.permissions, "approvals.resolve", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar title="الموافقات" subtitle="طلبات الموافقة" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض الموافقات.</section>
        </div>
      </>
    );
  }

  const { data, error } = await supabase
    .from("approval_requests")
    .select(
      "id,request_type,reference_type,reference_id,title,description,payload,status,requested_at,resolved_at,resolution_notes,requested_by,resolved_by,created_at",
    )
    .eq("company_id", context.companyId)
    .order("requested_at", { ascending: false })
    .limit(200);

  const requests = (data ?? []) as unknown as ApprovalRequest[];

  // الطلب محفوظ بأرقام تعريف (زبون، أصناف، عرض سعر). منجيب الأسماء لحتى المالك يفهم شو عم يوافق عليه.
  const payloads = requests.map((request) => request.payload ?? {});
  const traderIds = uuidList(payloads.map((payload) => payload.trader_id));
  const quoteIds = uuidList(payloads.map((payload) => payload.source_quote_id));
  const productIds = uuidList(
    payloads.flatMap((payload) =>
      Array.isArray(payload.items)
        ? payload.items.map((item: { product_id?: unknown }) => item?.product_id)
        : [],
    ),
  );

  const [membersResult, tradersResult, productsResult, quotesResult] = await Promise.all([
    supabase.rpc("get_company_member_names", { target_company: context.companyId }),
    traderIds.length
      ? supabase.from("traders").select("id,name").in("id", traderIds)
      : Promise.resolve({ data: [] as { id: string; name: string }[] }),
    productIds.length
      ? supabase.from("products").select("id,name,unit").in("id", productIds)
      : Promise.resolve({ data: [] as { id: string; name: string; unit: string | null }[] }),
    quoteIds.length
      ? supabase.from("sales_quotes").select("id,quote_number").in("id", quoteIds)
      : Promise.resolve({ data: [] as { id: string; quote_number: string }[] }),
  ]);

  const lookups: ApprovalLookups = {
    members: Object.fromEntries(
      ((membersResult.data ?? []) as { user_id: string; name: string }[]).map((row) => [
        row.user_id,
        row.name,
      ]),
    ),
    traders: Object.fromEntries((tradersResult.data ?? []).map((row) => [row.id, row.name])),
    products: Object.fromEntries(
      (productsResult.data ?? []).map((row) => [
        row.id,
        { name: row.name, unit: row.unit ?? null },
      ]),
    ),
    quotes: Object.fromEntries((quotesResult.data ?? []).map((row) => [row.id, row.quote_number])),
  };

  return (
    <>
      <Topbar
        title="الموافقات"
        subtitle="الطلبات المعلقة والمقبولة والمرفوضة"
        companyName={context.companyName}
      />

      {error ? (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض بيانات الموافقات. حاول تحديث الصفحة.
          </div>
        </div>
      ) : null}

      <ApprovalsClient
        companyId={context.companyId}
        currency={context.currency}
        requests={requests}
        lookups={lookups}
        canResolve={canResolve}
      />
    </>
  );
}
