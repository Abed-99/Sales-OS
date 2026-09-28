import { Topbar } from "@/components/topbar";
import {
  PartnersClient,
  type PartnerSummary,
  type PartnerTransaction,
  type PartnerCashbox,
} from "@/components/partners/partners-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function PartnersPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasPermission(context.permissions, "partners.view", context.isOwner);

  const canManage = hasPermission(context.permissions, "partners.manage", context.isOwner);

  const canTransact = hasPermission(context.permissions, "partners.transactions", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar
          title="الشركاء"
          subtitle="رأس المال وحركات الشركاء"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض الشركاء.</section>
        </div>
      </>
    );
  }

  const [partnersResult, transactionsResult, cashboxesResult] = await Promise.all([
    supabase
      .from("partner_summary")
      .select(
        "id,partner_number,name,phone,ownership_percent,profit_share_percent,active,notes,capital_contributions,drawings,partner_loan_balance,profit_distributions",
      )
      .eq("company_id", context.companyId)
      .order("name"),

    supabase
      .from("partner_transactions")
      .select(
        "id,partner_id,transaction_type,amount,currency,cashbox_id,transaction_date,notes,created_at",
      )
      .eq("company_id", context.companyId)
      .order("transaction_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(150),

    supabase
      .from("cashboxes")
      .select("id,name,currency,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("created_at"),
  ]);

  const results = [partnersResult, transactionsResult, cashboxesResult];

  const pageError = results.some((result) => Boolean(result.error));

  return (
    <>
      <Topbar
        title="الشركاء"
        subtitle="الملكية، رأس المال، المسحوبات والقروض والأرباح"
        companyName={context.companyName}
      />

      {pageError && (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض بيانات الشركاء. حاول تحديث الصفحة.
          </div>
        </div>
      )}

      <PartnersClient
        companyId={context.companyId}
        baseCurrency={context.currency}
        partners={(partnersResult.data ?? []) as unknown as PartnerSummary[]}
        transactions={(transactionsResult.data ?? []) as unknown as PartnerTransaction[]}
        cashboxes={(cashboxesResult.data ?? []) as unknown as PartnerCashbox[]}
        canManage={canManage}
        canTransact={canTransact}
      />
    </>
  );
}
