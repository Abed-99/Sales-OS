import { MapShell, type MapTrader } from "@/components/map/map-shell";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function MapPage({
  searchParams,
}: {
  searchParams: Promise<{ trader?: string | string[] }>;
}) {
  const params = await searchParams;
  const initialTraderId = Array.isArray(params.trader)
    ? params.trader[0] ?? null
    : params.trader ?? null;

  const context =
    await getCurrentContext();

  const {
    companyId,
    companyName,
    currency,
  } = context;

  const canView =
    hasPermission(
      context.permissions,
      "map.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="خريطة السوق"
          subtitle="مواقع التجار"
          companyName={companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض الخريطة.
          </section>
        </div>
      </>
    );
  }

  const supabase =
    await createClient();

  const { data, error } =
    await supabase.rpc(
      "get_map_traders",
      {
        target_company:
          companyId,
      }
    );

  const traders =
    error
      ? []
      : ((data ?? []) as unknown as MapTrader[]);

  return (
    <>
      <Topbar
        title="خريطة السوق"
        subtitle="مواقع الزبائن، ديونهم، وأقصر طريق للتوصيل"
        companyName={companyName}
      />
      {error && (
        <div className="page">
          <div
            className="toastError"
            role="alert"
          >
            تعذر تحميل مواقع التجار. حاول تحديث الصفحة.
          </div>
        </div>
      )}

      <MapShell
        traders={traders}
        initialTraderId={initialTraderId}
        companyId={companyId}
        currency={currency}
        canEditLocation={hasPermission(
          context.permissions,
          "traders.update",
          context.isOwner
        )}
      />
    </>
  );
}
