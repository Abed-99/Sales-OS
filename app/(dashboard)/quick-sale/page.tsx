import { QuickSaleClient } from "@/components/quick-sale/quick-sale-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function QuickSalePage() {
  const context = await getCurrentContext();
  const canSell = hasPermission(context.permissions, "sales.quick_sale", context.isOwner);

  if (!canSell) {
    return (
      <>
        <Topbar title="بيع سريع" subtitle="كاشير" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية البيع السريع.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const [productsResult, cashboxesResult] = await Promise.all([
    supabase
      .from("products")
      .select("id,name,sku,unit,sale_price,active,pack_size,pack_unit")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name")
      .limit(300),
    supabase
      .from("cashboxes")
      .select("id,name,currency")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("created_at"),
  ]);

  return (
    <>
      <Topbar
        title="بيع سريع"
        subtitle="زبون بالمحل: اختار الأصناف، اقبض، خلصنا"
        companyName={context.companyName}
      />
      <QuickSaleClient
        companyId={context.companyId}
        currency={context.currency}
        products={productsResult.data ?? []}
        cashboxes={cashboxesResult.data ?? []}
      />
    </>
  );
}
