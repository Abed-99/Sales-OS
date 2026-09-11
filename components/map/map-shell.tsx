"use client";

import dynamic from "next/dynamic";

export type MapTrader = {
  id: string;
  name: string;
  area: string | null;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  latitude: number | string;
  longitude: number | string;
  status: string;
};

const Inner = dynamic(
  () => import("./map-inner").then((module) => module.MapInner),
  {
    ssr: false,
    loading: () => (
      <div className="panel empty">
        <p>عم نحمل الخريطة...</p>
      </div>
    ),
  }
);

export function MapShell({
  traders,
  initialTraderId,
}: {
  traders: MapTrader[];
  initialTraderId: string | null;
}) {
  return (
    <Inner
      traders={traders}
      initialTraderId={initialTraderId}
    />
  );
}
