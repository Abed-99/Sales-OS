import { CashboxClient } from "@/components/cashbox/cashbox-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { createClient } from "@/lib/supabase/server";

function businessDate() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

export default async function CashboxPage() {
  const { companyId, companyName, currency } =
    await getCurrentContext();

  const supabase = await createClient();

  const [
    cashboxesResult,
    transactionsResult,
    expensesResult,
    summaryResult,
  ] = await Promise.all([
    supabase
      .from("cashboxes")
      .select("id,name,currency,active")
      .eq("company_id", companyId)
      .eq("active", true)
      .order("created_at"),

    supabase
      .from("cash_transactions")
      .select(`
        id,
        cashbox_id,
        direction,
        type,
        amount,
        notes,
        occurred_at,
        suppliers(name),
        cashboxes(name,currency)
      `)
      .eq("company_id", companyId)
      .order("occurred_at", { ascending: false })
      .limit(250),

    supabase
      .from("expenses")
      .select(`
        id,
        cashbox_id,
        category,
        amount,
        notes,
        occurred_at,
        cashboxes(name,currency)
      `)
      .eq("company_id", companyId)
      .order("occurred_at", { ascending: false })
      .limit(100),

    supabase.rpc("get_cashbox_summary", {
      target_company: companyId,
      target_date: businessDate(),
    }),
  ]);

  for (const result of [
    cashboxesResult,
    transactionsResult,
    expensesResult,
    summaryResult,
  ]) {
    if (result.error) {
      throw new Error(result.error.message);
    }
  }

  return (
    <>
      <Topbar
        title="الصندوق والمصاريف"
        subtitle="القبض، الدفعات، المصاريف والتسويات حسب كل صندوق وعملة"
        companyName={companyName}
      />

      <CashboxClient
        companyId={companyId}
        defaultCurrency={currency}
        cashboxes={cashboxesResult.data ?? []}
        initialTransactions={transactionsResult.data ?? []}
        initialExpenses={expensesResult.data ?? []}
        summary={summaryResult.data ?? []}
      />
    </>
  );
}
