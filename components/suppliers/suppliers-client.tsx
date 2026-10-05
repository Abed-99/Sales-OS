"use client";
import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { anyPhoneState, normalizeAnyPhone } from "@/lib/phone";
import { Icons } from "@/components/icons";
import { NumberInput } from "@/components/number-input";
import { matchesSearch } from "@/lib/search";
import { phoneText, nameInitial } from "@/lib/format";
type Row = {
  id: string;
  name: string;
  contact_name: string | null;
  phone: string | null;
  whatsapp: string | null;
  address: string | null;
  notes: string | null;
  active: boolean;
  payment_terms_days: number;
  supplier_type?: string | null;
  country?: string | null;
  currency?: string | null;
  created_at: string;
};

const supplierTypes: Record<string, string> = {
  factory: "مصنع",
  agent: "وكيل",
  wholesaler: "تاجر جملة",
  local: "مورد محلي",
  other: "غير ذلك",
};
const empty = {
  name: "",
  contact_name: "",
  phone: "",
  whatsapp: "",
  address: "",
  notes: "",
  active: true,
  payment_terms_days: "0",
  supplier_type: "",
  country: "",
  currency: "",
};
function friendlyError(error: { code?: string; message?: string } | null) {
  const message = error?.message?.toLowerCase() ?? "";
  if (
    error?.code === "42501" ||
    message.includes("not allowed") ||
    message.includes("permission")
  ) {
    return "ما عندك صلاحية لهالعملية.";
  }
  if (error?.code === "23505" || message.includes("duplicate")) {
    return "في مورد تاني بنفس البيانات.";
  }
  return "ما قدرنا نحفظ. تأكد من البيانات وجرّب مرة تانية.";
}

export function SuppliersClient({
  companyId,
  initialRows,
  initialError,
  canCreate,
  canUpdate,
  canArchive,
}: {
  companyId: string;
  initialRows: Row[];
  initialError: string | null;
  canCreate: boolean;
  canUpdate: boolean;
  canArchive: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [rows, setRows] = useState(initialRows);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Row | null>(null);
  const [f, setF] = useState(empty);
  const [msg, setMsg] = useState(initialError || "");
  const [saving, setSaving] = useState(false);
  const filtered = useMemo(
    () =>
      rows.filter(
        (r) =>
          !q ||
          matchesSearch(
            [
              r.name,
              r.contact_name,
              r.phone,
              r.address,
              r.country,
              supplierTypes[r.supplier_type ?? ""],
            ].join(" "),
            q,
          ),
      ),
    [rows, q],
  );
  function add() {
    setEditing(null);
    setF(empty);
    setMsg("");
    setOpen(true);
  }
  function edit(r: Row) {
    setEditing(r);
    setF({
      name: r.name,
      contact_name: r.contact_name || "",
      phone: r.phone || "",
      whatsapp: r.whatsapp || "",
      address: r.address || "",
      notes: r.notes || "",
      active: r.active,
      payment_terms_days: String(r.payment_terms_days ?? 0),
      supplier_type: r.supplier_type ?? "",
      country: r.country ?? "",
      currency: r.currency ?? "",
    });
    setOpen(true);
    setMsg("");
  }
  async function save(e: React.FormEvent) {
    e.preventDefault();
    const phone = f.phone ? normalizeAnyPhone(f.phone) : null,
      wa = f.whatsapp ? normalizeAnyPhone(f.whatsapp) : null;
    if (!f.name.trim()) return setMsg("اسم المورد مطلوب");
    if (f.phone && !phone)
      return setMsg("رقم الهاتف غير صحيح. اكتب رقم سوري أو رقم دولي بيبلّش بـ +");
    if (f.whatsapp && !wa)
      return setMsg("رقم الواتساب غير صحيح. اكتب رقم سوري أو رقم دولي بيبلّش بـ +");
    const paymentTerms = Number(f.payment_terms_days || 0);
    if (!Number.isInteger(paymentTerms) || paymentTerms < 0 || paymentTerms > 3650)
      return setMsg("مهلة الدفع لازم تكون عدد أيام بين 0 و 3650");
    setSaving(true);
    const payload = {
      company_id: companyId,
      name: f.name.trim(),
      contact_name: f.contact_name.trim() || null,
      phone,
      whatsapp: wa,
      address: f.address.trim() || null,
      notes: f.notes.trim() || null,
      active: f.active,
      payment_terms_days: paymentTerms,
      supplier_type: f.supplier_type || null,
      country: f.country.trim() || null,
      currency: /^[A-Za-z]{3}$/.test(f.currency.trim()) ? f.currency.trim().toUpperCase() : null,
    };
    if (editing) {
      const { data, error } = await supabase
        .from("suppliers")
        .update(payload)
        .eq("id", editing.id)
        .select()
        .single();
      if (error) {
        setSaving(false);
        setMsg(friendlyError(error));
        return;
      }
      setRows((x) => x.map((a) => (a.id === editing.id ? (data as Row) : a)));
    } else {
      const { data, error } = await supabase.from("suppliers").insert(payload).select().single();
      if (error) {
        setSaving(false);
        setMsg(friendlyError(error));
        return;
      }
      setRows((x) => [data as Row, ...x]);
    }
    setSaving(false);
    setOpen(false);
    router.refresh();
  }
  // ما في حذف: المورد إله فواتير ودفعات، فمنوقّفه بس وبيضل حسابه محفوظ.
  async function toggleActive(r: Row) {
    const next = !r.active;
    if (
      !confirm(next ? `إعادة تفعيل ${r.name}؟` : `إيقاف ${r.name}؟ حسابه وفواتيره بيضلوا محفوظين.`)
    )
      return;
    const { error } = await supabase
      .from("suppliers")
      .update({ active: next })
      .eq("id", r.id)
      .eq("company_id", companyId);
    if (error) return setMsg(friendlyError(error));
    setRows((x) => x.map((a) => (a.id === r.id ? { ...a, active: next } : a)));
    router.refresh();
  }
  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">مصادر الشراء</span>
          <h2>الموردين</h2>
          <p className="muted">سجل كل مورد، بياناته، وبعدها اربط أسعار الأصناف فيه.</p>
        </div>
        {canCreate && (
          <button className="primaryButton" onClick={add}>
            <Icons.plus size={15} /> إضافة مورد
          </button>
        )}
      </div>
      {msg && !open && (
        <div className="toastError" style={{ marginBottom: 12 }}>
          {msg}
        </div>
      )}
      <section className="statsGrid">
        <Mini t="كل الموردين" v={rows.length} />
        <Mini t="نشطين" v={rows.filter((r) => r.active).length} />
        <Mini t="مع واتساب" v={rows.filter((r) => r.whatsapp).length} />
        <Mini t="موقوفين" v={rows.filter((r) => !r.active).length} />
      </section>
      <section className="panel" style={{ marginTop: 14 }}>
        <div className="filters">
          <div className="searchBox">
            <Icons.search size={16} />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="ابحث باسم المورد أو الرقم..."
            />
          </div>
          <div />
          <div />
          <div className="resultCount">{filtered.length} نتيجة</div>
        </div>
        {!filtered.length ? (
          <div className="empty">
            <Icons.store size={28} />
            <h3>ما في موردين</h3>
            <p>أضف أول مورد حتى نقدر نربط الأصناف وأسعار الشراء.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>المورد</th>
                  <th>الهاتف</th>
                  <th>العنوان</th>
                  <th>شروط الدفع</th>
                  <th>الحالة</th>
                  <th>إجراءات</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <div className="merchant">
                        <div className="merchantLogo">{nameInitial(r.name)}</div>
                        <div>
                          <Link href={`/suppliers/${r.id}`}>
                            <strong>{r.name}</strong>
                          </Link>
                          <span>
                            {[supplierTypes[r.supplier_type ?? ""], r.country, r.contact_name]
                              .filter(Boolean)
                              .join(" • ") || "—"}
                          </span>
                        </div>
                      </div>
                    </td>
                    <td>
                      {r.whatsapp ? (
                        <a
                          className="softButton"
                          target="_blank"
                          rel="noreferrer"
                          href={`https://wa.me/${r.whatsapp.replace(/\D/g, "")}`}
                        >
                          <Icons.whatsapp size={13} /> {phoneText(r.whatsapp)}
                        </a>
                      ) : (
                        phoneText(r.phone) || "—"
                      )}
                    </td>
                    <td>{r.address || "—"}</td>
                    <td>{r.payment_terms_days > 0 ? `${r.payment_terms_days} يوم` : "نقدي"}</td>
                    <td>
                      <span className={`chip ${r.active ? "green" : "gray"}`}>
                        {r.active ? "نشط" : "موقوف"}
                      </span>
                    </td>
                    <td>
                      <div className="rowActions">
                        <Link className="softButton" href={`/suppliers/${r.id}`}>
                          الحساب
                        </Link>
                        {canUpdate && (
                          <button className="softButton" onClick={() => edit(r)}>
                            <Icons.edit size={13} /> تعديل
                          </button>
                        )}
                        {canArchive && (
                          <button
                            className={r.active ? "dangerButton" : "softButton"}
                            onClick={() => toggleActive(r)}
                          >
                            {r.active ? "إيقاف" : "تفعيل"}
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
      {open && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">{editing ? "تعديل" : "مورد جديد"}</span>
                <h2>{editing ? editing.name : "إضافة مورد"}</h2>
              </div>
              <button className="closeButton" onClick={() => setOpen(false)}>
                ×
              </button>
            </div>
            <form onSubmit={save}>
              <div className="formGrid">
                <F l="اسم المورد *" v={f.name} s={(v) => setF((x) => ({ ...x, name: v }))} />
                <F
                  l="اسم الشخص المسؤول"
                  v={f.contact_name}
                  s={(v) => setF((x) => ({ ...x, contact_name: v }))}
                />
                <Phone l="رقم الهاتف" v={f.phone} s={(v) => setF((x) => ({ ...x, phone: v }))} />
                <Phone l="واتساب" v={f.whatsapp} s={(v) => setF((x) => ({ ...x, whatsapp: v }))} />
                <label className="field">
                  <span>نوع المورد</span>
                  <select
                    value={f.supplier_type}
                    onChange={(e) => setF((x) => ({ ...x, supplier_type: e.target.value }))}
                  >
                    <option value="">غير محدد</option>
                    {Object.entries(supplierTypes).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>
                <F l="البلد" v={f.country} s={(v) => setF((x) => ({ ...x, country: v }))} />
                <label className="field">
                  <span>عملة التعامل</span>
                  <select
                    value={
                      ["", "USD", "SYP", "CNY", "EUR", "TRY", "AED"].includes(f.currency)
                        ? f.currency
                        : ""
                    }
                    onChange={(e) => setF((x) => ({ ...x, currency: e.target.value }))}
                  >
                    <option value="">غير محددة</option>
                    <option value="USD">USD دولار</option>
                    <option value="CNY">CNY يوان صيني</option>
                    <option value="SYP">SYP ليرة سورية</option>
                    <option value="EUR">EUR يورو</option>
                    <option value="TRY">TRY ليرة تركية</option>
                    <option value="AED">AED درهم</option>
                  </select>
                </label>
                <F l="العنوان" v={f.address} s={(v) => setF((x) => ({ ...x, address: v }))} full />
                {canArchive && (
                  <label className="field">
                    <span>الحالة</span>
                    <select
                      value={f.active ? "yes" : "no"}
                      onChange={(e) => setF((x) => ({ ...x, active: e.target.value === "yes" }))}
                    >
                      <option value="yes">نشط</option>
                      <option value="no">موقوف</option>
                    </select>
                  </label>
                )}
                <label className="field">
                  <span>مهلة الدفع (يوم)</span>
                  <NumberInput
                    min="0"
                    max="3650"
                    step="1"
                    value={f.payment_terms_days}
                    onChange={(e) => setF((x) => ({ ...x, payment_terms_days: e.target.value }))}
                  />
                  <small className="helpText">0 يعني الدفع مستحق بنفس اليوم.</small>
                </label>
                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={4}
                    value={f.notes}
                    onChange={(e) => setF((x) => ({ ...x, notes: e.target.value }))}
                  />
                </label>
              </div>
              {msg && (
                <div className="toastError" style={{ marginTop: 12 }}>
                  {msg}
                </div>
              )}
              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setOpen(false)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "حفظ"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}
function F({
  l,
  v,
  s,
  full = false,
}: {
  l: string;
  v: string;
  s: (v: string) => void;
  full?: boolean;
}) {
  return (
    <label className={`field ${full ? "full" : ""}`}>
      <span>{l}</span>
      <input value={v} onChange={(e) => s(e.target.value)} />
    </label>
  );
}
function Phone({ l, v, s }: { l: string; v: string; s: (v: string) => void }) {
  const st = anyPhoneState(v);
  return (
    <label className="field">
      <span>{l}</span>
      <input
        dir="ltr"
        value={v}
        onChange={(e) => s(e.target.value)}
        placeholder="0944123456 أو +86..."
      />
      <small
        className={st === "valid" ? "validText" : st === "invalid" ? "invalidText" : "helpText"}
      >
        {st === "valid"
          ? "✓ صحيح"
          : st === "invalid"
            ? "رقم غير صحيح"
            : "رقم سوري أو دولي، اختياري"}
      </small>
    </label>
  );
}
function Mini({ t, v }: { t: string; v: number }) {
  return (
    <div className="statCard">
      <div className="statLabel">{t}</div>
      <div className="statValue">{v}</div>
    </div>
  );
}
