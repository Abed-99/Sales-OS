"use client";

import {
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type FinanceAccount = {
  id: string;
  parent_id: string | null;
  code: string;
  name: string;
  account_type:
    | "asset"
    | "liability"
    | "equity"
    | "revenue"
    | "expense";
  account_group: string | null;
  normal_balance:
    | "debit"
    | "credit";
  system_key: string | null;
  allow_posting: boolean;
  is_system: boolean;
  active: boolean;
};

export type TrialBalanceRow = {
  company_id: string;
  account_id: string;
  code: string;
  name: string;
  account_type: string;
  account_group: string | null;
  normal_balance: string;
  debit: number;
  credit: number;
  balance: number;
};

export type FinanceJournal = {
  id: string;
  entry_number: string;
  entry_date: string;
  description: string;
  status: string;
  currency: string;
  exchange_rate_to_base: number;
  source_type: string | null;
  source_id: string | null;
  reversed_from_id: string | null;
  created_at: string;
};

type FinanceJournalLine = {
  id: string;
  account_id: string;
  debit: number;
  credit: number;
  base_debit: number;
  base_credit: number;
  memo: string | null;
};

export type FinanceRate = {
  id: string;
  currency: string;
  rate_date: string;
  rate_to_base: number;
  source: string | null;
  notes: string | null;
  created_at: string;
};

export type FinancePeriod = {
  id: string;
  period_start: string;
  period_end: string;
  status: "open" | "closed";
  closed_at: string | null;
  reopened_at: string | null;
  created_at: string;
};

type Tab =
  | "overview"
  | "accounts"
  | "journals"
  | "rates"
  | "periods";

type JournalDraftLine = {
  accountId: string;
  debit: string;
  credit: string;
  memo: string;
};

const accountTypeLabels: Record<string, string> = {
  asset: "╪ú╪╡┘ä",
  liability: "╪º┘ä╪¬╪▓╪º┘à",
  equity: "╪¡┘é┘ê┘é ┘à┘ä┘â┘è╪⌐",
  revenue: "╪Ñ┘è╪▒╪º╪»",
  expense: "┘à╪╡╪▒┘ê┘ü",
};

function numberValue(value: unknown) {
  const n = Number(value || 0);

  return Number.isFinite(n)
    ? n
    : 0;
}

function businessDate() {
  const parts = new Intl.DateTimeFormat(
    "en-CA",
    {
      timeZone: "Asia/Damascus",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }
  ).formatToParts(new Date());

  const values = Object.fromEntries(
    parts.map((part) => [
      part.type,
      part.value,
    ])
  );

  return `${values.year}-${values.month}-${values.day}`;
}

function businessMonth() {
  return businessDate().slice(0, 7);
}

function friendlyFinanceError() {
  return "تعذر تنفيذ العملية المالية. تأكد من البيانات والصلاحيات والفترة المالية ثم حاول مجددًا.";
}

export function FinanceClient({
  companyId,
  baseCurrency,
  accounts,
  trialBalance,
  journals,
  rates,
  periods,
  initialTab,
  journalPage,
  journalCount,
  ratePage,
  rateCount,
  periodPage,
  periodCount,
  pageSize,
  canWrite,
  canManualJournal,
  canReverseManualJournal,
  canClose,
  canReopen,
}: {
  companyId: string;
  baseCurrency: string;
  accounts: FinanceAccount[];
  trialBalance: TrialBalanceRow[];
  journals: FinanceJournal[];
  rates: FinanceRate[];
  periods: FinancePeriod[];
  initialTab: Tab;
  journalPage: number;
  journalCount: number;
  ratePage: number;
  rateCount: number;
  periodPage: number;
  periodCount: number;
  pageSize: number;
  canWrite: boolean;
  canManualJournal: boolean;
  canReverseManualJournal: boolean;
  canClose: boolean;
  canReopen: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();

  const [tab, setTab] =
    useState<Tab>(initialTab);

  const journalTotalPages = Math.max(
    1,
    Math.ceil(journalCount / pageSize)
  );

  const rateTotalPages = Math.max(
    1,
    Math.ceil(rateCount / pageSize)
  );

  const periodTotalPages = Math.max(
    1,
    Math.ceil(periodCount / pageSize)
  );

  function navigateFinance(
    nextTab: Tab,
    pageParam?:
      | "journalPage"
      | "ratePage"
      | "periodPage",
    page?: number
  ) {
    const params =
      new URLSearchParams(
        window.location.search
      );

    params.set("tab", nextTab);

    if (pageParam && page) {
      if (page <= 1) {
        params.delete(pageParam);
      } else {
        params.set(
          pageParam,
          String(page)
        );
      }
    }

    setTab(nextTab);

    router.push(
      `/finance?${params.toString()}`
    );
  }

  const [saving, setSaving] =
    useState(false);

  const [message, setMessage] =
    useState("");

  const [accountOpen, setAccountOpen] =
    useState(false);

  const [accountCode, setAccountCode] =
    useState("");

  const [accountName, setAccountName] =
    useState("");

  const [accountParent, setAccountParent] =
    useState("");

  const [accountType, setAccountType] =
    useState("asset");

  const [normalBalance, setNormalBalance] =
    useState("debit");

  const [allowPosting, setAllowPosting] =
    useState(true);

  const [rateOpen, setRateOpen] =
    useState(false);

  const [rateCurrency, setRateCurrency] =
    useState("");

  const [rateDate, setRateDate] =
    useState(businessDate());

  const [rateValue, setRateValue] =
    useState("");

  const [rateNotes, setRateNotes] =
    useState("");

  const [periodMonth, setPeriodMonth] =
    useState(businessMonth());

  const [journalOpen, setJournalOpen] =
    useState(false);

  const [journalDate, setJournalDate] =
    useState(businessDate());

  const [journalDescription, setJournalDescription] =
    useState("");

  const [journalCurrency, setJournalCurrency] =
    useState(baseCurrency);

  const [journalLines, setJournalLines] =
    useState<JournalDraftLine[]>([
      {
        accountId: "",
        debit: "",
        credit: "",
        memo: "",
      },
      {
        accountId: "",
        debit: "",
        credit: "",
        memo: "",
      },
    ]);

  const [selectedJournal, setSelectedJournal] =
    useState<FinanceJournal | null>(null);

  const [journalDetailLines, setJournalDetailLines] =
    useState<FinanceJournalLine[]>([]);

  const [journalDetailsOpen, setJournalDetailsOpen] =
    useState(false);

  const [journalDetailsLoading, setJournalDetailsLoading] =
    useState(false);

  const [journalReversalReason, setJournalReversalReason] =
    useState("");

  const [reversingJournal, setReversingJournal] =
    useState(false);

  const postingAccounts =
    useMemo(
      () =>
        accounts.filter(
          (account) =>
            account.active &&
            account.allow_posting
        ),
      [accounts]
    );

  const totalDebit =
    trialBalance.reduce(
      (sum, row) =>
        sum +
        numberValue(row.debit),
      0
    );

  const totalCredit =
    trialBalance.reduce(
      (sum, row) =>
        sum +
        numberValue(row.credit),
      0
    );

  const assets =
    trialBalance
      .filter(
        (row) =>
          row.account_type ===
          "asset"
      )
      .reduce(
        (sum, row) =>
          sum +
          numberValue(
            row.balance
          ),
        0
      );

  const liabilities =
    trialBalance
      .filter(
        (row) =>
          row.account_type ===
          "liability"
      )
      .reduce(
        (sum, row) =>
          sum -
          numberValue(
            row.balance
          ),
        0
      );

  const revenue =
    trialBalance
      .filter(
        (row) =>
          row.account_type ===
          "revenue"
      )
      .reduce(
        (sum, row) =>
          sum -
          numberValue(
            row.balance
          ),
        0
      );

  const expenses =
    trialBalance
      .filter(
        (row) =>
          row.account_type ===
          "expense"
      )
      .reduce(
        (sum, row) =>
          sum +
          numberValue(
            row.balance
          ),
        0
      );

  const netProfit =
    revenue -
    expenses;

  async function saveAccount(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !accountCode.trim() ||
      !accountName.trim()
    ) {
      setMessage(
        "╪º┘ä┘â┘ê╪» ┘ê╪º╪│┘à ╪º┘ä╪¡╪│╪º╪¿ ┘à╪╖┘ä┘ê╪¿┘è┘å."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "save_finance_account",
        {
          target_company:
            companyId,
          target_account:
            null,
          target_parent:
            accountParent ||
            null,
          target_code:
            accountCode.trim(),
          target_name:
            accountName.trim(),
          target_type:
            accountType,
          target_group:
            null,
          target_normal_balance:
            normalBalance,
          target_allow_posting:
            allowPosting,
          target_active:
            true,
        }
      );

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    setAccountOpen(false);
    setAccountCode("");
    setAccountName("");
    setAccountParent("");

    router.refresh();
  }

  async function saveRate(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    const normalizedRateCurrency =
      rateCurrency.trim().toUpperCase();

    if (
      !/^[A-Z]{3}$/.test(
        normalizedRateCurrency
      ) ||
      normalizedRateCurrency ===
        baseCurrency.toUpperCase() ||
      !rateDate ||
      rateDate > businessDate() ||
      numberValue(
        rateValue
      ) <= 0
    ) {
      setMessage(
        "╪º┘â╪¬╪¿ ╪º┘ä╪╣┘à┘ä╪⌐ ┘ê╪│╪╣╪▒ ╪º┘ä╪╡╪▒┘ü."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "save_finance_exchange_rate",
        {
          target_company:
            companyId,
          target_currency:
            normalizedRateCurrency,
          target_date:
            rateDate,
          target_rate:
            numberValue(
              rateValue
            ),
          target_notes:
            rateNotes.trim() ||
            null,
        }
      );

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    setRateOpen(false);
    setRateValue("");
    setRateNotes("");

    router.refresh();
  }

  async function changePeriod(
    action:
      | "close"
      | "reopen"
  ) {
    if (!periodMonth) {
      return;
    }

    const [
      year,
      month,
    ] =
      periodMonth
        .split("-")
        .map(Number);

    if (!year || !month) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        action === "close"
          ? "close_finance_month"
          : "reopen_finance_month",
        {
          target_company:
            companyId,
          target_year:
            year,
          target_month:
            month,
        }
      );

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    router.refresh();
  }

  async function saveJournal(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    const lines =
      journalLines
        .map((line) => ({
          account_id:
            line.accountId,
          debit:
            numberValue(
              line.debit
            ),
          credit:
            numberValue(
              line.credit
            ),
          memo:
            line.memo.trim() ||
            null,
        }))
        .filter(
          (line) =>
            line.account_id &&
            (
              line.debit > 0 ||
              line.credit > 0
            )
        );

    if (
      !journalDescription.trim()
    ) {
      setMessage(
        "╪º┘â╪¬╪¿ ╪¿┘è╪º┘å ╪º┘ä┘é┘è╪»."
      );
      return;
    }

    if (lines.length < 2) {
      setMessage(
        "╪º┘ä┘é┘è╪» ┘ä╪º╪▓┘à ┘è╪¡╪¬┘ê┘è ╪│╪╖╪▒┘è┘å ╪╣┘ä┘ë ╪º┘ä╪ú┘é┘ä."
      );
      return;
    }

    const debit =
      lines.reduce(
        (sum, line) =>
          sum +
          line.debit,
        0
      );

    const credit =
      lines.reduce(
        (sum, line) =>
          sum +
          line.credit,
        0
      );

    if (
      Math.abs(
        debit -
        credit
      ) > 0.009
    ) {
      setMessage(
        "╪º┘ä┘é┘è╪» ╪║┘è╪▒ ┘à╪¬┘ê╪º╪▓┘å."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "post_manual_journal_entry",
        {
          target_company:
            companyId,
          target_date:
            journalDate,
          target_description:
            journalDescription.trim(),
          target_currency:
            journalCurrency,
          target_exchange_rate:
            1,
          lines_payload:
            lines,
        }
      );

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    setJournalOpen(false);
    setJournalDescription("");
    setJournalCurrency(
      baseCurrency
    );

    setJournalLines([
      {
        accountId: "",
        debit: "",
        credit: "",
        memo: "",
      },
      {
        accountId: "",
        debit: "",
        credit: "",
        memo: "",
      },
    ]);

    router.refresh();
  }

  async function openJournalDetails(
    journal: FinanceJournal
  ) {
    setSelectedJournal(journal);
    setJournalDetailLines([]);
    setJournalReversalReason("");
    setMessage("");
    setJournalDetailsOpen(true);
    setJournalDetailsLoading(true);

    const { data, error } =
      await supabase
        .from("journal_lines")
        .select(
          "id,account_id,debit,credit,base_debit,base_credit,memo"
        )
        .eq("company_id", companyId)
        .eq("journal_entry_id", journal.id)
        .order("created_at", {
          ascending: true,
        });

    setJournalDetailsLoading(false);

    if (error) {
      console.error(
        "Finance journal details failed",
        error
      );

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    setJournalDetailLines(
      (data ?? []) as FinanceJournalLine[]
    );
  }

  async function reverseSelectedManualJournal() {
    if (
      !canReverseManualJournal ||
      !selectedJournal ||
      selectedJournal.source_type !== "manual" ||
      selectedJournal.status !== "posted" ||
      selectedJournal.reversed_from_id
    ) {
      setMessage(
        "هذا القيد غير قابل للعكس."
      );
      return;
    }

    if (!journalReversalReason.trim()) {
      setMessage(
        "سبب عكس القيد مطلوب."
      );
      return;
    }

    setReversingJournal(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "reverse_manual_journal_entry",
        {
          target_company: companyId,
          target_entry: selectedJournal.id,
          target_reason: journalReversalReason.trim(),
        }
      );

    setReversingJournal(false);

    if (error) {
      console.error(
        "Manual journal reversal failed",
        error
      );

      setMessage(
        friendlyFinanceError()
      );
      return;
    }

    setJournalDetailsOpen(false);
    setSelectedJournal(null);
    setJournalDetailLines([]);
    setJournalReversalReason("");
    router.refresh();
  }

  const tabButton = (
    key: Tab,
    label: string
  ) => (
    <button
      type="button"
      className={
        tab === key
          ? "primaryButton"
          : "softButton"
      }
      onClick={() =>
        navigateFinance(key)
      }
    >
      {label}
    </button>
  );

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Finance & Accounting
          </span>

          <h2>
            ╪º┘ä╪Ñ╪»╪º╪▒╪⌐ ╪º┘ä┘à╪º┘ä┘è╪⌐
          </h2>

          <p className="muted">
            ┘â┘ä ╪º┘ä╪╣┘à┘ä┘è╪º╪¬ ╪º┘ä╪¬╪┤╪║┘è┘ä┘è╪⌐ ╪¬╪¬╪▒╪¡┘ä ┘à╪¡╪º╪│╪¿┘è┘ï╪º ╪¿╪┤┘â┘ä ╪¬┘ä┘é╪º╪ª┘è.
          </p>
        </div>

        <div className="rowActions">
          {canManualJournal && (
            <button
              type="button"
              className="softButton"
              onClick={() => {
                setMessage("");
                setJournalOpen(
                  true
                );
              }}
            >
              <Icons.plus
                size={14}
              />
              ┘é┘è╪» ┘è╪»┘ê┘è
            </button>
          )}

          {canWrite && (
            <button
              type="button"
              className="primaryButton"
              onClick={() => {
                setMessage("");
                setAccountOpen(
                  true
                );
              }}
            >
              <Icons.plus
                size={14}
              />
              ╪¡╪│╪º╪¿ ╪¼╪»┘è╪»
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="╪º┘ä╪ú╪╡┘ê┘ä"
          value={`${assets.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="╪º┘ä╪º┘ä╪¬╪▓╪º┘à╪º╪¬"
          value={`${liabilities.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="╪º┘ä╪Ñ┘è╪▒╪º╪»╪º╪¬"
          value={`${revenue.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="╪º┘ä┘å╪¬┘è╪¼╪⌐ ╪º┘ä╪¡╪º┘ä┘è╪⌐"
          value={`${netProfit.toFixed(
            2
          )} ${baseCurrency}`}
        />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {tabButton(
          "overview",
          "┘å╪╕╪▒╪⌐ ╪╣╪º┘à╪⌐"
        )}

        {tabButton(
          "accounts",
          "╪┤╪¼╪▒╪⌐ ╪º┘ä╪¡╪│╪º╪¿╪º╪¬"
        )}

        {tabButton(
          "journals",
          "╪º┘ä┘é┘è┘ê╪»"
        )}

        {tabButton(
          "rates",
          "╪ú╪│╪╣╪º╪▒ ╪º┘ä╪╡╪▒┘ü"
        )}

        {tabButton(
          "periods",
          "╪º┘ä┘ü╪¬╪▒╪º╪¬ ╪º┘ä┘à╪º┘ä┘è╪⌐"
        )}
      </div>

      {message && (
        <div
          className="toastError"
          style={{
            marginTop: 12,
          }}
        >
          {message}
        </div>
      )}

      {tab ===
        "overview" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader panelPad">
            <div>
              <h2>
                ┘à┘è╪▓╪º┘å ╪º┘ä┘à╪▒╪º╪¼╪╣╪⌐
              </h2>

              <p>
                ╪º┘ä┘à╪»┘è┘å ┘ê╪º┘ä╪»╪º╪ª┘å ╪¿╪º┘ä╪╣┘à┘ä╪⌐ ╪º┘ä╪ú╪│╪º╪│┘è╪⌐
              </p>
            </div>
          </div>

          <TrialTable
            rows={
              trialBalance
            }
            currency={
              baseCurrency
            }
          />

          <div
            className="panelPad"
            style={{
              borderTop:
                "1px solid rgba(255,255,255,.06)",
            }}
          >
            <strong>
              ┘à╪¼┘à┘ê╪╣ ╪º┘ä┘à╪»┘è┘å:{" "}
              {totalDebit.toFixed(
                2
              )}{" "}
              {baseCurrency}
            </strong>

            <span
              className="muted"
              style={{
                marginInline: 15,
              }}
            >
              |
            </span>

            <strong>
              ┘à╪¼┘à┘ê╪╣ ╪º┘ä╪»╪º╪ª┘å:{" "}
              {totalCredit.toFixed(
                2
              )}{" "}
              {baseCurrency}
            </strong>
          </div>
        </section>
      )}

      {tab ===
        "accounts" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>╪º┘ä┘â┘ê╪»</th>
                  <th>╪º┘ä╪¡╪│╪º╪¿</th>
                  <th>╪º┘ä┘å┘ê╪╣</th>
                  <th>╪º┘ä╪▒╪╡┘è╪» ╪º┘ä╪╖╪¿┘è╪╣┘è</th>
                  <th>╪º┘ä╪¬╪▒╪¡┘è┘ä</th>
                  <th>╪º┘ä╪¡╪º┘ä╪⌐</th>
                </tr>
              </thead>

              <tbody>
                {accounts.map(
                  (account) => (
                    <tr
                      key={
                        account.id
                      }
                    >
                      <td>
                        <strong>
                          {
                            account.code
                          }
                        </strong>
                      </td>

                      <td>
                        {
                          account.name
                        }

                        {account.is_system && (
                          <div className="muted">
                            ╪¡╪│╪º╪¿ ┘å╪╕╪º┘à
                          </div>
                        )}
                      </td>

                      <td>
                        {accountTypeLabels[
                          account.account_type
                        ] ||
                          account.account_type}
                      </td>

                      <td>
                        {account.normal_balance ===
                        "debit"
                          ? "┘à╪»┘è┘å"
                          : "╪»╪º╪ª┘å"}
                      </td>

                      <td>
                        {account.allow_posting
                          ? "┘å╪╣┘à"
                          : "╪¬╪¼┘à┘è╪╣┘è"}
                      </td>

                      <td>
                        <span
                          className={`chip ${
                            account.active
                              ? "green"
                              : "gray"
                          }`}
                        >
                          {account.active
                            ? "┘å╪┤╪╖"
                            : "┘à┘ê┘é┘ê┘ü"}
                        </span>
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab ===
        "journals" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          {!journals.length ? (
            <div className="empty">
              <Icons.money
                size={28}
              />

              <h3>
                ┘à╪º ┘ü┘è ┘é┘è┘ê╪»
              </h3>

              <p>
                ╪ú┘ê┘ä ╪╣┘à┘ä┘è╪⌐ ┘à╪º┘ä┘è╪⌐ ╪▒╪¡ ╪¬┘ê┘ä╪» ┘é┘è╪» ╪¬┘ä┘é╪º╪ª┘è.
              </p>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>╪º┘ä┘é┘è╪»</th>
                    <th>╪º┘ä╪¬╪º╪▒┘è╪«</th>
                    <th>╪º┘ä╪¿┘è╪º┘å</th>
                    <th>╪º┘ä┘à╪╡╪»╪▒</th>
                    <th>╪º┘ä╪╣┘à┘ä╪⌐</th>
                    <th>╪º┘ä╪¡╪º┘ä╪⌐</th>
                  </tr>
                </thead>

                <tbody>
                  {journals.map(
                    (journal) => (
                      <tr
                        key={
                          journal.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              journal.entry_number
                            }
                          </strong>
                        </td>

                        <td>
                          {
                            journal.entry_date
                          }
                        </td>

                        <td>
                          {
                            journal.description
                          }
                        </td>

                        <td>
                          {sourceLabel(
                            journal.source_type
                          )}
                        </td>

                        <td>
                          {
                            journal.currency
                          }
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              journal.status ===
                              "posted"
                                ? "green"
                                : "orange"
                            }`}
                          >
                            {journal.status ===
                            "posted"
                              ? "┘à╪▒╪¡┘æ┘ä"
                              : "┘à╪╣┘â┘ê╪│"}
                          </span>
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}

          <div
            className="rowActions"
            style={{
              marginTop: 12,
              justifyContent: "space-between",
            }}
          >
            <button
              type="button"
              className="softButton"
              disabled={journalPage <= 1}
              onClick={() =>
                navigateFinance(
                  "journals",
                  "journalPage",
                  journalPage - 1
                )
              }
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${journalPage} \u0645\u0646 ${journalTotalPages} - ${journalCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={
                journalPage >=
                journalTotalPages
              }
              onClick={() =>
                navigateFinance(
                  "journals",
                  "journalPage",
                  journalPage + 1
                )
              }
            >
              {"\u0627\u0644\u062a\u0627\u0644\u064a"}
            </button>
          </div>
        </section>
      )}

      {tab ===
        "rates" && (
        <section
          className="panel panelPad"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader">
            <div>
              <h2>
                ╪ú╪│╪╣╪º╪▒ ╪º┘ä╪╡╪▒┘ü
              </h2>

              <p>
                ╪º┘ä╪╣┘à┘ä╪⌐ ╪º┘ä╪ú╪│╪º╪│┘è╪⌐:{" "}
                {baseCurrency}
              </p>
            </div>

            {canWrite && (
              <button
                type="button"
                className="primaryButton"
                onClick={() => {
                  setMessage("");
                  setRateOpen(
                    true
                  );
                }}
              >
                <Icons.plus
                  size={14}
                />
                ╪│╪╣╪▒ ╪╡╪▒┘ü
              </button>
            )}
          </div>

          {!rates.length ? (
            <p className="muted">
              ┘à╪º ┘ü┘è ╪ú╪│╪╣╪º╪▒ ╪╡╪▒┘ü ┘à╪│╪¼┘ä╪⌐.
            </p>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>╪º┘ä╪╣┘à┘ä╪⌐</th>
                    <th>╪º┘ä╪¬╪º╪▒┘è╪«</th>
                    <th>╪º┘ä╪│╪╣╪▒ ╪Ñ┘ä┘ë {baseCurrency}</th>
                    <th>┘à┘ä╪º╪¡╪╕╪º╪¬</th>
                  </tr>
                </thead>

                <tbody>
                  {rates.map(
                    (rate) => (
                      <tr
                        key={
                          rate.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              rate.currency
                            }
                          </strong>
                        </td>

                        <td>
                          {
                            rate.rate_date
                          }
                        </td>

                        <td>
                          {numberValue(
                            rate.rate_to_base
                          ).toFixed(
                            6
                          )}
                        </td>

                        <td>
                          {rate.notes ||
                            "ΓÇö"}
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}

          <div
            className="rowActions"
            style={{
              marginTop: 12,
              justifyContent: "space-between",
            }}
          >
            <button
              type="button"
              className="softButton"
              disabled={ratePage <= 1}
              onClick={() =>
                navigateFinance(
                  "rates",
                  "ratePage",
                  ratePage - 1
                )
              }
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${ratePage} \u0645\u0646 ${rateTotalPages} - ${rateCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={
                ratePage >= rateTotalPages
              }
              onClick={() =>
                navigateFinance(
                  "rates",
                  "ratePage",
                  ratePage + 1
                )
              }
            >
              {"\u0627\u0644\u062a\u0627\u0644\u064a"}
            </button>
          </div>
        </section>
      )}

      {tab ===
        "periods" && (
        <section
          className="panel panelPad"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader">
            <div>
              <h2>
                ╪Ñ┘é┘ü╪º┘ä ╪º┘ä╪ú╪┤┘ç╪▒
              </h2>

              <p>
                ╪º┘ä╪┤┘ç╪▒ ╪º┘ä┘à┘é┘ü┘ä ┘è┘à┘å╪╣ ╪ú┘è ╪¬╪▒╪¡┘è┘ä ┘à╪¡╪º╪│╪¿┘è ╪¼╪»┘è╪» ╪»╪º╪«┘ä┘ç.
              </p>
            </div>
          </div>

          <div className="formGrid">
            <label className="field">
              <span>
                ╪º┘ä╪┤┘ç╪▒
              </span>

              <input
                type="month"
                value={
                  periodMonth
                }
                onChange={(
                  event
                ) =>
                  setPeriodMonth(
                    event.target
                      .value
                  )
                }
              />
            </label>

            <div className="field">
              <span>
                ╪º┘ä╪Ñ╪¼╪▒╪º╪í
              </span>

              <div className="rowActions">
                {canClose && (
                  <button
                    type="button"
                    className="primaryButton"
                    disabled={
                      saving
                    }
                    onClick={() =>
                      void changePeriod(
                        "close"
                      )
                    }
                  >
                    ╪Ñ┘é┘ü╪º┘ä ╪º┘ä╪┤┘ç╪▒
                  </button>
                )}

                {canReopen && (
                  <button
                    type="button"
                    className="softButton"
                    disabled={
                      saving
                    }
                    onClick={() =>
                      void changePeriod(
                        "reopen"
                      )
                    }
                  >
                    ╪Ñ╪╣╪º╪»╪⌐ ┘ü╪¬╪¡
                  </button>
                )}
              </div>
            </div>
          </div>

          <div
            className="tableWrap"
            style={{
              marginTop: 16,
            }}
          >
            <table className="dataTable">
              <thead>
                <tr>
                  <th>┘à┘å</th>
                  <th>╪Ñ┘ä┘ë</th>
                  <th>╪º┘ä╪¡╪º┘ä╪⌐</th>
                </tr>
              </thead>

              <tbody>
                {periods.map(
                  (period) => (
                    <tr
                      key={
                        period.id
                      }
                    >
                      <td>
                        {
                          period.period_start
                        }
                      </td>

                      <td>
                        {
                          period.period_end
                        }
                      </td>

                      <td>
                        <span
                          className={`chip ${
                            period.status ===
                            "closed"
                              ? "orange"
                              : "green"
                          }`}
                        >
                          {period.status ===
                          "closed"
                            ? "┘à┘é┘ü┘ä"
                            : "┘à┘ü╪¬┘ê╪¡"}
                        </span>
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </table>
          </div>

          <div
            className="rowActions"
            style={{
              marginTop: 12,
              justifyContent: "space-between",
            }}
          >
            <button
              type="button"
              className="softButton"
              disabled={periodPage <= 1}
              onClick={() =>
                navigateFinance(
                  "periods",
                  "periodPage",
                  periodPage - 1
                )
              }
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${periodPage} \u0645\u0646 ${periodTotalPages} - ${periodCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={
                periodPage >=
                periodTotalPages
              }
              onClick={() =>
                navigateFinance(
                  "periods",
                  "periodPage",
                  periodPage + 1
                )
              }
            >
              {"\u0627\u0644\u062a\u0627\u0644\u064a"}
            </button>
          </div>
        </section>
      )}

      {journalDetailsOpen && selectedJournal && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{ maxWidth: 980 }}
            role="dialog"
            aria-modal="true"
            aria-labelledby="journal-details-title"
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Journal Entry
                </span>

                <h2 id="journal-details-title">
                  {selectedJournal.entry_number}
                </h2>

                <p className="muted">
                  {selectedJournal.description}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={reversingJournal}
                onClick={() => {
                  setJournalDetailsOpen(false);
                  setSelectedJournal(null);
                  setJournalDetailLines([]);
                  setJournalReversalReason("");
                  setMessage("");
                }}
                aria-label="إغلاق"
              >
                ×
              </button>
            </div>

            <div className="formGrid">
              <div className="field">
                <span>التاريخ</span>
                <strong>{selectedJournal.entry_date}</strong>
              </div>

              <div className="field">
                <span>المصدر</span>
                <strong>
                  {sourceLabel(selectedJournal.source_type)}
                </strong>
              </div>

              <div className="field">
                <span>العملة</span>
                <strong>{selectedJournal.currency}</strong>
              </div>

              <div className="field">
                <span>سعر الصرف</span>
                <strong>
                  {numberValue(
                    selectedJournal.exchange_rate_to_base
                  ).toFixed(6)}
                </strong>
              </div>
            </div>

            <div
              className="tableWrap"
              style={{ marginTop: 16 }}
            >
              {journalDetailsLoading ? (
                <div className="panelPad muted">
                  جاري تحميل تفاصيل القيد...
                </div>
              ) : journalDetailLines.length ? (
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الحساب</th>
                      <th>مدين</th>
                      <th>دائن</th>
                      <th>مدين أساسي</th>
                      <th>دائن أساسي</th>
                      <th>البيان</th>
                    </tr>
                  </thead>

                  <tbody>
                    {journalDetailLines.map((line) => {
                      const account = accounts.find(
                        (item) => item.id === line.account_id
                      );

                      return (
                        <tr key={line.id}>
                          <td>
                            <strong>
                              {account
                                ? `${account.code} - ${account.name}`
                                : "حساب غير متاح"}
                            </strong>
                          </td>

                          <td>
                            {numberValue(line.debit).toFixed(2)}
                          </td>

                          <td>
                            {numberValue(line.credit).toFixed(2)}
                          </td>

                          <td>
                            {numberValue(line.base_debit).toFixed(2)}{" "}
                            {baseCurrency}
                          </td>

                          <td>
                            {numberValue(line.base_credit).toFixed(2)}{" "}
                            {baseCurrency}
                          </td>

                          <td>{line.memo || "—"}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              ) : (
                <div className="panelPad muted">
                  لا توجد سطور لهذا القيد.
                </div>
              )}
            </div>

            {canReverseManualJournal &&
              selectedJournal.source_type === "manual" &&
              selectedJournal.status === "posted" &&
              !selectedJournal.reversed_from_id && (
                <div
                  className="panelPad"
                  style={{ marginTop: 16 }}
                >
                  <label className="field">
                    <span>سبب عكس القيد *</span>

                    <textarea
                      rows={3}
                      value={journalReversalReason}
                      onChange={(event) =>
                        setJournalReversalReason(
                          event.target.value
                        )
                      }
                      placeholder="اكتب سبب العكس بشكل واضح"
                    />
                  </label>

                  <p className="muted">
                    القيد الأصلي لن يُحذف. سيتم إنشاء قيد عكسي جديد مع الاحتفاظ بالتاريخ المحاسبي.
                  </p>
                </div>
              )}

            {message && (
              <div className="toastError" role="alert">
                {message}
              </div>
            )}

            <div className="modalActions">
              <button
                type="button"
                className="softButton"
                disabled={reversingJournal}
                onClick={() => {
                  setJournalDetailsOpen(false);
                  setSelectedJournal(null);
                  setJournalDetailLines([]);
                  setJournalReversalReason("");
                  setMessage("");
                }}
              >
                إغلاق
              </button>

              {canReverseManualJournal &&
                selectedJournal.source_type === "manual" &&
                selectedJournal.status === "posted" &&
                !selectedJournal.reversed_from_id && (
                  <button
                    type="button"
                    className="dangerButton"
                    disabled={
                      reversingJournal ||
                      !journalReversalReason.trim()
                    }
                    onClick={() =>
                      void reverseSelectedManualJournal()
                    }
                  >
                    {reversingJournal
                      ? "جاري العكس..."
                      : "عكس القيد"}
                  </button>
                )}
            </div>
          </section>
        </div>
      )}

      {accountOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Chart of Accounts
                </span>

                <h2>
                  ╪¡╪│╪º╪¿ ╪¼╪»┘è╪»
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setAccountOpen(
                    false
                  )
                }
              >
                ├ù
              </button>
            </div>

            <form
              onSubmit={
                saveAccount
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    ┘â┘ê╪» ╪º┘ä╪¡╪│╪º╪¿ *
                  </span>

                  <input
                    value={
                      accountCode
                    }
                    onChange={(
                      event
                    ) =>
                      setAccountCode(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    ╪º╪│┘à ╪º┘ä╪¡╪│╪º╪¿ *
                  </span>

                  <input
                    value={
                      accountName
                    }
                    onChange={(
                      event
                    ) =>
                      setAccountName(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    ╪º┘ä╪¡╪│╪º╪¿ ╪º┘ä╪ú╪¿
                  </span>

                  <select
                    value={
                      accountParent
                    }
                    onChange={(
                      event
                    ) =>
                      setAccountParent(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      ╪¿╪»┘ê┘å
                    </option>

                    {accounts.map(
                      (account) => (
                        <option
                          key={
                            account.id
                          }
                          value={
                            account.id
                          }
                        >
                          {account.code} -{" "}
                          {account.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    ╪º┘ä┘å┘ê╪╣
                  </span>

                  <select
                    value={
                      accountType
                    }
                    onChange={(
                      event
                    ) => {
                      const value =
                        event.target
                          .value;

                      setAccountType(
                        value
                      );

                      setNormalBalance(
                        value ===
                          "asset" ||
                          value ===
                          "expense"
                          ? "debit"
                          : "credit"
                      );
                    }}
                  >
                    <option value="asset">
                      ╪ú╪╡┘ä
                    </option>
                    <option value="liability">
                      ╪º┘ä╪¬╪▓╪º┘à
                    </option>
                    <option value="equity">
                      ╪¡┘é┘ê┘é ┘à┘ä┘â┘è╪⌐
                    </option>
                    <option value="revenue">
                      ╪Ñ┘è╪▒╪º╪»
                    </option>
                    <option value="expense">
                      ┘à╪╡╪▒┘ê┘ü
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    ╪º┘ä╪▒╪╡┘è╪» ╪º┘ä╪╖╪¿┘è╪╣┘è
                  </span>

                  <select
                    value={
                      normalBalance
                    }
                    onChange={(
                      event
                    ) =>
                      setNormalBalance(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="debit">
                      ┘à╪»┘è┘å
                    </option>
                    <option value="credit">
                      ╪»╪º╪ª┘å
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    ┘è╪│┘à╪¡ ╪¿╪º┘ä╪¬╪▒╪¡┘è┘ä
                  </span>

                  <select
                    value={
                      allowPosting
                        ? "yes"
                        : "no"
                    }
                    onChange={(
                      event
                    ) =>
                      setAllowPosting(
                        event.target
                          .value ===
                          "yes"
                      )
                    }
                  >
                    <option value="yes">
                      ┘å╪╣┘à
                    </option>
                    <option value="no">
                      ╪¡╪│╪º╪¿ ╪¬╪¼┘à┘è╪╣┘è
                    </option>
                  </select>
                </label>
              </div>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setAccountOpen(
                      false
                    )
                  }
                >
                  ╪Ñ┘ä╪║╪º╪í
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ╪¡┘ü╪╕ ╪º┘ä╪¡╪│╪º╪¿
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {rateOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Exchange Rate
                </span>

                <h2>
                  ╪¬╪│╪¼┘è┘ä ╪│╪╣╪▒ ╪╡╪▒┘ü
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setRateOpen(
                    false
                  )
                }
              >
                ├ù
              </button>
            </div>

            <form
              onSubmit={
                saveRate
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    ╪º┘ä╪╣┘à┘ä╪⌐
                  </span>

                  <input
                    value={
                      rateCurrency
                    }
                    onChange={(
                      event
                    ) =>
                      setRateCurrency(
                        event.target
                          .value.toUpperCase()
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    ╪º┘ä╪¬╪º╪▒┘è╪«
                  </span>

                  <input
                    type="date"
                    value={
                      rateDate
                    }
                    onChange={(
                      event
                    ) =>
                      setRateDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    1 {rateCurrency || "╪╣┘à┘ä╪⌐"} = ┘â┘à {baseCurrency}╪ƒ
                  </span>

                  <input
                    type="number"
                    min="0.00000001"
                    step="0.00000001"
                    value={
                      rateValue
                    }
                    onChange={(
                      event
                    ) =>
                      setRateValue(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    ┘à┘ä╪º╪¡╪╕╪º╪¬
                  </span>

                  <textarea
                    rows={3}
                    value={
                      rateNotes
                    }
                    onChange={(
                      event
                    ) =>
                      setRateNotes(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setRateOpen(
                      false
                    )
                  }
                >
                  ╪Ñ┘ä╪║╪º╪í
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ╪¡┘ü╪╕ ╪º┘ä╪│╪╣╪▒
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {journalOpen && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 950,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Manual Journal
                </span>

                <h2>
                  ┘é┘è╪» ┘è┘ê┘à┘è╪⌐ ┘è╪»┘ê┘è
                </h2>

                <p className="muted">
                  ┘ä┘ä╪º╪│╪¬╪«╪»╪º┘à ╪º┘ä┘à╪¡╪º╪│╪¿┘è ┘ü┘é╪╖.
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setJournalOpen(
                    false
                  )
                }
              >
                ├ù
              </button>
            </div>

            <form
              onSubmit={
                saveJournal
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    ╪º┘ä╪¬╪º╪▒┘è╪«
                  </span>

                  <input
                    type="date"
                    value={
                      journalDate
                    }
                    onChange={(
                      event
                    ) =>
                      setJournalDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    ╪º┘ä╪╣┘à┘ä╪⌐
                  </span>

                  <input
                    value={
                      journalCurrency
                    }
                    onChange={(
                      event
                    ) =>
                      setJournalCurrency(
                        event.target
                          .value.toUpperCase()
                      )
                    }
                  />
                </label>
                <label className="field full">
                  <span>
                    ╪º┘ä╪¿┘è╪º┘å *
                  </span>

                  <input
                    value={
                      journalDescription
                    }
                    onChange={(
                      event
                    ) =>
                      setJournalDescription(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div
                className="tableWrap"
                style={{
                  marginTop: 15,
                }}
              >
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>╪º┘ä╪¡╪│╪º╪¿</th>
                      <th>┘à╪»┘è┘å</th>
                      <th>╪»╪º╪ª┘å</th>
                      <th>╪¿┘è╪º┘å</th>
                      <th />
                    </tr>
                  </thead>

                  <tbody>
                    {journalLines.map(
                      (
                        line,
                        index
                      ) => (
                        <tr
                          key={
                            index
                          }
                        >
                          <td>
                            <select
                              value={
                                line.accountId
                              }
                              onChange={(
                                event
                              ) =>
                                setJournalLines(
                                  (
                                    current
                                  ) =>
                                    current.map(
                                      (
                                        row,
                                        rowIndex
                                      ) =>
                                        rowIndex ===
                                        index
                                          ? {
                                              ...row,
                                              accountId:
                                                event.target.value,
                                            }
                                          : row
                                    )
                                )
                              }
                            >
                              <option value="">
                                ╪º╪«╪¬╪º╪▒
                              </option>

                              {postingAccounts.map(
                                (
                                  account
                                ) => (
                                  <option
                                    key={
                                      account.id
                                    }
                                    value={
                                      account.id
                                    }
                                  >
                                    {
                                      account.code
                                    }{" "}
                                    -{" "}
                                    {
                                      account.name
                                    }
                                  </option>
                                )
                              )}
                            </select>
                          </td>

                          <td>
                            <input
                              type="number"
                              min="0"
                              step="0.01"
                              value={
                                line.debit
                              }
                              onChange={(
                                event
                              ) =>
                                setJournalLines(
                                  (
                                    current
                                  ) =>
                                    current.map(
                                      (
                                        row,
                                        rowIndex
                                      ) =>
                                        rowIndex ===
                                        index
                                          ? {
                                              ...row,
                                              debit:
                                                event.target.value,
                                              credit:
                                                event.target.value
                                                  ? ""
                                                  : row.credit,
                                            }
                                          : row
                                    )
                                )
                              }
                            />
                          </td>

                          <td>
                            <input
                              type="number"
                              min="0"
                              step="0.01"
                              value={
                                line.credit
                              }
                              onChange={(
                                event
                              ) =>
                                setJournalLines(
                                  (
                                    current
                                  ) =>
                                    current.map(
                                      (
                                        row,
                                        rowIndex
                                      ) =>
                                        rowIndex ===
                                        index
                                          ? {
                                              ...row,
                                              credit:
                                                event.target.value,
                                              debit:
                                                event.target.value
                                                  ? ""
                                                  : row.debit,
                                            }
                                          : row
                                    )
                                )
                              }
                            />
                          </td>

                          <td>
                            <input
                              value={
                                line.memo
                              }
                              onChange={(
                                event
                              ) =>
                                setJournalLines(
                                  (
                                    current
                                  ) =>
                                    current.map(
                                      (
                                        row,
                                        rowIndex
                                      ) =>
                                        rowIndex ===
                                        index
                                          ? {
                                              ...row,
                                              memo:
                                                event.target.value,
                                            }
                                          : row
                                    )
                                )
                              }
                            />
                          </td>

                          <td>
                            {journalLines.length >
                              2 && (
                              <button
                                type="button"
                                className="dangerButton"
                                onClick={() =>
                                  setJournalLines(
                                    (
                                      current
                                    ) =>
                                      current.filter(
                                        (
                                          _,
                                          rowIndex
                                        ) =>
                                          rowIndex !==
                                          index
                                      )
                                  )
                                }
                              >
                                ├ù
                              </button>
                            )}
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>

              <button
                type="button"
                className="softButton"
                style={{
                  marginTop: 10,
                }}
                onClick={() =>
                  setJournalLines(
                    (
                      current
                    ) => [
                      ...current,
                      {
                        accountId:
                          "",
                        debit: "",
                        credit: "",
                        memo: "",
                      },
                    ]
                  )
                }
              >
                <Icons.plus
                  size={13}
                />
                ╪│╪╖╪▒ ╪¼╪»┘è╪»
              </button>

              <div
                className="rowActions"
                style={{
                  marginTop: 14,
                }}
              >
                <strong>
                  ┘à╪»┘è┘å:{" "}
                  {journalLines
                    .reduce(
                      (
                        sum,
                        row
                      ) =>
                        sum +
                        numberValue(
                          row.debit
                        ),
                      0
                    )
                    .toFixed(2)}
                </strong>

                <strong>
                  ╪»╪º╪ª┘å:{" "}
                  {journalLines
                    .reduce(
                      (
                        sum,
                        row
                      ) =>
                        sum +
                        numberValue(
                          row.credit
                        ),
                      0
                    )
                    .toFixed(2)}
                </strong>
              </div>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setJournalOpen(
                      false
                    )
                  }
                >
                  ╪Ñ┘ä╪║╪º╪í
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ╪¬╪▒╪¡┘è┘ä ╪º┘ä┘é┘è╪»
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}

function TrialTable({
  rows,
  currency,
}: {
  rows: TrialBalanceRow[];
  currency: string;
}) {
  return (
    <div className="tableWrap">
      <table className="dataTable">
        <thead>
          <tr>
            <th>╪º┘ä┘â┘ê╪»</th>
            <th>╪º┘ä╪¡╪│╪º╪¿</th>
            <th>┘à╪»┘è┘å</th>
            <th>╪»╪º╪ª┘å</th>
            <th>╪º┘ä╪▒╪╡┘è╪»</th>
          </tr>
        </thead>

        <tbody>
          {rows.map(
            (row) => (
              <tr
                key={
                  row.account_id
                }
              >
                <td>
                  <strong>
                    {row.code}
                  </strong>
                </td>

                <td>
                  {row.name}
                </td>

                <td>
                  {numberValue(
                    row.debit
                  ).toFixed(2)}{" "}
                  {currency}
                </td>

                <td>
                  {numberValue(
                    row.credit
                  ).toFixed(2)}{" "}
                  {currency}
                </td>

                <td>
                  {numberValue(
                    row.balance
                  ).toFixed(2)}
                </td>
              </tr>
            )
          )}
        </tbody>
      </table>
    </div>
  );
}

function sourceLabel(
  source: string | null
) {
  const labels: Record<string, string> = {
    manual: "┘è╪»┘ê┘è",
    sales_invoice:
      "┘ü╪º╪¬┘ê╪▒╪⌐ ╪¿┘è╪╣",
    purchase_invoice:
      "┘ü╪º╪¬┘ê╪▒╪⌐ ╪┤╪▒╪º╪í",
    customer_payment:
      "┘é╪¿╪╢ ╪╣┘à┘è┘ä",
    customer_payment_allocation:
      "╪¬╪«╪╡┘è╪╡ ┘é╪¿╪╢",
    supplier_payment:
      "╪»┘ü╪╣ ┘à┘ê╪▒╪»",
    supplier_payment_allocation:
      "╪¬╪«╪╡┘è╪╡ ┘à┘ê╪▒╪»",
    inventory_movement:
      "╪¡╪▒┘â╪⌐ ┘à╪«╪▓┘ê┘å",
    expense:
      "┘à╪╡╪▒┘ê┘ü",
    payroll_run:
      "╪▒┘ê╪º╪¬╪¿",
    payroll_payment:
      "╪»┘ü╪╣ ╪▒╪º╪¬╪¿",
    cash_transaction:
      "╪¡╪▒┘â╪⌐ ╪╡┘å╪»┘ê┘é",
    reversal:
      "┘é┘è╪» ╪╣┘â╪│┘è",
  };

  return source
    ? labels[source] ||
        source
    : "ΓÇö";
}

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {title}
      </div>

      <div className="statValue">
        {value}
      </div>
    </div>
  );
}
