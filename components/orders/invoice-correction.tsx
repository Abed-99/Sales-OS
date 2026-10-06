"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

import { DeliveryFeeFields, deliveryFeeParams, type DeliveryFeeValue } from "@/components/delivery-fee-fields";
import { NumberInput } from "@/components/number-input";
import type { OwnerAction } from "@/components/owner-pin";
import { SearchPicker, type PickerOption } from "@/components/search-picker";
import { formatMoney as money } from "@/lib/format";
import { searchProducts, type ProductPick } from "@/lib/pickers";

type Line = {
  key: string;
  product_id: string;
  name: string;
  unit: string | null;
  quantity: string;
  price: string;
};

type Done = { invoice_id: string; invoice_number: string; order_id: string; total: number; balance_due: number; currency: string };

function friendly(message: string) {
  const m = message.toLowerCase();
  if (m.includes("not allowed") || m.includes("permission")) return "ما عندك صلاحية تصحيح الفواتير.";
  if (m.includes("order has other invoices"))
    return "طلبية هالفاتورة إلها أكتر من تسليمة، فما بتتصحّح هون. ألغِ الفاتورة واعمل وحدة جديدة.";
  if (m.includes("posted return")) return "الفاتورة عليها مرتجع. اعكس المرتجع أول.";
  if (m.includes("not enough stock")) return "ما في كمية كافية بالمخزون للأصناف الجديدة.";
  if (m.includes("owner approval required")) return "في سعر تحت الكلفة أو تحت أقل سعر، وبدو موافقة المالك.";
  if (m.includes("credit") || m.includes("ائتمان")) return "الفاتورة الجديدة بتتجاوز حد دين الزبون.";
  if (m.includes("period") && m.includes("closed")) return "الشهر مقفل. افتحه من صفحة المالية أول.";
  if (m.includes("only posted")) return "الفاتورة ملغاة من قبل.";
  return "ما قدرنا نصحّح الفاتورة. ما تغيّر شي، حاول مرة تانية.";
}

/**
 * تصحيح فاتورة بيع: بتطلع الأصناف والأسعار القديمة، بتعدّل اللي بدك ياه، وبخطوة وحدة
 * بتنلغى القديمة وبتنعمل جديدة بدالها (والدفعات بتنتقل عليها).
 */
export function InvoiceCorrection({
  supabase,
  companyId,
  currency,
  invoice,
  askOwner,
  onClose,
  onDone,
}: {
  supabase: SupabaseClient;
  companyId: string;
  currency: string;
  invoice: { id: string; invoice_number: string; delivery_fee: number; paid_total: number };
  askOwner: (action: OwnerAction, reason: string) => Promise<boolean>;
  onClose: () => void;
  onDone: () => void;
}) {
  const [lines, setLines] = useState<Line[]>([]);
  const [loading, setLoading] = useState(true);
  const [fee, setFee] = useState<DeliveryFeeValue>({
    mode: Number(invoice.delivery_fee) > 0 ? "customer" : "none",
    amount: Number(invoice.delivery_fee) > 0 ? String(invoice.delivery_fee) : "",
    cashboxId: "",
  });
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [pick, setPick] = useState("");

  const findProducts = useMemo(
    () => (term: string) => searchProducts(supabase, companyId, term),
    [supabase, companyId],
  );

  useEffect(() => {
    let alive = true;
    void supabase
      .from("sales_invoice_items")
      .select("id,product_id,description,unit,quantity,unit_price")
      .eq("invoice_id", invoice.id)
      .order("created_at")
      .then(({ data, error }) => {
        if (!alive) return;
        if (error) setMessage("ما قدرنا نحمّل أصناف الفاتورة.");
        setLines(
          (data ?? []).map((row) => ({
            key: row.id as string,
            product_id: row.product_id as string,
            name: row.description as string,
            unit: (row.unit as string | null) ?? null,
            quantity: String(Number(row.quantity)),
            price: String(Number(row.unit_price)),
          })),
        );
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [supabase, invoice.id]);

  const subtotal = lines.reduce((sum, line) => sum + Number(line.quantity) * Number(line.price), 0);
  const customerFee = fee.mode === "customer" ? Number(fee.amount) || 0 : 0;

  function update(key: string, patch: Partial<Line>) {
    setLines((current) => current.map((line) => (line.key === key ? { ...line, ...patch } : line)));
  }

  function addProduct(option: PickerOption<ProductPick> | null) {
    const product = option?.data;
    setPick("");
    if (!product) return;
    if (lines.some((line) => line.product_id === product.id)) {
      setMessage("الصنف موجود بالفاتورة، عدّل كميتو.");
      return;
    }
    setMessage("");
    setLines((current) => [
      ...current,
      {
        key: crypto.randomUUID(),
        product_id: product.id,
        name: product.name,
        unit: product.unit,
        quantity: "1",
        price: product.sale_price != null ? String(product.sale_price) : "",
      },
    ]);
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");

    if (!lines.length) return setMessage("لازم يضل صنف واحد على الأقل. إذا بدك تلغي البيعة كلها، استعمل إلغاء الفاتورة.");
    if (lines.some((line) => !(Number(line.quantity) > 0) || line.price.trim() === "" || !(Number(line.price) >= 0))) {
      return setMessage("راجع الكميات والأسعار.");
    }
    if (!reason.trim()) return setMessage("اكتب سبب التصحيح.");
    const feeParams = deliveryFeeParams(fee);
    if (!feeParams.ok) return setMessage(feeParams.message);

    // نفس الصنف بسطرين (من فاتورة قديمة) بينجمعوا بسطر واحد.
    const merged = new Map<string, { product_id: string; quantity: number; sale_unit_price: number }>();
    for (const line of lines) {
      const current = merged.get(line.product_id);
      if (current && current.sale_unit_price !== Number(line.price)) {
        return setMessage(`${line.name} مكرّر بسعرين مختلفين. خلّيه سطر واحد.`);
      }
      merged.set(line.product_id, {
        product_id: line.product_id,
        quantity: (current?.quantity ?? 0) + Number(line.quantity),
        sale_unit_price: Number(line.price),
      });
    }

    const run = () =>
      supabase.rpc("correct_sales_invoice", {
        target_company: companyId,
        target_invoice: invoice.id,
        target_reason: reason.trim(),
        items_payload: [...merged.values()],
        target_delivery_fee: feeParams.params.target_delivery_fee,
      });

    setSaving(true);
    try {
      let result = await run();

      // كل مرة بيوقف على شي بدو المالك (صلاحية الإلغاء، سعر تحت الكلفة، حد الدين) منسألو ومنعيد.
      for (let attempt = 0; attempt < 3 && result.error; attempt += 1) {
        const raw = result.error.message.toLowerCase();
        const needed: [OwnerAction, string] | null = raw.includes("not allowed")
          ? ["cancel_invoice", "تصحيح الفاتورة بيلغي القديمة، وبدو صلاحية أو موافقة المالك."]
          : raw.includes("owner approval required")
            ? ["approve", "في صنف سعرو تحت الكلفة أو تحت أقل سعر."]
            : raw.includes("credit") || raw.includes("ائتمان")
              ? ["credit_limit", "الفاتورة الجديدة بتتجاوز حد دين الزبون."]
              : null;
        if (!needed || !(await askOwner(...needed))) break;
        result = await run();
      }

      if (result.error) return setMessage(friendly(result.error.message));
      setDone(result.data as Done);
      onDone();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modalOverlay" style={{ zIndex: 1200 }}>
      <section className="modal" role="dialog" aria-modal="true" style={{ width: "94vw", maxWidth: 820 }}>
        <div className="modalHeader">
          <div>
            <span className="eyebrow">تصحيح فاتورة</span>
            <h2>{invoice.invoice_number}</h2>
          </div>
          <button type="button" className="closeButton" aria-label="إغلاق" disabled={saving} onClick={onClose}>
            ×
          </button>
        </div>

        {done ? (
          <div style={{ textAlign: "center" }}>
            <h3>انصلحت الفاتورة ✓</h3>
            <p className="muted">
              {invoice.invoice_number} انلغت، وانعملت بدالها <strong>{done.invoice_number}</strong> بمجموع{" "}
              {money(Number(done.total), done.currency)}
              {Number(done.balance_due) > 0.001 ? ` • الباقي عالزبون ${money(Number(done.balance_due), done.currency)}` : " • مسددة"}
            </p>
            <div className="rowActions" style={{ justifyContent: "center" }}>
              <a className="primaryButton" href={`/print/invoice/${done.invoice_id}`} target="_blank" rel="noreferrer">
                طباعة / واتساب
              </a>
              <Link className="softButton" href={`/orders?order=${done.order_id}`} onClick={onClose}>
                عرض الطلبية الجديدة
              </Link>
            </div>
          </div>
        ) : (
          <form onSubmit={save}>
            <p className="muted">
              عدّل الأصناف والكميات والأسعار. لما تحفظ، الفاتورة القديمة بتنلغى والبضاعة بترجع للمستودع، وبتنعمل فاتورة
              جديدة بالأرقام الصح
              {Number(invoice.paid_total) > 0 ? "، والمدفوع عالقديمة بينتقل عالجديدة" : ""}.
            </p>

            {loading ? <p className="muted">عم نحمّل الأصناف...</p> : null}

            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الصنف</th>
                    <th>الكمية</th>
                    <th>السعر</th>
                    <th>المجموع</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {lines.map((line) => (
                    <tr key={line.key}>
                      <td>
                        <strong>{line.name}</strong>
                        {line.unit ? <div className="muted">{line.unit}</div> : null}
                      </td>
                      <td>
                        <NumberInput
                          min="0.001"
                          step="any"
                          style={{ width: 80 }}
                          value={line.quantity}
                          onChange={(event) => update(line.key, { quantity: event.target.value })}
                        />
                      </td>
                      <td>
                        <NumberInput
                          min="0"
                          step="any"
                          style={{ width: 90 }}
                          value={line.price}
                          onChange={(event) => update(line.key, { price: event.target.value })}
                        />
                      </td>
                      <td>{money(Number(line.quantity) * Number(line.price) || 0, currency)}</td>
                      <td>
                        <button
                          type="button"
                          className="dangerButton"
                          aria-label={`شيل ${line.name}`}
                          onClick={() => setLines((current) => current.filter((row) => row.key !== line.key))}
                        >
                          ×
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <label className="field" style={{ marginTop: 10 }}>
              <span>ضيف صنف</span>
              <SearchPicker<ProductPick>
                value={pick}
                placeholder="اسم الصنف أو الباركود..."
                options={[]}
                onSearch={findProducts}
                onChange={(_, option) => addProduct(option)}
              />
            </label>

            <DeliveryFeeFields value={fee} onChange={setFee} currency={currency} />

            <p style={{ textAlign: "end" }}>
              <strong>
                المجموع الجديد: {money(subtotal + customerFee, currency)}
              </strong>
              <br />
              <small className="muted">قبل الضريبة إذا مفعّلة</small>
            </p>

            <label className="field">
              <span>سبب التصحيح *</span>
              <textarea
                rows={2}
                value={reason}
                onChange={(event) => setReason(event.target.value)}
                placeholder="مثلاً: الكمية غلط، السعر غلط..."
              />
            </label>

            {message ? (
              <div className="toastError" role="alert">
                {message}
              </div>
            ) : null}

            <div className="modalActions">
              <button type="button" className="softButton" disabled={saving} onClick={onClose}>
                رجوع
              </button>
              <button className="primaryButton" disabled={saving || loading}>
                {saving ? "عم نصحّح..." : "تصحيح الفاتورة"}
              </button>
            </div>
          </form>
        )}
      </section>
    </div>
  );
}
