"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

import { Icons } from "@/components/icons";
import { useOwnerPin } from "@/components/owner-pin";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import { SearchPicker, type PickerOption } from "@/components/search-picker";
import { UnitToggle } from "@/components/unit-toggle";
import { BarcodeScanButton } from "@/components/barcode-scan";
import {
  productOption,
  searchProducts,
  recentTraders,
  searchTraders,
  type ProductPick,
  type TraderPick,
} from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";
import {
  convertPrice,
  toBasePrice,
  toBaseQuantity,
  traderPrices,
  type UnitMode,
} from "@/lib/units";
import { NumberInput } from "@/components/number-input";
import { formatMoney as money, formatNumber, todayDamascus as today } from "@/lib/format";

type Line = {
  key: string;
  product: ProductPick;
  quantity: string;
  price: string;
  mode: UnitMode;
};

type Done = {
  order_number: string | null;
  order_id: string;
  invoice_id: string;
  total: number;
  paid: number;
  credit_used?: number;
  currency: string;
};

function friendly(message: string) {
  const text = message.toLowerCase();
  if (text.includes("not enough stock")) return "في صنف ما في منو كمية كافية بالمخزون.";
  if (text.includes("paid amount exceeds")) return "المبلغ المدفوع أكبر من الفاتورة.";
  if (text.includes("not allowed")) return "ما عندك صلاحية البيع السريع.";
  if (text.includes("financial period is closed")) return "الشهر مقفل بالمالية.";
  if (text.includes("missing exchange rate")) return "ما في سعر صرف لعملة الصندوق.";
  if (text.includes("inactive product")) return "في صنف موقوف.";
  return "ما قدرنا نخلّص البيع. راجع الأصناف والمبالغ.";
}

export function QuickSaleClient({
  companyId,
  currency,
  products,
  cashboxes,
  tax = null,
}: {
  companyId: string;
  currency: string;
  products: ProductPick[];
  cashboxes: { id: string; name: string; currency: string }[];
  tax?: { rate: number; label: string } | null;
}) {
  const [supabase] = useState(() => createClient());
  const ownerPin = useOwnerPin(supabase, companyId);

  const [trader, setTrader] = useState("");
  const [lines, setLines] = useState<Line[]>([]);
  const [scan, setScan] = useState("");
  const [cashboxId, setCashboxId] = useState(
    cashboxes.find((box) => box.currency === currency)?.id ?? cashboxes[0]?.id ?? "",
  );
  const [txRate, setTxRate] = useState("");
  const [paid, setPaid] = useState("");
  const [method, setMethod] = useState("cash");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [done, setDone] = useState<Done | null>(null);

  const productOptions = useMemo(() => products.map((row) => productOption(row)), [products]);
  const findProducts = useMemo(
    () => (term: string) => searchProducts(supabase, companyId, term),
    [supabase, companyId],
  );
  const findTraders = useMemo(
    () => (term: string) => searchTraders(supabase, companyId, term),
    [supabase, companyId],
  );
  const [traderOptions, setTraderOptions] = useState<PickerOption<TraderPick>[]>([]);
  useEffect(() => {
    void recentTraders(supabase, companyId).then(setTraderOptions);
  }, [supabase, companyId]);

  const cashbox = cashboxes.find((box) => box.id === cashboxId);
  const subtotal = lines.reduce((sum, line) => sum + Number(line.quantity) * Number(line.price), 0);
  const taxAmount = tax ? Math.round(subtotal * tax.rate) / 100 : 0;
  const total = subtotal + taxAmount;
  const paidValue = paid.trim() === "" ? total : Number(paid);
  const foreign = cashbox && cashbox.currency !== currency;
  const cashAmount = foreign ? paidValue * Number(txRate || 0) : paidValue;

  async function addProduct(option: PickerOption<ProductPick> | null) {
    if (!option?.data) return;
    const product = option.data;
    setScan("");
    setMessage("");
    const existing = lines.find((line) => line.product.id === product.id);
    if (existing) {
      // نفس الصنف مرة تانية (باركود): منزيد الكمية.
      setLines((current) =>
        current.map((line) =>
          line.key === existing.key
            ? { ...line, quantity: String(Number(line.quantity || 0) + 1) }
            : line,
        ),
      );
      return;
    }
    const line: Line = {
      key: crypto.randomUUID(),
      product,
      quantity: "1",
      price: product.sale_price != null ? String(product.sale_price) : "",
      mode: "base",
    };
    setLines((current) => [...current, line]);
    if (trader) {
      const prices = await traderPrices(supabase, companyId, trader, [product.id]);
      const level = prices.get(product.id);
      if (level != null) {
        setLines((current) =>
          current.map((row) => (row.key === line.key ? { ...row, price: String(level) } : row)),
        );
      }
    }
  }

  async function chooseTrader(id: string) {
    setTrader(id);
    if (!id || !lines.length) return;
    const prices = await traderPrices(
      supabase,
      companyId,
      id,
      lines.map((line) => line.product.id),
    );
    setLines((current) =>
      current.map((line) => {
        const base = prices.get(line.product.id);
        return base == null
          ? line
          : {
              ...line,
              price: convertPrice(String(base), "base", line.mode, line.product.pack_size),
            };
      }),
    );
  }

  function update(key: string, patch: Partial<Line>) {
    setLines((current) => current.map((line) => (line.key === key ? { ...line, ...patch } : line)));
  }

  async function finish() {
    setMessage("");
    if (!lines.length) return setMessage("ضيف صنف واحد على الأقل.");
    if (
      lines.some(
        (line) =>
          !(Number(line.quantity) > 0) || !(Number(line.price) >= 0) || line.price.trim() === "",
      )
    ) {
      return setMessage("راجع الكميات والأسعار.");
    }
    if (!(paidValue >= 0) || paidValue > total + 0.001) {
      return setMessage("المبلغ المدفوع لازم يكون بين صفر ومجموع الفاتورة.");
    }
    if (paidValue > 0 && !cashbox) return setMessage("اختار الصندوق.");

    setSaving(true);
    try {
      if (paidValue > 0 && cashbox) {
        const rateError = await applyTransactionRate(
          supabase,
          companyId,
          cashbox.currency,
          currency,
          today(),
          txRate,
        );
        if (rateError) return setMessage(rateError);
      }

      const sell = () =>
        supabase.rpc("quick_sale", {
          target_company: companyId,
          target_trader: trader || null,
          items_payload: lines.map((line) => ({
            product_id: line.product.id,
            quantity: toBaseQuantity(Number(line.quantity), line.mode, line.product.pack_size),
            sale_unit_price: toBasePrice(Number(line.price), line.mode, line.product.pack_size),
          })),
          target_cashbox: cashboxId || null,
          // فاضي = دفع كامل: القاعدة بتحسب المجموع مع الضريبة بالضبط.
          target_paid_amount: paid.trim() === "" ? null : Number(paidValue.toFixed(2)),
          target_cash_amount: Number(cashAmount.toFixed(2)),
          target_method: method,
          target_notes: null,
        });

      let { data, error } = await sell();

      if (error?.message.toLowerCase().includes("owner approval required")) {
        const unlocked = await ownerPin.ask(
          "approve",
          "في صنف سعرو تحت الكلفة أو تحت أقل سعر. المالك بيكتب رمزو ليكمل البيع.",
        );
        if (!unlocked) return setMessage("البيع ما تم: السعر بدو موافقة المالك.");
        ({ data, error } = await sell());
      }

      if (error) return setMessage(friendly(error.message));

      setDone(data as Done);
      setLines([]);
      setPaid("");
      setTrader("");
    } finally {
      setSaving(false);
    }
  }

  if (done) {
    return (
      <div className="page">
        <section
          className="panel panelPad"
          style={{ maxWidth: 560, margin: "0 auto", textAlign: "center" }}
        >
          <Icons.check size={34} />
          <h2>تم البيع ✓</h2>
          <p className="muted">{done.order_number}</p>
          <div className="statValue">{money(Number(done.total), done.currency)}</div>
          <p>
            المدفوع: {money(Number(done.paid), done.currency)}
            {Number(done.credit_used ?? 0) > 0.001
              ? ` • من رصيدو عنا: ${money(Number(done.credit_used), done.currency)}`
              : ""}
            {Number(done.total) - Number(done.paid) - Number(done.credit_used ?? 0) > 0.001
              ? ` • الباقي دين: ${money(
                  Number(done.total) - Number(done.paid) - Number(done.credit_used ?? 0),
                  done.currency,
                )}`
              : ""}
          </p>
          <div className="rowActions" style={{ justifyContent: "center", marginTop: 14 }}>
            <button type="button" className="primaryButton" onClick={() => setDone(null)}>
              <Icons.plus size={14} /> بيع جديد
            </button>
            <Link className="softButton" href={`/print/invoice/${done.invoice_id}`}>
              طباعة / واتساب
            </Link>
            <Link className="softButton" href={`/orders?order=${done.order_id}`}>
              عرض الطلبية
            </Link>
          </div>
        </section>
      </div>
    );
  }

  return (
    <div className="page">
      {ownerPin.modal}

      <div className="pageGrid">
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الأصناف</h2>
              <p>امسح الباركود أو اكتب اسم الصنف واضغط Enter</p>
            </div>
          </div>

          <div className="rowActions" style={{ flexWrap: "nowrap", alignItems: "flex-start" }}>
            <div style={{ flex: 1 }}>
              <SearchPicker
                key={lines.length}
                autoFocus
                openOnFocus={false}
                value={scan}
                placeholder="باركود أو اسم الصنف..."
                options={productOptions}
                onSearch={findProducts}
                onChange={(_, option) => void addProduct(option)}
              />
            </div>
            <BarcodeScanButton
              onDetect={async (code) => {
                const found = await searchProducts(supabase, companyId, code);
                const exact = found.find((option) => option.code === code) ?? found[0];
                if (exact) void addProduct(exact);
                else setMessage(`ما في صنف بالباركود ${code}.`);
              }}
            />
          </div>

          <div className="tableWrap" style={{ marginTop: 12 }}>
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
                      <strong>{line.product.name}</strong>
                    </td>
                    <td>
                      <NumberInput
                        min="0.001"
                        step="any"
                        style={{ width: 80 }}
                        value={line.quantity}
                        onChange={(event) => update(line.key, { quantity: event.target.value })}
                      />
                      <UnitToggle
                        mode={line.mode}
                        unit={line.product.unit}
                        packUnit={line.product.pack_unit}
                        packSize={line.product.pack_size}
                        quantity={line.quantity}
                        onChange={(mode) =>
                          update(line.key, {
                            mode,
                            price: convertPrice(
                              line.price,
                              line.mode,
                              mode,
                              line.product.pack_size,
                            ),
                          })
                        }
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
                        onClick={() =>
                          setLines((current) => current.filter((row) => row.key !== line.key))
                        }
                      >
                        ×
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!lines.length ? (
              <p className="muted" style={{ padding: 12 }}>
                لسا ما في أصناف.
              </p>
            ) : null}
          </div>
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الدفع</h2>
            </div>
          </div>

          <div className="authForm">
            <label className="field">
              <span>الزبون (اختياري)</span>
              <SearchPicker<TraderPick>
                value={trader}
                placeholder="زبون نقدي"
                options={traderOptions}
                onSearch={findTraders}
                onChange={(id) => void chooseTrader(id)}
              />
            </label>

            {taxAmount > 0 ? (
              <p className="muted">
                الصافي {money(subtotal, currency)} + {tax?.label} {tax?.rate}%:{" "}
                {money(taxAmount, currency)}
              </p>
            ) : null}
            <div className="statValue">{money(total, currency)}</div>

            <label className="field">
              <span>الصندوق</span>
              <select value={cashboxId} onChange={(event) => setCashboxId(event.target.value)}>
                {cashboxes.map((box) => (
                  <option key={box.id} value={box.id}>
                    {box.name} - {box.currency}
                  </option>
                ))}
              </select>
            </label>

            <RateField
              supabase={supabase}
              companyId={companyId}
              currency={cashbox?.currency ?? ""}
              baseCurrency={currency}
              date={today()}
              value={txRate}
              onChange={setTxRate}
            />

            <label className="field">
              <span>المدفوع ({currency})</span>
              <NumberInput
                min="0"
                step="any"
                placeholder={`كامل: ${formatNumber(total)}`}
                value={paid}
                onChange={(event) => setPaid(event.target.value)}
              />
              {foreign && Number(txRate) > 0 ? (
                <small className="helpText">
                  = {cashAmount.toLocaleString("en-US", { maximumFractionDigits: 0 })}{" "}
                  {cashbox?.currency}
                </small>
              ) : null}
              {paidValue < total - 0.001 ? (
                <small className="helpText">الباقي بيصير دين على الزبون.</small>
              ) : null}
            </label>

            <label className="field">
              <span>طريقة الدفع</span>
              <select value={method} onChange={(event) => setMethod(event.target.value)}>
                <option value="cash">كاش</option>
                <option value="bank">تحويل</option>
                <option value="card">بطاقة</option>
                <option value="other">غير ذلك</option>
              </select>
            </label>

            {message ? <div className="toastError">{message}</div> : null}

            <button
              type="button"
              className="primaryButton"
              disabled={saving || !lines.length}
              onClick={() => void finish()}
            >
              {saving ? "عم نخلّص..." : "إتمام البيع"}
            </button>
          </div>
        </aside>
      </div>
    </div>
  );
}
