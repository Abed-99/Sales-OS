"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import { createClient } from "@/lib/supabase/client";

type Relation<T> = T | T[] | null;
const one = <T,>(value: Relation<T>) => (Array.isArray(value) ? (value[0] ?? null) : value);

type Status = "ordered" | "shipped" | "at_port" | "customs" | "arrived" | "closed" | "cancelled";

export type ShipmentRow = {
  id: string;
  shipment_number: string;
  container_number: string | null;
  origin_country: string | null;
  shipped_on: string | null;
  expected_on: string | null;
  arrived_on: string | null;
  status: Status;
  notes: string | null;
  closed_at: string | null;
  import_shipment_costs: {
    id: string;
    cost_type: string;
    amount: number;
    currency: string;
    base_amount: number;
    cost_date: string;
    notes: string | null;
  }[];
  purchase_invoices: {
    id: string;
    invoice_number: string;
    supplier_invoice_number: string | null;
    total: number;
    currency: string;
    suppliers: Relation<{ name: string }>;
  }[];
};

type Preview = {
  product_id: string;
  product_name: string;
  quantity: number;
  received: number;
  goods_value: number;
  allocated_cost: number;
  unit_goods_cost: number;
  unit_landed_cost: number;
};

const statusLabels: Record<Status, string> = {
  ordered: "انطلب",
  shipped: "انشحن",
  at_port: "بالمرفأ",
  customs: "بالجمارك",
  arrived: "وصل",
  closed: "مسكّر (توزّعت المصاريف)",
  cancelled: "ملغى",
};

const costLabels: Record<string, string> = {
  freight: "شحن بحري",
  customs: "جمارك",
  clearance: "تخليص",
  transport: "نقل",
  insurance: "تأمين",
  other: "مصاريف أخرى",
};

const money = (value: number, currency: string) =>
  `${Number(value).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;

const today = () => new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });

function friendly(message: string) {
  const text = message.toLowerCase();
  if (text.includes("receive all")) return "لازم تستلم كل بضاعة الكونتينر قبل توزيع المصاريف.";
  if (text.includes("no purchase invoices")) return "اربط فاتورة شراء وحدة على الأقل بالكونتينر.";
  if (text.includes("closed")) return "الكونتينر مسكّر.";
  if (text.includes("pay from cashbox")) return "ما عندك صلاحية الدفع من الصندوق.";
  if (text.includes("financial period")) return "الشهر مقفل بالمالية.";
  if (text.includes("missing exchange rate")) return "ما في سعر صرف لعملة الصندوق.";
  if (text.includes("not allowed")) return "ما عندك صلاحية.";
  return "ما قدرنا نكمّل العملية.";
}

export function ImportsClient({
  companyId,
  currency,
  shipments,
  freeInvoices,
  cashboxes,
  canManage,
}: {
  companyId: string;
  currency: string;
  shipments: ShipmentRow[];
  freeInvoices: ShipmentRow["purchase_invoices"];
  cashboxes: { id: string; name: string; currency: string }[];
  canManage: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [form, setForm] = useState<{
    id: string | null;
    container: string;
    origin: string;
    shipped: string;
    expected: string;
    arrived: string;
    status: Status;
    notes: string;
  } | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [cost, setCost] = useState({
    type: "freight",
    amount: "",
    cashbox: cashboxes[0]?.id ?? "",
    date: today(),
    notes: "",
  });
  const [txRate, setTxRate] = useState("");
  const [preview, setPreview] = useState<Preview[] | null>(null);

  const open = shipments.find((row) => row.id === openId) ?? null;

  async function run<T>(action: () => PromiseLike<{ data: T; error: { message: string } | null }>) {
    setBusy(true);
    setMessage("");
    const { data, error } = await action();
    setBusy(false);
    if (error) {
      setMessage(friendly(error.message));
      return null;
    }
    router.refresh();
    return data;
  }

  async function saveShipment(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form) return;
    const id = await run(() =>
      supabase.rpc("save_import_shipment", {
        target_company: companyId,
        target_shipment: form.id,
        target_container: form.container,
        target_origin: form.origin,
        target_shipped_on: form.shipped || null,
        target_expected_on: form.expected || null,
        target_arrived_on: form.arrived || null,
        target_status: form.status,
        target_notes: form.notes,
      }),
    );
    if (id) {
      setForm(null);
      setOpenId(id as string);
    }
  }

  async function addCost(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!open) return;
    const box = cashboxes.find((row) => row.id === cost.cashbox);
    if (!box || !(Number(cost.amount) > 0)) return setMessage("اكتب المبلغ واختار الصندوق.");
    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      box.currency,
      currency,
      cost.date,
      txRate,
    );
    if (rateError) return setMessage(rateError);
    const ok = await run(() =>
      supabase.rpc("add_shipment_cost", {
        target_company: companyId,
        target_shipment: open.id,
        target_type: cost.type,
        target_amount: Number(cost.amount),
        target_cashbox: cost.cashbox,
        target_date: cost.date,
        target_notes: cost.notes,
      }),
    );
    if (ok) {
      setCost((current) => ({ ...current, amount: "", notes: "" }));
      setPreview(null);
    }
  }

  async function loadPreview() {
    if (!open) return;
    const data = await run(() =>
      supabase.rpc("preview_shipment_allocation", {
        target_company: companyId,
        target_shipment: open.id,
      }),
    );
    if (data) setPreview(data as Preview[]);
  }

  const costTotal = (row: ShipmentRow) =>
    row.import_shipment_costs.reduce((sum, item) => sum + Number(item.base_amount), 0);
  const goodsTotal = (row: ShipmentRow) =>
    row.purchase_invoices.reduce((sum, item) => sum + Number(item.total), 0);

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المشتريات</span>
          <h2>الاستيراد والكونتينرات</h2>
          <p className="muted">
            اربط فواتير الشراء بالكونتينر، سجّل مصاريفو، وبالآخر وزّعها عالأصناف.
          </p>
        </div>
        {canManage ? (
          <button
            type="button"
            className="primaryButton"
            onClick={() =>
              setForm({
                id: null,
                container: "",
                origin: "الصين",
                shipped: "",
                expected: "",
                arrived: "",
                status: "ordered",
                notes: "",
              })
            }
          >
            <Icons.plus size={14} /> كونتينر جديد
          </button>
        ) : null}
      </div>

      {message && !open && !form ? <div className="toastError">{message}</div> : null}

      <section className="panel">
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>الشحنة</th>
                <th>الحالة</th>
                <th>البضاعة</th>
                <th>المصاريف</th>
                <th>نسبة المصاريف</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {shipments.map((row) => {
                const goods = goodsTotal(row);
                const costs = costTotal(row);
                return (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.shipment_number}</strong>
                      <div className="muted">
                        {[
                          row.container_number,
                          row.origin_country,
                          row.expected_on && `متوقع ${row.expected_on}`,
                        ]
                          .filter(Boolean)
                          .join(" • ")}
                      </div>
                    </td>
                    <td>
                      <span
                        className={`chip ${row.status === "closed" ? "green" : row.status === "cancelled" ? "gray" : "orange"}`}
                      >
                        {statusLabels[row.status]}
                      </span>
                    </td>
                    <td>
                      {money(goods, currency)}
                      <div className="muted">{row.purchase_invoices.length} فاتورة</div>
                    </td>
                    <td>{money(costs, currency)}</td>
                    <td>{goods > 0 ? `${((costs / goods) * 100).toFixed(1)}%` : "—"}</td>
                    <td>
                      <button
                        type="button"
                        className="softButton"
                        onClick={() => {
                          setMessage("");
                          setPreview(null);
                          setOpenId(row.id);
                        }}
                      >
                        فتح
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {!shipments.length ? <p className="muted panelPad">ما في كونتينرات لسا.</p> : null}
        </div>
      </section>

      {form ? (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <h2>{form.id ? "تعديل الكونتينر" : "كونتينر جديد"}</h2>
              <button type="button" className="closeButton" onClick={() => setForm(null)}>
                ×
              </button>
            </div>
            <form onSubmit={saveShipment}>
              <div className="formGrid">
                <label className="field">
                  <span>رقم الكونتينر</span>
                  <input
                    dir="ltr"
                    value={form.container}
                    onChange={(e) => setForm({ ...form, container: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>بلد المنشأ</span>
                  <input
                    value={form.origin}
                    onChange={(e) => setForm({ ...form, origin: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>تاريخ الشحن</span>
                  <input
                    type="date"
                    value={form.shipped}
                    onChange={(e) => setForm({ ...form, shipped: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>الوصول المتوقع</span>
                  <input
                    type="date"
                    value={form.expected}
                    onChange={(e) => setForm({ ...form, expected: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>تاريخ الوصول</span>
                  <input
                    type="date"
                    value={form.arrived}
                    onChange={(e) => setForm({ ...form, arrived: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>الحالة</span>
                  <select
                    value={form.status}
                    onChange={(e) => setForm({ ...form, status: e.target.value as Status })}
                  >
                    {(
                      [
                        "ordered",
                        "shipped",
                        "at_port",
                        "customs",
                        "arrived",
                        "cancelled",
                      ] as Status[]
                    ).map((status) => (
                      <option key={status} value={status}>
                        {statusLabels[status]}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={2}
                    value={form.notes}
                    onChange={(e) => setForm({ ...form, notes: e.target.value })}
                  />
                </label>
              </div>
              {message ? <div className="toastError">{message}</div> : null}
              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setForm(null)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={busy}>
                  حفظ
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {open ? (
        <div className="modalOverlay">
          <section className="modal" style={{ maxWidth: 960 }}>
            <div className="modalHeader">
              <div>
                <span className="eyebrow">{statusLabels[open.status]}</span>
                <h2>
                  {open.shipment_number} {open.container_number ? `• ${open.container_number}` : ""}
                </h2>
              </div>
              <div className="rowActions">
                {canManage && open.status !== "closed" ? (
                  <button
                    type="button"
                    className="softButton"
                    onClick={() => {
                      setForm({
                        id: open.id,
                        container: open.container_number ?? "",
                        origin: open.origin_country ?? "",
                        shipped: open.shipped_on ?? "",
                        expected: open.expected_on ?? "",
                        arrived: open.arrived_on ?? "",
                        status: open.status,
                        notes: open.notes ?? "",
                      });
                      setOpenId(null);
                    }}
                  >
                    تعديل
                  </button>
                ) : null}
                <button type="button" className="closeButton" onClick={() => setOpenId(null)}>
                  ×
                </button>
              </div>
            </div>

            <h3>فواتير الشراء</h3>
            <div className="quickList">
              {open.purchase_invoices.map((invoice) => (
                <div className="quickItem" key={invoice.id}>
                  <div className="quickIcon">{"🧾"}</div>
                  <div>
                    <strong>
                      {invoice.invoice_number}{" "}
                      {invoice.supplier_invoice_number
                        ? `(${invoice.supplier_invoice_number})`
                        : ""}
                    </strong>
                    <span>{one(invoice.suppliers)?.name}</span>
                  </div>
                  <div className="count">{money(invoice.total, invoice.currency)}</div>
                  {canManage && open.status !== "closed" ? (
                    <button
                      type="button"
                      className="dangerButton"
                      onClick={() =>
                        void run(() =>
                          supabase.rpc("link_invoice_to_shipment", {
                            target_company: companyId,
                            target_invoice: invoice.id,
                            target_shipment: null,
                          }),
                        )
                      }
                    >
                      فك
                    </button>
                  ) : null}
                </div>
              ))}
            </div>
            {canManage && open.status !== "closed" && freeInvoices.length ? (
              <select
                style={{ marginTop: 8 }}
                value=""
                onChange={(event) =>
                  event.target.value &&
                  void run(() =>
                    supabase.rpc("link_invoice_to_shipment", {
                      target_company: companyId,
                      target_invoice: event.target.value,
                      target_shipment: open.id,
                    }),
                  )
                }
              >
                <option value="">+ ربط فاتورة شراء بهالكونتينر...</option>
                {freeInvoices.map((invoice) => (
                  <option key={invoice.id} value={invoice.id}>
                    {invoice.invoice_number} • {one(invoice.suppliers)?.name} •{" "}
                    {money(invoice.total, invoice.currency)}
                  </option>
                ))}
              </select>
            ) : null}

            <h3 style={{ marginTop: 18 }}>المصاريف</h3>
            <div className="quickList">
              {open.import_shipment_costs.map((item) => (
                <div className="quickItem" key={item.id}>
                  <div className="quickIcon">{"💵"}</div>
                  <div>
                    <strong>{costLabels[item.cost_type] ?? item.cost_type}</strong>
                    <span>
                      {item.cost_date}
                      {item.notes ? ` • ${item.notes}` : ""}
                    </span>
                  </div>
                  <div className="count">
                    {money(item.amount, item.currency)}
                    {item.currency !== currency ? ` = ${money(item.base_amount, currency)}` : ""}
                  </div>
                </div>
              ))}
            </div>

            {canManage && open.status !== "closed" ? (
              <form className="formGrid" style={{ marginTop: 10 }} onSubmit={addCost}>
                <label className="field">
                  <span>نوع المصروف</span>
                  <select
                    value={cost.type}
                    onChange={(e) => setCost({ ...cost, type: e.target.value })}
                  >
                    {Object.entries(costLabels).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>المبلغ</span>
                  <input
                    type="number"
                    min="0"
                    step="any"
                    value={cost.amount}
                    onChange={(e) => setCost({ ...cost, amount: e.target.value })}
                  />
                </label>
                <label className="field">
                  <span>من صندوق</span>
                  <select
                    value={cost.cashbox}
                    onChange={(e) => setCost({ ...cost, cashbox: e.target.value })}
                  >
                    {cashboxes.map((box) => (
                      <option key={box.id} value={box.id}>
                        {box.name} - {box.currency}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>التاريخ</span>
                  <input
                    type="date"
                    value={cost.date}
                    onChange={(e) => setCost({ ...cost, date: e.target.value })}
                  />
                </label>
                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={cashboxes.find((box) => box.id === cost.cashbox)?.currency ?? ""}
                  baseCurrency={currency}
                  date={cost.date}
                  value={txRate}
                  onChange={setTxRate}
                />
                <label className="field">
                  <span>ملاحظة</span>
                  <input
                    value={cost.notes}
                    onChange={(e) => setCost({ ...cost, notes: e.target.value })}
                  />
                </label>
                <div className="field">
                  <span>&nbsp;</span>
                  <button className="softButton" disabled={busy}>
                    + تسجيل المصروف
                  </button>
                </div>
              </form>
            ) : null}

            <div className="rowActions" style={{ marginTop: 18 }}>
              <button type="button" className="softButton" onClick={() => void loadPreview()}>
                الكلفة الواصلة لكل صنف
              </button>
              {canManage && open.status !== "closed" ? (
                <button
                  type="button"
                  className="primaryButton"
                  disabled={busy}
                  onClick={async () => {
                    if (
                      !window.confirm(
                        "توزيع المصاريف عالأصناف وإقفال الكونتينر؟ بعدها ما بتقدر تضيف مصاريف.",
                      )
                    )
                      return;
                    const result = await run(() =>
                      supabase.rpc("close_import_shipment", {
                        target_company: companyId,
                        target_shipment: open.id,
                      }),
                    );
                    if (result) await loadPreview();
                  }}
                >
                  توزيع المصاريف وإقفال
                </button>
              ) : null}
            </div>

            {preview ? (
              <div className="tableWrap" style={{ marginTop: 12 }}>
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الصنف</th>
                      <th>الكمية</th>
                      <th>مستلم</th>
                      <th>قيمة البضاعة</th>
                      <th>حصتو من المصاريف</th>
                      <th>كلفة القطعة بالفاتورة</th>
                      <th>الكلفة الواصلة للقطعة</th>
                    </tr>
                  </thead>
                  <tbody>
                    {preview.map((row) => (
                      <tr key={row.product_id}>
                        <td>{row.product_name}</td>
                        <td>{Number(row.quantity)}</td>
                        <td>{Number(row.received)}</td>
                        <td>{money(row.goods_value, currency)}</td>
                        <td>{money(row.allocated_cost, currency)}</td>
                        <td>{money(row.unit_goods_cost, currency)}</td>
                        <td>
                          <strong>{money(row.unit_landed_cost, currency)}</strong>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : null}

            {message ? (
              <div className="toastError" style={{ marginTop: 10 }}>
                {message}
              </div>
            ) : null}
          </section>
        </div>
      ) : null}
    </div>
  );
}
