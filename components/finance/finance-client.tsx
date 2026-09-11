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
  created_at: string;
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
  asset: "أصل",
  liability: "التزام",
  equity: "حقوق ملكية",
  revenue: "إيراد",
  expense: "مصروف",
};

function numberValue(value: unknown) {
  const n = Number(value || 0);

  return Number.isFinite(n)
    ? n
    : 0;
}

function today() {
  return new Date()
    .toISOString()
    .slice(0, 10);
}

function currentMonth() {
  return new Date()
    .toISOString()
    .slice(0, 7);
}

export function FinanceClient({
  companyId,
  baseCurrency,
  accounts,
  trialBalance,
  journals,
  rates,
  periods,
  canWrite,
  canManualJournal,
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
  canWrite: boolean;
  canManualJournal: boolean;
  canClose: boolean;
  canReopen: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();

  const [tab, setTab] =
    useState<Tab>("overview");

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
    useState("SYP");

  const [rateDate, setRateDate] =
    useState(today());

  const [rateValue, setRateValue] =
    useState("");

  const [rateNotes, setRateNotes] =
    useState("");

  const [periodMonth, setPeriodMonth] =
    useState(currentMonth());

  const [journalOpen, setJournalOpen] =
    useState(false);

  const [journalDate, setJournalDate] =
    useState(today());

  const [journalDescription, setJournalDescription] =
    useState("");

  const [journalCurrency, setJournalCurrency] =
    useState(baseCurrency);

  const [journalRate, setJournalRate] =
    useState("1");

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
        "الكود واسم الحساب مطلوبين."
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
      setMessage(
        error.message
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

    if (
      !rateCurrency.trim() ||
      numberValue(
        rateValue
      ) <= 0
    ) {
      setMessage(
        "اكتب العملة وسعر الصرف."
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
            rateCurrency.trim(),
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
      setMessage(
        error.message
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
      setMessage(
        error.message
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
        "اكتب بيان القيد."
      );
      return;
    }

    if (lines.length < 2) {
      setMessage(
        "القيد لازم يحتوي سطرين على الأقل."
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
        "القيد غير متوازن."
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
            journalCurrency ===
            baseCurrency
              ? 1
              : numberValue(
                  journalRate
                ),
          lines_payload:
            lines,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setJournalOpen(false);
    setJournalDescription("");
    setJournalCurrency(
      baseCurrency
    );
    setJournalRate("1");

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
        setTab(key)
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
            الإدارة المالية
          </h2>

          <p className="muted">
            كل العمليات التشغيلية تترحل محاسبيًا بشكل تلقائي.
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
              قيد يدوي
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
              حساب جديد
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="الأصول"
          value={`${assets.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="الالتزامات"
          value={`${liabilities.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="الإيرادات"
          value={`${revenue.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="النتيجة الحالية"
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
          "نظرة عامة"
        )}

        {tabButton(
          "accounts",
          "شجرة الحسابات"
        )}

        {tabButton(
          "journals",
          "القيود"
        )}

        {tabButton(
          "rates",
          "أسعار الصرف"
        )}

        {tabButton(
          "periods",
          "الفترات المالية"
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
                ميزان المراجعة
              </h2>

              <p>
                المدين والدائن بالعملة الأساسية
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
              مجموع المدين:{" "}
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
              مجموع الدائن:{" "}
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
                  <th>الكود</th>
                  <th>الحساب</th>
                  <th>النوع</th>
                  <th>الرصيد الطبيعي</th>
                  <th>الترحيل</th>
                  <th>الحالة</th>
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
                            حساب نظام
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
                          ? "مدين"
                          : "دائن"}
                      </td>

                      <td>
                        {account.allow_posting
                          ? "نعم"
                          : "تجميعي"}
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
                            ? "نشط"
                            : "موقوف"}
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
                ما في قيود
              </h3>

              <p>
                أول عملية مالية رح تولد قيد تلقائي.
              </p>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>القيد</th>
                    <th>التاريخ</th>
                    <th>البيان</th>
                    <th>المصدر</th>
                    <th>العملة</th>
                    <th>الحالة</th>
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
                              ? "مرحّل"
                              : "معكوس"}
                          </span>
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}
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
                أسعار الصرف
              </h2>

              <p>
                العملة الأساسية:{" "}
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
                سعر صرف
              </button>
            )}
          </div>

          {!rates.length ? (
            <p className="muted">
              ما في أسعار صرف مسجلة.
            </p>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>العملة</th>
                    <th>التاريخ</th>
                    <th>السعر إلى {baseCurrency}</th>
                    <th>ملاحظات</th>
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
                            "—"}
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}
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
                إقفال الأشهر
              </h2>

              <p>
                الشهر المقفل يمنع أي ترحيل محاسبي جديد داخله.
              </p>
            </div>
          </div>

          <div className="formGrid">
            <label className="field">
              <span>
                الشهر
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
                الإجراء
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
                    إقفال الشهر
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
                    إعادة فتح
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
                  <th>من</th>
                  <th>إلى</th>
                  <th>الحالة</th>
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
                            ? "مقفل"
                            : "مفتوح"}
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

      {accountOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Chart of Accounts
                </span>

                <h2>
                  حساب جديد
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
                ×
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
                    كود الحساب *
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
                    اسم الحساب *
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
                    الحساب الأب
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
                      بدون
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
                    النوع
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
                      أصل
                    </option>
                    <option value="liability">
                      التزام
                    </option>
                    <option value="equity">
                      حقوق ملكية
                    </option>
                    <option value="revenue">
                      إيراد
                    </option>
                    <option value="expense">
                      مصروف
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    الرصيد الطبيعي
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
                      مدين
                    </option>
                    <option value="credit">
                      دائن
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    يسمح بالترحيل
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
                      نعم
                    </option>
                    <option value="no">
                      حساب تجميعي
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
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  حفظ الحساب
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
                  تسجيل سعر صرف
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
                ×
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
                    العملة
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
                    التاريخ
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
                    1 {rateCurrency || "عملة"} = كم {baseCurrency}؟
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
                    ملاحظات
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
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  حفظ السعر
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
                  قيد يومية يدوي
                </h2>

                <p className="muted">
                  للاستخدام المحاسبي فقط.
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
                ×
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
                    التاريخ
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
                    العملة
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

                {journalCurrency !==
                  baseCurrency && (
                  <label className="field">
                    <span>
                      سعر الصرف
                    </span>

                    <input
                      type="number"
                      min="0.00000001"
                      step="0.00000001"
                      value={
                        journalRate
                      }
                      onChange={(
                        event
                      ) =>
                        setJournalRate(
                          event.target
                            .value
                        )
                      }
                    />
                  </label>
                )}

                <label className="field full">
                  <span>
                    البيان *
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
                      <th>الحساب</th>
                      <th>مدين</th>
                      <th>دائن</th>
                      <th>بيان</th>
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
                                اختار
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
                                ×
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
                سطر جديد
              </button>

              <div
                className="rowActions"
                style={{
                  marginTop: 14,
                }}
              >
                <strong>
                  مدين:{" "}
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
                  دائن:{" "}
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
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ترحيل القيد
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
            <th>الكود</th>
            <th>الحساب</th>
            <th>مدين</th>
            <th>دائن</th>
            <th>الرصيد</th>
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
    manual: "يدوي",
    sales_invoice:
      "فاتورة بيع",
    purchase_invoice:
      "فاتورة شراء",
    customer_payment:
      "قبض عميل",
    customer_payment_allocation:
      "تخصيص قبض",
    supplier_payment:
      "دفع مورد",
    supplier_payment_allocation:
      "تخصيص مورد",
    inventory_movement:
      "حركة مخزون",
    expense:
      "مصروف",
    payroll_run:
      "رواتب",
    payroll_payment:
      "دفع راتب",
    cash_transaction:
      "حركة صندوق",
    reversal:
      "قيد عكسي",
  };

  return source
    ? labels[source] ||
        source
    : "—";
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