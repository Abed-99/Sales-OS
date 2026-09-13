import { redirect } from "next/navigation";
import { CashboxClient } from "@/components/cashbox/cashbox-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { createClient } from "@/lib/supabase/server";

const TRANSACTION_PAGE_SIZE = 50;
const EXPENSE_PAGE_SIZE = 25;

function businessDate() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function positivePage(value: string | undefined) {
  const parsed = Number.parseInt(value ?? "1", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

function clean(value: string | undefined, max = 100) {
  return (value ?? "").trim().slice(0, max);
}

export default async function CashboxPage({
  searchParams,
}: {
  searchParams: Promise<{
    txPage?: string;
    expensePage?: string;
    q?: string;
    type?: string;
    cashbox?: string;
  }>;
}) {
  const {
    companyId,
    companyName,
    currency,
    isOwner,
    permissions,
  } = await getCurrentContext();

  const canViewCashbox =
    isOwner || permissions.includes("finance.cashbox_view");
  const canWriteCashbox =
    isOwner || permissions.includes("finance.cashbox_write");
  const canViewExpenses =
    isOwner ||
    permissions.includes("finance.expenses_view") ||
    permissions.includes("reports.finance") ||
    permissions.includes("reports.profit");
  const canWriteExpenses =
    isOwner || permissions.includes("finance.expenses_write");

  if (!canViewCashbox) {
    redirect("/");
  }

  const params = await searchParams;
  const txPage = positivePage(params.txPage);
  const expensePage = positivePage(params.expensePage);
  const q = clean(params.q, 80);
  const safeSearch = q
    .replace(/[^\p{L}\p{N}\s@_-]/gu, " ")
    .trim();
  const type = clean(params.type, 50);
  const cashboxFilter = clean(params.cashbox, 80);

  const supabase = await createClient();

  const cashboxesResult = await supabase
    .from("cashboxes")
    .select("id,name,currency,active")
    .eq("company_id", companyId)
    .eq("active", true)
    .order("created_at");

  const activeCashboxIds = new Set(
    (cashboxesResult.data ?? []).map((item) => item.id)
  );

  const safeCashboxFilter =
    cashboxFilter && activeCashboxIds.has(cashboxFilter)
      ? cashboxFilter
      : "";

  let transactionsQuery = supabase
    .from("cash_transactions")
    .select(
      `
        id,
        cashbox_id,
        direction,
        type,
        amount,
        notes,
        occurred_at,
        suppliers(name),
        cashboxes(name,currency)
      `,
      { count: "exact" }
    )
    .eq("company_id", companyId);

  if (safeCashboxFilter) {
    transactionsQuery = transactionsQuery.eq(
      "cashbox_id",
      safeCashboxFilter
    );
  }

  if (type) {
    transactionsQuery = transactionsQuery.eq("type", type);
  }

  if (safeSearch) {
    transactionsQuery = transactionsQuery.ilike(
      "notes",
      `%${safeSearch.replace(/[%_]/g, "\\$&")}%`
    );
  }

  const txFrom = (txPage - 1) * TRANSACTION_PAGE_SIZE;
  const txTo = txFrom + TRANSACTION_PAGE_SIZE - 1;

  const transactionsResult = await transactionsQuery
    .order("occurred_at", { ascending: false })
    .range(txFrom, txTo);

  let expenseData: any[] = [];
  let expenseError: { message: string } | null = null;
  let expenseCount = 0;

  if (canViewExpenses) {
    let expensesQuery = supabase
      .from("expenses")
      .select(
        `
          id,
          cashbox_id,
          category,
          amount,
          notes,
          occurred_at,
          cashboxes(name,currency)
        `,
        { count: "exact" }
      )
      .eq("company_id", companyId);

    if (safeCashboxFilter) {
      expensesQuery = expensesQuery.eq(
        "cashbox_id",
        safeCashboxFilter
      );
    }

    if (safeSearch) {
      const escaped = safeSearch.replace(/[%_]/g, "\\$&");
      expensesQuery = expensesQuery.or(
        `category.ilike.%${escaped}%,notes.ilike.%${escaped}%`
      );
    }

    const expenseFrom =
      (expensePage - 1) * EXPENSE_PAGE_SIZE;
    const expenseTo =
      expenseFrom + EXPENSE_PAGE_SIZE - 1;

    const result = await expensesQuery
      .order("occurred_at", { ascending: false })
      .range(expenseFrom, expenseTo);

    expenseData = result.data ?? [];
    expenseError = result.error;
    expenseCount = result.count ?? 0;
  }

  const summaryResult = await supabase.rpc(
    "get_cashbox_summary",
    {
      target_company: companyId,
      target_date: businessDate(),
    }
  );

  const pageError =
    cashboxesResult.error ||
    transactionsResult.error ||
    expenseError ||
    summaryResult.error
      ? "تعذر تحميل بعض بيانات الصندوق. جرّب تحديث الصفحة."
      : null;

  const txCount = transactionsResult.count ?? 0;
  const txTotalPages = Math.max(
    1,
    Math.ceil(txCount / TRANSACTION_PAGE_SIZE)
  );
  const expenseTotalPages = Math.max(
    1,
    Math.ceil(expenseCount / EXPENSE_PAGE_SIZE)
  );

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
        initialExpenses={expenseData}
        summary={summaryResult.data ?? []}
        canViewExpenses={canViewExpenses}
        canWriteCashbox={canWriteCashbox}
        canWriteExpenses={canWriteExpenses}
        pageError={pageError}
        txPage={Math.min(txPage, txTotalPages)}
        txTotalPages={txTotalPages}
        expensePage={Math.min(expensePage, expenseTotalPages)}
        expenseTotalPages={expenseTotalPages}
        q={q}
        type={type}
        cashboxFilter={safeCashboxFilter}
      />
    </>
  );
}
