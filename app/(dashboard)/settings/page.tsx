import { Topbar } from "@/components/topbar";
import { SettingsClient } from "@/components/settings/settings-client";

import { getCurrentContext } from "@/lib/current-context";
import { createClient } from "@/lib/supabase/server";

export default async function SettingsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const [{ data: profile }, { data: company }] = await Promise.all([
    supabase
      .from("profiles")
      .select("full_name")
      .eq("id", context.user.id)
      .maybeSingle(),
    supabase
      .from("companies")
      .select("id,name,phone,whatsapp,default_currency")
      .eq("id", context.companyId)
      .maybeSingle(),
  ]);

  return (
    <>
      <Topbar
        title="Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª"
        subtitle="Ø§Ù„Ø­Ø³Ø§Ø¨ØŒ Ø§Ù„Ø´Ø±ÙƒØ© ÙˆØ¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§Ù„Ù†Ø¸Ø§Ù…"
        companyName={context.companyName}
      />
      <SettingsClient
        email={context.email}
        roleName={context.roleName}
        isOwner={context.isOwner}
        permissions={context.permissions}
        initialName={profile?.full_name || context.userName}
        company={
          (company || {
            id: context.companyId,
            name: context.companyName,
            phone: null,
            whatsapp: null,
            default_currency: context.currency,
          })
        }
      />
    </>
  );
}

