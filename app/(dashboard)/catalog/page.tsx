import { CatalogClient, type CatalogLink } from "@/components/catalog/catalog-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function CatalogPage({
  searchParams,
}: {
  searchParams: Promise<{ trader?: string }>;
}) {
  const { trader } = await searchParams;
  const context = await getCurrentContext();
  const canManage = hasAnyPermission(
    context.permissions,
    ["orders.create", "products.update"],
    context.isOwner,
  );

  if (!canManage) {
    return (
      <>
        <Topbar title="الكتالوج" subtitle="روابط البضاعة للتجار" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const [links, categories, levels, preset] = await Promise.all([
    supabase
      .from("catalog_links")
      .select(
        "id,token,title,trader_id,show_prices,price_level_id,show_description,show_images,stock_mode,hide_out_of_stock,category_ids,allow_orders,active,expires_at,view_count,last_viewed_at,created_at,traders(name,phone,whatsapp)",
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false })
      .limit(200),
    supabase.from("categories").select("id,name").eq("company_id", context.companyId).order("name"),
    supabase
      .from("price_levels")
      .select("id,name")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("sort_order"),
    trader
      ? supabase
          .from("traders")
          .select("id,name,area,phone,whatsapp,price_level_id")
          .eq("company_id", context.companyId)
          .eq("id", trader)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  return (
    <>
      <Topbar
        title="الكتالوج"
        subtitle="رابط بضاعة بتبعتو للتاجر: بتختار شو يبين فيه (سعر، شرح، صور، مخزون)"
        companyName={context.companyName}
      />
      <CatalogClient
        companyId={context.companyId}
        links={(links.data ?? []) as unknown as CatalogLink[]}
        categories={categories.data ?? []}
        priceLevels={levels.data ?? []}
        presetTrader={preset.data ?? null}
      />
    </>
  );
}
