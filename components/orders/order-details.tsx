"use client";

import { useCallback, useEffect, useState } from "react";
import type { FormEvent } from "react";

import { createClient } from "@/lib/supabase/client";

type Item = {
  id: string;
  quantity: number;
  sale_unit_price: number;
  line_total: number;
  products:
    | { name: string; sku: string | null; unit?: string | null }
    | { name: string; sku: string | null }[]
    | null;
};

export type OrderDetailsOrder = {
  id: string;
  order_number: string | null;
  status: string;
  total: number;
  notes: string | null;
  created_at: string;
  cancellation_reason: string | null;
  traders: { name: string; area: string | null } | { name: string; area: string | null }[] | null;
  sales_order_items: Item[];
};

type Invoice = {
  id: string;
  invoice_number: string;
  invoice_date: string;
  currency: string;
  total: number;
  paid_total: number;
  balance_due: number;
  status: string;
  cancellation_reason: string | null;
};

type Payment = {
  allocationId: string;
  invoiceNumber: string;
  amount: number;
  invoiceCurrency: string;
  payment: {
    id: string;
    payment_number: string;
    payment_date: string;
    amount: number;
    status: string;
    payment_currency: string | null;
    reversal_reason: string | null;
  };
};

type Action =
  | { kind: "cancel-invoice"; id: string; label: string }
  | { kind: "reverse-payment"; id: string; label: string };

function one<T>(value: T | T[] | null) {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function money(value: number, currency: string) {
  return `${new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value || 0))} ${currency}`;
}

function qty(value: number) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 3 }).format(Number(value || 0));
}

function friendly(message: string) {
  const m = message.toLowerCase();
  if (m.includes("not allowed") || m.includes("permission")) return "ما عندك صلاحية لهالعملية.";
  if (m.includes("reverse allocated customer payments"))
    return "لازم تعكس القبض اللي على الفاتورة أول، بعدين بتقدر تلغيها.";
  if (m.includes("posted return")) return "الفاتورة عليها مرتجع. اعكس المرتجع أول.";
  if (m.includes("period") && m.includes("closed")) return "الشهر مقفل. افتحه من صفحة المالية أول.";
  return "ما قدرنا ننفّذ العملية. حاول مرة تانية.";
}

export function OrderDetails({
  order,
  companyId,
  currency,
  canCancelInvoice,
  canReversePayment,
  onClose,
  onChanged,
}: {
  order: OrderDetailsOrder;
  companyId: string;
  currency: string;
  canCancelInvoice: boolean;
  canReversePayment: boolean;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [supabase] = useState(() => createClient());
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [action, setAction] = useState<Action | null>(null);
  const [reason, setReason] = useState("");
  const [actionError, setActionError] = useState("");
  const [working, setWorking] = useState(false);

  const trader = one(order.traders);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");

    const invoiceResult = await supabase
      .from("sales_invoices")
      .select(
        "id,invoice_number,invoice_date,currency,total,paid_total,balance_due,status,cancellation_reason",
      )
      .eq("company_id", companyId)
      .eq("order_id", order.id)
      .order("invoice_date");

    // ما عنده صلاحية يشوف الفواتير: منعرض الأصناف بس.
    const loadedInvoices = invoiceResult.error ? [] : ((invoiceResult.data ?? []) as Invoice[]);
    setInvoices(loadedInvoices);

    if (loadedInvoices.length) {
      const allocationResult = await supabase
        .from("customer_payment_allocations")
        .select(
          "id,amount,sales_invoice_id,customer_payments(id,payment_number,payment_date,amount,status,payment_currency,reversal_reason)",
        )
        .eq("company_id", companyId)
        .in(
          "sales_invoice_id",
          loadedInvoices.map((invoice) => invoice.id),
        );

      if (!allocationResult.error) {
        const byId = new Map(loadedInvoices.map((invoice) => [invoice.id, invoice]));
        setPayments(
          (allocationResult.data ?? []).flatMap((row) => {
            const payment = one(
              row.customer_payments as Payment["payment"] | Payment["payment"][] | null,
            );
            const invoice = byId.get(row.sales_invoice_id as string);
            return payment && invoice
              ? [
                  {
                    allocationId: row.id as string,
                    invoiceNumber: invoice.invoice_number,
                    amount: Number(row.amount),
                    invoiceCurrency: invoice.currency,
                    payment,
                  },
                ]
              : [];
          }),
        );
      }
    } else {
      setPayments([]);
    }

    setLoading(false);
  }, [companyId, order.id, supabase]);

  useEffect(() => {
    void load();
  }, [load]);

  async function confirmAction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!action) return;
    if (!reason.trim()) {
      setActionError("اكتب السبب.");
      return;
    }

    setWorking(true);
    setActionError("");

    const result =
      action.kind === "cancel-invoice"
        ? await supabase.rpc("cancel_sales_invoice", {
            target_company: companyId,
            target_invoice: action.id,
            target_reason: reason.trim(),
          })
        : await supabase.rpc("reverse_customer_payment", {
            target_company: companyId,
            target_payment: action.id,
            target_reason: reason.trim(),
          });

    setWorking(false);

    if (result.error) {
      setActionError(friendly(result.error.message));
      return;
    }

    setAction(null);
    setReason("");
    await load();
    onChanged();
  }

  return (
    <div
      className="modalOverlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !working) onClose();
      }}
    >
      <section
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="order-details-title"
        style={{ width: "94vw", maxWidth: 900 }}
      >
        <div className="modalHeader">
          <div>
            <span className="eyebrow">
              {trader?.name || "زبون"}
              {trader?.area ? ` • ${trader.area}` : ""}
            </span>
            <h2 id="order-details-title">{order.order_number ?? `#${order.id.slice(0, 8)}`}</h2>
          </div>
          <button type="button" className="closeButton" aria-label="إغلاق" onClick={onClose}>
            ×
          </button>
        </div>

        {order.cancellation_reason ? (
          <div className="toastError">ملغاة: {order.cancellation_reason}</div>
        ) : null}
        {order.notes ? <p className="muted">{order.notes}</p> : null}

        <h3>الأصناف</h3>
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>الصنف</th>
                <th>الكمية</th>
                <th>السعر</th>
                <th>الإجمالي</th>
              </tr>
            </thead>
            <tbody>
              {order.sales_order_items.map((item) => {
                const product = one(item.products);
                return (
                  <tr key={item.id}>
                    <td>
                      <strong>{product?.name || "صنف"}</strong>
                      {product?.sku ? <div className="muted">{product.sku}</div> : null}
                    </td>
                    <td>{qty(item.quantity)}</td>
                    <td>{money(item.sale_unit_price, currency)}</td>
                    <td>
                      <strong>{money(item.line_total, currency)}</strong>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p style={{ textAlign: "end" }}>
          <strong>الإجمالي: {money(order.total, currency)}</strong>
        </p>

        {loading ? <p className="muted">عم نحمّل الفواتير والقبض...</p> : null}
        {error ? <div className="toastError">{error}</div> : null}

        {!loading && invoices.length ? (
          <>
            <h3>الفواتير</h3>
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الفاتورة</th>
                    <th>التاريخ</th>
                    <th>الإجمالي</th>
                    <th>المدفوع</th>
                    <th>الباقي</th>
                    <th>الحالة</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {invoices.map((invoice) => (
                    <tr key={invoice.id}>
                      <td>
                        <strong>{invoice.invoice_number}</strong>
                      </td>
                      <td>{invoice.invoice_date}</td>
                      <td>{money(invoice.total, invoice.currency)}</td>
                      <td>{money(invoice.paid_total, invoice.currency)}</td>
                      <td>{money(invoice.balance_due, invoice.currency)}</td>
                      <td>
                        {invoice.status === "cancelled" ? (
                          <>
                            <span className="chip gray">ملغاة</span>
                            {invoice.cancellation_reason ? (
                              <div className="muted">{invoice.cancellation_reason}</div>
                            ) : null}
                          </>
                        ) : (
                          <span
                            className={`chip ${Number(invoice.balance_due) <= 0 ? "green" : "orange"}`}
                          >
                            {Number(invoice.balance_due) <= 0 ? "مسددة" : "عليها باقي"}
                          </span>
                        )}
                      </td>
                      <td>
                        {canCancelInvoice && invoice.status === "posted" ? (
                          <button
                            type="button"
                            className="dangerButton"
                            onClick={() => {
                              setAction({
                                kind: "cancel-invoice",
                                id: invoice.id,
                                label: invoice.invoice_number,
                              });
                              setReason("");
                              setActionError("");
                            }}
                          >
                            إلغاء الفاتورة
                          </button>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        ) : null}

        {!loading && payments.length ? (
          <>
            <h3>القبض</h3>
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>القبض</th>
                    <th>التاريخ</th>
                    <th>على الفاتورة</th>
                    <th>المبلغ</th>
                    <th>الحالة</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {payments.map((row) => (
                    <tr key={row.allocationId}>
                      <td>
                        <strong>{row.payment.payment_number}</strong>
                        {row.payment.payment_currency &&
                        row.payment.payment_currency !== row.invoiceCurrency ? (
                          <div className="muted">
                            انقبض {money(row.payment.amount, row.payment.payment_currency)}
                          </div>
                        ) : null}
                      </td>
                      <td>{row.payment.payment_date}</td>
                      <td>{row.invoiceNumber}</td>
                      <td>{money(row.amount, row.invoiceCurrency)}</td>
                      <td>
                        {row.payment.status === "posted" ? (
                          <span className="chip green">مثبت</span>
                        ) : (
                          <>
                            <span className="chip gray">معكوس</span>
                            {row.payment.reversal_reason ? (
                              <div className="muted">{row.payment.reversal_reason}</div>
                            ) : null}
                          </>
                        )}
                      </td>
                      <td>
                        {canReversePayment && row.payment.status === "posted" ? (
                          <button
                            type="button"
                            className="dangerButton"
                            onClick={() => {
                              setAction({
                                kind: "reverse-payment",
                                id: row.payment.id,
                                label: row.payment.payment_number,
                              });
                              setReason("");
                              setActionError("");
                            }}
                          >
                            عكس القبض
                          </button>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        ) : null}

        {action ? (
          <form className="panel panelPad" style={{ marginTop: 14 }} onSubmit={confirmAction}>
            <strong>
              {action.kind === "cancel-invoice"
                ? `إلغاء الفاتورة ${action.label}`
                : `عكس القبض ${action.label}`}
            </strong>
            <p className="muted">
              {action.kind === "cancel-invoice"
                ? "البيعة بتنلغى: الدين بينشال عن الزبون، والبضاعة بترجع للمستودع بنفس كلفتها."
                : "المصاري بترجع تطلع من الصندوق، والمبلغ بيرجع دين على الزبون."}
            </p>
            <label className="field">
              <span>السبب *</span>
              <textarea
                value={reason}
                onChange={(event) => setReason(event.target.value)}
                rows={2}
              />
            </label>
            {actionError ? <div className="toastError">{actionError}</div> : null}
            <div className="modalActions">
              <button
                type="button"
                className="softButton"
                disabled={working}
                onClick={() => setAction(null)}
              >
                رجوع
              </button>
              <button className="dangerButton" disabled={working}>
                {working ? "عم ننفّذ..." : "تأكيد"}
              </button>
            </div>
          </form>
        ) : null}

        <div className="modalActions">
          <button type="button" className="softButton" onClick={onClose}>
            إغلاق
          </button>
        </div>
      </section>
    </div>
  );
}
