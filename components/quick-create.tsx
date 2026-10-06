"use client";

import { useCallback, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

import { NumberInput } from "@/components/number-input";
import type { PickerOption } from "@/components/search-picker";
import { anyPhoneState, normalizeAnyPhone } from "@/lib/phone";
import { productOption, type ProductPick, type SupplierPick, type TraderPick } from "@/lib/pickers";

export type QuickCreateKind = "trader" | "supplier" | "product";

type Pending = {
  kind: QuickCreateKind;
  resolve: (option: PickerOption | null) => void;
};

const titles: Record<QuickCreateKind, string> = {
  trader: "زبون جديد",
  supplier: "مورد جديد",
  product: "صنف جديد",
};

function friendly(kind: QuickCreateKind, message: string) {
  const m = message.toLowerCase();
  if (m.includes("not allowed") || m.includes("permission") || m.includes("row-level security")) {
    return "ما عندك صلاحية تضيف " + (kind === "trader" ? "زبائن" : kind === "supplier" ? "موردين" : "أصناف") + ".";
  }
  if (m.includes("مستخدم عند تاجر") || m.includes("duplicate")) return "الرقم مستخدم عند زبون تاني.";
  if (m.includes("sale price")) return "سعر البيع غلط.";
  return "ما قدرنا نحفظ. راجع المعلومات وحاول مرة تانية.";
}

/**
 * إضافة زبون أو مورد أو صنف من جوّا الفاتورة بدون ما تطلع منها.
 * `create` بترجّع الخيار الجديد (أو null إذا سكّر النافذة)، ومربع البحث بيختارو لحالو.
 * باقي التفاصيل (الموقع، حد الدين، الصورة...) بتنكمّل بعدين من صفحتو.
 */
export function useQuickCreate(supabase: SupabaseClient, companyId: string) {
  const [pending, setPending] = useState<Pending | null>(null);
  const pendingRef = useRef<Pending | null>(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [area, setArea] = useState("");
  const [price, setPrice] = useState("");
  const [unit, setUnit] = useState("قطعة");
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  const create = useCallback(<T,>(kind: QuickCreateKind, term: string) => {
    pendingRef.current?.resolve(null);
    setName(term);
    setPhone("");
    setArea("");
    setPrice("");
    setUnit("قطعة");
    setMessage("");
    return new Promise<PickerOption<T> | null>((resolve) => {
      const next: Pending = { kind, resolve: resolve as Pending["resolve"] };
      pendingRef.current = next;
      setPending(next);
    });
  }, []);

  function finish(option: PickerOption | null) {
    pendingRef.current?.resolve(option);
    pendingRef.current = null;
    setPending(null);
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    // النافذة جوّا فورم الفاتورة، فما لازم الحفظ يبعت الفاتورة كمان.
    event.stopPropagation();
    if (!pending) return;
    setMessage("");

    const cleanName = name.trim();
    if (!cleanName) return setMessage("الاسم مطلوب.");

    const normalizedPhone = phone.trim() ? normalizeAnyPhone(phone) : null;
    if (pending.kind !== "product" && phone.trim() && !normalizedPhone) {
      return setMessage("الرقم غلط. اكتب رقم سوري أو رقم دولي بيبلّش بـ +");
    }

    setSaving(true);
    try {
      if (pending.kind === "trader") {
        const { data, error } = await supabase
          .from("traders")
          .insert({
            company_id: companyId,
            name: cleanName,
            phone: normalizedPhone,
            whatsapp: normalizedPhone,
            area: area.trim() || null,
          })
          .select("id,name,area,phone")
          .single();
        if (error) return setMessage(friendly("trader", error.message));
        const row = data as TraderPick;
        finish({ id: row.id, label: row.name, hint: [row.area, row.phone].filter(Boolean).join(" • ") || null, data: row });
        return;
      }

      if (pending.kind === "supplier") {
        const { data, error } = await supabase
          .from("suppliers")
          .insert({ company_id: companyId, name: cleanName, phone: normalizedPhone, whatsapp: normalizedPhone })
          .select("id,name")
          .single();
        if (error) return setMessage(friendly("supplier", error.message));
        const row = data as SupplierPick;
        finish({ id: row.id, label: row.name, hint: null, data: row });
        return;
      }

      const salePrice = price.trim() === "" ? 0 : Number(price);
      if (!Number.isFinite(salePrice) || salePrice < 0) return setMessage("سعر البيع غلط.");

      const { data: id, error } = await supabase.rpc("save_product_with_supplier_prices", {
        target_company: companyId,
        target_product: null,
        product_name: cleanName,
        product_sku: null,
        product_brand: null,
        target_category: null,
        product_unit: unit.trim() || "قطعة",
        product_sale_price: salePrice,
        product_minimum_sale_price: null,
        product_image_url: null,
        product_active: true,
        supplier_prices_payload: [],
      });
      if (error) return setMessage(friendly("product", error.message));
      const row: ProductPick = {
        id: id as string,
        name: cleanName,
        sku: null,
        unit: unit.trim() || "قطعة",
        sale_price: salePrice,
        active: true,
        pack_size: null,
        pack_unit: null,
        barcode: null,
      };
      finish(productOption(row) as PickerOption);
    } finally {
      setSaving(false);
    }
  }

  // برّا فورم الفاتورة (فورم جوّا فورم ما بيشتغل).
  const modal = pending && typeof document !== "undefined" ? createPortal(
    <div className="modalOverlay" style={{ zIndex: 1250 }}>
      <section className="modal" role="dialog" aria-modal="true" aria-labelledby="quick-create-title" style={{ maxWidth: 460 }}>
        <div className="modalHeader">
          <div>
            <span className="eyebrow">إضافة سريعة</span>
            <h2 id="quick-create-title">{titles[pending.kind]}</h2>
          </div>
          <button type="button" className="closeButton" aria-label="إغلاق" disabled={saving} onClick={() => finish(null)}>
            ×
          </button>
        </div>

        <form className="authForm" onSubmit={save}>
          <label className="field">
            <span>الاسم *</span>
            <input value={name} onChange={(event) => setName(event.target.value)} autoFocus required />
          </label>

          {pending.kind === "product" ? (
            <div className="formGrid">
              <label className="field">
                <span>سعر البيع</span>
                <NumberInput value={price} min="0" step="any" placeholder="0" onChange={(event) => setPrice(event.target.value)} />
              </label>
              <label className="field">
                <span>الوحدة</span>
                <input value={unit} onChange={(event) => setUnit(event.target.value)} />
              </label>
            </div>
          ) : (
            <label className="field">
              <span>الهاتف / واتساب</span>
              <input
                dir="ltr"
                inputMode="tel"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="09xxxxxxxx"
              />
              {phone.trim() && anyPhoneState(phone) === "invalid" ? (
                <small className="invalidText">الرقم مش مظبوط</small>
              ) : null}
            </label>
          )}

          {pending.kind === "trader" ? (
            <label className="field">
              <span>المنطقة</span>
              <input value={area} onChange={(event) => setArea(event.target.value)} />
            </label>
          ) : null}

          <small className="helpText">
            {pending.kind === "product"
              ? "الباركود والصورة والكرتونة بتكمّلهن بعدين من صفحة الأصناف."
              : pending.kind === "trader"
                ? "الموقع وحد الدين بتكمّلهن بعدين من صفحة العملاء."
                : "باقي التفاصيل بتكمّلها بعدين من صفحة الموردين."}
          </small>

          {message ? (
            <div className="toastError" role="alert">
              {message}
            </div>
          ) : null}

          <div className="modalActions">
            <button type="button" className="softButton" disabled={saving} onClick={() => finish(null)}>
              رجوع
            </button>
            <button className="primaryButton" disabled={saving}>
              {saving ? "عم نحفظ..." : "حفظ واختيار"}
            </button>
          </div>
        </form>
      </section>
    </div>,
    document.body,
  ) : null;

  return { create, modal };
}
