import { Topbar } from "@/components/topbar";
import { SettingsClient } from "@/components/settings/settings-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function SettingsPage() {
  const context = await getCurrentContext();
  const canView = hasPermission(context.permissions, "settings.view", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar
          title="الإعدادات"
          subtitle="الحساب، الشركة وإعدادات النظام"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض الإعدادات.</section>
        </div>
      </>
    );
  }

  const supabase = await createClient();

  const [profileResult, companyResult] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", context.user.id).maybeSingle(),
    supabase
      .from("companies")
      .select(
        "id,name,phone,whatsapp,address,default_currency,tax_enabled,tax_rate,tax_number,tax_label",
      )
      .eq("id", context.companyId)
      .maybeSingle(),
  ]);

  // بعد أول قيد محاسبي ما عاد فينا نغيّر العملة الأساسية.
  const { data: hasPin } = await supabase.rpc("has_owner_pin", {
    target_company: context.companyId,
  });

  const { count: journalCount } = await supabase
    .from("journal_entries")
    .select("id", { count: "exact", head: true })
    .eq("company_id", context.companyId);

  const profile = profileResult.data;

  const company = companyResult.data;

  const pageError = Boolean(profileResult.error) || Boolean(companyResult.error);

  return (
    <>
      <Topbar
        title="الإعدادات"
        subtitle="الحساب، الشركة وإعدادات النظام"
        companyName={context.companyName}
      />
      {pageError && (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض بيانات الإعدادات. حاول تحديث الصفحة.
          </div>
        </div>
      )}

      <SettingsClient
        email={context.email}
        roleName={context.roleName}
        isOwner={context.isOwner}
        permissions={context.permissions}
        initialName={profile?.full_name || context.userName}
        currencyLocked={(journalCount ?? 0) > 0}
        hasOwnerPin={Boolean(hasPin)}
        company={
          company || {
            id: context.companyId,
            name: context.companyName,
            phone: null,
            whatsapp: null,
            address: null,
            default_currency: context.currency,
          }
        }
      />
    </>
  );
}
