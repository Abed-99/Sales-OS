"use client";

import { useMemo, useState } from "react";

import { createClient } from "@/lib/supabase/client";
import { money } from "@/lib/print-format";
import { waNumber } from "@/lib/wa-send";

import styles from "./public-catalog.module.css";
import { formatQty as qty } from "@/lib/format";

export type PublicCatalogProduct = {
  id: string;
  name: string;
  brand: string | null;
  sku: string | null;
  unit: string | null;
  pack_size: number | null;
  pack_unit: string | null;
  category_id: string | null;
  image_url: string | null;
  description: string | null;
  price: number | null;
  in_stock: boolean | null;
  quantity: number | null;
};

export type PublicCatalogData = {
  company: {
    name: string;
    logo_url: string | null;
    phone: string | null;
    whatsapp: string | null;
    address: string | null;
    currency: string;
  };
  link: {
    title: string;
    trader_name: string | null;
    show_prices: boolean;
    show_description: boolean;
    show_images: boolean;
    stock_mode: "hidden" | "available" | "quantity";
    allow_orders: boolean;
  };
  categories: Array<{ id: string; name: string }>;
  products: PublicCatalogProduct[];
};

export function PublicCatalog({ token, data }: { token: string; data: PublicCatalogData }) {
  const { company, link, categories, products } = data;
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState<string>("");
  const [cart, setCart] = useState<Record<string, number>>({});
  const [cartOpen, setCartOpen] = useState(false);
  const [phone, setPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [printing, setPrinting] = useState(false);

  const visible = useMemo(() => {
    const words = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
    return products.filter((product) => {
      if (category && product.category_id !== category) return false;
      if (!words.length) return true;
      const text = [product.name, product.brand, product.sku, product.description]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return words.every((word) => text.includes(word));
    });
  }, [products, search, category]);

  const cartLines = products.filter((product) => cart[product.id] > 0);
  const cartTotal = cartLines.reduce(
    (sum, product) => sum + (product.price ?? 0) * cart[product.id],
    0,
  );

  function setQty(id: string, value: number) {
    setCart((current) => {
      const next = { ...current };
      if (!Number.isFinite(value) || value <= 0) delete next[id];
      else next[id] = Math.round(value * 1000) / 1000;
      return next;
    });
  }

  async function sendOrder() {
    if (!cartLines.length) return;
    if (!phone.trim()) {
      setMessage({ ok: false, text: "اكتب رقم تلفونك المسجّل عنا." });
      return;
    }
    setSending(true);
    setMessage(null);
    try {
      const { data: result, error } = await createClient().rpc("submit_catalog_order", {
        target_token: token,
        target_phone: phone,
        items_payload: cartLines.map((product) => ({ product_id: product.id, quantity: cart[product.id] })),
        target_notes: notes.trim() || null,
      });
      if (error) {
        const text = /Too many/i.test(error.message)
          ? "في محاولات كتير. جرّب بعد شوي أو احكينا عالواتساب."
          : "ما قدرنا نبعت الطلب. جرّب مرة تانية أو احكينا عالواتساب.";
        setMessage({ ok: false, text });
        return;
      }
      const reply = result as { ok: boolean; quote_number?: string };
      if (!reply.ok) {
        setMessage({
          ok: false,
          text: "هاد الرقم مش مسجّل عنا. اكتب الرقم اللي عطيتنا ياه، أو احكينا عالواتساب.",
        });
        return;
      }
      setCart({});
      setNotes("");
      setCartOpen(false);
      window.scrollTo({ top: 0, behavior: "smooth" });
      setMessage({
        ok: true,
        text: `وصلنا طلبك (رقم ${reply.quote_number}). رح نراجعو ونتواصل معك. شكرًا 🌷`,
      });
    } finally {
      setSending(false);
    }
  }

  async function printCatalog() {
    // الصور بتتحمّل عند الحاجة؛ قبل الطباعة منحمّلها كلها.
    setPrinting(true);
    await new Promise((resolve) => setTimeout(resolve, 50));
    await Promise.all(
      Array.from(document.images)
        .filter((image) => !image.complete)
        .map((image) => new Promise((resolve) => ((image.onload = resolve), (image.onerror = resolve)))),
    );
    window.print();
    setPrinting(false);
  }

  const wa = waNumber(company.whatsapp || company.phone);
  const categoryName = (id: string | null) => categories.find((row) => row.id === id)?.name;

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        {company.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={company.logo_url} alt="" className={styles.logo} />
        ) : (
          <div className={styles.logoText}>{company.name.slice(0, 1)}</div>
        )}
        <div className={styles.headerText}>
          <h1>{company.name}</h1>
          <p>
            {link.title}
            {link.trader_name && !link.title.includes(link.trader_name) ? ` — لـ ${link.trader_name}` : ""}
          </p>
        </div>
        <div className={styles.headerActions}>
          {wa ? (
            <a className={styles.waButton} href={`https://wa.me/${wa}`} target="_blank" rel="noreferrer">
              واتساب
            </a>
          ) : null}
          <button type="button" className={styles.ghostButton} onClick={printCatalog}>
            PDF / طباعة
          </button>
        </div>
      </header>

      <div className={styles.toolbar}>
        <input
          className={styles.search}
          type="search"
          placeholder="دوّر على صنف، ماركة، أو كود..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
        {categories.length > 1 ? (
          <div className={styles.chips}>
            <button
              type="button"
              className={!category ? styles.chipActive : styles.chip}
              onClick={() => setCategory("")}
            >
              الكل
            </button>
            {categories.map((row) => (
              <button
                key={row.id}
                type="button"
                className={category === row.id ? styles.chipActive : styles.chip}
                onClick={() => setCategory(row.id)}
              >
                {row.name}
              </button>
            ))}
          </div>
        ) : null}
      </div>

      {message && !cartOpen ? (
        <div className={message.ok ? styles.noticeOk : styles.noticeError}>{message.text}</div>
      ) : null}

      <p className={styles.count}>{visible.length} صنف</p>

      <section className={styles.grid}>
        {visible.map((product) => {
          const inCart = cart[product.id] ?? 0;
          return (
            <article key={product.id} className={styles.card}>
              {link.show_images ? (
                product.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={product.image_url}
                    alt={product.name}
                    className={styles.image}
                    loading={printing ? "eager" : "lazy"}
                  />
                ) : (
                  <div className={styles.noImage}>{product.name.slice(0, 1)}</div>
                )
              ) : null}
              <div className={styles.cardBody}>
                <h2>{product.name}</h2>
                <p className={styles.meta}>
                  {[product.brand, categoryName(product.category_id)].filter(Boolean).join(" · ")}
                </p>
                {product.pack_size ? (
                  <p className={styles.meta}>
                    {product.pack_unit || "كرتونة"} = {qty(Number(product.pack_size))} {product.unit}
                  </p>
                ) : null}
                {link.show_description && product.description ? (
                  <p className={styles.description}>{product.description}</p>
                ) : null}
                <div className={styles.cardFooter}>
                  {link.show_prices && product.price != null ? (
                    <strong className={styles.price}>
                      {money(product.price, company.currency)}
                      <small> / {product.unit}</small>
                    </strong>
                  ) : (
                    <span />
                  )}
                  {product.in_stock === null ? null : product.in_stock ? (
                    <span className={styles.inStock}>
                      {product.quantity != null ? `متوفر: ${qty(Number(product.quantity))}` : "متوفر"}
                    </span>
                  ) : (
                    <span className={styles.outStock}>غير متوفر</span>
                  )}
                </div>
                {link.allow_orders ? (
                  <div className={styles.qtyRow}>
                    {inCart > 0 ? (
                      <>
                        <button type="button" onClick={() => setQty(product.id, inCart - 1)}>
                          −
                        </button>
                        <input
                          inputMode="decimal"
                          value={inCart}
                          onChange={(event) => setQty(product.id, Number(event.target.value))}
                        />
                        <button type="button" onClick={() => setQty(product.id, inCart + 1)}>
                          +
                        </button>
                      </>
                    ) : (
                      <button type="button" className={styles.addButton} onClick={() => setQty(product.id, 1)}>
                        أضف للطلب
                      </button>
                    )}
                    {product.pack_size ? (
                      <button
                        type="button"
                        className={styles.packButton}
                        onClick={() => setQty(product.id, inCart + Number(product.pack_size))}
                      >
                        + {product.pack_unit || "كرتونة"}
                      </button>
                    ) : null}
                  </div>
                ) : null}
              </div>
            </article>
          );
        })}
      </section>

      {!visible.length ? <p className={styles.emptyText}>ما لقينا شي بهاد البحث.</p> : null}

      <footer className={styles.footer}>
        {[company.phone, company.address].filter(Boolean).join(" · ")}
      </footer>

      {link.allow_orders && cartLines.length ? (
        <button type="button" className={styles.cartBar} onClick={() => setCartOpen(true)}>
          <span>🛒 طلبك: {cartLines.length} صنف</span>
          {link.show_prices ? <strong>{money(cartTotal, company.currency)}</strong> : null}
        </button>
      ) : null}

      {cartOpen ? (
        <div className={styles.sheetOverlay} onClick={() => setCartOpen(false)}>
          <div className={styles.sheet} onClick={(event) => event.stopPropagation()}>
            <div className={styles.sheetHeader}>
              <h2>طلبك</h2>
              <button type="button" className={styles.ghostButton} onClick={() => setCartOpen(false)}>
                رجوع
              </button>
            </div>
            {cartLines.length ? (
              <ul className={styles.cartList}>
                {cartLines.map((product) => (
                  <li key={product.id}>
                    <span>{product.name}</span>
                    <span>
                      {qty(cart[product.id])} {product.unit}
                      {link.show_prices && product.price != null
                        ? ` · ${money(product.price * cart[product.id], company.currency)}`
                        : ""}
                    </span>
                    <button type="button" onClick={() => setQty(product.id, 0)} aria-label="شيل">
                      ✕
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <p className={styles.emptyText}>الطلب فاضي.</p>
            )}
            {link.show_prices && cartLines.length ? (
              <p className={styles.total}>المجموع التقريبي: {money(cartTotal, company.currency)}</p>
            ) : null}
            <label className={styles.field}>
              <span>رقم تلفونك (المسجّل عنا)</span>
              <input
                dir="ltr"
                inputMode="tel"
                placeholder="09xxxxxxxx"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
              />
            </label>
            <label className={styles.field}>
              <span>ملاحظة (اختياري)</span>
              <textarea rows={2} maxLength={500} value={notes} onChange={(event) => setNotes(event.target.value)} />
            </label>
            {message ? (
              <div className={message.ok ? styles.noticeOk : styles.noticeError}>{message.text}</div>
            ) : null}
            <button
              type="button"
              className={styles.sendButton}
              disabled={sending || !cartLines.length}
              onClick={sendOrder}
            >
              {sending ? "عم نبعت..." : "ابعت الطلب"}
            </button>
            <p className={styles.hint}>الأسعار والكميات بتتأكد من الشركة قبل التجهيز.</p>
          </div>
        </div>
      ) : null}
    </main>
  );
}
