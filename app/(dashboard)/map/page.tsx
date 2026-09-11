import { MapShell } from "@/components/map/map-shell";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
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

  const { companyId, companyName } = await getCurrentContext();
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("traders")
    .select(
      "id,name,area,address,phone,whatsapp,latitude,longitude,status"
    )
    .eq("company_id", companyId)
    .not("latitude", "is", null)
    .not("longitude", "is", null)
    .order("area");

  if (error) {
    throw new Error(error.message);
  }

  return (
    <>
      <Topbar
        title="خريطة السوق"
        subtitle="كل التجار ذوي الموقع، مع ترتيب جولة تقريبي"
        companyName={companyName}
      />
      <MapShell
        traders={data ?? []}
        initialTraderId={initialTraderId}
      />
    </>
  );
}
