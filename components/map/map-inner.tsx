"use client";

import L from "leaflet";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  MapContainer,
  Marker,
  Polyline,
  Popup,
  TileLayer,
  useMap,
  useMapEvents,
} from "react-leaflet";

import { Icons } from "@/components/icons";
import { normalizeSyrianMobile } from "@/lib/phone";
import { googleMapsRouteLinks, planRoute, type LatLng } from "@/lib/route";
import { createClient } from "@/lib/supabase/client";

import type { MapProps, MapTrader } from "./map-shell";
import { formatNumber } from "@/lib/format";

const DAMASCUS: [number, number] = [33.5138, 36.2765];

const COLORS = {
  paid: "#18aa80",
  owes: "#d6ad55",
  overdue: "#df7c7c",
  me: "#70aee7",
  picking: "#ffffff",
};

type Located = MapTrader & { lat: number; lng: number };
type Mode = "customers" | "deliveries";

function pin(color: string, label = "•") {
  return L.divIcon({
    className: "",
    html: `<div style="width:32px;height:32px;border-radius:10px;background:${color};color:#06231c;display:grid;place-items:center;font-weight:900;border:2px solid rgba(255,255,255,.8);box-shadow:0 6px 16px rgba(0,0,0,.35)">${label}</div>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  });
}

function debtColor(trader: MapTrader) {
  if (trader.overdue) return COLORS.overdue;
  if ((trader.balance_due ?? 0) > 0) return COLORS.owes;
  return COLORS.paid;
}

function locate(onDone: (point: LatLng) => void, onError: (message: string) => void) {
  if (!navigator.geolocation) {
    onError("المتصفح ما بيدعم تحديد الموقع.");
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (position) => onDone({ lat: position.coords.latitude, lng: position.coords.longitude }),
    () => onError("ما قدرنا نحدد موقعك. تأكد من إذن الموقع وحاول مرة ثانية."),
    { enableHighAccuracy: true, timeout: 10000 },
  );
}

function whatsappLink(trader: MapTrader) {
  const phone = trader.whatsapp ? normalizeSyrianMobile(trader.whatsapp) : null;
  return phone ? `https://wa.me/${phone.replace(/\D/g, "")}` : null;
}

/** Keeps the view on the visible pins; falls back to Damascus when there are none. */
function FitToPoints({ points }: { points: LatLng[] }) {
  const map = useMap();
  const key = points.map((p) => `${p.lat},${p.lng}`).join("|");

  useEffect(() => {
    if (!points.length) {
      map.setView(DAMASCUS, 12);
    } else if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 15);
    } else {
      map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number])), {
        padding: [40, 40],
        maxZoom: 15,
      });
    }
    // Refit only when the set of points changes, not on every render.
  }, [key]);

  return null;
}

function PickOnClick({ onPick }: { onPick: (point: LatLng) => void }) {
  useMapEvents({
    click: (event) => onPick({ lat: event.latlng.lat, lng: event.latlng.lng }),
  });
  return null;
}

export function MapInner({
  traders: initialTraders,
  initialTraderId,
  initialMode = "customers",
  companyId,
  currency,
  canEditLocation,
}: MapProps) {
  const [supabase] = useState(() => createClient());
  const [traders, setTraders] = useState(initialTraders);
  const [mode, setMode] = useState<Mode>(initialMode);
  const [area, setArea] = useState("all");
  const [me, setMe] = useState<LatLng>();
  const [message, setMessage] = useState("");
  const [route, setRoute] = useState<{ stops: Located[]; totalKm: number }>();

  // Setting a customer's location.
  const [pickingId, setPickingId] = useState("");
  const [picked, setPicked] = useState<LatLng>();
  const [saving, setSaving] = useState(false);

  const money = (value: number) =>
    `${value.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${currency}`;

  const areas = useMemo(
    () => Array.from(new Set(traders.map((t) => t.area).filter((a): a is string => Boolean(a)))),
    [traders],
  );

  const inArea = area === "all" ? traders : traders.filter((t) => t.area === area);

  const located: Located[] = inArea
    .filter((t) => t.latitude != null && t.longitude != null)
    .map((t) => ({ ...t, lat: Number(t.latitude), lng: Number(t.longitude) }));

  const unlocated = inArea.filter((t) => t.latitude == null || t.longitude == null);
  const canSeeDeliveries = traders.some((t) => t.pending_orders != null);
  const deliveryStops = located.filter((t) => (t.pending_orders ?? 0) > 0);
  const deliveriesWithoutLocation = unlocated.filter((t) => (t.pending_orders ?? 0) > 0);

  const shown: Located[] = mode === "deliveries" ? (route?.stops ?? deliveryStops) : located;

  const focused = located.find((t) => t.id === initialTraderId);
  const fitPoints: LatLng[] = focused
    ? [focused]
    : [...shown, ...(me ? [me] : []), ...(picked ? [picked] : [])];

  function switchMode(next: Mode) {
    setMode(next);
    setRoute(undefined);
    setMessage("");
  }

  function planDeliveries() {
    if (!deliveryStops.length) return;
    setRoute(planRoute(deliveryStops, me));
  }

  function startPicking(id: string) {
    setPickingId(id);
    setPicked(undefined);
    setMessage("");
  }

  async function saveLocation() {
    if (!pickingId || !picked) return;
    setSaving(true);
    const { error } = await supabase
      .from("traders")
      .update({ latitude: picked.lat, longitude: picked.lng })
      .eq("id", pickingId)
      .eq("company_id", companyId);
    setSaving(false);

    if (error) {
      setMessage("ما قدرنا نحفظ الموقع. تأكد من الصلاحيات وحاول مرة ثانية.");
      return;
    }

    setTraders((rows) =>
      rows.map((t) =>
        t.id === pickingId ? { ...t, latitude: picked.lat, longitude: picked.lng } : t,
      ),
    );
    setPickingId("");
    setPicked(undefined);
    setRoute(undefined);
    setMessage("");
  }

  const routeLine: [number, number][] = route
    ? [
        ...(me ? [[me.lat, me.lng] as [number, number]] : []),
        ...route.stops.map((s) => [s.lat, s.lng] as [number, number]),
      ]
    : [];

  const googleLinks = route ? googleMapsRouteLinks(route.stops, me) : [];

  return (
    <div className="page">
      {message && (
        <div className="toastError" role="status" style={{ marginBottom: 12 }}>
          {message}
        </div>
      )}

      <div className="pageTitle">
        <div>
          <span className="eyebrow">خريطة السوق</span>
          <h2>{mode === "customers" ? "الزبائن على الخريطة" : "طريق التوصيل"}</h2>
          <p className="muted">
            {mode === "customers"
              ? "أخضر: ما عليه شي • أصفر: عليه دين • أحمر: متأخر بالدفع"
              : "الترتيب حسب أقصر مسافة. الطريق الفعلي بيحدده Google Maps."}
          </p>
        </div>

        <div className="rowActions mapToolbar">
          <button
            className={mode === "customers" ? "primaryButton" : "softButton"}
            onClick={() => switchMode("customers")}
          >
            <Icons.users size={14} /> الزبائن
          </button>
          {canSeeDeliveries && (
            <button
              className={mode === "deliveries" ? "primaryButton" : "softButton"}
              onClick={() => switchMode("deliveries")}
            >
              <Icons.truck size={14} /> التوصيلات (
              {deliveryStops.length + deliveriesWithoutLocation.length})
            </button>
          )}
          <select
            className="softButton"
            value={area}
            onChange={(event) => {
              setArea(event.target.value);
              setRoute(undefined);
            }}
          >
            <option value="all">كل المناطق</option>
            {areas.map((name) => (
              <option key={name}>{name}</option>
            ))}
          </select>
          <button className="softButton" onClick={() => locate(setMe, setMessage)}>
            <Icons.map size={14} /> موقعي
          </button>
        </div>
      </div>

      <div className="mapWrap">
        <MapContainer center={DAMASCUS} zoom={12} style={{ height: "100%", width: "100%" }}>
          <TileLayer
            attribution="&copy; OpenStreetMap contributors"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <FitToPoints points={fitPoints} />
          {pickingId && <PickOnClick onPick={setPicked} />}

          {me && (
            <Marker position={[me.lat, me.lng]} icon={pin(COLORS.me, "أنا")}>
              <Popup>موقعي الحالي</Popup>
            </Marker>
          )}

          {picked && (
            <Marker position={[picked.lat, picked.lng]} icon={pin(COLORS.picking, "📍")} />
          )}

          {shown.map((trader, index) => (
            <Marker
              key={trader.id}
              position={[trader.lat, trader.lng]}
              icon={pin(
                debtColor(trader),
                route
                  ? String(index + 1)
                  : mode === "deliveries"
                    ? String(trader.pending_orders)
                    : "•",
              )}
            >
              <Popup>
                <strong>{trader.name}</strong>
                {trader.area && <div>{trader.area}</div>}
                {trader.address && <div>{trader.address}</div>}
                {trader.balance_due != null && (
                  <div>
                    {trader.balance_due > 0
                      ? `عليه: ${money(trader.balance_due)}${trader.overdue ? " (متأخر)" : ""}`
                      : "ما عليه شي"}
                  </div>
                )}
                {(trader.pending_orders ?? 0) > 0 && (
                  <div>
                    {trader.pending_orders} طلبية للتوصيل • {money(trader.pending_total ?? 0)}
                  </div>
                )}
                <div className="rowActions" style={{ marginTop: 8 }}>
                  <a
                    className="softButton"
                    target="_blank"
                    rel="noreferrer"
                    href={googleMapsRouteLinks([trader])[0]}
                  >
                    <Icons.route size={13} /> خذني لعنده
                  </a>
                  {whatsappLink(trader) && (
                    <a
                      className="softButton"
                      target="_blank"
                      rel="noreferrer"
                      href={whatsappLink(trader)!}
                    >
                      <Icons.whatsapp size={13} />
                    </a>
                  )}
                  <Link className="softButton" href={`/customers/${trader.id}`}>
                    الملف
                  </Link>
                </div>
              </Popup>
            </Marker>
          ))}

          {routeLine.length > 1 && (
            <Polyline positions={routeLine} pathOptions={{ color: COLORS.paid }} />
          )}
        </MapContainer>
      </div>

      {mode === "customers" && canEditLocation && (
        <section className="panel panelPad" style={{ marginTop: 13 }}>
          <div className="panelHeader">
            <div>
              <h2>زبائن بدون موقع ({unlocated.length})</h2>
              <p>اختار زبون، وبعدين اكبس على مكان محله على الخريطة أو استعمل موقعك إذا كنت عنده.</p>
            </div>
          </div>

          {unlocated.length === 0 ? (
            <p className="muted">كل الزبائن إلهم موقع على الخريطة.</p>
          ) : (
            <div className="rowActions">
              <select
                className="softButton"
                value={pickingId}
                onChange={(event) => startPicking(event.target.value)}
              >
                <option value="">اختار زبون...</option>
                {unlocated.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                    {t.area ? ` - ${t.area}` : ""}
                  </option>
                ))}
              </select>

              {pickingId && (
                <>
                  <span className="muted">
                    {picked ? "تمام، اكبس «احفظ الموقع»." : "اكبس على مكان المحل على الخريطة 👆"}
                  </span>
                  <button className="softButton" onClick={() => locate(setPicked, setMessage)}>
                    <Icons.map size={14} /> أنا عند المحل هلق
                  </button>
                  <button
                    className="primaryButton"
                    disabled={!picked || saving}
                    onClick={saveLocation}
                  >
                    {saving ? "عم نحفظ..." : "احفظ الموقع"}
                  </button>
                  <button className="softButton" onClick={() => startPicking("")}>
                    إلغاء
                  </button>
                </>
              )}
            </div>
          )}
        </section>
      )}

      {mode === "deliveries" && (
        <section className="panel panelPad" style={{ marginTop: 13 }}>
          <div className="panelHeader">
            <div>
              <h2>
                {route
                  ? `${route.stops.length} وقفة • تقريبًا ${formatNumber(route.totalKm, 1)} كم`
                  : `${deliveryStops.length} زبون بانتظار التوصيل`}
              </h2>
              <p>
                {me
                  ? "الطريق بيبلّش من موقعك الحالي."
                  : "اكبس «موقعي» فوق إذا بدك الطريق يبلّش من مكانك."}
              </p>
            </div>
            {!route && deliveryStops.length > 0 && (
              <button className="primaryButton" onClick={planDeliveries}>
                <Icons.route size={14} /> رتّب أقصر طريق
              </button>
            )}
          </div>

          {deliveriesWithoutLocation.length > 0 && (
            <div className="toastError" style={{ marginBottom: 10 }}>
              {deliveriesWithoutLocation.length} زبون عندهم طلبيات بس ما إلهم موقع:{" "}
              {deliveriesWithoutLocation.map((t) => t.name).join("، ")}. حدد مواقعهم من تبويب
              الزبائن.
            </div>
          )}

          {route && (
            <>
              <div className="rowActions" style={{ marginBottom: 10 }}>
                {googleLinks.map((href, index) => (
                  <a
                    key={href}
                    className="primaryButton"
                    target="_blank"
                    rel="noreferrer"
                    href={href}
                  >
                    <Icons.truck size={14} />
                    {googleLinks.length > 1
                      ? ` ابدأ الجزء ${index + 1} بـ Google Maps`
                      : " ابدأ التوصيل بـ Google Maps"}
                  </a>
                ))}
                <button className="softButton" onClick={() => setRoute(undefined)}>
                  إلغاء الترتيب
                </button>
              </div>

              <div className="mapRouteList">
                {route.stops.map((stop, index) => (
                  <div className="routeItem" key={stop.id}>
                    <div className="routeNum">{index + 1}</div>
                    <div style={{ flex: 1 }}>
                      <strong>{stop.name}</strong>
                      <div className="muted">
                        {stop.pending_orders} طلبية • {money(stop.pending_total ?? 0)}
                        {stop.area ? ` • ${stop.area}` : ""}
                        {(stop.balance_due ?? 0) > 0 ? ` • عليه ${money(stop.balance_due!)}` : ""}
                      </div>
                    </div>
                    {whatsappLink(stop) && (
                      <a
                        className="softButton"
                        target="_blank"
                        rel="noreferrer"
                        href={whatsappLink(stop)!}
                      >
                        <Icons.whatsapp size={13} />
                      </a>
                    )}
                  </div>
                ))}
              </div>
            </>
          )}
        </section>
      )}
    </div>
  );
}
