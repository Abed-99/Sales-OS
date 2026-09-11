"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

type QuoteStatus =
  | "draft"
  | "sent"
  | "accepted"
  | "rejected"
  | "cancelled"
  | "converted";

type Relation<T> = T | T[] | null;

type QuoteTraderRelation = {
  name: string;
  area: string | null;
};

type QuoteProductRelation = {
  name: string;
  sku: string | null;
  unit: string;
};

export type QuoteTrader = {
  id: string;
  name: string;
  area: string | null;
  status: string;
};

export type QuoteProduct = {
  id: string;
  name: string;
  sku: string | null;
  sale_price: number | null;
  minimum_sale_price: number | null;
  unit: string;
  active: boolean;
};

export type QuoteItem = {
  id: string;
  product_id: string;
  quantity: number;
  sale_unit_price: number;
  line_total: number;
  minimum_sale_price_snapshot: number | null;
  reference_cost_snapshot: number | null;
  products: Relation<QuoteProductRelation>;
};

export type QuoteRow = {
  id: string;
  trader_id: string;
  quote_number: string;
  quote_date: string;
  valid_until: string | null;
  status: QuoteStatus;
  currency: string;
  subtotal: number;
  total: number;
  notes: string | null;
  accepted_at: string | null;
  converted_order_id: string | null;
  created_at: string;
  traders: Relation<QuoteTraderRelation>;
  sales_quote_items: QuoteItem[];
};

type DraftItem = {
  key: string;
  product_id: string;
  quantity: string;
  sale_unit_price: string;
};

function one<T>(value: Relation<T>): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value;
}

function emptyItem(): DraftItem {
  return {
    key: crypto.randomUUID(),
    product_id: "",
    quantity: "1",
    sale_unit_price: "",
  };
}

function datePlusDays(days: number) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

const labels: Record<QuoteStatus, string> = {
  draft: "مسودة",
  sent: "مرسل",
  accepted: "مقبول",
  rejected: "مرفوض",
  cancelled: "ملغي",
  converted: "تحوّل لطلبية",
};

function statusColor(status: QuoteStatus) {
  if (status === "accepted" || status === "converted") return "green";
  if (status === "rejected" || status === "cancelled") return "gray";
  if (status === "sent") return "blue";
  return "orange";
}

export function QuotesClient({
  companyId,
  currency,
  initialQuotes,
  traders,
  products,
  canCreate,
  canUpdate,
}: {
  companyId: string;
  currency: string;
  initialQuotes: QuoteRow[];
  traders: QuoteTrader[];
  products: QuoteProduct[];
  canCreate: boolean;
  canUpdate: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [quotes, setQuotes] = useState(initialQuotes);
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<QuoteRow | null>(null);
  const [trader, setTrader] = useState("");
  const [validUntil, setValidUntil] = useState(datePlusDays(7));
  const [notes, setNotes] = useState("");
  const [items, setItems] = useState<DraftItem[]>([emptyItem()]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [busyId, setBusyId] = useState("");

  const stats = useMemo(() => ({
    all: quotes.length,
    open: quotes.filter((q) => q.status === "draft" || q.status === "sent").length,
    accepted: quotes.filter((q) => q.status === "accepted").length,
    converted: quotes.filter((q) => q.status === "converted").length,
  }), [quotes]);

  const draftTotal = useMemo(
    () => items.reduce((sum, item) => {
      const q = Number(item.quantity || 0);
      const p = Number(item.sale_unit_price || 0);
      return sum + (Number.isFinite(q * p) ? q * p : 0);
    }, 0),
    [items]
  );

  function startAdd() {
    setTrader("");
    setValidUntil(datePlusDays(7));
    setNotes("");
    setItems([emptyItem()]);
    setMessage("");
    setOpen(true);
  }

  function chooseProduct(index: number, productId: string) {
    const product = products.find((p) => p.id === productId);
    setItems((current) => current.map((item, i) =>
      i === index
        ? {
            ...item,
            product_id: productId,
            sale_unit_price: product?.sale_price != null ? String(product.sale_price) : "",
          }
        : item
    ));
  }

  function updateItem(index: number, changes: Partial<DraftItem>) {
    setItems((current) => current.map((item, i) =>
      i === index ? { ...item, ...changes } : item
    ));
  }

  async function createQuote(event: React.FormEvent) {
    event.preventDefault();
    setMessage("");

    if (!trader) {
      setMessage("اختار العميل.");
      return;
    }

    if (!items.length || items.some((item) => {
      const qty = Number(item.quantity);
      const price = Number(item.sale_unit_price);
      return !item.product_id || !Number.isFinite(qty) || qty <= 0 || !Number.isFinite(price) || price < 0;
    })) {
      setMessage("راجع الأصناف والكميات والأسعار.");
      return;
    }

    setSaving(true);
    const { error } = await supabase.rpc("create_sales_quote", {
      target_company: companyId,
      target_trader: trader,
      target_valid_until: validUntil || null,
      target_notes: notes.trim() || null,
      items_payload: items.map((item) => ({
        product_id: item.product_id,
        quantity: Number(item.quantity),
        sale_unit_price: Number(item.sale_unit_price),
      })),
    });
    setSaving(false);

    if (error) {
      setMessage(error.message);
      return;
    }

    setOpen(false);
    router.refresh();
    window.setTimeout(() => window.location.reload(), 100);
  }

  async function setStatus(row: QuoteRow, status: Exclude<QuoteStatus, "draft" | "converted">) {
    setBusyId(row.id);
    const { error } = await supabase.rpc("set_sales_quote_status", {
      target_company: companyId,
      target_quote: row.id,
      target_status: status,
    });
    setBusyId("");

    if (error) {
      window.alert(error.message);
      return;
    }

    setQuotes((current) => current.map((q) =>
      q.id === row.id ? { ...q, status } : q
    ));
    setSelected((current) => current?.id === row.id ? { ...current, status } : current);
    router.refresh();
  }

  async function convert(row: QuoteRow) {
    setBusyId(row.id);
    const { data, error } = await supabase.rpc("convert_sales_quote_to_order", {
      target_company: companyId,
      target_quote: row.id,
    });
    setBusyId("");

    if (error) {
      window.alert(error.message);
      return;
    }

    const result = data as { status?: string; order_id?: string | null } | null;

    if (result?.status === "pending_approval") {
      window.alert("السعر تحت التكلفة أو الحد الأدنى. تم إرسال طلب موافقة تلقائياً.");
      router.refresh();
      return;
    }

    if (result?.order_id) {
      router.push(`/orders?order=${result.order_id}`);
      router.refresh();
      return;
    }

    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">عروض الأسعار</span>
          <h2>عروض الأسعار</h2>
          <p className="muted">من العرض للطلبية بدون إعادة إدخال الأصناف.</p>
        </div>
        {canCreate && (
          <button className="primaryButton" onClick={startAdd}>
            <Icons.plus size={15} /> عرض سعر جديد
          </button>
        )}
      </div>

      <section className="statsGrid">
        <Mini title="كل العروض" value={String(stats.all)} />
        <Mini title="مفتوحة" value={String(stats.open)} />
        <Mini title="مقبولة" value={String(stats.accepted)} />
        <Mini title="تحولت لطلب" value={String(stats.converted)} />
      </section>

      <section className="panel" style={{ marginTop: 14 }}>
        {!quotes.length ? (
          <div className="empty">
            <Icons.money size={28} />
            <h3>ما في عروض أسعار بعد</h3>
            <p>أنشئ أول عرض سعر للعميل.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>الرقم</th>
                  <th>العميل</th>
                  <th>التاريخ</th>
                  <th>الصلاحية</th>
                  <th>الإجمالي</th>
                  <th>الحالة</th>
                  <th>إجراءات</th>
                </tr>
              </thead>
              <tbody>
                {quotes.map((row) => {
                  const traderRow = one(row.traders);
                  const expired = !!row.valid_until && row.valid_until < new Date().toISOString().slice(0, 10) && !["converted", "rejected", "cancelled"].includes(row.status);
                  return (
                    <tr key={row.id}>
                      <td><strong>{row.quote_number}</strong></td>
                      <td>{traderRow?.name ?? "—"}<span className="muted" style={{ display: "block" }}>{traderRow?.area ?? ""}</span></td>
                      <td>{row.quote_date}</td>
                      <td>{row.valid_until ?? "بدون"}{expired ? <span className="chip orange" style={{ marginInlineStart: 6 }}>منتهي</span> : null}</td>
                      <td><strong>{Number(row.total).toFixed(2)} {row.currency}</strong></td>
                      <td><span className={`chip ${statusColor(row.status)}`}>{labels[row.status]}</span></td>
                      <td>
                        <div className="rowActions">
                          <button type="button" className="softButton" onClick={() => setSelected(row)}>تفاصيل</button>
                          {canUpdate && row.status === "draft" && (
                            <button type="button" className="softButton" disabled={busyId === row.id} onClick={() => void setStatus(row, "sent")}>إرسال</button>
                          )}
                          {canUpdate && row.status === "sent" && !expired && (
                            <button type="button" className="softButton" disabled={busyId === row.id} onClick={() => void setStatus(row, "accepted")}>قبول</button>
                          )}
                          {canCreate && row.status === "accepted" && !expired && (
                            <button type="button" className="primaryButton" disabled={busyId === row.id} onClick={() => void convert(row)}>تحويل لطلب</button>
                          )}
                          {row.converted_order_id && (
                            <Link className="softButton" href={`/orders?order=${row.converted_order_id}`}>الطلبية</Link>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {open && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div><span className="eyebrow">عرض جديد</span><h2>إنشاء عرض سعر</h2></div>
              <button type="button" className="closeButton" onClick={() => setOpen(false)}>×</button>
            </div>
            <form onSubmit={createQuote}>
              <div className="formGrid">
                <label className="field">
                  <span>العميل</span>
                  <select value={trader} onChange={(e) => setTrader(e.target.value)}>
                    <option value="">اختر العميل</option>
                    {traders.map((t) => <option key={t.id} value={t.id}>{t.name}{t.area ? ` - ${t.area}` : ""}</option>)}
                  </select>
                </label>
                <label className="field">
                  <span>صالح لغاية</span>
                  <input type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} />
                </label>
              </div>

              <div className="panel panelPad" style={{ marginTop: 14 }}>
                <div className="panelHeader">
                  <div><h2>الأصناف</h2><p>سعر البيع قابل للتعديل ضمن العرض.</p></div>
                  <button type="button" className="softButton" onClick={() => setItems((x) => [...x, emptyItem()])}>
                    <Icons.plus size={13} /> صنف
                  </button>
                </div>
                <div className="tableWrap">
                  <table>
                    <thead><tr><th>الصنف</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th><th /></tr></thead>
                    <tbody>
                      {items.map((item, index) => {
                        const total = Number(item.quantity || 0) * Number(item.sale_unit_price || 0);
                        return (
                          <tr key={item.key}>
                            <td>
                              <select value={item.product_id} onChange={(e) => chooseProduct(index, e.target.value)}>
                                <option value="">اختر</option>
                                {products.map((p) => <option key={p.id} value={p.id}>{p.name}{p.sku ? ` - ${p.sku}` : ""}</option>)}
                              </select>
                            </td>
                            <td><input style={{ width: 95 }} type="number" min="0.001" step="0.001" value={item.quantity} onChange={(e) => updateItem(index, { quantity: e.target.value })} /></td>
                            <td><input style={{ width: 120 }} type="number" min="0" step="0.01" value={item.sale_unit_price} onChange={(e) => updateItem(index, { sale_unit_price: e.target.value })} /></td>
                            <td>{Number.isFinite(total) ? total.toFixed(2) : "0.00"} {currency}</td>
                            <td><button type="button" className="dangerButton" disabled={items.length === 1} onClick={() => setItems((x) => x.filter((_, i) => i !== index))}>×</button></td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>

              <label className="field" style={{ marginTop: 14 }}>
                <span>ملاحظات</span>
                <textarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} />
              </label>

              <div className="panel panelPad" style={{ marginTop: 14 }}>
                <div className="panelHeader">
                  <div><h2>إجمالي العرض</h2><p>قبل تحويله لطلبية.</p></div>
                  <div className="statValue">{draftTotal.toFixed(2)} {currency}</div>
                </div>
              </div>

              {message && <div className="toastError" style={{ marginTop: 12 }}>{message}</div>}
              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setOpen(false)}>إلغاء</button>
                <button className="primaryButton" disabled={saving}>{saving ? "عم نحفظ..." : "حفظ العرض"}</button>
              </div>
            </form>
          </section>
        </div>
      )}

      {selected && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div><span className="eyebrow">{selected.quote_number}</span><h2>{one(selected.traders)?.name ?? "عرض سعر"}</h2></div>
              <button type="button" className="closeButton" onClick={() => setSelected(null)}>×</button>
            </div>
            <div className="quickList">
              {selected.sales_quote_items.map((item) => {
                const p = one(item.products);
                const guard = Math.max(Number(item.minimum_sale_price_snapshot || 0), Number(item.reference_cost_snapshot || 0));
                const below = Number(item.sale_unit_price) < guard;
                return (
                  <div className="quickItem" key={item.id}>
                    <div className="quickIcon"><Icons.box size={15} /></div>
                    <div>
                      <strong>{p?.name ?? "صنف"}</strong>
                      <span>{Number(item.quantity)} × {Number(item.sale_unit_price).toFixed(2)} {selected.currency}{below ? " • يحتاج موافقة عند التحويل" : ""}</span>
                    </div>
                    <div className="count">{Number(item.line_total).toFixed(2)}</div>
                  </div>
                );
              })}
            </div>
            {selected.notes && <p className="muted" style={{ marginTop: 14 }}>{selected.notes}</p>}
            <div className="modalActions">
              {canUpdate && selected.status === "sent" && (
                <button type="button" className="dangerButton" onClick={() => void setStatus(selected, "rejected")}>رفض</button>
              )}
              {canUpdate && (selected.status === "draft" || selected.status === "sent" || selected.status === "accepted") && (
                <button type="button" className="softButton" onClick={() => void setStatus(selected, "cancelled")}>إلغاء العرض</button>
              )}
              <button type="button" className="softButton" onClick={() => setSelected(null)}>إغلاق</button>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return <div className="statCard"><div className="statLabel">{title}</div><div className="statValue">{value}</div></div>;
}
