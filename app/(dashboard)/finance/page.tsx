import { Topbar } from "@/components/topbar";
import {
  FinanceClient,
  type FinanceAccount,
  type FinanceJournal,
  type FinancePeriod,
  type FinanceRate,
  type TrialBalanceRow,
} from "@/components/finance/finance-client";
import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

type FinanceTab =
  | "overview"
  | "accounts"
  | "journals"
  | "rates"
  | "periods";

type FinanceSearchParams = {
  tab?: string | string[];
  journalPage?: string | string[];
  ratePage?: string | string[];
  periodPage?: string | string[];
};

function readPage(
  value: string | string[] | undefined
) {
  const raw = Array.isArray(value)
    ? value[0]
    : value;

  const parsed = Number.parseInt(
    raw ?? "1",
    10
  );

  return Number.isFinite(parsed) &&
    parsed > 0
    ? parsed
    : 1;
}

export default async function FinancePage({
  searchParams,
}: {
  searchParams: Promise<FinanceSearchParams>;
}) {
  const params = await searchParams;
  const pageSize = 50;

  const requestedTab =
    Array.isArray(params.tab)
      ? params.tab[0]
      : params.tab;

  const initialTab: FinanceTab =
    requestedTab === "accounts" ||
    requestedTab === "journals" ||
    requestedTab === "rates" ||
    requestedTab === "periods"
      ? requestedTab
      : "overview";

  const journalPage = readPage(
    params.journalPage
  );
  const ratePage = readPage(
    params.ratePage
  );
  const periodPage = readPage(
    params.periodPage
  );

  const journalFrom =
    (journalPage - 1) * pageSize;
  const journalTo =
    journalFrom + pageSize - 1;

  const rateFrom =
    (ratePage - 1) * pageSize;
  const rateTo =
    rateFrom + pageSize - 1;

  const periodFrom =
    (periodPage - 1) * pageSize;
  const periodTo =
    periodFrom + pageSize - 1;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "finance.accounts_view",
      "reports.finance",
    ],
    context.isOwner
  );

  const canWrite = hasPermission(
    context.permissions,
    "finance.accounts_write",
    context.isOwner
  );

  const canManualJournal = hasPermission(
    context.permissions,
    "finance.manual_journal",
    context.isOwner
  );

  const canClose = hasPermission(
    context.permissions,
    "finance.month_close",
    context.isOwner
  );

  const canReopen = hasPermission(
    context.permissions,
    "finance.month_reopen",
    context.isOwner
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="المالية"
          subtitle="الحسابات والقيود"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض المالية.
          </section>
        </div>
      </>
    );
  }

  const [
    accountsResult,
    trialResult,
    journalsResult,
    ratesResult,
    periodsResult,
  ] = await Promise.all([
    supabase
      .from("finance_accounts")
      .select(
        "id,parent_id,code,name,account_type,account_group,normal_balance,system_key,allow_posting,is_system,active"
      )
      .eq("company_id", context.companyId)
      .order("code"),

    supabase
      .from("finance_trial_balance")
      .select(
        "company_id,account_id,code,name,account_type,account_group,normal_balance,debit,credit,balance"
      )
      .eq("company_id", context.companyId)
      .order("code"),

    supabase
      .from("journal_entries")
      .select(
        "id,entry_number,entry_date,description,status,currency,exchange_rate_to_base,source_type,source_id,reversed_from_id,created_at"
      )
      .eq("company_id", context.companyId)
      .order("entry_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(150),

    supabase
      .from("finance_exchange_rates")
      .select(
        "id,currency,rate_date,rate_to_base,source,notes,created_at"
      )
      .eq("company_id", context.companyId)
      .order("rate_date", { ascending: false })
      .limit(100),

    supabase
      .from("finance_periods")
      .select(
        "id,period_start,period_end,status,closed_at,reopened_at,created_at"
      )
      .eq("company_id", context.companyId)
      .order("period_start", { ascending: false })
      .limit(60),
  ]);

  const results = [
    accountsResult,
    trialResult,
    journalsResult,
    ratesResult,
    periodsResult,
  ];

  const failedResult = results.find(
    (result) => result.error
  );

  if (failedResult?.error) {
    console.error(
      "Finance data load failed",
      failedResult.error
    );

    return (
      <>
        <Topbar
          title="المالية"
          subtitle="المحاسبة المزدوجة، القيود، الحسابات والفترات المالية"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            تعذر تحميل البيانات المالية. حاول مرة أخرى.
          </section>
        </div>
      </>
    );
  }

  return (
    <>
      <Topbar
        title="المالية"
        subtitle="المحاسبة المزدوجة، القيود، الحسابات والفترات المالية"
        companyName={context.companyName}
      />

      <FinanceClient
        companyId={context.companyId}
        baseCurrency={context.currency}
        accounts={
          (accountsResult.data ?? []) as unknown as FinanceAccount[]
        }
        trialBalance={
          (trialResult.data ?? []) as unknown as TrialBalanceRow[]
        }
        journals={
          (journalsResult.data ?? []) as unknown as FinanceJournal[]
        }
        rates={
          (ratesResult.data ?? []) as unknown as FinanceRate[]
        }
        periods={
          (periodsResult.data ?? []) as unknown as FinancePeriod[]
        }
        initialTab={initialTab}
      journalPage={journalPage}
      journalCount={journalsResult.count ?? 0}
      ratePage={ratePage}
      rateCount={ratesResult.count ?? 0}
      periodPage={periodPage}
      periodCount={periodsResult.count ?? 0}
      pageSize={pageSize}
      canWrite={canWrite}
        canManualJournal={canManualJournal}
        canReverseManualJournal={
          hasPermission(
            context.permissions,
            "finance.manual_journal_reverse",
            context.isOwner
          )
        }
        canClose={canClose}
        canReopen={canReopen}
      />
    </>
  );
}