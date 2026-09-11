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

export default async function FinancePage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "finance.accounts_view",
      "reports.finance",
      "finance.cashbox_view",
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
        "id,entry_number,entry_date,description,status,currency,exchange_rate_to_base,source_type,source_id,created_at"
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

  for (const result of results) {
    if (result.error) {
      throw new Error(result.error.message);
    }
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
        canWrite={canWrite}
        canManualJournal={canManualJournal}
        canClose={canClose}
        canReopen={canReopen}
      />
    </>
  );
}