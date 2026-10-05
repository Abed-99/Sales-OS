"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";
import { NumberInput } from "@/components/number-input";
import { formatNumber, todayDamascus as businessDate, formatDate } from "@/lib/format";

export type FinanceAccount = {
  id: string;
  parent_id: string | null;
  code: string;
  name: string;
  account_type: "asset" | "liability" | "equity" | "revenue" | "expense";
  account_group: string | null;
  normal_balance: "debit" | "credit";
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

type Tab = "overview" | "accounts" | "journals" | "rates" | "periods";

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

  return Number.isFinite(n) ? n : 0;
}

/** Shows a stored rate the way people say it: "1 USD = 13,000 SYP". */
function unitsPerBase(rateToBase: unknown, baseCurrency: string, currency: string) {
  const rate = numberValue(rateToBase);

  if (rate <= 0) {
    return "—";
  }

  const units = 1 / rate;

  return `1 ${baseCurrency} = ${units.toLocaleString("en-US", {
    maximumFractionDigits: units >= 100 ? 0 : 4,
  })} ${currency}`;
}

function businessMonth() {
  return businessDate().slice(0, 7);
}

function friendlyFinanceError(error?: { code?: string; message?: string } | null) {
  const message = (error?.message ?? "").toLowerCase();

  if (message.includes("not allowed") || error?.code === "42501")
    return "ما عندك صلاحية لهالعملية.";
  if (
    message.includes("financial period is closed") ||
    (message.includes("period") && message.includes("closed"))
  )
    return "هالشهر مقفل. افتحو من «الفترات المالية» أول.";
  if (message.includes("missing exchange rate"))
    return "ما في سعر صرف مسجّل لهالعملة بهاليوم أو قبلو. سجّل السعر من «أسعار الصرف».";
  if (message.includes("not balanced")) return "القيد مو متوازن: مجموع المدين لازم يساوي الدائن.";
  if (message.includes("at least two lines")) return "القيد لازم يكون فيه سطرين على الأقل.";
  if (message.includes("invalid posting account"))
    return "في حساب بالقيد تجميعي أو موقوف، ما بينرحّل عليه.";
  if (error?.code === "23505" || message.includes("duplicate"))
    return "في حساب بنفس الكود. اختار كود تاني.";
  if (message.includes("system account")) return "هاد حساب نظام، ما فيك تغيّر نوعو أو ترتيبو.";
  if (message.includes("classification cannot be changed"))
    return "الحساب عليه قيود، ما فيك تغيّر نوعو.";
  if (message.includes("own parent") || message.includes("hierarchy cycle"))
    return "ترتيب الحسابات غلط (الحساب ما بيصير أب لحالو).";
  if (message.includes("future exchange rate")) return "ما فيك تسجّل سعر صرف لتاريخ بالمستقبل.";
  if (message.includes("base currency does not need"))
    return "هي العملة الأساسية، ما بدها سعر صرف.";
  if (message.includes("closed financial period not found")) return "هالشهر مو مقفل أصلًا.";
  if (message.includes("only original manual journals"))
    return "بس القيود اليدوية الأصلية بتنعكس من هون.";
  return "تعذر تنفيذ العملية. تأكد من البيانات وحاول مرة تانية.";
}

/** Latest saved rate on or before the date, as "1 BASE = X CUR". */
function rateHint(rates: FinanceRate[], currency: string, date: string, baseCurrency: string) {
  const match = rates
    .filter((rate) => rate.currency === currency && rate.rate_date <= date)
    .sort((a, b) => (a.rate_date < b.rate_date ? 1 : -1))[0];

  return match
    ? `${unitsPerBase(match.rate_to_base, baseCurrency, currency)} (سعر ${formatDate(match.rate_date)})`
    : null;
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
  q,
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
  q: string;
  canWrite: boolean;
  canManualJournal: boolean;
  canReverseManualJournal: boolean;
  canClose: boolean;
  canReopen: boolean;
}) {
  const [supabase] = useState(() => createClient());

  const router = useRouter();

  const [tab, setTab] = useState<Tab>(initialTab);

  const journalTotalPages = Math.max(1, Math.ceil(journalCount / pageSize));

  const rateTotalPages = Math.max(1, Math.ceil(rateCount / pageSize));

  const periodTotalPages = Math.max(1, Math.ceil(periodCount / pageSize));

  const [journalSearch, setJournalSearch] = useState(q);

  function searchJournals(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const params = new URLSearchParams(window.location.search);
    params.set("tab", "journals");
    params.delete("journalPage");
    if (journalSearch.trim()) params.set("q", journalSearch.trim());
    else params.delete("q");
    router.push(`/finance?${params.toString()}`);
  }

  function navigateFinance(
    nextTab: Tab,
    pageParam?: "journalPage" | "ratePage" | "periodPage",
    page?: number,
  ) {
    const params = new URLSearchParams(window.location.search);

    params.set("tab", nextTab);

    if (pageParam && page) {
      if (page <= 1) {
        params.delete(pageParam);
      } else {
        params.set(pageParam, String(page));
      }
    }

    setTab(nextTab);

    router.push(`/finance?${params.toString()}`);
  }

  const [saving, setSaving] = useState(false);

  const [message, setMessage] = useState("");

  const [accountOpen, setAccountOpen] = useState(false);

  const [accountCode, setAccountCode] = useState("");

  const [accountName, setAccountName] = useState("");

  const [accountParent, setAccountParent] = useState("");

  const [accountType, setAccountType] = useState("asset");

  const [normalBalance, setNormalBalance] = useState("debit");

  const [allowPosting, setAllowPosting] = useState(true);

  const [editingAccount, setEditingAccount] = useState<FinanceAccount | null>(null);

  const [accountActive, setAccountActive] = useState(true);

  function openAccountForm(account: FinanceAccount | null) {
    setMessage("");
    setEditingAccount(account);
    setAccountCode(account?.code ?? "");
    setAccountName(account?.name ?? "");
    setAccountParent(account?.parent_id ?? "");
    setAccountType(account?.account_type ?? "asset");
    setNormalBalance(account?.normal_balance ?? "debit");
    setAllowPosting(account?.allow_posting ?? true);
    setAccountActive(account?.active ?? true);
    setAccountOpen(true);
  }

  const [rateOpen, setRateOpen] = useState(false);

  const [rateCurrency, setRateCurrency] = useState("");

  const [rateDate, setRateDate] = useState(businessDate());

  const [rateValue, setRateValue] = useState("");

  const [rateNotes, setRateNotes] = useState("");

  const [periodMonth, setPeriodMonth] = useState(businessMonth());

  const [journalOpen, setJournalOpen] = useState(false);

  const [journalDate, setJournalDate] = useState(businessDate());

  const [journalDescription, setJournalDescription] = useState("");

  const [journalCurrency, setJournalCurrency] = useState(baseCurrency);

  const [journalLines, setJournalLines] = useState<JournalDraftLine[]>([
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

  const [selectedJournal, setSelectedJournal] = useState<FinanceJournal | null>(null);

  const [journalDetailLines, setJournalDetailLines] = useState<FinanceJournalLine[]>([]);

  const [journalDetailsOpen, setJournalDetailsOpen] = useState(false);

  const [journalDetailsLoading, setJournalDetailsLoading] = useState(false);

  const [journalReversalReason, setJournalReversalReason] = useState("");

  const [reversingJournal, setReversingJournal] = useState(false);

  const postingAccounts = useMemo(
    () => accounts.filter((account) => account.active && account.allow_posting),
    [accounts],
  );

  const totalDebit = trialBalance.reduce((sum, row) => sum + numberValue(row.debit), 0);

  const totalCredit = trialBalance.reduce((sum, row) => sum + numberValue(row.credit), 0);

  const assets = trialBalance
    .filter((row) => row.account_type === "asset")
    .reduce((sum, row) => sum + numberValue(row.balance), 0);

  const liabilities = trialBalance
    .filter((row) => row.account_type === "liability")
    .reduce((sum, row) => sum - numberValue(row.balance), 0);

  const revenue = trialBalance
    .filter((row) => row.account_type === "revenue")
    .reduce((sum, row) => sum - numberValue(row.balance), 0);

  const expenses = trialBalance
    .filter((row) => row.account_type === "expense")
    .reduce((sum, row) => sum + numberValue(row.balance), 0);

  const netProfit = revenue - expenses;

  async function saveAccount(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!accountCode.trim() || !accountName.trim()) {
      setMessage("الكود واسم الحساب مطلوبين.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc("save_finance_account", {
      target_company: companyId,
      target_account: editingAccount?.id ?? null,
      target_parent: accountParent || null,
      target_code: accountCode.trim(),
      target_name: accountName.trim(),
      target_type: accountType,
      target_group: editingAccount?.account_group ?? null,
      target_normal_balance: normalBalance,
      target_allow_posting: allowPosting,
      target_active: accountActive,
    });

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    setAccountOpen(false);
    setEditingAccount(null);
    setAccountCode("");
    setAccountName("");
    setAccountParent("");

    router.refresh();
  }

  async function saveRate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const normalizedRateCurrency = rateCurrency.trim().toUpperCase();

    if (
      !/^[A-Z]{3}$/.test(normalizedRateCurrency) ||
      normalizedRateCurrency === baseCurrency.toUpperCase() ||
      !rateDate ||
      rateDate > businessDate() ||
      numberValue(rateValue) <= 0
    ) {
      setMessage("اكتب العملة وسعر الصرف.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc("save_finance_exchange_rate", {
      target_company: companyId,
      target_currency: normalizedRateCurrency,
      target_date: rateDate,
      // الشاشة بتسأل "1 دولار = كم ليرة"، والقاعدة بتخزّن قيمة الليرة الوحدة بالدولار.
      target_rate: 1 / numberValue(rateValue),
      target_notes: rateNotes.trim() || null,
    });

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    setRateOpen(false);
    setRateValue("");
    setRateNotes("");

    router.refresh();
  }

  async function changePeriod(action: "close" | "reopen") {
    if (!periodMonth) {
      return;
    }

    const [year, month] = periodMonth.split("-").map(Number);

    if (!year || !month) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc(
      action === "close" ? "close_finance_month" : "reopen_finance_month",
      {
        target_company: companyId,
        target_year: year,
        target_month: month,
      },
    );

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    router.refresh();
  }

  async function saveJournal(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const lines = journalLines
      .map((line) => ({
        account_id: line.accountId,
        debit: numberValue(line.debit),
        credit: numberValue(line.credit),
        memo: line.memo.trim() || null,
      }))
      .filter((line) => line.account_id && (line.debit > 0 || line.credit > 0));

    if (!journalDescription.trim()) {
      setMessage("اكتب بيان القيد.");
      return;
    }

    if (lines.length < 2) {
      setMessage("القيد لازم يحتوي سطرين على الأقل.");
      return;
    }

    const debit = lines.reduce((sum, line) => sum + line.debit, 0);

    const credit = lines.reduce((sum, line) => sum + line.credit, 0);

    if (Math.abs(debit - credit) > 0.009) {
      setMessage("القيد غير متوازن.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc("post_manual_journal_entry", {
      target_company: companyId,
      target_date: journalDate,
      target_description: journalDescription.trim(),
      target_currency: journalCurrency,
      target_exchange_rate: 1,
      lines_payload: lines,
    });

    setSaving(false);

    if (error) {
      console.error("Finance operation failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    setJournalOpen(false);
    setJournalDescription("");
    setJournalCurrency(baseCurrency);

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

  async function openJournalDetails(journal: FinanceJournal) {
    setSelectedJournal(journal);
    setJournalDetailLines([]);
    setJournalReversalReason("");
    setMessage("");
    setJournalDetailsOpen(true);
    setJournalDetailsLoading(true);

    const { data, error } = await supabase
      .from("journal_lines")
      .select("id,account_id,debit,credit,base_debit,base_credit,memo")
      .eq("company_id", companyId)
      .eq("journal_entry_id", journal.id)
      .order("created_at", {
        ascending: true,
      });

    setJournalDetailsLoading(false);

    if (error) {
      console.error("Finance journal details failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    setJournalDetailLines((data ?? []) as FinanceJournalLine[]);
  }

  async function reverseSelectedManualJournal() {
    if (
      !canReverseManualJournal ||
      !selectedJournal ||
      selectedJournal.source_type !== "manual" ||
      selectedJournal.status !== "posted" ||
      selectedJournal.reversed_from_id
    ) {
      setMessage("هذا القيد غير قابل للعكس.");
      return;
    }

    if (!journalReversalReason.trim()) {
      setMessage("سبب عكس القيد مطلوب.");
      return;
    }

    setReversingJournal(true);
    setMessage("");

    const { error } = await supabase.rpc("reverse_manual_journal_entry", {
      target_company: companyId,
      target_entry: selectedJournal.id,
      target_reason: journalReversalReason.trim(),
    });

    setReversingJournal(false);

    if (error) {
      console.error("Manual journal reversal failed", error);

      setMessage(friendlyFinanceError(error));
      return;
    }

    setJournalDetailsOpen(false);
    setSelectedJournal(null);
    setJournalDetailLines([]);
    setJournalReversalReason("");
    router.refresh();
  }

  const tabButton = (key: Tab, label: string) => (
    <button
      type="button"
      className={tab === key ? "primaryButton" : "softButton"}
      onClick={() => navigateFinance(key)}
    >
      {label}
    </button>
  );

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المالية</span>

          <h2>الإدارة المالية</h2>

          <p className="muted">كل العمليات التشغيلية تترحل محاسبيًا بشكل تلقائي.</p>
        </div>

        <div className="rowActions">
          {canManualJournal && (
            <button
              type="button"
              className="softButton"
              onClick={() => {
                setMessage("");
                setJournalOpen(true);
              }}
            >
              <Icons.plus size={14} />
              قيد يدوي
            </button>
          )}

          {canWrite && (
            <button type="button" className="primaryButton" onClick={() => openAccountForm(null)}>
              <Icons.plus size={14} />
              حساب جديد
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini title="الأصول" value={`${formatNumber(assets)} ${baseCurrency}`} />

        <Mini title="الالتزامات" value={`${formatNumber(liabilities)} ${baseCurrency}`} />

        <Mini title="الإيرادات" value={`${formatNumber(revenue)} ${baseCurrency}`} />

        <Mini title="النتيجة الحالية" value={`${formatNumber(netProfit)} ${baseCurrency}`} />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {tabButton("overview", "نظرة عامة")}

        {tabButton("accounts", "شجرة الحسابات")}

        {tabButton("journals", "القيود")}

        {tabButton("rates", "أسعار الصرف")}

        {tabButton("periods", "الفترات المالية")}
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

      {tab === "overview" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader panelPad">
            <div>
              <h2>ميزان المراجعة</h2>

              <p>المدين والدائن بالعملة الأساسية</p>
            </div>
          </div>

          <TrialTable rows={trialBalance} currency={baseCurrency} />

          <div
            className="panelPad"
            style={{
              borderTop: "1px solid rgba(255,255,255,.06)",
            }}
          >
            <strong>
              مجموع المدين: {formatNumber(totalDebit)} {baseCurrency}
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
              مجموع الدائن: {formatNumber(totalCredit)} {baseCurrency}
            </strong>
          </div>
        </section>
      )}

      {tab === "accounts" && (
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
                  {canWrite ? <th /> : null}
                </tr>
              </thead>

              <tbody>
                {accounts.map((account) => (
                  <tr key={account.id}>
                    <td>
                      <strong>{account.code}</strong>
                    </td>

                    <td>
                      {account.name}

                      {account.is_system && <div className="muted">حساب نظام</div>}
                    </td>

                    <td>{accountTypeLabels[account.account_type] || account.account_type}</td>

                    <td>{account.normal_balance === "debit" ? "مدين" : "دائن"}</td>

                    <td>{account.allow_posting ? "نعم" : "تجميعي"}</td>

                    <td>
                      <span className={`chip ${account.active ? "green" : "gray"}`}>
                        {account.active ? "نشط" : "موقوف"}
                      </span>
                    </td>

                    {canWrite ? (
                      <td>
                        {account.is_system ? null : (
                          <button
                            type="button"
                            className="softButton"
                            onClick={() => openAccountForm(account)}
                          >
                            <Icons.edit size={13} /> تعديل
                          </button>
                        )}
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab === "journals" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <form className="panelPad rowActions" onSubmit={searchJournals}>
            <div className="searchBox" style={{ flex: 1, minWidth: 220 }}>
              <Icons.search size={14} />
              <input
                value={journalSearch}
                onChange={(event) => setJournalSearch(event.target.value)}
                placeholder="بحث برقم القيد أو البيان (اسم زبون، رقم فاتورة...)"
                aria-label="بحث بالقيود"
              />
            </div>
            <button className="softButton">بحث</button>
          </form>

          {!journals.length ? (
            <div className="empty">
              <Icons.money size={28} />

              <h3>{q ? "ما في قيود مطابقة للبحث" : "ما في قيود"}</h3>

              <p>{q ? "جرّب كلمة تانية." : "أول عملية مالية رح تولد قيد تلقائي."}</p>
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
                    <th />
                  </tr>
                </thead>

                <tbody>
                  {journals.map((journal) => (
                    <tr key={journal.id}>
                      <td>
                        <strong>{journal.entry_number}</strong>
                      </td>

                      <td>{formatDate(journal.entry_date)}</td>

                      <td>{journal.description}</td>

                      <td>{sourceLabel(journal.source_type)}</td>

                      <td>{journal.currency}</td>

                      <td>
                        <span
                          className={`chip ${journal.status === "posted" ? "green" : "orange"}`}
                        >
                          {journal.status === "posted" ? "مرحّل" : "معكوس"}
                        </span>
                      </td>

                      <td>
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void openJournalDetails(journal)}
                        >
                          عرض
                        </button>
                      </td>
                    </tr>
                  ))}
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
              onClick={() => navigateFinance("journals", "journalPage", journalPage - 1)}
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${journalPage} \u0645\u0646 ${journalTotalPages} - ${journalCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={journalPage >= journalTotalPages}
              onClick={() => navigateFinance("journals", "journalPage", journalPage + 1)}
            >
              {"\u0627\u0644\u062a\u0627\u0644\u064a"}
            </button>
          </div>
        </section>
      )}

      {tab === "rates" && (
        <section
          className="panel panelPad"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader">
            <div>
              <h2>أسعار الصرف</h2>

              <p>العملة الأساسية: {baseCurrency}</p>
            </div>

            {canWrite && (
              <button
                type="button"
                className="primaryButton"
                onClick={() => {
                  setMessage("");
                  setRateOpen(true);
                }}
              >
                <Icons.plus size={14} />
                سعر صرف
              </button>
            )}
          </div>

          {!rates.length ? (
            <p className="muted">ما في أسعار صرف مسجلة.</p>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>العملة</th>
                    <th>التاريخ</th>
                    <th>سعر الصرف</th>
                    <th>ملاحظات</th>
                  </tr>
                </thead>

                <tbody>
                  {rates.map((rate) => (
                    <tr key={rate.id}>
                      <td>
                        <strong>{rate.currency}</strong>
                      </td>

                      <td>{formatDate(rate.rate_date)}</td>

                      <td>{unitsPerBase(rate.rate_to_base, baseCurrency, rate.currency)}</td>

                      <td>{rate.notes || "—"}</td>
                    </tr>
                  ))}
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
              onClick={() => navigateFinance("rates", "ratePage", ratePage - 1)}
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${ratePage} \u0645\u0646 ${rateTotalPages} - ${rateCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={ratePage >= rateTotalPages}
              onClick={() => navigateFinance("rates", "ratePage", ratePage + 1)}
            >
              {"\u0627\u0644\u062a\u0627\u0644\u064a"}
            </button>
          </div>
        </section>
      )}

      {tab === "periods" && (
        <section
          className="panel panelPad"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader">
            <div>
              <h2>إقفال الأشهر</h2>

              <p>الشهر المقفل يمنع أي ترحيل محاسبي جديد داخله.</p>
            </div>
          </div>

          <div className="formGrid">
            <label className="field">
              <span>الشهر</span>

              <input
                type="month"
                value={periodMonth}
                onChange={(event) => setPeriodMonth(event.target.value)}
              />
            </label>

            <div className="field">
              <span>الإجراء</span>

              <div className="rowActions">
                {canClose && (
                  <button
                    type="button"
                    className="primaryButton"
                    disabled={saving}
                    onClick={() => void changePeriod("close")}
                  >
                    إقفال الشهر
                  </button>
                )}

                {canReopen && (
                  <button
                    type="button"
                    className="softButton"
                    disabled={saving}
                    onClick={() => void changePeriod("reopen")}
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
                {periods.map((period) => (
                  <tr key={period.id}>
                    <td>{period.period_start}</td>

                    <td>{period.period_end}</td>

                    <td>
                      <span className={`chip ${period.status === "closed" ? "orange" : "green"}`}>
                        {period.status === "closed" ? "مقفل" : "مفتوح"}
                      </span>
                    </td>
                  </tr>
                ))}
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
              onClick={() => navigateFinance("periods", "periodPage", periodPage - 1)}
            >
              {"\u0627\u0644\u0633\u0627\u0628\u0642"}
            </button>

            <span className="muted">
              {`\u0635\u0641\u062d\u0629 ${periodPage} \u0645\u0646 ${periodTotalPages} - ${periodCount} \u0633\u062c\u0644`}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={periodPage >= periodTotalPages}
              onClick={() => navigateFinance("periods", "periodPage", periodPage + 1)}
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
                <span className="eyebrow">قيد</span>

                <h2 id="journal-details-title">{selectedJournal.entry_number}</h2>

                <p className="muted">{selectedJournal.description}</p>
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
                <strong>{formatDate(selectedJournal.entry_date)}</strong>
              </div>

              <div className="field">
                <span>المصدر</span>
                <strong>{sourceLabel(selectedJournal.source_type)}</strong>
              </div>

              <div className="field">
                <span>العملة</span>
                <strong>{selectedJournal.currency}</strong>
              </div>

              <div className="field">
                <span>سعر الصرف</span>
                <strong>
                  {selectedJournal.currency === baseCurrency
                    ? "—"
                    : unitsPerBase(
                        selectedJournal.exchange_rate_to_base,
                        baseCurrency,
                        selectedJournal.currency,
                      )}
                </strong>
              </div>
            </div>

            <div className="tableWrap" style={{ marginTop: 16 }}>
              {journalDetailsLoading ? (
                <div className="panelPad muted">جاري تحميل تفاصيل القيد...</div>
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
                      const account = accounts.find((item) => item.id === line.account_id);

                      return (
                        <tr key={line.id}>
                          <td>
                            <strong>
                              {account ? `${account.code} - ${account.name}` : "حساب غير متاح"}
                            </strong>
                          </td>

                          <td>{formatNumber(numberValue(line.debit))}</td>

                          <td>{formatNumber(numberValue(line.credit))}</td>

                          <td>
                            {formatNumber(numberValue(line.base_debit))} {baseCurrency}
                          </td>

                          <td>
                            {formatNumber(numberValue(line.base_credit))} {baseCurrency}
                          </td>

                          <td>{line.memo || "—"}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              ) : (
                <div className="panelPad muted">لا توجد سطور لهذا القيد.</div>
              )}
            </div>

            {canReverseManualJournal &&
              selectedJournal.source_type === "manual" &&
              selectedJournal.status === "posted" &&
              !selectedJournal.reversed_from_id && (
                <div className="panelPad" style={{ marginTop: 16 }}>
                  <label className="field">
                    <span>سبب عكس القيد *</span>

                    <textarea
                      rows={3}
                      value={journalReversalReason}
                      onChange={(event) => setJournalReversalReason(event.target.value)}
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
                    disabled={reversingJournal || !journalReversalReason.trim()}
                    onClick={() => void reverseSelectedManualJournal()}
                  >
                    {reversingJournal ? "جاري العكس..." : "عكس القيد"}
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
                <span className="eyebrow">شجرة الحسابات</span>

                <h2>{editingAccount ? `تعديل ${editingAccount.code}` : "حساب جديد"}</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setAccountOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={saveAccount}>
              <div className="formGrid">
                <label className="field">
                  <span>كود الحساب *</span>

                  <input
                    value={accountCode}
                    disabled={Boolean(editingAccount?.is_system)}
                    onChange={(event) => setAccountCode(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>اسم الحساب *</span>

                  <input
                    value={accountName}
                    onChange={(event) => setAccountName(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>الحساب الأب</span>

                  <select
                    value={accountParent}
                    onChange={(event) => setAccountParent(event.target.value)}
                  >
                    <option value="">بدون</option>

                    {accounts.map((account) => (
                      <option key={account.id} value={account.id}>
                        {account.code} - {account.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>النوع</span>

                  <select
                    value={accountType}
                    disabled={Boolean(editingAccount?.is_system)}
                    onChange={(event) => {
                      const value = event.target.value;

                      setAccountType(value);

                      setNormalBalance(
                        value === "asset" || value === "expense" ? "debit" : "credit",
                      );
                    }}
                  >
                    <option value="asset">أصل</option>
                    <option value="liability">التزام</option>
                    <option value="equity">حقوق ملكية</option>
                    <option value="revenue">إيراد</option>
                    <option value="expense">مصروف</option>
                  </select>
                </label>

                <label className="field">
                  <span>الرصيد الطبيعي</span>

                  <select
                    value={normalBalance}
                    onChange={(event) => setNormalBalance(event.target.value)}
                  >
                    <option value="debit">مدين</option>
                    <option value="credit">دائن</option>
                  </select>
                </label>

                <label className="field">
                  <span>يسمح بالترحيل</span>

                  <select
                    value={allowPosting ? "yes" : "no"}
                    disabled={Boolean(editingAccount?.is_system)}
                    onChange={(event) => setAllowPosting(event.target.value === "yes")}
                  >
                    <option value="yes">نعم</option>
                    <option value="no">حساب تجميعي</option>
                  </select>
                </label>

                {editingAccount && !editingAccount.is_system ? (
                  <label className="field">
                    <span>الحالة</span>

                    <select
                      value={accountActive ? "yes" : "no"}
                      onChange={(event) => setAccountActive(event.target.value === "yes")}
                    >
                      <option value="yes">نشط</option>
                      <option value="no">موقوف (ما بينرحّل عليه)</option>
                    </select>
                  </label>
                ) : null}
              </div>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setAccountOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
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
                <span className="eyebrow">سعر الصرف</span>

                <h2>تسجيل سعر صرف</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setRateOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={saveRate}>
              <div className="formGrid">
                <label className="field">
                  <span>العملة</span>

                  <input
                    value={rateCurrency}
                    onChange={(event) => setRateCurrency(event.target.value.toUpperCase())}
                  />
                </label>

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={rateDate}
                    onChange={(event) => setRateDate(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>
                    1 {baseCurrency} = كم {rateCurrency || "من العملة"}؟ (مثلًا 13000)
                  </span>

                  <NumberInput
                    min="0.0001"
                    step="any"
                    value={rateValue}
                    onChange={(event) => setRateValue(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>

                  <textarea
                    rows={3}
                    value={rateNotes}
                    onChange={(event) => setRateNotes(event.target.value)}
                  />
                </label>
              </div>

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setRateOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
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
                <span className="eyebrow">قيد يدوي</span>

                <h2>قيد يومية يدوي</h2>

                <p className="muted">للاستخدام المحاسبي فقط.</p>
              </div>

              <button type="button" className="closeButton" onClick={() => setJournalOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={saveJournal}>
              <div className="formGrid">
                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={journalDate}
                    onChange={(event) => setJournalDate(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>العملة</span>

                  <select
                    value={journalCurrency}
                    onChange={(event) => setJournalCurrency(event.target.value)}
                  >
                    {[baseCurrency, ...new Set(rates.map((rate) => rate.currency))]
                      .filter((code, index, list) => list.indexOf(code) === index)
                      .map((code) => (
                        <option key={code} value={code}>
                          {code}
                        </option>
                      ))}
                  </select>

                  {journalCurrency !== baseCurrency ? (
                    <small className="helpText">
                      {rateHint(rates, journalCurrency, journalDate, baseCurrency) ??
                        "ما في سعر صرف مسجّل لهالتاريخ، سجّلو أول من «أسعار الصرف»."}
                    </small>
                  ) : null}
                </label>
                <label className="field full">
                  <span>البيان *</span>

                  <input
                    value={journalDescription}
                    onChange={(event) => setJournalDescription(event.target.value)}
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
                    {journalLines.map((line, index) => (
                      <tr key={index}>
                        <td>
                          <select
                            value={line.accountId}
                            onChange={(event) =>
                              setJournalLines((current) =>
                                current.map((row, rowIndex) =>
                                  rowIndex === index
                                    ? {
                                        ...row,
                                        accountId: event.target.value,
                                      }
                                    : row,
                                ),
                              )
                            }
                          >
                            <option value="">اختار</option>

                            {postingAccounts.map((account) => (
                              <option key={account.id} value={account.id}>
                                {account.code} - {account.name}
                              </option>
                            ))}
                          </select>
                        </td>

                        <td>
                          <NumberInput
                            min="0"
                            step="0.01"
                            value={line.debit}
                            onChange={(event) =>
                              setJournalLines((current) =>
                                current.map((row, rowIndex) =>
                                  rowIndex === index
                                    ? {
                                        ...row,
                                        debit: event.target.value,
                                        credit: event.target.value ? "" : row.credit,
                                      }
                                    : row,
                                ),
                              )
                            }
                          />
                        </td>

                        <td>
                          <NumberInput
                            min="0"
                            step="0.01"
                            value={line.credit}
                            onChange={(event) =>
                              setJournalLines((current) =>
                                current.map((row, rowIndex) =>
                                  rowIndex === index
                                    ? {
                                        ...row,
                                        credit: event.target.value,
                                        debit: event.target.value ? "" : row.debit,
                                      }
                                    : row,
                                ),
                              )
                            }
                          />
                        </td>

                        <td>
                          <input
                            value={line.memo}
                            onChange={(event) =>
                              setJournalLines((current) =>
                                current.map((row, rowIndex) =>
                                  rowIndex === index
                                    ? {
                                        ...row,
                                        memo: event.target.value,
                                      }
                                    : row,
                                ),
                              )
                            }
                          />
                        </td>

                        <td>
                          {journalLines.length > 2 && (
                            <button
                              type="button"
                              className="dangerButton"
                              onClick={() =>
                                setJournalLines((current) =>
                                  current.filter((_, rowIndex) => rowIndex !== index),
                                )
                              }
                            >
                              ×
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
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
                  setJournalLines((current) => [
                    ...current,
                    {
                      accountId: "",
                      debit: "",
                      credit: "",
                      memo: "",
                    },
                  ])
                }
              >
                <Icons.plus size={13} />
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
                  {formatNumber(journalLines.reduce((sum, row) => sum + numberValue(row.debit), 0))}
                </strong>

                <strong>
                  دائن:{" "}
                  {formatNumber(journalLines.reduce((sum, row) => sum + numberValue(row.credit), 0))}
                </strong>
              </div>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setJournalOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
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

function TrialTable({ rows, currency }: { rows: TrialBalanceRow[]; currency: string }) {
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
          {rows.map((row) => (
            <tr key={row.account_id}>
              <td>
                <strong>{row.code}</strong>
              </td>

              <td>{row.name}</td>

              <td>
                {formatNumber(numberValue(row.debit))} {currency}
              </td>

              <td>
                {formatNumber(numberValue(row.credit))} {currency}
              </td>

              <td>{formatNumber(numberValue(row.balance))}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function sourceLabel(source: string | null) {
  const labels: Record<string, string> = {
    manual: "يدوي",
    sales_invoice: "فاتورة بيع",
    purchase_invoice: "فاتورة شراء",
    customer_payment: "قبض عميل",
    customer_payment_allocation: "تخصيص قبض",
    supplier_payment: "دفع مورد",
    supplier_payment_allocation: "تخصيص مورد",
    inventory_movement: "حركة مخزون",
    expense: "مصروف",
    payroll_run: "رواتب",
    payroll_payment: "دفع راتب",
    cash_transaction: "حركة صندوق",
    reversal: "قيد عكسي",
    sales_return: "مرتجع مبيعات",
    sales_return_reversal: "عكس مرتجع مبيعات",
    purchase_return: "مرتجع مشتريات",
    purchase_return_reversal: "عكس مرتجع مشتريات",
    customer_payment_release: "رصيد للزبون من مرتجع",
    employee_loan_disbursement: "صرف سلفة موظف",
    fixed_asset: "شراء أصل",
    asset_disposal: "بيع أو شطب أصل",
    import_cost: "مصروف استيراد",
    import_shipment: "توزيع مصاريف استيراد",
    asset_depreciation: "إهلاك أصول",
    partner_transaction: "حركة شريك",
    goods_receipt: "استلام بضاعة",
  };

  return source ? labels[source] || source : "—";
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>

      <div className="statValue">{value}</div>
    </div>
  );
}
