"use client";

import L from "leaflet";
import { useEffect } from "react";
import { MapContainer, Marker, Polyline, Popup, TileLayer, useMap } from "react-leaflet";

import type { LatLng } from "@/lib/route";

import { STATUS_COLORS, STATUS_LABELS, type LocatedShop } from "./shared";

const DAMASCUS: [number, number] = [33.5138, 36.2765];

function pin(color: string, label: string) {
  return L.divIcon({
    className: "",
    html: `<div style="width:30px;height:30px;border-radius:10px;background:${color};color:#06231c;display:grid;place-items:center;font-weight:900;font-size:13px;border:2px solid rgba(255,255,255,.85);box-shadow:0 6px 16px rgba(0,0,0,.35)">${label}</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  });
}

const mePin = pin("#ffffff", "●");

function FitToPoints({ points }: { points: LatLng[] }) {
  const map = useMap();
  const key = points.map((p) => `${p.lat},${p.lng}`).join("|");
  useEffect(() => {
    if (!points.length) map.setView(DAMASCUS, 12, { animate: false });
    else if (points.length === 1) map.setView([points[0].lat, points[0].lng], 15, { animate: false });
    else
      map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number])), {
        animate: false,
        padding: [36, 36],
        maxZoom: 16,
      });
    // بس لما تتغيّر النقاط.
  }, [key]);
  return null;
}

// الخريطة بتنرسم قبل ما ياخد مكانها حجمو، فمنعيد حساب الحجم.
function FitContainer() {
  const map = useMap();
  useEffect(() => {
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(map.getContainer());
    return () => observer.disconnect();
  }, [map]);
  return null;
}

export function VisitsMap({
  shops,
  order,
  me,
}: {
  shops: LocatedShop[];
  /** ترتيب الطريق (أرقام المحلات) إذا انحسب. */
  order: string[] | null;
  me?: LatLng;
}) {
  const position = new Map(order?.map((id, index) => [id, index + 1]));
  const routeLine: [number, number][] = order
    ? [
        ...(me ? [[me.lat, me.lng] as [number, number]] : []),
        ...order
          .map((id) => shops.find((shop) => shop.id === id))
          .filter((shop): shop is LocatedShop => Boolean(shop))
          .map((shop) => [shop.lat, shop.lng] as [number, number]),
      ]
    : [];

  return (
    <MapContainer center={DAMASCUS} zoom={12} style={{ height: "100%", width: "100%" }}>
      <TileLayer
        attribution="&copy; OpenStreetMap contributors"
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitContainer />
      <FitToPoints points={[...shops, ...(me ? [me] : [])]} />
      {routeLine.length > 1 ? <Polyline positions={routeLine} pathOptions={{ color: "#27c99b", weight: 4 }} /> : null}
      {me ? <Marker position={[me.lat, me.lng]} icon={mePin} /> : null}
      {shops.map((shop) => (
        <Marker
          key={shop.id}
          position={[shop.lat, shop.lng]}
          icon={pin(STATUS_COLORS[shop.status], position.has(shop.id) ? String(position.get(shop.id)) : "•")}
        >
          <Popup>
            <strong>{shop.name}</strong>
            <br />
            {[shop.area, STATUS_LABELS[shop.status]].filter(Boolean).join(" • ")}
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}
