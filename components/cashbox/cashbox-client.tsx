"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Icons } from "@/components/icons";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import { createClient } from "@/lib/supabase/client";
import { NumberInput } from "@/components/number-input";
import { formatNumber, formatSigned, formatDateTime as formatDamascusDateTime, formatDate as formatDamascusDate, todayDamascus } from "@/lib/format";

const expenseCategories = [
  "بنزين",
  "صيانة ربيت",
  "زيت",
  "هاتف وإنترنت",
  "تحميل وتنزيل",
  "طعام شغل",
  "إيجار",
  "رواتب",
  "أخرى",
];

type CashboxRow = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
};

type RelatedCashbox = {
  name: string;
  currency: string;
};

type RelatedSupplier = {
  name: string;
};

type CashboxBalance = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
  balance: number | string;
};

type CashTransactionRow = {
  id: string;
  cashbox_id: string;
  direction: "in" | "out";
  type: string;
  amount: number | string;
  notes: string | null;
  occurred_at: string;
  created_at?: string | null;
  suppliers: RelatedSupplier | RelatedSupplier[] | null;
  traders?: RelatedSupplier | RelatedSupplier[] | null;
  cashboxes: RelatedCashbox | RelatedCashbox[] | null;
};

type ExpenseRow = {
  id: string;
  cashbox_id: string | null;
  category: string;
  amount: number | string;
  notes: string | null;
  occurred_at: string;
  cashboxes: RelatedCashbox | RelatedCashbox[] | null;
};

type SummaryRow = {
  currency: string;
  balance: number | string;
  today_in: number | string;
  today_out: number | string;
  month_expense: number | string;
};

const movementLabels: Record<string, string> = {
  sale_receipt: "قبض من زبون",
  supplier_payment: "دفع لمورد",
  expense: "مصروف",
  adjustment_in: "رصيد افتتاحي / زيادة بالصندوق",
  adjustment_out: "نقص بالصندوق",
  customer_payment_reversal: "عكس قبض من زبون",
  supplier_payment_reversal: "عكس دفعة مورد",
  payroll_payment: "دفع راتب",
  asset_purchase: "شراء أصل",
  asset_sale: "بيع أصل",
  import_cost: "مصروف استيراد",
  employee_advance: "سلفة موظف",
  employee_loan: "قرض موظف",
  partner_distribution: "توزيع شريك",
};

function one<T>(value: T | T[] | null | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }

  return value ?? null;
}

/**
 * بعض الحركات (قبض، دفعة مورد، رواتب) محفوظ إلها التاريخ بس، فساعتها بتطلع 12:00.
 * إذا انسجلت بنفس اليوم منفرجي ساعة التسجيل الحقيقية، وإلا التاريخ بس.
 */
function formatMovementTime(occurredAt: string, createdAt?: string | null) {
  const day = (value: string) =>
    new Date(value).toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
  const time = new Date(occurredAt).toLocaleTimeString("en-GB", {
    timeZone: "Asia/Damascus",
    hour: "2-digit",
    minute: "2-digit",
  });
  if (time !== "00:00" && time !== "12:00")
    return formatDamascusDateTime(occurredAt);
  if (createdAt && day(createdAt) === day(occurredAt))
    return formatDamascusDateTime(createdAt);
  return formatDamascusDate(occurredAt);
}

function formatSummary(
  rows: SummaryRow[],
  field: "balance" | "today_in" | "today_out" | "month_expense",
  fallbackCurrency: string,
) {
  if (!rows.length) {
    return `0.00 ${fallbackCurrency}`;
  }

  return rows
    .map((row) => `${formatNumber(Number(row[field] || 0))} ${row.currency}`)
    .join("\n"); // كل عملة بسطر لحالها
}

export function CashboxClient({
  companyId,
  defaultCurrency,
  cashboxes,
  initialTransactions,
  initialExpenses,
  summary,
  balances,
  canViewExpenses,
  canWriteCashbox,
  canWriteExpenses,
  pageError,
  txPage,
  txTotalPages,
  expensePage,
  expenseTotalPages,
  q,
  type,
  cashboxFilter,
}: {
  companyId: string;
  defaultCurrency: string;
  cashboxes: CashboxRow[];
  initialTransactions: CashTransactionRow[];
  initialExpenses: ExpenseRow[];
  summary: SummaryRow[];
  balances: CashboxBalance[];
  canViewExpenses: boolean;
  canWriteCashbox: boolean;
  canWriteExpenses: boolean;
  pageError: string | null;
  txPage: number;
  txTotalPages: number;
  expensePage: number;
  expenseTotalPages: number;
  q: string;
  type: string;
  cashboxFilter: string;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const defaultCashboxId = useMemo(() => {
    return (
      cashboxes.find(
        (cashbox) =>
          cashbox.currency.toUpperCase() === defaultCurrency.toUpperCase(),
      )?.id ??
      cashboxes[0]?.id ??
      ""
    );
  }, [cashboxes, defaultCurrency]);

  const [expenseOpen, setExpenseOpen] = useState(false);
  const [movementOpen, setMovementOpen] = useState(false);
  const [category, setCategory] = useState(expenseCategories[0]);
  const [amount, setAmount] = useState("");
  const [notes, setNotes] = useState("");
  const [cashboxId, setCashboxId] = useState(defaultCashboxId);
  // سعر الصرف لحظة العملية إذا الصندوق مش بالعملة الأساسية.
  const [txRate, setTxRate] = useState("");
  const [movementType, setMovementType] = useState("adjustment_in");
  const [saving, setSaving] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);

  // إدارة الصناديق: إضافة، تعديل الاسم، إيقاف/تفعيل.
  const [boxForm, setBoxForm] = useState<{
    id: string | null;
    name: string;
    currency: string;
  } | null>(null);
  const [boxMessage, setBoxMessage] = useState("");

  function openNewBox() {
    setBoxMessage("");
    setBoxForm({
      id: null,
      name: "",
      currency: defaultCurrency === "USD" ? "SYP" : "USD",
    });
  }

  async function saveBox(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!boxForm) return;
    const name = boxForm.name.trim();
    const currency = boxForm.currency.trim().toUpperCase();
    if (!name) return setBoxMessage("اكتب اسم الصندوق.");
    if (!/^[A-Z]{3}$/.test(currency))
      return setBoxMessage("العملة لازم تكون 3 أحرف، متل USD أو SYP.");

    setSaving(true);
    const { error } = boxForm.id
      ? await supabase
          .from("cashboxes")
          .update({ name })
          .eq("id", boxForm.id)
          .eq("company_id", companyId)
      : await supabase
          .from("cashboxes")
          .insert({ company_id: companyId, name, currency });
    setSaving(false);

    if (error) {
      setBoxMessage(
        error.code === "23505"
          ? "في صندوق بنفس الاسم."
          : "ما قدرنا نحفظ الصندوق. تأكد من الصلاحيات.",
      );
      return;
    }
    setBoxForm(null);
    router.refresh();
  }

  async function toggleBox(box: CashboxBalance) {
    setFeedback(null);
    const { error } = await supabase
      .from("cashboxes")
      .update({ active: !box.active })
      .eq("id", box.id)
      .eq("company_id", companyId);
    if (error) {
      setFeedback(
        error.message.toLowerCase().includes("balance")
          ? `ما فيك توقف "${box.name}" وفيه مصاري. انقل الرصيد أول.`
          : "ما قدرنا نغيّر حالة الصندوق.",
      );
      return;
    }
    router.refresh();
  }

  function openExpense() {
    if (!canWriteExpenses) {
      setFeedback("ما عندك صلاحية لإضافة مصروف.");
      return;
    }

    setFeedback(null);
    setAmount("");
    setNotes("");
    setCashboxId(defaultCashboxId);
    setExpenseOpen(true);
  }

  function openMovement() {
    if (!canWriteCashbox) {
      setFeedback("ما عندك صلاحية لإجراء تسوية صندوق.");
      return;
    }

    setFeedback(null);
    setAmount("");
    setNotes("");
    setCashboxId(defaultCashboxId);
    setMovementType("adjustment_in");
    setMovementOpen(true);
  }

  async function addExpense(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!cashboxId) {
      setFeedback("اختار صندوق أولاً.");
      return;
    }

    if (Number(amount) <= 0) {
      setFeedback("اكتب مبلغ صحيح أكبر من صفر.");
      return;
    }

    setFeedback(null);
    setSaving(true);

    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      cashboxes.find((cashbox) => cashbox.id === cashboxId)?.currency ?? "",
      defaultCurrency,
      todayDamascus(),
      txRate,
    );

    if (rateError) {
      setSaving(false);
      setFeedback(rateError);
      return;
    }

    const { error } = await supabase.rpc("record_expense", {
      target_company: companyId,
      target_cashbox: cashboxId,
      expense_category: category,
      expense_amount: Number(amount),
      expense_notes: notes.trim() || null,
    });

    setSaving(false);

    if (error) {
      setFeedback(
        "تعذر حفظ العملية. تأكد من البيانات والصلاحيات وحاول مرة ثانية.",
      );
      return;
    }

    setExpenseOpen(false);
    setAmount("");
    setNotes("");
    router.refresh();
  }

  async function addMovement(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!cashboxId) {
      setFeedback("اختار صندوق أولاً.");
      return;
    }

    if (Number(amount) <= 0) {
      setFeedback("اكتب مبلغ صحيح أكبر من صفر.");
      return;
    }

    setFeedback(null);
    setSaving(true);

    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      cashboxes.find((cashbox) => cashbox.id === cashboxId)?.currency ?? "",
      defaultCurrency,
      todayDamascus(),
      txRate,
    );

    if (rateError) {
      setSaving(false);
      setFeedback(rateError);
      return;
    }

    const { error } = await supabase.rpc("record_cash_movement", {
      target_company: companyId,
      target_cashbox: cashboxId,
      movement_type: movementType,
      movement_amount: Number(amount),
      movement_notes: notes.trim() || null,
    });

    setSaving(false);

    if (error) {
      setFeedback(
        "تعذر حفظ العملية. تأكد من البيانات والصلاحيات وحاول مرة ثانية.",
      );
      return;
    }

    setMovementOpen(false);
    setAmount("");
    setNotes("");
    router.refresh();
  }

  const hasCashboxes = cashboxes.length > 0;

  function pageHref(kind: "tx" | "expense", page: number) {
    const params = new URLSearchParams();

    if (q) params.set("q", q);
    if (type) params.set("type", type);
    if (cashboxFilter) params.set("cashbox", cashboxFilter);

    if (kind === "tx" && page > 1) {
      params.set("txPage", String(page));
    }

    if (kind === "expense" && page > 1) {
      params.set("expensePage", String(page));
    }

    if (kind !== "tx" && txPage > 1) {
      params.set("txPage", String(txPage));
    }

    if (kind !== "expense" && expensePage > 1) {
      params.set("expensePage", String(expensePage));
    }

    const query = params.toString();
    return query ? `/cashbox?${query}` : "/cashbox";
  }

  return (
    <div className="page">
      {(pageError || feedback) && (
        <div className="panel panelPad" role="alert" aria-live="polite">
          <strong>تنبيه</strong>
          <p className="muted">{feedback || pageError}</p>
        </div>
      )}

      <div className="pageTitle">
        <div>
          <span className="eyebrow">المحاسبة اليومية</span>
          <h2>الصندوق</h2>
          <p className="muted">
            كل عملة محسوبة لحالها، بدون خلط أرصدة الصناديق.
          </p>
        </div>

        <div className="rowActions">
          {canWriteCashbox && (
            <button
              type="button"
              className="softButton"
              onClick={openMovement}
              disabled={!hasCashboxes || saving}
            >
              <Icons.money size={14} /> تسوية صندوق
            </button>
          )}

          {canWriteExpenses && (
            <button
              type="button"
              className="primaryButton"
              onClick={openExpense}
              disabled={!hasCashboxes || saving}
            >
              <Icons.plus size={14} /> مصروف
            </button>
          )}
        </div>
      </div>

      {!hasCashboxes && (
        <section className="panel empty">
          <Icons.wallet size={28} />
          <h3>ما في صندوق نشط</h3>
          <p>لازم يكون في صندوق نشط قبل تسجيل مصروف أو تسوية.</p>
        </section>
      )}

      <section className="panel panelPad" style={{ marginBottom: 14 }}>
        <div className="panelHeader">
          <div>
            <h2>الصناديق</h2>
            <p>كل صندوق برصيده وعملته</p>
          </div>
          {canWriteCashbox ? (
            <button type="button" className="softButton" onClick={openNewBox}>
              <Icons.plus size={14} /> صندوق جديد
            </button>
          ) : null}
        </div>
        <div className="quickList">
          {balances.map((box) => (
            <div className="quickItem" key={box.id}>
              <div className="quickIcon">
                <Icons.wallet size={15} />
              </div>
              <div>
                <strong>{box.name}</strong>
                <span>
                  {box.active ? box.currency : `${box.currency} • موقوف`}
                </span>
              </div>
              <div className="count">
                {Number(box.balance || 0).toLocaleString("en-US", {
                  maximumFractionDigits: 2,
                })}{" "}
                {box.currency}
              </div>
              {canWriteCashbox ? (
                <div className="rowActions">
                  <button
                    type="button"
                    className="softButton"
                    onClick={() => {
                      setBoxMessage("");
                      setBoxForm({
                        id: box.id,
                        name: box.name,
                        currency: box.currency,
                      });
                    }}
                  >
                    <Icons.edit size={13} />
                  </button>
                  <button
                    type="button"
                    className="softButton"
                    onClick={() => void toggleBox(box)}
                  >
                    {box.active ? "إيقاف" : "تفعيل"}
                  </button>
                </div>
              ) : null}
            </div>
          ))}
        </div>
      </section>

      <section className="statsGrid">
        <Mini
          title="الرصيد الحالي"
          value={formatSummary(summary, "balance", defaultCurrency)}
        />
        <Mini
          title="داخل اليوم"
          value={formatSummary(summary, "today_in", defaultCurrency)}
        />
        <Mini
          title="خارج اليوم"
          value={formatSummary(summary, "today_out", defaultCurrency)}
        />
        <Mini
          title="مصاريف الشهر"
          value={formatSummary(summary, "month_expense", defaultCurrency)}
        />
      </section>

      <div className="pageGrid">
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>حركات الصندوق</h2>
              <p>آخر الحركات بكل الصناديق</p>
            </div>
          </div>

          {!initialTransactions.length ? (
            <div className="empty">
              <Icons.wallet size={28} />
              <h3>ما في حركات</h3>
              <p>أول قبض أو شراء أو مصروف رح يظهر هون.</p>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الحركة</th>
                    <th>البيان</th>
                    <th>الصندوق</th>
                    <th>المبلغ</th>
                    <th>التاريخ</th>
                  </tr>
                </thead>

                <tbody>
                  {initialTransactions.map((transaction) => {
                    const cashbox = one(transaction.cashboxes);
                    const supplier =
                      one(transaction.suppliers) ?? one(transaction.traders);
                    const transactionCurrency =
                      cashbox?.currency || defaultCurrency;

                    return (
                      <tr key={transaction.id}>
                        <td>
                          <span
                            className={`chip ${
                              transaction.direction === "in"
                                ? "green"
                                : "orange"
                            }`}
                          >
                            {transaction.direction === "in" ? "داخل" : "خارج"}
                          </span>
                        </td>

                        <td>
                          <strong>
                            {movementLabels[transaction.type] ||
                              transaction.type}
                          </strong>
                          <div className="muted">
                            {transaction.notes || supplier?.name || ""}
                          </div>
                        </td>

                        <td>{cashbox?.name || "—"}</td>

                        <td
                          className={
                            transaction.direction === "in"
                              ? "kpiPositive"
                              : "kpiNegative"
                          }
                        >
                          {formatSigned(
                            (transaction.direction === "in" ? 1 : -1) * Number(transaction.amount),
                          )}{" "}
                          {transactionCurrency}
                        </td>

                        <td>
                          {formatMovementTime(
                            transaction.occurred_at,
                            transaction.created_at,
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {txTotalPages > 1 && (
            <div className="rowActions">
              <button
                type="button"
                className="softButton"
                disabled={txPage <= 1}
                onClick={() => router.push(pageHref("tx", txPage - 1))}
              >
                السابق
              </button>

              <span className="muted">
                صفحة {txPage} من {txTotalPages}
              </span>

              <button
                type="button"
                className="softButton"
                disabled={txPage >= txTotalPages}
                onClick={() => router.push(pageHref("tx", txPage + 1))}
              >
                التالي
              </button>
            </div>
          )}
        </section>

        {canViewExpenses && (
          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>مصاريف التشغيل</h2>
                <p>آخر المصاريف</p>
              </div>
            </div>

            {!initialExpenses.length ? (
              <p className="muted">ما في مصاريف مسجلة.</p>
            ) : (
              <div className="quickList">
                {initialExpenses.map((expense) => {
                  const cashbox = one(expense.cashboxes);

                  return (
                    <div className="quickItem" key={expense.id}>
                      <div className="quickIcon">
                        <Icons.money size={14} />
                      </div>

                      <div>
                        <strong>{expense.category}</strong>
                        <span>
                          {expense.notes ||
                            formatDamascusDate(expense.occurred_at)}
                          {cashbox?.name ? ` • ${cashbox.name}` : ""}
                        </span>
                      </div>

                      <div className="count">
                        {formatNumber(Number(expense.amount))}{" "}
                        {cashbox?.currency || defaultCurrency}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            {expenseTotalPages > 1 && (
              <div className="rowActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={expensePage <= 1}
                  onClick={() =>
                    router.push(pageHref("expense", expensePage - 1))
                  }
                >
                  السابق
                </button>

                <span className="muted">
                  صفحة {expensePage} من {expenseTotalPages}
                </span>

                <button
                  type="button"
                  className="softButton"
                  disabled={expensePage >= expenseTotalPages}
                  onClick={() =>
                    router.push(pageHref("expense", expensePage + 1))
                  }
                >
                  التالي
                </button>
              </div>
            )}
          </aside>
        )}
      </div>

      {expenseOpen && canWriteExpenses && (
        <div
          className="modalOverlay"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget && !saving) {
              setExpenseOpen(false);
            }
          }}
        >
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">مصروف جديد</span>
                <h2>تسجيل مصروف</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق نافذة المصروف"
                onClick={() => setExpenseOpen(false)}
                disabled={saving}
              >
                ×
              </button>
            </div>

            <form onSubmit={addExpense}>
              <div className="formGrid">
                <CashboxField
                  cashboxes={cashboxes}
                  value={cashboxId}
                  onChange={setCashboxId}
                />

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={
                    cashboxes.find((cashbox) => cashbox.id === cashboxId)
                      ?.currency ?? ""
                  }
                  baseCurrency={defaultCurrency}
                  date={todayDamascus()}
                  value={txRate}
                  onChange={setTxRate}
                />

                <label className="field">
                  <span>الفئة</span>
                  <select
                    value={category}
                    onChange={(event) => setCategory(event.target.value)}
                  >
                    {expenseCategories.map((item) => (
                      <option key={item}>{item}</option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>المبلغ</span>
                  <NumberInput
                    min="0.01"
                    step="0.01"
                    inputMode="decimal"
                    required
                    value={amount}
                    onChange={(event) => setAmount(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    maxLength={500}
                    value={notes}
                    onChange={(event) => setNotes(event.target.value)}
                  />
                </label>
              </div>

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setExpenseOpen(false)}
                  disabled={saving}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "حفظ المصروف"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {movementOpen && canWriteCashbox && (
        <div
          className="modalOverlay"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget && !saving) {
              setMovementOpen(false);
            }
          }}
        >
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">تسوية يدوية</span>
                <h2>تسوية الصندوق</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق نافذة التسوية"
                onClick={() => setMovementOpen(false)}
                disabled={saving}
              >
                ×
              </button>
            </div>

            <form onSubmit={addMovement}>
              <div className="formGrid">
                <CashboxField
                  cashboxes={cashboxes}
                  value={cashboxId}
                  onChange={setCashboxId}
                />

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={
                    cashboxes.find((cashbox) => cashbox.id === cashboxId)
                      ?.currency ?? ""
                  }
                  baseCurrency={defaultCurrency}
                  date={todayDamascus()}
                  value={txRate}
                  onChange={setTxRate}
                />

                <label className="field">
                  <span>نوع التسوية</span>
                  <select
                    value={movementType}
                    onChange={(event) => setMovementType(event.target.value)}
                  >
                    <option value="adjustment_in">
                      رصيد افتتاحي / زيادة بالصندوق
                    </option>
                    <option value="adjustment_out">
                      نقص بالصندوق (بينحسب مصروف)
                    </option>
                  </select>
                  <small className="helpText">
                    لإيداع رأس مال أو سحب شريك استعمل صفحة الشركاء، مشان يتسجل
                    على حسابه.
                  </small>
                </label>

                <label className="field">
                  <span>المبلغ</span>
                  <NumberInput
                    min="0.01"
                    step="0.01"
                    inputMode="decimal"
                    required
                    value={amount}
                    onChange={(event) => setAmount(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    maxLength={500}
                    value={notes}
                    onChange={(event) => setNotes(event.target.value)}
                  />
                </label>
              </div>

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setMovementOpen(false)}
                  disabled={saving}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "تسجيل التسوية"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
      {boxForm ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="box-title"
          >
            <div className="modalHeader">
              <h2 id="box-title">
                {boxForm.id ? "تعديل الصندوق" : "صندوق جديد"}
              </h2>
              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق"
                onClick={() => setBoxForm(null)}
              >
                ×
              </button>
            </div>
            <form onSubmit={saveBox}>
              <div className="formGrid">
                <label className="field">
                  <span>اسم الصندوق</span>
                  <input
                    value={boxForm.name}
                    placeholder="مثلًا: صندوق الليرة"
                    onChange={(event) =>
                      setBoxForm({ ...boxForm, name: event.target.value })
                    }
                  />
                </label>
                <label className="field">
                  <span>العملة</span>
                  <select
                    value={
                      ["USD", "SYP"].includes(boxForm.currency)
                        ? boxForm.currency
                        : "OTHER"
                    }
                    disabled={Boolean(boxForm.id)}
                    onChange={(event) =>
                      setBoxForm({
                        ...boxForm,
                        currency:
                          event.target.value === "OTHER"
                            ? ""
                            : event.target.value,
                      })
                    }
                  >
                    <option value="USD">USD - دولار</option>
                    <option value="SYP">SYP - ليرة سورية</option>
                    <option value="OTHER">عملة تانية...</option>
                  </select>
                  {!["USD", "SYP"].includes(boxForm.currency) && !boxForm.id ? (
                    <input
                      dir="ltr"
                      maxLength={3}
                      placeholder="مثلًا CNY"
                      value={boxForm.currency}
                      onChange={(event) =>
                        setBoxForm({
                          ...boxForm,
                          currency: event.target.value.toUpperCase(),
                        })
                      }
                    />
                  ) : null}
                  {boxForm.id ? (
                    <small className="helpText">
                      عملة الصندوق ما بتتغيّر بعد ما ينعمل.
                    </small>
                  ) : null}
                </label>
              </div>
              {boxMessage ? (
                <div className="toastError">{boxMessage}</div>
              ) : null}
              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setBoxForm(null)}
                >
                  إلغاء
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "حفظ"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function CashboxField({
  cashboxes,
  value,
  onChange,
}: {
  cashboxes: CashboxRow[];
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="field">
      <span>الصندوق</span>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        required
      >
        {cashboxes.map((cashbox) => (
          <option key={cashbox.id} value={cashbox.id}>
            {cashbox.name} — {cashbox.currency}
          </option>
        ))}
      </select>
    </label>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>
      <div className="statValue" style={{ whiteSpace: "pre-line" }}>
        {value}
      </div>
    </div>
  );
}
