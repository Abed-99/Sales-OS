"use client";

import L from "leaflet";
import { useEffect, useState } from "react";
import { MapContainer, Marker, TileLayer, useMap, useMapEvents } from "react-leaflet";

import { Icons } from "@/components/icons";

import type { LocationPickerProps } from "./location-picker";

const DAMASCUS: [number, number] = [33.5138, 36.2765];

const pin = L.divIcon({
  className: "",
  html: '<div style="width:30px;height:30px;border-radius:10px;background:#18aa80;color:#06231c;display:grid;place-items:center;font-weight:900;border:2px solid rgba(255,255,255,.85);box-shadow:0 6px 16px rgba(0,0,0,.35)">📍</div>',
  iconSize: [30, 30],
  iconAnchor: [15, 15],
});

function PickOnClick({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (event) => onPick(event.latlng.lat, event.latlng.lng) });
  return null;
}

function FollowValue({ value }: { value: [number, number] | null }) {
  const map = useMap();
  const key = value ? value.join(",") : "";
  useEffect(() => {
    // بدون حركة: النافذة ممكن تتسكّر بالنص وتطلع غلطة من Leaflet.
    if (value) map.setView(value, Math.max(map.getZoom(), 15), { animate: false });
    // Recenter only when the chosen point changes.
  }, [key]);
  return null;
}

// الخريطة جوّا نافذة بتنرسم قبل ما النافذة تاخد حجمها، فبتطلع رمادية؛ منعيد حساب الحجم
// كل ما تغيّر حجم مكانها.
function FitContainer() {
  const map = useMap();
  useEffect(() => {
    const container = map.getContainer();
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(container);
    const timer = window.setTimeout(() => map.invalidateSize(), 300);
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
    };
  }, [map]);
  return null;
}

export function LocationPickerInner({ latitude, longitude, onChange }: LocationPickerProps) {
  const [message, setMessage] = useState("");
  const value: [number, number] | null =
    latitude != null && longitude != null ? [latitude, longitude] : null;

  const set = (lat: number, lng: number) =>
    onChange(Number(lat.toFixed(7)), Number(lng.toFixed(7)));

  function locateMe() {
    setMessage("");
    if (!navigator.geolocation) {
      setMessage("المتصفح ما بيدعم تحديد الموقع.");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (position) => set(position.coords.latitude, position.coords.longitude),
      () => setMessage("ما قدرنا نحدد موقعك. تأكد من إذن الموقع."),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  return (
    <div className="locationPicker">
      <div className="locationPickerMap">
        <MapContainer
          center={value ?? DAMASCUS}
          zoom={value ? 15 : 12}
          style={{ height: "100%", width: "100%" }}
        >
          <TileLayer
            attribution="&copy; OpenStreetMap contributors"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <FitContainer />
          <PickOnClick onPick={set} />
          <FollowValue value={value} />
          {value ? <Marker position={value} icon={pin} /> : null}
        </MapContainer>
      </div>

      <div className="rowActions">
        <button type="button" className="softButton" onClick={locateMe}>
          <Icons.map size={14} /> أنا عند المحل هلق
        </button>
        {value ? (
          <button type="button" className="softButton" onClick={() => onChange(null, null)}>
            مسح الموقع
          </button>
        ) : null}
        <span className="muted">
          {value
            ? "✓ الموقع محدد. فيك تكبس بمكان تاني لتغيّره."
            : "اكبس على مكان المحل على الخريطة."}
        </span>
      </div>

      {message ? <small className="invalidText">{message}</small> : null}
    </div>
  );
}
