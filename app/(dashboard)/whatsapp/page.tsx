import {
  WhatsAppClient,
  type DebtorRow,
  type OptInRow,
} from "@/components/whatsapp/whatsapp-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import type { OutboxMessage } from "@/components/whatsapp/outbox-panel";
import { createClient } from "@/lib/supabase/server";

export default async function WhatsAppPage() {
  const context = await getCurrentContext();
  const canView = hasAnyPermission(
    context.permissions,
    ["traders.view", "traders.view_balance"],
    context.isOwner,
  );

  if (!canView) {
    return (
      <>
        <Topbar title="مركز واتساب" subtitle="الرسائل والحملات" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية.</section>
        </div>
      </>
    );
  }

  const canSeeBalances = hasAnyPermission(
    context.permissions,
    ["traders.view_balance", "reports.finance", "payments.sales_view"],
    context.isOwner,
  );

  const supabase = await createClient();
  await supabase.rpc("refresh_whatsapp_outbox", { target_company: context.companyId });

  const [invoices, optIns, pendingResult, recentResult, companyResult] = await Promise.all([
    canSeeBalances
      ? supabase
          .from("sales_invoices")
          .select("trader_id,balance_due,currency,due_date,traders!inner(id,name,phone,whatsapp)")
          .eq("company_id", context.companyId)
          .eq("status", "posted")
          .gt("balance_due", 0)
          .limit(1000)
      : Promise.resolve({ data: [] as never[] }),
    supabase
      .from("traders")
      .select("id,name,phone,whatsapp,area")
      .eq("company_id", context.companyId)
      .eq("whatsapp_marketing_opt_in", true)
      .neq("status", "inactive")
      .order("name")
      .limit(1000),
    supabase
      .from("whatsapp_outbox")
      .select(
        "id,kind,trader_id,phone,message,document_type,document_id,status,created_at,sent_at,traders(name,phone,whatsapp)",
      )
      .eq("company_id", context.companyId)
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(200),
    supabase
      .from("whatsapp_outbox")
      .select(
        "id,kind,trader_id,phone,message,document_type,document_id,status,created_at,sent_at,traders(name,phone,whatsapp)",
      )
      .eq("company_id", context.companyId)
      .neq("status", "pending")
      .order("sent_at", { ascending: false, nullsFirst: false })
      .limit(20),
    supabase
      .from("companies")
      .select("whatsapp_settings,whatsapp_templates")
      .eq("id", context.companyId)
      .maybeSingle(),
  ]);

  const defaults = {
    invoice: "مرحبا {الاسم}، هي فاتورتك رقم {الرقم} بقيمة {المبلغ}. شكرًا لتعاملك معنا 🌷 {الشركة}",
    receipt: "مرحبا {الاسم}، استلمنا منك {المبلغ}، شكرًا إلك. رصيدك الحالي: {الباقي}. {الشركة}",
    delivery: "مرحبا {الاسم}، طلبيتك رقم {الرقم} طلعت بالطريق إليك{السائق}. {الشركة}",
    reminder:
      "مرحبا {الاسم}، تذكير لطيف: عليك رصيد {الباقي}، منو {المبلغ} متأخر. منشكر تعاونك 🌷 {الشركة}",
    statement: "مرحبا {الاسم}، هاد كشف حسابك لغاية {الشهر}. الرصيد: {الباقي}. {الشركة}",
  };

  // ديون كل زبون (مجمّعة من فواتيره المفتوحة).
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
  const debtors = new Map<string, DebtorRow>();
  for (const row of (invoices.data ?? []) as unknown as {
    trader_id: string;
    balance_due: number;
    currency: string;
    due_date: string | null;
    traders: { id: string; name: string; phone: string | null; whatsapp: string | null };
  }[]) {
    const trader = Array.isArray(row.traders) ? row.traders[0] : row.traders;
    const current = debtors.get(row.trader_id) ?? {
      id: row.trader_id,
      name: trader?.name ?? "",
      phone: trader?.whatsapp || trader?.phone || null,
      balance: 0,
      overdue: 0,
      currency: row.currency,
    };
    current.balance += Number(row.balance_due);
    if (row.due_date && row.due_date < today) current.overdue += Number(row.balance_due);
    debtors.set(row.trader_id, current);
  }

  return (
    <>
      <Topbar
        title="مركز واتساب"
        subtitle="تذكير الزبائن بالديون، كشوف الحساب، والحملات"
        companyName={context.companyName}
      />
      <WhatsAppClient
        companyId={context.companyId}
        companyName={context.companyName}
        pending={(pendingResult.data ?? []) as unknown as OutboxMessage[]}
        recent={(recentResult.data ?? []) as unknown as OutboxMessage[]}
        settings={{
          invoice: true,
          receipt: true,
          delivery: true,
          reminder: true,
          statement: true,
          reminder_days: 7,
          ...((companyResult.data?.whatsapp_settings ?? {}) as object),
        }}
        templates={(companyResult.data?.whatsapp_templates ?? {}) as Record<string, string>}
        defaults={defaults}
        canManageSettings={hasPermission(
          context.permissions,
          "settings.manage_company",
          context.isOwner,
        )}
        debtors={[...debtors.values()].sort(
          (a, b) => b.overdue - a.overdue || b.balance - a.balance,
        )}
        optIns={(optIns.data ?? []) as OptInRow[]}
      />
    </>
  );
}
