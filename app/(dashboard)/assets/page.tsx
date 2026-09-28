import { Topbar } from "@/components/topbar";
import {
  AssetsClient,
  type FixedAsset,
  type AssetDepreciation,
} from "@/components/assets/assets-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function AssetsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasPermission(context.permissions, "assets.view", context.isOwner);

  const canManage = hasPermission(context.permissions, "assets.manage", context.isOwner);

  const canDepreciate = hasPermission(context.permissions, "assets.depreciate", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar
          title="الأصول"
          subtitle="الأصول الثابتة والإهلاك"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض الأصول.</section>
        </div>
      </>
    );
  }

  const [assetsResult, depreciationResult, cashboxesResult] = await Promise.all([
    supabase
      .from("fixed_asset_summary")
      .select(
        "id,asset_number,name,category,description,purchase_date,in_service_date,currency,purchase_cost,salvage_value,useful_life_months,depreciation_method,accumulated_depreciation,status,disposal_date,disposal_amount,notes,created_at,book_value,monthly_depreciation",
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false }),

    supabase
      .from("asset_depreciation_entries")
      .select("id,asset_id,period_start,period_end,amount,posted_at")
      .eq("company_id", context.companyId)
      .order("period_end", { ascending: false })
      .limit(100),

    supabase
      .from("cashboxes")
      .select("id,name,currency")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
  ]);
  const pageError = Boolean(assetsResult.error) || Boolean(depreciationResult.error);

  return (
    <>
      <Topbar
        title="الأصول الثابتة"
        subtitle="الأصول، القيمة الدفترية والإهلاك الشهري"
        companyName={context.companyName}
      />

      {pageError && (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض بيانات الأصول. حاول تحديث الصفحة.
          </div>
        </div>
      )}

      <AssetsClient
        companyId={context.companyId}
        baseCurrency={context.currency}
        assets={(assetsResult.data ?? []) as unknown as FixedAsset[]}
        depreciation={(depreciationResult.data ?? []) as unknown as AssetDepreciation[]}
        cashboxes={cashboxesResult.data ?? []}
        canManage={canManage}
        canDepreciate={canDepreciate}
      />
    </>
  );
}
