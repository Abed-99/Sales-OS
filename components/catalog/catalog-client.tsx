"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { SearchPicker, type PickerOption } from "@/components/search-picker";
import { searchTraders, type TraderPick } from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";
import { waNumber } from "@/lib/wa-send";
import { formatQty, formatDate } from "@/lib/format";

type Relation<T> = T | T[] | null;
const one = <T,>(value: Relation<T>) => (Array.isArray(value) ? (value[0] ?? null) : value);

type StockMode = "hidden" | "available" | "quantity";

export type CatalogLink = {
  id: string;
  token: string;
  title: string;
  trader_id: string | null;
  show_prices: boolean;
  price_level_id: string | null;
  show_description: boolean;
  show_images: boolean;
  stock_mode: StockMode;
  hide_out_of_stock: boolean;
  category_ids: string[] | null;
  allow_orders: boolean;
  active: boolean;
  expires_at: string | null;
  view_count: number;
  last_viewed_at: string | null;
  created_at: string;
  traders: Relation<{ name: string; phone: string | null; whatsapp: string | null }>;
};

type PresetTrader = {
  id: string;
  name: string;
  area: string | null;
  phone: string | null;
  whatsapp: string | null;
  price_level_id: string | null;
};

type Form = {
  title: string;
  trader_id: string;
  show_prices: boolean;
  price_level_id: string;
  show_description: boolean;
  show_images: boolean;
  stock_mode: StockMode;
  hide_out_of_stock: boolean;
  category_ids: string[];
  allow_orders: boolean;
  expires_on: string;
};

const emptyForm = (): Form => ({
  title: "",
  trader_id: "",
  show_prices: true,
  price_level_id: "",
  show_description: true,
  show_images: true,
  stock_mode: "available",
  hide_out_of_stock: false,
  category_ids: [],
  allow_orders: false,
  expires_on: "",
});

const stockLabels: Record<StockMode, string> = {
  hidden: "ما يبين المخزون",
  available: "متوفر / غير متوفر",
  quantity: "مع الكمية",
};

const catalogUrl = (token: string) => `${window.location.origin}/c/${token}`;

function Toggle({
  checked,
  onChange,
  label,
  hint,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  hint?: string;
}) {
  return (
    <label className="quickItem" style={{ cursor: "pointer" }}>
      <input
        type="checkbox"
        checked={checked}
        style={{ width: 18, height: 18, flex: "none", margin: 0 }}
        onChange={(event) => onChange(event.target.checked)}
      />
      <div>
        <strong>{label}</strong>
        {hint ? <span>{hint}</span> : null}
      </div>
    </label>
  );
}

export function CatalogClient({
  companyId,
  links,
  categories,
  priceLevels,
  presetTrader,
}: {
  companyId: string;
  links: CatalogLink[];
  categories: Array<{ id: string; name: string }>;
  priceLevels: Array<{ id: string; name: string }>;
  presetTrader: PresetTrader | null;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<CatalogLink | null>(null);
  const [form, setForm] = useState<Form>(emptyForm);
  const [traderOptions, setTraderOptions] = useState<PickerOption<TraderPick>[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [copied, setCopied] = useState("");

  // جاي من صفحة الزبون (?trader=...): افتح رابط جديد إلو مباشرة.
  useEffect(() => {
    if (!presetTrader) return;
    setTraderOptions([
      { id: presetTrader.id, label: presetTrader.name, hint: presetTrader.area, data: presetTrader },
    ]);
    setForm({
      ...emptyForm(),
      trader_id: presetTrader.id,
      price_level_id: presetTrader.price_level_id ?? "",
    });
    setEditing(null);
    setOpen(true);
  }, [presetTrader]);

  const set = <K extends keyof Form>(key: K, value: Form[K]) =>
    setForm((current) => ({ ...current, [key]: value }));

  function startNew() {
    setEditing(null);
    setForm(emptyForm());
    setMessage("");
    setOpen(true);
  }

  function startEdit(link: CatalogLink) {
    const trader = one(link.traders);
    if (link.trader_id && trader) {
      setTraderOptions([{ id: link.trader_id, label: trader.name, hint: trader.phone }]);
    }
    setEditing(link);
    setForm({
      title: link.title,
      trader_id: link.trader_id ?? "",
      show_prices: link.show_prices,
      price_level_id: link.price_level_id ?? "",
      show_description: link.show_description,
      show_images: link.show_images,
      stock_mode: link.stock_mode,
      hide_out_of_stock: link.hide_out_of_stock,
      category_ids: link.category_ids ?? [],
      allow_orders: link.allow_orders,
      expires_on: link.expires_at ? link.expires_at.slice(0, 10) : "",
    });
    setMessage("");
    setOpen(true);
  }

  async function pickTrader(id: string) {
    set("trader_id", id);
    if (!id) return;
    // سعر الرابط = مستوى سعر التاجر تلقائيًا (بتقدر تغيّرو).
    const { data } = await supabase
      .from("traders")
      .select("price_level_id")
      .eq("company_id", companyId)
      .eq("id", id)
      .maybeSingle();
    set("price_level_id", data?.price_level_id ?? "");
  }

  async function save() {
    setBusy(true);
    setMessage("");
    const { data, error } = await supabase.rpc("save_catalog_link", {
      target_company: companyId,
      target_link: editing?.id ?? null,
      settings: {
        title: form.title.trim(),
        trader_id: form.trader_id || null,
        show_prices: form.show_prices,
        price_level_id: form.show_prices ? form.price_level_id || null : null,
        show_description: form.show_description,
        show_images: form.show_images,
        stock_mode: form.stock_mode,
        hide_out_of_stock: form.hide_out_of_stock,
        category_ids: form.category_ids,
        allow_orders: form.allow_orders,
        // لآخر يوم الانتهاء بتوقيت دمشق.
        expires_at: form.expires_on ? `${form.expires_on}T23:59:59+03:00` : null,
      },
    });
    setBusy(false);
    if (error) {
      setMessage("ما قدرنا نحفظ الرابط. جرّب مرة تانية.");
      return;
    }
    setOpen(false);
    router.replace("/catalog");
    router.refresh();
    if (!editing && data) setCopied(`new:${data as string}`);
  }

  async function setActive(link: CatalogLink, active: boolean) {
    if (!active && !window.confirm(`توقيف "${link.title}"؟ اللي معو الرابط ما رح يقدر يفتحو.`)) return;
    const { error } = await supabase.rpc("set_catalog_link_active", {
      target_company: companyId,
      target_link: link.id,
      target_active: active,
    });
    if (error) {
      setMessage("ما قدرنا نغيّر حالة الرابط.");
      return;
    }
    router.refresh();
  }

  async function copy(link: CatalogLink) {
    try {
      await navigator.clipboard.writeText(catalogUrl(link.token));
      setCopied(link.id);
      window.setTimeout(() => setCopied(""), 2000);
    } catch {
      window.prompt("انسخ الرابط:", catalogUrl(link.token));
    }
  }

  function sendWhatsApp(link: CatalogLink) {
    const trader = one(link.traders);
    const text = `${trader ? `مرحبا ${trader.name}،\n` : ""}هاد كتالوج البضاعة عنا${
      link.show_prices ? " مع الأسعار" : ""
    }:\n${catalogUrl(link.token)}`;
    const number = waNumber(trader?.whatsapp || trader?.phone);
    window.open(
      `https://wa.me/${number}?text=${encodeURIComponent(text)}`,
      "_blank",
      "noopener,noreferrer",
    );
  }

  const justCreated = copied.startsWith("new:") ? links.find((link) => `new:${link.id}` === copied) : null;

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">كتالوج البضاعة</span>
          <h2>روابط الكتالوج</h2>
          <p className="muted">
            كل رابط إلو إعداداتو. رابط عام للكل، أو رابط خاص لتاجر بأسعار مستواه. الكلفة ما بتطلع أبدًا.
          </p>
        </div>
        <button type="button" className="primaryButton" onClick={startNew}>
          + رابط جديد
        </button>
      </div>

      {message && !open ? <div className="toastError">{message}</div> : null}

      {justCreated ? (
        <section className="panel panelPad" style={{ marginBottom: 14, borderColor: "rgba(47,202,158,.4)" }}>
          <strong>✅ الرابط جاهز: {justCreated.title}</strong>
          <div className="rowActions" style={{ marginTop: 10 }}>
            <button type="button" className="primaryButton" onClick={() => sendWhatsApp(justCreated)}>
              ابعت عالواتساب
            </button>
            <button type="button" className="softButton" onClick={() => void copy(justCreated)}>
              نسخ الرابط
            </button>
            <a className="softButton" href={`/c/${justCreated.token}`} target="_blank" rel="noreferrer">
              شوف متل التاجر
            </a>
          </div>
        </section>
      ) : null}

      <section className="panel">
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>الرابط</th>
                <th>شو بيبين</th>
                <th>فتحوه</th>
                <th>الحالة</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {links.map((link) => {
                const trader = one(link.traders);
                const level = priceLevels.find((row) => row.id === link.price_level_id)?.name;
                const expired = link.expires_at ? new Date(link.expires_at) < new Date() : false;
                return (
                  <tr key={link.id} style={{ opacity: link.active && !expired ? 1 : 0.55 }}>
                    <td>
                      <strong>{link.title}</strong>
                      <div className="muted">{trader ? `خاص لـ ${trader.name}` : "عام لكل التجار"}</div>
                    </td>
                    <td>
                      <div className="rowActions">
                        <span className={`chip ${link.show_prices ? "green" : "gray"}`}>
                          {link.show_prices ? `سعر ${level ?? "عادي"}` : "بلا أسعار"}
                        </span>
                        <span className="chip blue">{stockLabels[link.stock_mode]}</span>
                        {link.show_images ? <span className="chip gray">صور</span> : null}
                        {link.show_description ? <span className="chip gray">شرح</span> : null}
                        {link.category_ids?.length ? (
                          <span className="chip gray">
                            {link.category_ids
                              .map((id) => categories.find((row) => row.id === id)?.name)
                              .filter(Boolean)
                              .join("، ")}
                          </span>
                        ) : null}
                        {link.allow_orders ? <span className="chip orange">بيقبل طلبات</span> : null}
                      </div>
                    </td>
                    <td>
                      {formatQty(link.view_count)} مرة
                      {link.last_viewed_at ? (
                        <div className="muted">
                          آخر مرة {formatDate(link.last_viewed_at)}
                        </div>
                      ) : null}
                    </td>
                    <td>
                      {!link.active ? (
                        <span className="chip gray">موقوف</span>
                      ) : expired ? (
                        <span className="chip orange">انتهى</span>
                      ) : (
                        <span className="chip green">شغّال</span>
                      )}
                    </td>
                    <td>
                      <div className="rowActions">
                        {link.active && !expired ? (
                          <>
                            <button type="button" className="primaryButton" onClick={() => sendWhatsApp(link)}>
                              واتساب
                            </button>
                            <button type="button" className="softButton" onClick={() => void copy(link)}>
                              {copied === link.id ? "انتسخ ✓" : "نسخ"}
                            </button>
                            <a className="softButton" href={`/c/${link.token}`} target="_blank" rel="noreferrer">
                              فتح
                            </a>
                          </>
                        ) : null}
                        <button type="button" className="softButton" onClick={() => startEdit(link)}>
                          تعديل
                        </button>
                        {link.active ? (
                          <button type="button" className="dangerButton" onClick={() => void setActive(link, false)}>
                            توقيف
                          </button>
                        ) : (
                          <button type="button" className="softButton" onClick={() => void setActive(link, true)}>
                            تفعيل
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {!links.length ? (
            <div className="empty">
              <h3>ما في روابط لسا</h3>
              <p>اعمل رابط، واختار شو يبين فيه، وابعتو للتاجر عالواتساب.</p>
            </div>
          ) : null}
        </div>
      </section>

      {open ? (
        <div className="modalOverlay" onClick={() => setOpen(false)}>
          <div className="modal" onClick={(event) => event.stopPropagation()}>
            <div className="modalHeader">
              <div>
                <span className="eyebrow">كتالوج</span>
                <h2>{editing ? "تعديل الرابط" : "رابط جديد"}</h2>
              </div>
              <button type="button" className="closeButton" onClick={() => setOpen(false)}>
                ✕
              </button>
            </div>

            <div className="formGrid">
              <label className="field">
                <span>لمين؟ (اختياري)</span>
                <SearchPicker
                  value={form.trader_id}
                  options={traderOptions}
                  onChange={(id) => void pickTrader(id)}
                  onSearch={(term) => searchTraders(supabase, companyId, term)}
                  placeholder="فاضي = رابط عام للكل"
                />
              </label>
              <label className="field">
                <span>اسم الرابط</span>
                <input
                  value={form.title}
                  maxLength={120}
                  placeholder={form.trader_id ? "تلقائي: كتالوج + اسم التاجر" : "كتالوج البضاعة"}
                  onChange={(event) => set("title", event.target.value)}
                />
              </label>

              <div className="field full">
                <span>شو يبين بالكتالوج؟</span>
                <div className="quickList">
                  <Toggle
                    checked={form.show_prices}
                    onChange={(value) => set("show_prices", value)}
                    label="الأسعار"
                    hint="إذا طفيتها، بيشوف الأصناف بلا أسعار"
                  />
                  {form.show_prices ? (
                    <label className="field" style={{ paddingInlineStart: 30 }}>
                      <span>أي سعر؟</span>
                      <select
                        value={form.price_level_id}
                        onChange={(event) => set("price_level_id", event.target.value)}
                      >
                        <option value="">سعر البيع العادي</option>
                        {priceLevels.map((level) => (
                          <option key={level.id} value={level.id}>
                            سعر {level.name}
                          </option>
                        ))}
                      </select>
                    </label>
                  ) : null}
                  <Toggle
                    checked={form.show_images}
                    onChange={(value) => set("show_images", value)}
                    label="الصور"
                  />
                  <Toggle
                    checked={form.show_description}
                    onChange={(value) => set("show_description", value)}
                    label="الشرح"
                    hint="الشرح بينكتب بصفحة الأصناف لكل صنف"
                  />
                </div>
              </div>

              <label className="field">
                <span>المخزون</span>
                <select
                  value={form.stock_mode}
                  onChange={(event) => set("stock_mode", event.target.value as StockMode)}
                >
                  {(Object.keys(stockLabels) as StockMode[]).map((mode) => (
                    <option key={mode} value={mode}>
                      {stockLabels[mode]}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>ينتهي بتاريخ (اختياري)</span>
                <input type="date" value={form.expires_on} onChange={(event) => set("expires_on", event.target.value)} />
              </label>

              <div className="field full">
                <Toggle
                  checked={form.hide_out_of_stock}
                  onChange={(value) => set("hide_out_of_stock", value)}
                  label="خبّي الأصناف اللي خلصت"
                />
              </div>

              {categories.length ? (
                <div className="field full">
                  <span>التصنيفات (ولا وحدة = كل البضاعة)</span>
                  <div className="rowActions">
                    {categories.map((category) => {
                      const checked = form.category_ids.includes(category.id);
                      return (
                        <label key={category.id} className={`chip ${checked ? "green" : "gray"}`} style={{ cursor: "pointer", fontSize: 11 }}>
                          <input
                            type="checkbox"
                            checked={checked}
                            style={{ display: "none" }}
                            onChange={() =>
                              set(
                                "category_ids",
                                checked
                                  ? form.category_ids.filter((id) => id !== category.id)
                                  : [...form.category_ids, category.id],
                              )
                            }
                          />
                          {checked ? "✓ " : ""}
                          {category.name}
                        </label>
                      );
                    })}
                  </div>
                </div>
              ) : null}

              <div className="field full">
                <Toggle
                  checked={form.allow_orders}
                  onChange={(value) => set("allow_orders", value)}
                  label="التاجر بيقدر يطلب من الكتالوج"
                  hint="بيختار أصناف وبيكتب رقم تلفونو (لازم يكون مسجّل عنا)، والطلب بينزل عندك بعروض الأسعار لتراجعو"
                />
              </div>
            </div>

            {message ? (
              <div className="toastError" style={{ marginTop: 12 }}>
                {message}
              </div>
            ) : null}

            <div className="modalActions">
              <button type="button" className="softButton" onClick={() => setOpen(false)}>
                إلغاء
              </button>
              <button type="button" className="primaryButton" disabled={busy} onClick={() => void save()}>
                {busy ? "عم نحفظ..." : editing ? "حفظ" : "اعمل الرابط"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
