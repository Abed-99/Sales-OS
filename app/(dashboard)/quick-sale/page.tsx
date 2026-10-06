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
  const [productsResult, cashboxesResult, companyResult] = await Promise.all([
    supabase
      .from("products")
      .select("id,name,sku,unit,sale_price,active,pack_size,pack_unit,barcode")
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
    supabase
      .from("companies")
      .select("tax_enabled,tax_rate,tax_label")
      .eq("id", context.companyId)
      .maybeSingle(),
  ]);

  const tax = companyResult.data?.tax_enabled
    ? { rate: Number(companyResult.data.tax_rate), label: companyResult.data.tax_label }
    : null;

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
        tax={tax}
        canPayDelivery={hasPermission(context.permissions, "finance.expenses_write", context.isOwner)}
      />
    </>
  );
}
