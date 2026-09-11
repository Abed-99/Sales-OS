"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

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

type CashTransactionRow = {
  id: string;
  cashbox_id: string;
  direction: "in" | "out";
  type: string;
  amount: number | string;
  notes: string | null;
  occurred_at: string;
  suppliers: RelatedSupplier | RelatedSupplier[] | null;
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
  adjustment_in: "تسوية داخلة",
  adjustment_out: "تسوية خارجة",
  payroll_payment: "دفع راتب",
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

function formatSummary(
  rows: SummaryRow[],
  field: "balance" | "today_in" | "today_out" | "month_expense",
  fallbackCurrency: string
) {
  if (!rows.length) {
    return `0.00 ${fallbackCurrency}`;
  }

  return rows
    .map(
      (row) =>
        `${Number(row[field] || 0).toFixed(2)} ${row.currency}`
    )
    .join(" • ");
}

export function CashboxClient({
  companyId,
  defaultCurrency,
  cashboxes,
  initialTransactions,
  initialExpenses,
  summary,
}: {
  companyId: string;
  defaultCurrency: string;
  cashboxes: CashboxRow[];
  initialTransactions: CashTransactionRow[];
  initialExpenses: ExpenseRow[];
  summary: SummaryRow[];
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const defaultCashboxId = useMemo(() => {
    return (
      cashboxes.find(
        (cashbox) =>
          cashbox.currency.toUpperCase() ===
          defaultCurrency.toUpperCase()
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
  const [movementType, setMovementType] = useState("adjustment_in");
  const [saving, setSaving] = useState(false);

  function openExpense() {
    setAmount("");
    setNotes("");
    setCashboxId(defaultCashboxId);
    setExpenseOpen(true);
  }

  function openMovement() {
    setAmount("");
    setNotes("");
    setCashboxId(defaultCashboxId);
    setMovementType("adjustment_in");
    setMovementOpen(true);
  }

  async function addExpense(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!cashboxId) {
      alert("اختار صندوق أولاً");
      return;
    }

    if (Number(amount) <= 0) {
      alert("اكتب مبلغ صحيح");
      return;
    }

    setSaving(true);

    const { error } = await supabase.rpc("record_expense", {
      target_company: companyId,
      target_cashbox: cashboxId,
      expense_category: category,
      expense_amount: Number(amount),
      expense_notes: notes.trim() || null,
    });

    setSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    setExpenseOpen(false);
    setAmount("");
    setNotes("");
    router.refresh();
  }

  async function addMovement(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!cashboxId) {
      alert("اختار صندوق أولاً");
      return;
    }

    if (Number(amount) <= 0) {
      alert("اكتب مبلغ صحيح");
      return;
    }

    setSaving(true);

    const { error } = await supabase.rpc("record_cash_movement", {
      target_company: companyId,
      target_cashbox: cashboxId,
      movement_type: movementType,
      movement_amount: Number(amount),
      movement_notes: notes.trim() || null,
    });

    setSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    setMovementOpen(false);
    setAmount("");
    setNotes("");
    router.refresh();
  }

  const hasCashboxes = cashboxes.length > 0;

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المحاسبة اليومية</span>
          <h2>الصندوق</h2>
          <p className="muted">
            كل عملة محسوبة لحالها، بدون خلط أرصدة الصناديق.
          </p>
        </div>

        <div className="rowActions">
          <button
            className="softButton"
            onClick={openMovement}
            disabled={!hasCashboxes}
          >
            <Icons.money size={14} /> تسوية صندوق
          </button>

          <button
            className="primaryButton"
            onClick={openExpense}
            disabled={!hasCashboxes}
          >
            <Icons.plus size={14} /> مصروف
          </button>
        </div>
      </div>

      {!hasCashboxes && (
        <section className="panel empty">
          <Icons.wallet size={28} />
          <h3>ما في صندوق نشط</h3>
          <p>لازم يكون في صندوق نشط قبل تسجيل مصروف أو تسوية.</p>
        </section>
      )}

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
                    const supplier = one(transaction.suppliers);
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
                            {transaction.direction === "in"
                              ? "داخل"
                              : "خارج"}
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
                          {transaction.direction === "in" ? "+" : "-"}
                          {Number(transaction.amount).toFixed(2)}{" "}
                          {transactionCurrency}
                        </td>

                        <td>
                          {new Date(
                            transaction.occurred_at
                          ).toLocaleString("ar")}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

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
              {initialExpenses.slice(0, 10).map((expense) => {
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
                          new Date(
                            expense.occurred_at
                          ).toLocaleDateString("ar")}
                        {cashbox?.name ? ` • ${cashbox.name}` : ""}
                      </span>
                    </div>

                    <div className="count">
                      {Number(expense.amount).toFixed(2)}{" "}
                      {cashbox?.currency || defaultCurrency}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </aside>
      </div>

      {expenseOpen && (
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
                className="closeButton"
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

                <label className="field">
                  <span>الفئة</span>
                  <select
                    value={category}
                    onChange={(event) =>
                      setCategory(event.target.value)
                    }
                  >
                    {expenseCategories.map((item) => (
                      <option key={item}>{item}</option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>المبلغ</span>
                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    value={amount}
                    onChange={(event) =>
                      setAmount(event.target.value)
                    }
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
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

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving ? "عم نحفظ..." : "حفظ المصروف"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {movementOpen && (
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
                className="closeButton"
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

                <label className="field">
                  <span>نوع التسوية</span>
                  <select
                    value={movementType}
                    onChange={(event) =>
                      setMovementType(event.target.value)
                    }
                  >
                    <option value="adjustment_in">
                      تسوية داخلة
                    </option>
                    <option value="adjustment_out">
                      تسوية خارجة
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>المبلغ</span>
                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    value={amount}
                    onChange={(event) =>
                      setAmount(event.target.value)
                    }
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
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

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving ? "عم نحفظ..." : "تسجيل التسوية"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
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

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>
      <div className="statValue">{value}</div>
    </div>
  );
}
