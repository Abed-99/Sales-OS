"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import { createClient } from "@/lib/supabase/client";

function num(value: unknown) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

function today() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

export type PartnerSummary = {
  id: string;
  partner_number: string | null;
  name: string;
  phone: string | null;
  ownership_percent: number;
  profit_share_percent: number;
  active: boolean;
  notes: string | null;
  capital_contributions: number;
  drawings: number;
  partner_loan_balance: number;
  profit_distributions: number;
};

export type PartnerTransaction = {
  id: string;
  partner_id: string;
  transaction_type:
    | "capital_contribution"
    | "drawing"
    | "partner_loan_in"
    | "partner_loan_repayment"
    | "profit_distribution";
  amount: number;
  currency: string;
  cashbox_id: string | null;
  transaction_date: string;
  notes: string | null;
  created_at: string;
};

export type PartnerCashbox = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
};

export function PartnersClient({
  companyId,
  baseCurrency,
  partners,
  transactions,
  cashboxes,
  canManage,
  canTransact,
}: {
  companyId: string;
  baseCurrency: string;
  partners: PartnerSummary[];
  transactions: PartnerTransaction[];
  cashboxes: PartnerCashbox[];
  canManage: boolean;
  canTransact: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const [search, setSearch] = useState("");
  const [partnerOpen, setPartnerOpen] = useState(false);
  const [movementOpen, setMovementOpen] = useState(false);

  const [editing, setEditing] = useState<PartnerSummary | null>(null);

  const [number, setNumber] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [ownership, setOwnership] = useState("");
  const [profitShare, setProfitShare] = useState("");
  const [notes, setNotes] = useState("");
  const [active, setActive] = useState(true);

  const [movementPartner, setMovementPartner] = useState("");
  const [movementType, setMovementType] =
    useState<PartnerTransaction["transaction_type"]>("capital_contribution");
  const [movementAmount, setMovementAmount] = useState("");
  const [movementCurrency, setMovementCurrency] = useState(baseCurrency);
  const [movementCashbox, setMovementCashbox] = useState("");
  const [movementDate, setMovementDate] = useState(today());
  const [txRate, setTxRate] = useState("");
  const [movementNotes, setMovementNotes] = useState("");

  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();

    if (!q) {
      return partners;
    }

    return partners.filter((partner) =>
      [partner.name, partner.phone, partner.partner_number].some((value) =>
        value?.toLowerCase().includes(q),
      ),
    );
  }, [partners, search]);

  const activePartners = partners.filter((partner) => partner.active);

  const transactionCurrencies = [
    ...new Set(transactions.map((transaction) => transaction.currency.trim().toUpperCase())),
  ];

  const completeTransactionHistory = transactions.length < 150;

  const safeSingleCurrencyTotals = completeTransactionHistory && transactionCurrencies.length <= 1;

  const partnerDisplayCurrency = transactionCurrencies[0] ?? baseCurrency;

  const totalCapital = partners.reduce(
    (sum, partner) => sum + num(partner.capital_contributions),
    0,
  );

  const totalDrawings = partners.reduce((sum, partner) => sum + num(partner.drawings), 0);

  const totalLoans = partners.reduce((sum, partner) => sum + num(partner.partner_loan_balance), 0);

  function partnerName(id: string) {
    return partners.find((partner) => partner.id === id)?.name || "شريك";
  }

  function openNewPartner() {
    setEditing(null);
    setNumber("");
    setName("");
    setPhone("");
    setOwnership("");
    setProfitShare("");
    setNotes("");
    setActive(true);
    setMessage("");
    setPartnerOpen(true);
  }

  function openEditPartner(partner: PartnerSummary) {
    setEditing(partner);
    setNumber(partner.partner_number || "");
    setName(partner.name);
    setPhone(partner.phone || "");
    setOwnership(String(num(partner.ownership_percent)));
    setProfitShare(String(num(partner.profit_share_percent)));
    setNotes(partner.notes || "");
    setActive(partner.active);
    setMessage("");
    setPartnerOpen(true);
  }

  async function savePartner(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!name.trim()) {
      setMessage("اسم الشريك مطلوب.");
      return;
    }

    if (num(ownership) > 100 || num(profitShare) > 100) {
      setMessage("النسبة لا يمكن أن تتجاوز 100%.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc("save_partner", {
      target_company: companyId,
      target_partner: editing?.id || null,
      target_number: number.trim() || null,
      target_name: name.trim(),
      target_phone: phone.trim() || null,
      target_ownership_percent: num(ownership),
      target_profit_share_percent: num(profitShare),
      target_notes: notes.trim() || null,
      target_active: active,
    });

    setSaving(false);

    if (error) {
      setMessage(partnerError(error));
      return;
    }

    setPartnerOpen(false);
    router.refresh();
  }

  function openMovement(partnerId?: string) {
    const selected = partnerId || activePartners[0]?.id || "";

    const firstCashbox =
      cashboxes.find((cashbox) => cashbox.currency === baseCurrency) ?? cashboxes[0];

    setMovementPartner(selected);
    setMovementType("capital_contribution");
    setMovementAmount("");
    setMovementCurrency(firstCashbox?.currency || baseCurrency);
    setMovementCashbox(firstCashbox?.id || "");
    setMovementDate(today());
    setMovementNotes("");
    setMessage("");
    setMovementOpen(true);
  }

  function changeCurrency(value: string) {
    const currency = value.toUpperCase();

    setMovementCurrency(currency);

    const matching = cashboxes.find((cashbox) => cashbox.currency === currency);

    setMovementCashbox(matching?.id || "");
  }

  async function saveMovement(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!movementPartner || !movementCashbox || num(movementAmount) <= 0) {
      setMessage("اختار الشريك والصندوق واكتب مبلغ صحيح.");
      return;
    }

    setSaving(true);
    setMessage("");

    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      movementCurrency,
      baseCurrency,
      movementDate,
      txRate,
    );

    if (rateError) {
      setSaving(false);
      setMessage(rateError);
      return;
    }

    const { error } = await supabase.rpc("record_partner_transaction", {
      target_company: companyId,
      target_partner: movementPartner,
      target_type: movementType,
      target_amount: num(movementAmount),
      target_currency: movementCurrency,
      target_cashbox: movementCashbox,
      target_date: movementDate,
      target_notes: movementNotes.trim() || null,
    });

    setSaving(false);

    if (error) {
      setMessage(partnerError(error));
      return;
    }

    setMovementOpen(false);
    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">الشركاء وحقوق الملكية</span>

          <h2>إدارة الشركاء</h2>

          <p className="muted">الملكية ورأس المال والمسحوبات وقروض الشركاء وتوزيعات الأرباح.</p>
        </div>

        <div className="rowActions">
          {canTransact && (
            <button
              type="button"
              className="softButton"
              disabled={!activePartners.length}
              onClick={() => openMovement()}
            >
              <Icons.money size={14} />
              حركة شريك
            </button>
          )}

          {canManage && (
            <button type="button" className="primaryButton" onClick={openNewPartner}>
              <Icons.plus size={14} />
              شريك جديد
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini title="الشركاء" value={String(activePartners.length)} />

        <Mini
          title="رأس المال المدخل"
          value={
            safeSingleCurrencyTotals
              ? `${totalCapital.toFixed(2)} ${partnerDisplayCurrency}`
              : "حسب العملة"
          }
        />

        <Mini
          title="المسحوبات"
          value={
            safeSingleCurrencyTotals
              ? `${totalDrawings.toFixed(2)} ${partnerDisplayCurrency}`
              : "حسب العملة"
          }
        />

        <Mini
          title="قروض الشركاء"
          value={
            safeSingleCurrencyTotals
              ? `${totalLoans.toFixed(2)} ${partnerDisplayCurrency}`
              : "حسب العملة"
          }
        />
      </section>

      <section className="panel" style={{ marginTop: 14 }}>
        <div className="filters">
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="بحث باسم الشريك..."
            />
          </div>

          <div />
          <div />

          <div className="resultCount">{filtered.length} شريك</div>
        </div>

        {!filtered.length ? (
          <div className="empty">
            <Icons.users size={30} />
            <h3>ما في شركاء</h3>
            <p>أضف أول شريك ورصيد ملكيته.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الشريك</th>
                  <th>الملكية</th>
                  <th>حصة الربح</th>
                  <th>رأس المال</th>
                  <th>المسحوبات</th>
                  <th>قرض الشريك</th>
                  <th>توزيعات الأرباح</th>
                  <th />
                </tr>
              </thead>

              <tbody>
                {filtered.map((partner) => (
                  <tr key={partner.id}>
                    <td>
                      <strong>{partner.name}</strong>
                      <div className="muted">{partner.partner_number || partner.phone || ""}</div>
                    </td>

                    <td>{num(partner.ownership_percent).toFixed(2)}%</td>

                    <td>{num(partner.profit_share_percent).toFixed(2)}%</td>

                    <td>{num(partner.capital_contributions).toFixed(2)}</td>

                    <td>{num(partner.drawings).toFixed(2)}</td>

                    <td>{num(partner.partner_loan_balance).toFixed(2)}</td>

                    <td>{num(partner.profit_distributions).toFixed(2)}</td>

                    <td>
                      <div className="rowActions">
                        {canTransact && partner.active && (
                          <button
                            type="button"
                            className="softButton"
                            onClick={() => openMovement(partner.id)}
                          >
                            حركة
                          </button>
                        )}

                        {canManage && (
                          <button
                            type="button"
                            className="softButton"
                            onClick={() => openEditPartner(partner)}
                          >
                            <Icons.edit size={13} />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="panel panelPad" style={{ marginTop: 14 }}>
        <div className="panelHeader">
          <div>
            <h2>آخر حركات الشركاء</h2>
            <p>رأس مال، سحوبات، قروض وتوزيعات</p>
          </div>
        </div>

        {!transactions.length ? (
          <p className="muted">ما في حركات مسجلة.</p>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الشريك</th>
                  <th>الحركة</th>
                  <th>المبلغ</th>
                  <th>التاريخ</th>
                  <th>ملاحظات</th>
                </tr>
              </thead>

              <tbody>
                {transactions.map((transaction) => (
                  <tr key={transaction.id}>
                    <td>{partnerName(transaction.partner_id)}</td>

                    <td>{transactionLabel(transaction.transaction_type)}</td>

                    <td>
                      <strong>
                        {num(transaction.amount).toFixed(2)} {transaction.currency}
                      </strong>
                    </td>

                    <td>{transaction.transaction_date}</td>

                    <td>{transaction.notes || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {partnerOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">الشريك</span>
                <h2>{editing ? "تعديل الشريك" : "شريك جديد"}</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setPartnerOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={savePartner}>
              <div className="formGrid">
                <Field label="اسم الشريك *" value={name} setValue={setName} />

                <Field label="رقم الشريك" value={number} setValue={setNumber} />

                <Field label="الهاتف" value={phone} setValue={setPhone} />

                <NumberField label="نسبة الملكية %" value={ownership} setValue={setOwnership} />

                <NumberField
                  label="نسبة توزيع الربح %"
                  value={profitShare}
                  setValue={setProfitShare}
                />

                <label className="field">
                  <span>الحالة</span>

                  <select
                    value={active ? "yes" : "no"}
                    onChange={(event) => setActive(event.target.value === "yes")}
                  >
                    <option value="yes">نشط</option>
                    <option value="no">موقوف</option>
                  </select>
                </label>

                <label className="field full">
                  <span>ملاحظات</span>

                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(event) => setNotes(event.target.value)}
                  />
                </label>
              </div>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setPartnerOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  حفظ الشريك
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {movementOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">حركة الشريك</span>

                <h2>حركة شريك</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setMovementOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={saveMovement}>
              <div className="formGrid">
                <label className="field">
                  <span>الشريك</span>

                  <select
                    value={movementPartner}
                    onChange={(event) => setMovementPartner(event.target.value)}
                  >
                    {activePartners.map((partner) => (
                      <option key={partner.id} value={partner.id}>
                        {partner.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>نوع الحركة</span>

                  <select
                    value={movementType}
                    onChange={(event) =>
                      setMovementType(event.target.value as PartnerTransaction["transaction_type"])
                    }
                  >
                    <option value="capital_contribution">إضافة رأس مال</option>

                    <option value="drawing">سحب شخصي</option>

                    <option value="partner_loan_in">قرض من الشريك للشركة</option>

                    <option value="partner_loan_repayment">تسديد قرض للشريك</option>

                    <option value="profit_distribution">توزيع أرباح</option>
                  </select>
                </label>

                <NumberField label="المبلغ" value={movementAmount} setValue={setMovementAmount} />

                <Field label="العملة" value={movementCurrency} setValue={changeCurrency} />

                <label className="field">
                  <span>الصندوق</span>

                  <select
                    value={movementCashbox}
                    onChange={(event) => setMovementCashbox(event.target.value)}
                  >
                    <option value="">اختار</option>

                    {cashboxes
                      .filter((cashbox) => cashbox.currency === movementCurrency)
                      .map((cashbox) => (
                        <option key={cashbox.id} value={cashbox.id}>
                          {cashbox.name} - {cashbox.currency}
                        </option>
                      ))}
                  </select>
                </label>

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={movementDate}
                    onChange={(event) => setMovementDate(event.target.value)}
                  />
                </label>

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={movementCurrency}
                  baseCurrency={baseCurrency}
                  date={movementDate}
                  value={txRate}
                  onChange={setTxRate}
                />

                <label className="field full">
                  <span>ملاحظات</span>

                  <textarea
                    rows={3}
                    value={movementNotes}
                    onChange={(event) => setMovementNotes(event.target.value)}
                  />
                </label>
              </div>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setMovementOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  تسجيل الحركة
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}

function partnerError(error: { message?: string } | null) {
  const message = (error?.message ?? "").toLowerCase();
  const map: [string, string][] = [
    ["not allowed", "ما عندك صلاحية لهالعملية."],
    ["total ownership exceeds 100", "مجموع نسب الملكية لكل الشركاء صار أكتر من 100%."],
    ["total profit share exceeds 100", "مجموع حصص الربح لكل الشركاء صار أكتر من 100%."],
    ["financial period is closed", "هالشهر مقفل بالمالية."],
    ["invalid cashbox or currency", "الصندوق لازم يكون شغّال وبنفس عملة الحركة."],
    ["cashbox is required", "اختار الصندوق."],
    ["partner name is required", "اسم الشريك مطلوب."],
    ["missing exchange rate", "ما في سعر صرف مسجّل لهالعملة بهاليوم."],
    ["duplicate", "في شريك بنفس الرقم."],
  ];
  return map.find(([key]) => message.includes(key))?.[1] ?? "تعذر تنفيذ العملية. حاول مرة تانية.";
}

function transactionLabel(type: PartnerTransaction["transaction_type"]) {
  const labels = {
    capital_contribution: "رأس مال",
    drawing: "سحب شخصي",
    partner_loan_in: "قرض من الشريك",
    partner_loan_repayment: "تسديد قرض",
    profit_distribution: "توزيع أرباح",
  };

  return labels[type];
}

function Field({
  label,
  value,
  setValue,
}: {
  label: string;
  value: string;
  setValue: (value: string) => void;
}) {
  return (
    <label className="field">
      <span>{label}</span>

      <input value={value} onChange={(event) => setValue(event.target.value)} />
    </label>
  );
}

function NumberField({
  label,
  value,
  setValue,
}: {
  label: string;
  value: string;
  setValue: (value: string) => void;
}) {
  return (
    <label className="field">
      <span>{label}</span>

      <input
        type="number"
        min="0"
        step="0.01"
        value={value}
        onChange={(event) => setValue(event.target.value)}
      />
    </label>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>
      <div className="statValue">{value}</div>
    </div>
  );
}
