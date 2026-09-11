import { Topbar } from "@/components/topbar";
import { SuppliersClient } from "@/components/suppliers/suppliers-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

export default async function SuppliersPage() {
  const { companyId, companyName } = await getCurrentContext();
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("suppliers")
    .select("*")
    .eq("company_id", companyId)
    .order("created_at", { ascending: false });

  return (
    <>
      <Topbar
        title="Ø§Ù„Ù…ÙˆØ±Ø¯ÙˆÙ†"
        subtitle="Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…ÙˆØ±Ø¯ÙŠÙ†ØŒ Ø§Ù„ØªÙˆØ§ØµÙ„ ÙˆØ£Ø³Ø¹Ø§Ø± Ø§Ù„Ø´Ø±Ø§Ø¡"
        companyName={companyName}
      />
      <SuppliersClient
        companyId={companyId}
        initialRows={data || []}
        initialError={error?.message || null}
      />
    </>
  );
}

