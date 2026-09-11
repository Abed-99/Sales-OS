import { Topbar } from "@/components/topbar";
import { CustomersClient } from "@/components/customers/customers-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

export default async function CustomersPage() {
  const { companyId, companyName } = await getCurrentContext();
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("traders")
    .select(
      "id,name,contact_name,phone,whatsapp,area,address,latitude,longitude,status,notes,whatsapp_marketing_opt_in,credit_limit,payment_terms_days,created_at,updated_at"
    )
    .eq("company_id", companyId)
    .order("created_at", { ascending: false });

  return (
    <>
      <Topbar
        title="Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡"
        subtitle="Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡ØŒ Ø§Ù„ØªÙˆØ§ØµÙ„ØŒ Ø§Ù„Ø²ÙŠØ§Ø±Ø§Øª ÙˆØ§Ù„Ù…ØªØ§Ø¨Ø¹Ø©"
        companyName={companyName}
      />
      <CustomersClient
        companyId={companyId}
        initialTraders={data || []}
        initialError={error?.message || null}
      />
    </>
  );
}

