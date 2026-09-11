import { notFound } from "next/navigation";
import { Topbar } from "@/components/topbar";
import { TraderDetailClient } from "@/components/customers/trader-detail-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

export default async function CustomerDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const [traderResult, visitsResult, ordersResult] = await Promise.all([
    supabase
      .from("traders")
      .select(
        "id,name,contact_name,phone,whatsapp,area,address,latitude,longitude,status,notes,whatsapp_marketing_opt_in,credit_limit,payment_terms_days,created_at,updated_at"
      )
      .eq("company_id", context.companyId)
      .eq("id", id)
      .maybeSingle(),
    supabase
      .from("trader_visits")
      .select("id,result,notes,contacted_at,next_follow_up_at")
      .eq("company_id", context.companyId)
      .eq("trader_id", id)
      .order("contacted_at", { ascending: false }),
    supabase
      .from("sales_orders")
      .select("id,status,total,created_at")
      .eq("company_id", context.companyId)
      .eq("trader_id", id)
      .order("created_at", { ascending: false }),
  ]);

  if (traderResult.error) throw new Error(traderResult.error.message);
  if (visitsResult.error) throw new Error(visitsResult.error.message);
  if (ordersResult.error) throw new Error(ordersResult.error.message);
  if (!traderResult.data) notFound();

  return (
    <>
      <Topbar
        title={traderResult.data.name}
        subtitle="ملف العميل، الزيارات والمتابعات والطلبات"
        companyName={context.companyName}
      />
      <TraderDetailClient
        companyId={context.companyId}
        trader={traderResult.data}
        initialVisits={visitsResult.data ?? []}
        orders={ordersResult.data ?? []}
      />
    </>
  );
}
