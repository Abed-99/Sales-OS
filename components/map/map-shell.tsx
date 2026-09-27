"use client";

import dynamic from "next/dynamic";

export type MapTrader = {
  id: string;
  name: string;
  area: string | null;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  latitude: number | string | null;
  longitude: number | string | null;
  status: string;
  /** null when the viewer can't see balances. */
  balance_due: number | null;
  overdue: boolean | null;
  /** null when the viewer can't see deliveries. */
  pending_orders: number | null;
  pending_total: number | null;
};

export type MapProps = {
  traders: MapTrader[];
  initialTraderId: string | null;
  companyId: string;
  currency: string;
  canEditLocation: boolean;
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

export function MapShell(props: MapProps) {
  return <Inner {...props} />;
}
