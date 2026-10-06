"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { SearchPicker } from "@/components/search-picker";
import { useQuickCreate } from "@/components/quick-create";
import { UnitToggle } from "@/components/unit-toggle";
import { searchProducts, searchSuppliers, type ProductPick } from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";
import { convertPrice, toBasePrice, toBaseQuantity, type UnitMode } from "@/lib/units";
import { NumberInput } from "@/components/number-input";
import { formatMoney as money, formatQty, formatDate } from "@/lib/format";
import { matchesSearch } from "@/lib/search";

type Relation<T> = T | T[] | null;
const one = <T,>(value: Relation<T>) => (Array.isArray(value) ? (value[0] ?? null) : value);

export type PurchaseOrderRow = {
  id: string;
  po_number: string;
  order_date: string;
  expected_date: string | null;
  status: "draft" | "sent" | "confirmed" | "converted" | "cancelled";
  currency: string;
  total: number;
  notes: string | null;
  converted_invoice_id: string | null;
  suppliers: Relation<{ name: string }>;
  purchase_order_items: {
    id: string;
    quantity: number;
    unit_cost: number;
    line_total: number;
    products: Relation<{ name: string; unit: string | null }>;
  }[];
};

type Line = {
  key: string;
  product: ProductPick | null;
  quantity: string;
  cost: string;
  mode: UnitMode;
};

const statusLabels: Record<PurchaseOrderRow["status"], string> = {
  draft: "مسودة",
  sent: "انبعت للمورد",
  confirmed: "أكّدو المورد",
  converted: "صار فاتورة",
  cancelled: "ملغى",
};

const statusChip: Record<PurchaseOrderRow["status"], string> = {
  draft: "gray",
  sent: "blue",
  confirmed: "orange",
  converted: "green",
  cancelled: "gray",
};

const newLine = (): Line => ({
  key: crypto.randomUUID(),
  product: null,
  quantity: "1",
  cost: "",
  mode: "base",
});

export function PurchaseOrdersClient({
  canAdd = {},
  companyId,
  currency,
  orders,
  suppliers,
  canCreate,
}: {
  companyId: string;
  currency: string;
  orders: PurchaseOrderRow[];
  suppliers: { id: string; name: string }[];
  canCreate: boolean;
  canAdd?: { trader?: boolean; supplier?: boolean; product?: boolean };
}) {
  const [supabase] = useState(() => createClient());
  const quick = useQuickCreate(supabase, companyId);
  const router = useRouter();

  const [open, setOpen] = useState(false);
  const [supplier, setSupplier] = useState("");
  const [expected, setExpected] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([newLine()]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [convert, setConvert] = useState<PurchaseOrderRow | null>(null);
  const [supplierInvoice, setSupplierInvoice] = useState("");
  const [search, setSearch] = useState("");

  const supplierOptions = useMemo(
    () => suppliers.map((row) => ({ id: row.id, label: row.name })),
    [suppliers],
  );
  const findSuppliers = useMemo(
    () => (term: string) => searchSuppliers(supabase, companyId, term),
    [supabase, companyId],
  );
  const findProducts = useMemo(
    () => (term: string) => searchProducts(supabase, companyId, term),
    [supabase, companyId],
  );

  const total = lines.reduce(
    (sum, line) => sum + Number(line.quantity) * Number(line.cost || 0),
    0,
  );

  const filtered = orders.filter((order) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return matchesSearch(
      [
        order.po_number,
        one(order.suppliers)?.name,
        ...order.purchase_order_items.map((i) => one(i.products)?.name),
      ].join(" "),
      q,
    );
  });

  function update(key: string, patch: Partial<Line>) {
    setLines((current) => current.map((line) => (line.key === key ? { ...line, ...patch } : line)));
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");
    const ready = lines.filter((line) => line.product);
    if (!supplier) return setMessage("اختار المورد.");
    if (!ready.length) return setMessage("ضيف صنف واحد على الأقل.");
    if (ready.some((line) => !(Number(line.quantity) > 0))) return setMessage("راجع الكميات.");

    setSaving(true);
    const { error } = await supabase.rpc("create_purchase_order", {
      target_company: companyId,
      target_supplier: supplier,
      target_expected_date: expected || null,
      target_notes: notes.trim() || null,
      items_payload: ready.map((line) => ({
        product_id: line.product!.id,
        quantity: toBaseQuantity(Number(line.quantity), line.mode, line.product!.pack_size),
        unit_cost: toBasePrice(Number(line.cost || 0), line.mode, line.product!.pack_size),
      })),
    });
    setSaving(false);
    if (error) return setMessage("ما قدرنا نحفظ أمر الشراء. تأكد من المورد والأصناف.");
    setOpen(false);
    setSupplier("");
    setExpected("");
    setNotes("");
    setLines([newLine()]);
    router.refresh();
  }

  async function setStatus(order: PurchaseOrderRow, status: string) {
    await supabase.rpc("set_purchase_order_status", {
      target_company: companyId,
      target_order: order.id,
      target_status: status,
    });
    router.refresh();
  }

  async function doConvert(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!convert) return;
    setSaving(true);
    setMessage("");
    const { data, error } = await supabase.rpc("convert_purchase_order", {
      target_company: companyId,
      target_order: convert.id,
      target_supplier_invoice_number: supplierInvoice.trim() || null,
      target_invoice_date: new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" }),
    });
    setSaving(false);
    if (error) {
      return setMessage(
        error.message.toLowerCase().includes("closed")
          ? "أمر الشراء مسكّر (صار فاتورة أو انلغى)."
          : "ما قدرنا نحوّلو لفاتورة.",
      );
    }
    setConvert(null);
    void data;
    router.push("/purchases");
  }

  return (
    <div className="page">
      {quick.modal}
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المشتريات</span>
          <h2>أوامر الشراء</h2>
          <p className="muted">أمر الشراء ما بيأثر عالمخزون ولا عالحسابات لحتى يصير فاتورة.</p>
        </div>
        <div className="rowActions">
          <Link className="softButton" href="/purchases">
            فواتير الشراء
          </Link>
          {canCreate ? (
            <button type="button" className="primaryButton" onClick={() => setOpen(true)}>
              <Icons.plus size={14} /> أمر شراء جديد
            </button>
          ) : null}
        </div>
      </div>

      <section className="panel">
        <div className="panelPad">
          <div className="searchBox" style={{ width: "100%" }}>
            <Icons.search size={14} />
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="بحث برقم الأمر أو المورد أو الصنف..."
            />
          </div>
        </div>
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>الأمر</th>
                <th>المورد</th>
                <th>الأصناف</th>
                <th>المجموع</th>
                <th>الحالة</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((order) => (
                <tr key={order.id}>
                  <td>
                    <strong>{order.po_number}</strong>
                    <div className="muted">
                      {formatDate(order.order_date)}
                      {order.expected_date ? ` • متوقع ${formatDate(order.expected_date)}` : ""}
                    </div>
                  </td>
                  <td>{one(order.suppliers)?.name}</td>
                  <td>
                    {order.purchase_order_items
                      .map((item) => `${one(item.products)?.name} × ${formatQty(item.quantity)}`)
                      .join("، ")}
                  </td>
                  <td>{money(order.total, order.currency)}</td>
                  <td>
                    <span className={`chip ${statusChip[order.status]}`}>
                      {statusLabels[order.status]}
                    </span>
                  </td>
                  <td>
                    <div className="rowActions">
                      <Link className="softButton" href={`/print/purchase-order/${order.id}`}>
                        طباعة / واتساب
                      </Link>
                      {canCreate && order.status === "draft" ? (
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void setStatus(order, "sent")}
                        >
                          انبعت
                        </button>
                      ) : null}
                      {canCreate && order.status === "sent" ? (
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void setStatus(order, "confirmed")}
                        >
                          أكّد
                        </button>
                      ) : null}
                      {canCreate && !["converted", "cancelled"].includes(order.status) ? (
                        <>
                          <button
                            type="button"
                            className="primaryButton"
                            onClick={() => {
                              setMessage("");
                              setSupplierInvoice("");
                              setConvert(order);
                            }}
                          >
                            وصلت الفاتورة
                          </button>
                          <button
                            type="button"
                            className="dangerButton"
                            onClick={() => {
                              if (window.confirm(`إلغاء ${order.po_number}؟`))
                                void setStatus(order, "cancelled");
                            }}
                          >
                            إلغاء
                          </button>
                        </>
                      ) : null}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!filtered.length ? <p className="muted panelPad">ما في أوامر شراء.</p> : null}
        </div>
      </section>

      {open ? (
        <div className="modalOverlay">
          <section className="modal" style={{ maxWidth: 900 }}>
            <div className="modalHeader">
              <h2>أمر شراء جديد</h2>
              <button type="button" className="closeButton" onClick={() => setOpen(false)}>
                ×
              </button>
            </div>
            <form onSubmit={save}>
              <div className="formGrid">
                <label className="field">
                  <span>المورد *</span>
                  <SearchPicker
                    value={supplier}
                    placeholder="اكتب اسم المورد..."
                    options={supplierOptions}
                    onSearch={findSuppliers}
                    onCreate={canAdd.supplier ? (term) => quick.create("supplier", term) : undefined}
                    createLabel="مورد"
                    onChange={(id) => setSupplier(id)}
                  />
                </label>
                <label className="field">
                  <span>تاريخ الوصول المتوقع</span>
                  <input
                    type="date"
                    value={expected}
                    onChange={(event) => setExpected(event.target.value)}
                  />
                </label>
              </div>

              <div className="quickList" style={{ marginTop: 12 }}>
                {lines.map((line) => (
                  <div className="quickItem" key={line.key}>
                    <SearchPicker
                      value={line.product?.id ?? ""}
                      placeholder="اسم الصنف أو كودو..."
                      options={[]}
                      onSearch={findProducts}
                      onCreate={canAdd.product ? (term) => quick.create("product", term) : undefined}
                      createLabel="صنف"
                      onChange={(_, option) =>
                        update(line.key, {
                          product: (option?.data as ProductPick) ?? null,
                          mode: "base",
                        })
                      }
                    />
                    <NumberInput
                      min="0.001"
                      step="any"
                      placeholder="الكمية"
                      value={line.quantity}
                      onChange={(event) => update(line.key, { quantity: event.target.value })}
                    />
                    <UnitToggle
                      mode={line.mode}
                      unit={line.product?.unit}
                      packUnit={line.product?.pack_unit}
                      packSize={line.product?.pack_size}
                      quantity={line.quantity}
                      onChange={(mode) =>
                        update(line.key, {
                          mode,
                          cost: convertPrice(line.cost, line.mode, mode, line.product?.pack_size),
                        })
                      }
                    />
                    <NumberInput
                      min="0"
                      step="any"
                      placeholder="السعر المتوقع"
                      value={line.cost}
                      onChange={(event) => update(line.key, { cost: event.target.value })}
                    />
                    <button
                      type="button"
                      className="dangerButton"
                      disabled={lines.length === 1}
                      onClick={() =>
                        setLines((current) => current.filter((row) => row.key !== line.key))
                      }
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>

              <button
                type="button"
                className="softButton"
                style={{ marginTop: 10 }}
                onClick={() => setLines((current) => [...current, newLine()])}
              >
                <Icons.plus size={13} /> صنف
              </button>

              <label className="field" style={{ marginTop: 12 }}>
                <span>ملاحظات للمورد</span>
                <textarea
                  rows={2}
                  value={notes}
                  onChange={(event) => setNotes(event.target.value)}
                />
              </label>

              <div className="statValue" style={{ marginTop: 10 }}>
                {money(total, currency)}
              </div>

              {message ? <div className="toastError">{message}</div> : null}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setOpen(false)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "حفظ أمر الشراء"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {convert ? (
        <div className="modalOverlay">
          <section className="modal" style={{ maxWidth: 480 }}>
            <div className="modalHeader">
              <div>
                <span className="eyebrow">{convert.po_number}</span>
                <h2>تحويل لفاتورة شراء</h2>
                <p className="muted">
                  بتنعمل فاتورة شراء بنفس الأصناف والأسعار ({money(convert.total, convert.currency)}
                  ). إذا الكميات أو الأسعار تغيّرت، عدّل الفاتورة بعدين أو ألغيها وسجّل الصح.
                </p>
              </div>
              <button type="button" className="closeButton" onClick={() => setConvert(null)}>
                ×
              </button>
            </div>
            <form onSubmit={doConvert}>
              <label className="field">
                <span>رقم فاتورة المورد</span>
                <input
                  value={supplierInvoice}
                  onChange={(event) => setSupplierInvoice(event.target.value)}
                />
              </label>
              {message ? <div className="toastError">{message}</div> : null}
              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setConvert(null)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحوّل..." : "إنشاء فاتورة الشراء"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}
