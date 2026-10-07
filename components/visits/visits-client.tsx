"use client";

import dynamic from "next/dynamic";
import { useMemo, useState } from "react";
import type { FormEvent } from "react";

import { Icons } from "@/components/icons";
import { LocationPicker } from "@/components/map/location-picker";
import { formatNumber } from "@/lib/format";
import { googleMapsSearchLink, isShortMapLink, parseLatLng } from "@/lib/geo-link";
import { anyPhoneState, normalizeAnyPhone } from "@/lib/phone";
import { googleMapsRouteLinks, planRoute, type LatLng } from "@/lib/route";
import { createClient } from "@/lib/supabase/client";

import {
  STATUS_CHIPS,
  STATUS_LABELS,
  type LocatedShop,
  type VisitShop,
  type VisitStatus,
} from "./shared";

export type { VisitShop } from "./shared";

const VisitsMap = dynamic(() => import("./visits-map").then((module) => module.VisitsMap), {
  ssr: false,
  loading: () => <p className="muted">عم نحمّل الخريطة...</p>,
});

type Form = {
  id: string | null;
  name: string;
  area: string;
  phone: string;
  notes: string;
  latitude: number | null;
  longitude: number | null;
  link: string;
};

const emptyForm = (area = ""): Form => ({
  id: null,
  name: "",
  area,
  phone: "",
  notes: "",
  latitude: null,
  longitude: null,
  link: "",
});

function located(shop: VisitShop): LocatedShop | null {
  if (shop.latitude == null || shop.longitude == null) return null;
  return { ...shop, lat: Number(shop.latitude), lng: Number(shop.longitude) };
}

function friendly(message: string) {
  const m = message.toLowerCase();
  if (m.includes("not allowed") || m.includes("permission") || m.includes("row-level security"))
    return "ما عندك صلاحية لهالشي.";
  if (m.includes("مستخدم عند تاجر") || m.includes("duplicate")) return "الرقم مستخدم عند محل أو زبون تاني.";
  return "ما قدرنا نحفظ. حاول مرة تانية.";
}

export function VisitsClient({
  companyId,
  initialShops,
  loadError,
  canCreate,
  canEdit,
}: {
  companyId: string;
  initialShops: VisitShop[];
  loadError: string | null;
  canCreate: boolean;
  canEdit: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const [shops, setShops] = useState(initialShops);
  const [message, setMessageState] = useState({ text: loadError ?? "", error: Boolean(loadError) });
  const setMessage = (text: string, error = true) => setMessageState({ text, error });

  // الطريق
  const [include, setInclude] = useState<VisitStatus[]>(["new", "interested"]);
  const [me, setMe] = useState<LatLng>();
  const [route, setRoute] = useState<{ stops: LocatedShop[]; totalKm: number } | null>(null);
  const [locating, setLocating] = useState(false);

  // إضافة / تعديل
  const [form, setForm] = useState<Form | null>(null);
  const [formMessage, setFormMessage] = useState("");
  const [saving, setSaving] = useState(false);
  const [reading, setReading] = useState(false);
  const [bulk, setBulk] = useState<{ text: string; area: string } | null>(null);
  const [busyId, setBusyId] = useState("");

  const locatedShops = useMemo(
    () => shops.map(located).filter((shop): shop is LocatedShop => Boolean(shop)),
    [shops],
  );
  const candidates = locatedShops.filter((shop) => include.includes(shop.status));
  const noLocation = shops.filter((shop) => !located(shop));
  const counts = {
    new: shops.filter((shop) => shop.status === "new").length,
    contacted: shops.filter((shop) => shop.status === "contacted").length,
    interested: shops.filter((shop) => shop.status === "interested").length,
  };

  function plan(start?: LatLng) {
    if (!candidates.length) {
      setMessage("ما في محلات إلها موقع ضمن اللي اخترتهن. حدّد مواقع المحلات أول.");
      return;
    }
    setMessage("");
    setRoute(planRoute(candidates, start));
  }

  function planFromMe() {
    if (!navigator.geolocation) {
      plan();
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const point = { lat: position.coords.latitude, lng: position.coords.longitude };
        setMe(point);
        setLocating(false);
        plan(point);
      },
      () => {
        setLocating(false);
        setMessage("ما قدرنا نعرف موقعك، فرتّبنا الطريق من أول محل. Google Maps بيبلّش من مكانك.", false);
        plan();
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  const googleLinks = route ? googleMapsRouteLinks(route.stops, me) : [];

  async function setStatus(shop: VisitShop, status: VisitStatus | "customer" | "inactive") {
    setBusyId(shop.id);
    setMessage("");
    const { error } = await supabase
      .from("traders")
      .update({ status })
      .eq("company_id", companyId)
      .eq("id", shop.id);
    setBusyId("");
    if (error) return setMessage(friendly(error.message));

    if (status === "customer" || status === "inactive") {
      setShops((current) => current.filter((row) => row.id !== shop.id));
      setRoute((current) =>
        current ? { ...current, stops: current.stops.filter((stop) => stop.id !== shop.id) } : current,
      );
    } else {
      setShops((current) => current.map((row) => (row.id === shop.id ? { ...row, status } : row)));
    }
  }

  function openEdit(shop: VisitShop) {
    const point = located(shop);
    setForm({
      id: shop.id,
      name: shop.name,
      area: shop.area ?? "",
      phone: shop.phone ?? "",
      notes: shop.notes ?? "",
      latitude: point?.lat ?? null,
      longitude: point?.lng ?? null,
      link: "",
    });
    setFormMessage("");
  }

  async function resolveLocation(text: string): Promise<LatLng | null> {
    const direct = parseLatLng(text);
    if (direct) return direct;
    if (!isShortMapLink(text)) return null;
    try {
      const response = await fetch("/api/geo/resolve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: text }),
      });
      const data = (await response.json()) as Partial<LatLng>;
      return response.ok && data.lat != null && data.lng != null ? { lat: data.lat, lng: data.lng } : null;
    } catch {
      return null;
    }
  }

  async function readLink() {
    if (!form) return;
    const text = form.link.trim();
    if (!text) return;
    setFormMessage("");

    const direct = parseLatLng(text);
    if (direct) {
      setForm({ ...form, latitude: direct.lat, longitude: direct.lng, link: "" });
      return;
    }

    if (!isShortMapLink(text)) {
      setFormMessage("ما لقينا موقع بهالرابط. انسخ رابط المشاركة من Google Maps أو الإحداثيات.");
      return;
    }

    setReading(true);
    try {
      const response = await fetch("/api/geo/resolve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: text }),
      });
      const data = (await response.json()) as Partial<LatLng>;
      if (!response.ok || data.lat == null || data.lng == null) {
        setFormMessage("ما قدرنا نقرأ الموقع من الرابط. جرّب تكبس على مكان المحل بالخريطة.");
        return;
      }
      setForm((current) => (current ? { ...current, latitude: data.lat!, longitude: data.lng!, link: "" } : current));
    } catch {
      setFormMessage("ما قدرنا نفتح الرابط. تأكد من الإنترنت.");
    } finally {
      setReading(false);
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form) return;
    setFormMessage("");

    const name = form.name.trim();
    if (!name) return setFormMessage("اسم المحل مطلوب.");
    const phone = form.phone.trim() ? normalizeAnyPhone(form.phone) : null;
    if (form.phone.trim() && !phone) return setFormMessage("الرقم غلط. اكتب رقم سوري أو دولي بيبلّش بـ +");

    const payload = {
      name,
      area: form.area.trim() || null,
      phone,
      whatsapp: phone,
      notes: form.notes.trim() || null,
      latitude: form.latitude,
      longitude: form.longitude,
    };

    setSaving(true);
    try {
      if (form.id) {
        const { data, error } = await supabase
          .from("traders")
          .update(payload)
          .eq("company_id", companyId)
          .eq("id", form.id)
          .select("id,name,area,address,phone,whatsapp,latitude,longitude,status,notes")
          .single();
        if (error) return setFormMessage(friendly(error.message));
        setShops((current) => current.map((row) => (row.id === form.id ? (data as VisitShop) : row)));
      } else {
        const { data, error } = await supabase
          .from("traders")
          .insert({ ...payload, company_id: companyId })
          .select("id,name,area,address,phone,whatsapp,latitude,longitude,status,notes")
          .single();
        if (error) return setFormMessage(friendly(error.message));
        setShops((current) => [data as VisitShop, ...current]);
      }
      setRoute(null);
      setForm(null);
    } finally {
      setSaving(false);
    }
  }

  async function saveBulk(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!bulk) return;
    const byName = new Map(shops.map((shop) => [shop.name.trim(), shop]));

    // كل سطر محل: "الاسم"، "الاسم - المنطقة"، ومعو (اختياري) رابط Google Maps أو إحداثيات بأي مكان بالسطر.
    const lines = bulk.text
      .split("\n")
      .map((line) => line.replace(/^\s*(\d+[.)-]|[•*-])\s*/, "").trim())
      .filter(Boolean)
      .map((line) => {
        const link =
          line.match(/https?:\/\/\S+/)?.[0] ?? line.match(/-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+/)?.[0] ?? "";
        const rest = line.replace(link, "").replace(/[\s:،,–—-]+$/, "").trim();
        const [name, area] = rest.split(/\s+[-–—]\s+/);
        return { name: (name ?? "").trim(), area: (area ?? bulk.area).trim() || null, link };
      })
      .filter((row) => row.name);

    if (!lines.length) return;

    setSaving(true);
    try {
      // المواقع أول (الروابط القصيرة بتنفتح وحدة وحدة).
      const located = await Promise.all(lines.map((row) => (row.link ? resolveLocation(row.link) : null)));
      const badLinks = lines.filter((row, index) => row.link && !located[index]).map((row) => row.name);

      // محل موجود ومعو رابط = منحدّث موقعو بس.
      const updates = lines
        .map((row, index) => ({ shop: byName.get(row.name), point: located[index] }))
        .filter((item): item is { shop: VisitShop; point: LatLng } => Boolean(item.shop && item.point));
      for (const { shop, point } of updates) {
        const { error } = await supabase
          .from("traders")
          .update({ latitude: point.lat, longitude: point.lng })
          .eq("company_id", companyId)
          .eq("id", shop.id);
        if (error) return setMessage(friendly(error.message));
      }

      const seen = new Set<string>();
      const inserts = lines
        .map((row, index) => ({ row, point: located[index] }))
        .filter(({ row }) => !byName.has(row.name) && !seen.has(row.name) && seen.add(row.name))
        .map(({ row, point }) => ({
          company_id: companyId,
          name: row.name,
          area: row.area,
          latitude: point?.lat ?? null,
          longitude: point?.lng ?? null,
        }));

      let added: VisitShop[] = [];
      if (inserts.length) {
        const { data, error } = await supabase
          .from("traders")
          .insert(inserts)
          .select("id,name,area,address,phone,whatsapp,latitude,longitude,status,notes");
        if (error) return setMessage(friendly(error.message));
        added = (data ?? []) as VisitShop[];
      }

      const moved = new Map(updates.map(({ shop, point }) => [shop.id, point]));
      setShops((current) => [
        ...added,
        ...current.map((shop) => {
          const point = moved.get(shop.id);
          return point ? { ...shop, latitude: point.lat, longitude: point.lng } : shop;
        }),
      ]);
      setRoute(null);
      setBulk(null);

      const withLocation = added.filter((shop) => shop.latitude != null).length + updates.length;
      const parts = [
        added.length ? `انضاف ${added.length} محل` : "",
        withLocation ? `${withLocation} صار إلهن موقع` : "",
        badLinks.length ? `ما قدرنا نقرأ موقع: ${badLinks.join("، ")}` : "",
      ].filter(Boolean);
      setMessage(parts.length ? `${parts.join(" • ")}.` : "ما في شي جديد بالقائمة.", badLinks.length > 0);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page">
      <div className="statsGrid">
        <div className="statCard">
          <div className="statLabel">لسا ما انزاروا</div>
          <div className="statValue">{counts.new}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">مهتمين</div>
          <div className="statValue">{counts.interested}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">زرتهم</div>
          <div className="statValue">{counts.contacted}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">بدون موقع</div>
          <div className="statValue">{noLocation.length}</div>
        </div>
      </div>

      {message.text ? (
        <div className={message.error ? "toastError" : "toastSuccess"} role="status" style={{ marginTop: 12 }}>
          {message.text}
        </div>
      ) : null}

      <div className="pageGrid">
        <section className="panel visitsMap">
          <VisitsMap shops={locatedShops} order={route ? route.stops.map((stop) => stop.id) : null} me={me} />
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>أقصر طريق</h2>
              <p>اختار مين بدك تزور، والبرنامج بيرتّبلك الطريق</p>
            </div>
          </div>

          <div className="feeChoices" role="group" aria-label="مين يدخل بالطريق">
            {(["new", "interested", "contacted"] as VisitStatus[]).map((status) => (
              <button
                key={status}
                type="button"
                aria-pressed={include.includes(status)}
                className={include.includes(status) ? "softButton active" : "softButton"}
                onClick={() => {
                  setRoute(null);
                  setInclude((current) =>
                    current.includes(status) ? current.filter((item) => item !== status) : [...current, status],
                  );
                }}
              >
                {STATUS_LABELS[status]} ({counts[status]})
              </button>
            ))}
          </div>

          <div className="rowActions" style={{ marginTop: 12 }}>
            <button type="button" className="primaryButton" disabled={locating} onClick={planFromMe}>
              <Icons.route size={15} /> {locating ? "عم نحدد موقعك..." : "رتّب الطريق من مكاني"}
            </button>
            <button type="button" className="softButton" onClick={() => plan()}>
              من أول محل
            </button>
          </div>

          {route ? (
            <>
              <p className="muted" style={{ marginTop: 12 }}>
                {route.stops.length} محل • تقريبًا {formatNumber(route.totalKm, 1)} كم (خط مستقيم)
              </p>

              <div className="rowActions">
                {googleLinks.map((href, index) => (
                  <a key={href} className="primaryButton" href={href} target="_blank" rel="noreferrer">
                    <Icons.map size={14} /> افتح بـ Google Maps
                    {googleLinks.length > 1 ? ` (قسم ${index + 1})` : ""}
                  </a>
                ))}
              </div>

              <div className="mapRouteList">
                {route.stops.map((stop, index) => (
                  <div className="routeItem" key={stop.id}>
                    <div className="routeNum">{index + 1}</div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <strong>{stop.name}</strong>
                      <div className="muted">{[stop.area, STATUS_LABELS[stop.status]].filter(Boolean).join(" • ")}</div>
                    </div>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <p className="muted" style={{ marginTop: 12 }}>
              {candidates.length} محل إلو موقع رح يدخل بالطريق.
              {noLocation.length ? ` و${noLocation.length} بدون موقع ما رح يدخلوا.` : ""}
            </p>
          )}
        </aside>
      </div>

      <section className="panel panelPad" style={{ marginTop: 13 }}>
        <div className="panelHeader">
          <div>
            <h2>المحلات</h2>
            <p>لما تزور محل غيّر حالتو. "صار زبون" و"مش مناسب" بيطلعوه من هالقائمة.</p>
          </div>
          {canCreate ? (
            <div className="rowActions">
              <button
                type="button"
                className="primaryButton"
                onClick={() => {
                  setForm(emptyForm());
                  setFormMessage("");
                }}
              >
                <Icons.plus size={14} /> محل
              </button>
              <button type="button" className="softButton" onClick={() => setBulk({ text: "", area: "" })}>
                ضيف قائمة
              </button>
            </div>
          ) : null}
        </div>

        {!shops.length ? (
          <div className="empty" style={{ minHeight: 160 }}>
            <h3>ما في محلات بالقائمة</h3>
            <p>ضيف المحلات اللي بدك تزورها، واحد واحد أو قائمة كاملة مرة وحدة.</p>
          </div>
        ) : (
          <div className="visitList">
            {shops.map((shop) => {
              const hasLocation = Boolean(located(shop));
              return (
                <div className="visitRow" key={shop.id}>
                  <div className="visitInfo">
                    <strong>{shop.name}</strong>
                    <span className="muted">
                      {[shop.area, shop.phone].filter(Boolean).join(" • ") || "—"}
                    </span>
                    {shop.notes ? <span className="muted">📝 {shop.notes}</span> : null}
                    <span>
                      <span className={`chip ${STATUS_CHIPS[shop.status]}`}>{STATUS_LABELS[shop.status]}</span>{" "}
                      {!hasLocation ? <span className="chip orange">بدون موقع</span> : null}
                    </span>
                  </div>

                  <div className="rowActions">
                    {hasLocation ? (
                      <a
                        className="softButton"
                        href={googleMapsRouteLinks([located(shop)!])[0]}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <Icons.route size={13} /> خذني لعندو
                      </a>
                    ) : (
                      <a
                        className="softButton"
                        href={googleMapsSearchLink(shop.name, shop.area)}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <Icons.search size={13} /> دوّر عليه
                      </a>
                    )}
                    {canEdit ? (
                      <>
                        <button type="button" className="softButton" onClick={() => openEdit(shop)}>
                          {hasLocation ? "تعديل" : "حدّد الموقع"}
                        </button>
                        {shop.status !== "contacted" ? (
                          <button
                            type="button"
                            className="softButton"
                            disabled={busyId === shop.id}
                            onClick={() => void setStatus(shop, "contacted")}
                          >
                            زرتو
                          </button>
                        ) : null}
                        {shop.status !== "interested" ? (
                          <button
                            type="button"
                            className="softButton"
                            disabled={busyId === shop.id}
                            onClick={() => void setStatus(shop, "interested")}
                          >
                            مهتم
                          </button>
                        ) : null}
                        <button
                          type="button"
                          className="softButton"
                          disabled={busyId === shop.id}
                          onClick={() => void setStatus(shop, "customer")}
                        >
                          صار زبون
                        </button>
                        <button
                          type="button"
                          className="dangerButton"
                          disabled={busyId === shop.id}
                          onClick={() => {
                            if (confirm(`${shop.name} مش مناسب؟ بيطلع من القائمة (وبيضل محفوظ بالعملاء الموقوفين).`))
                              void setStatus(shop, "inactive");
                          }}
                        >
                          مش مناسب
                        </button>
                      </>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      {form ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true" aria-labelledby="visit-form-title">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">جولة الزيارات</span>
                <h2 id="visit-form-title">{form.id ? form.name : "محل جديد"}</h2>
              </div>
              <button type="button" className="closeButton" aria-label="إغلاق" disabled={saving} onClick={() => setForm(null)}>
                ×
              </button>
            </div>

            <form onSubmit={save}>
              <div className="formGrid">
                <label className="field">
                  <span>اسم المحل *</span>
                  <input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required />
                </label>
                <label className="field">
                  <span>المنطقة</span>
                  <input
                    value={form.area}
                    placeholder="مثلاً: جرمانا"
                    onChange={(event) => setForm({ ...form, area: event.target.value })}
                  />
                </label>
                <label className="field">
                  <span>الهاتف</span>
                  <input
                    dir="ltr"
                    inputMode="tel"
                    value={form.phone}
                    onChange={(event) => setForm({ ...form, phone: event.target.value })}
                  />
                  {form.phone.trim() && anyPhoneState(form.phone) === "invalid" ? (
                    <small className="invalidText">الرقم مش مظبوط</small>
                  ) : null}
                </label>
                <label className="field">
                  <span>ملاحظات</span>
                  <input
                    value={form.notes}
                    placeholder="مثلاً: بيبيع برادات، صاحبو أبو سامر"
                    onChange={(event) => setForm({ ...form, notes: event.target.value })}
                  />
                </label>

                <div className="field full">
                  <span>الموقع</span>
                  <div className="rowActions" style={{ flexWrap: "nowrap" }}>
                    <input
                      dir="ltr"
                      style={{ flex: 1, minWidth: 0 }}
                      value={form.link}
                      placeholder="الصق رابط Google Maps أو الإحداثيات"
                      onChange={(event) => setForm({ ...form, link: event.target.value })}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") {
                          event.preventDefault();
                          void readLink();
                        }
                      }}
                    />
                    <button type="button" className="softButton" disabled={reading || !form.link.trim()} onClick={() => void readLink()}>
                      {reading ? "عم نقرأ..." : "اقرأ الموقع"}
                    </button>
                  </div>
                  <small className="helpText">
                    بـ Google Maps: دوّر على المحل ← مشاركة ← نسخ الرابط، والصقو هون.{" "}
                    {form.name.trim() ? (
                      <a href={googleMapsSearchLink(form.name, form.area)} target="_blank" rel="noreferrer">
                        دوّر عليه بـ Google Maps
                      </a>
                    ) : null}
                  </small>
                  <LocationPicker
                    latitude={form.latitude}
                    longitude={form.longitude}
                    onChange={(latitude, longitude) => setForm((current) => (current ? { ...current, latitude, longitude } : current))}
                  />
                </div>
              </div>

              {formMessage ? (
                <div className="toastError" role="alert">
                  {formMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button type="button" className="softButton" disabled={saving} onClick={() => setForm(null)}>
                  رجوع
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : "حفظ"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {bulk ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true" aria-labelledby="visit-bulk-title">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">جولة الزيارات</span>
                <h2 id="visit-bulk-title">ضيف قائمة محلات</h2>
              </div>
              <button type="button" className="closeButton" aria-label="إغلاق" disabled={saving} onClick={() => setBulk(null)}>
                ×
              </button>
            </div>
            <form onSubmit={saveBulk} className="authForm">
              <label className="field">
                <span>كل محل بسطر: "الاسم - المنطقة"، وإذا معك رابط Google Maps حطّو بآخر السطر</span>
                <textarea
                  rows={8}
                  value={bulk.text}
                  placeholder={"Avatar - ساحة السيوف - https://maps.app.goo.gl/...\nالبيت الأوروبي\nالزربا للإنارة 33.4842, 36.3431"}
                  onChange={(event) => setBulk({ ...bulk, text: event.target.value })}
                />
              </label>
              <label className="field">
                <span>المنطقة (للي ما إلهن منطقة بالسطر)</span>
                <input value={bulk.area} placeholder="مثلاً: جرمانا" onChange={(event) => setBulk({ ...bulk, area: event.target.value })} />
              </label>
              <small className="helpText">
                المحل الموجود بنفس الاسم ما بينضاف مرتين، بس إذا معو رابط بيتحدّث موقعو. اللي بلا رابط بتحدّد موقعو بعدين من
                "حدّد الموقع".
              </small>
              <div className="modalActions">
                <button type="button" className="softButton" disabled={saving} onClick={() => setBulk(null)}>
                  رجوع
                </button>
                <button className="primaryButton" disabled={saving || !bulk.text.trim()}>
                  {saving ? "عم نضيف..." : "ضيف"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}
