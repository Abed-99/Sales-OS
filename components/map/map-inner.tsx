"use client";

import L from "leaflet";
import { useMemo, useState } from "react";
import {
  MapContainer,
  Marker,
  Polyline,
  Popup,
  TileLayer,
} from "react-leaflet";
import { Icons } from "@/components/icons";
import { nearestNeighborRoute } from "@/lib/route";
import type { MapTrader } from "./map-shell";

const DEFAULT_CENTER: [number, number] = [33.5138, 36.2765];

function markerIcon(number?: number) {
  return L.divIcon({
    className: "",
    html: `<div style="width:32px;height:32px;border-radius:10px;background:#18aa80;color:#06231c;display:grid;place-items:center;font-weight:900;border:2px solid rgba(255,255,255,.75);box-shadow:0 6px 16px rgba(0,0,0,.35)">${number ?? "•"}</div>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  });
}

function coordinates(trader: MapTrader): [number, number] {
  return [Number(trader.latitude), Number(trader.longitude)];
}

export function MapInner({
  traders,
  initialTraderId,
}: {
  traders: MapTrader[];
  initialTraderId: string | null;
}) {
  const [area, setArea] = useState("all");
  const [route, setRoute] = useState<MapTrader[]>([]);
  const [start, setStart] = useState<
    { lat: number; lng: number } | undefined
  >();

  const areas = useMemo(
    () =>
      Array.from(
        new Set(
          traders
            .map((trader) => trader.area)
            .filter((value): value is string => Boolean(value))
        )
      ),
    [traders]
  );

  const filtered =
    area === "all"
      ? traders
      : traders.filter((trader) => trader.area === area);

  const focusedTrader =
    filtered.find((trader) => trader.id === initialTraderId) ?? null;

  const center = focusedTrader
    ? coordinates(focusedTrader)
    : filtered[0]
      ? coordinates(filtered[0])
      : DEFAULT_CENTER;

  function planRoute() {
    const traderById = new Map(
      filtered.map((trader) => [trader.id, trader])
    );

    const points = filtered.map((trader) => ({
      id: trader.id,
      name: trader.name,
      lat: Number(trader.latitude),
      lng: Number(trader.longitude),
    }));

    const ordered = nearestNeighborRoute(points, start);

    setRoute(
      ordered
        .map((point) => traderById.get(point.id))
        .filter((trader): trader is MapTrader => Boolean(trader))
    );
  }

  function locate() {
    navigator.geolocation?.getCurrentPosition(
      (position) =>
        setStart({
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        }),
      () => alert("ما قدرنا نحدد موقعك"),
      {
        enableHighAccuracy: true,
        timeout: 8000,
      }
    );
  }

  const shown = route.length ? route : filtered;

  const routeLine: [number, number][] = [
    ...(start ? ([[start.lat, start.lng]] as [number, number][]) : []),
    ...route.map(coordinates),
  ];

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">تغطية السوق</span>
          <h2>التجار على الخريطة</h2>
          <p className="muted">
            ترتيب الجولة هون تقريبي حسب المسافة الجوية، مو حسب زحمة الطرق.
          </p>
        </div>

        <div className="rowActions">
          <select
            value={area}
            onChange={(event) => {
              setArea(event.target.value);
              setRoute([]);
            }}
            style={{
              background: "#0b1b17",
              color: "white",
              border: "1px solid rgba(255,255,255,.08)",
              borderRadius: 11,
              padding: "9px 12px",
            }}
          >
            <option value="all">كل المناطق</option>
            {areas.map((areaName) => (
              <option key={areaName}>{areaName}</option>
            ))}
          </select>

          <button
            className="softButton"
            onClick={locate}
          >
            <Icons.map size={14} /> موقعي
          </button>

          <button
            className="primaryButton"
            onClick={planRoute}
          >
            <Icons.route size={14} /> رتّب الجولة
          </button>
        </div>
      </div>

      {!filtered.length ? (
        <section className="panel empty">
          <Icons.map size={30} />
          <h3>ما في تجار مع لوكيشن</h3>
          <p>أضف Latitude وLongitude من ملف التاجر حتى يظهر هون.</p>
        </section>
      ) : (
        <>
          <div className="mapWrap">
            <MapContainer
              key={`${area}-${initialTraderId ?? "all"}-${route.length}-${start?.lat ?? 0}`}
              center={center}
              zoom={focusedTrader ? 15 : 12}
              style={{ height: "100%", width: "100%" }}
            >
              <TileLayer
                attribution="&copy; OpenStreetMap contributors"
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              />

              {start && (
                <Marker
                  position={[start.lat, start.lng]}
                  icon={markerIcon(0)}
                >
                  <Popup>موقعي الحالي</Popup>
                </Marker>
              )}

              {shown.map((trader, index) => (
                <Marker
                  key={trader.id}
                  position={coordinates(trader)}
                  icon={markerIcon(route.length ? index + 1 : undefined)}
                >
                  <Popup>
                    <strong>{trader.name}</strong>
                    <br />
                    {trader.area || ""}
                    <br />
                    {trader.address || ""}
                  </Popup>
                </Marker>
              ))}

              {routeLine.length > 1 && (
                <Polyline
                  positions={routeLine}
                  pathOptions={{ color: "#18aa80" }}
                />
              )}
            </MapContainer>
          </div>

          {route.length > 0 && (
            <section
              className="panel panelPad"
              style={{ marginTop: 13 }}
            >
              <div className="panelHeader">
                <div>
                  <h2>ترتيب الجولة المقترح</h2>
                  <p>{route.length} توقف</p>
                </div>
              </div>

              <div className="mapRouteList">
                {route.map((trader, index) => (
                  <div
                    className="routeItem"
                    key={trader.id}
                  >
                    <div className="routeNum">{index + 1}</div>

                    <div style={{ flex: 1 }}>
                      <strong>{trader.name}</strong>
                      <div className="muted">
                        {trader.area || ""}
                        {trader.address ? ` • ${trader.address}` : ""}
                      </div>
                    </div>

                    {trader.whatsapp && (
                      <a
                        className="softButton"
                        target="_blank"
                        rel="noreferrer"
                        href={`https://wa.me/${String(trader.whatsapp).replace(/\D/g, "")}`}
                      >
                        <Icons.whatsapp size={13} />
                      </a>
                    )}
                  </div>
                ))}
              </div>
            </section>
          )}
        </>
      )}
    </div>
  );
}
