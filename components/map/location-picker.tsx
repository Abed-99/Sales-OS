"use client";

import dynamic from "next/dynamic";

export type LocationPickerProps = {
  latitude: number | null;
  longitude: number | null;
  onChange: (latitude: number | null, longitude: number | null) => void;
};

// Leaflet needs the browser, so the map loads on the client only.
const Inner = dynamic(
  () => import("./location-picker-inner").then((module) => module.LocationPickerInner),
  {
    ssr: false,
    loading: () => <p className="muted">عم نحمّل الخريطة...</p>,
  },
);

export function LocationPicker(props: LocationPickerProps) {
  return <Inner {...props} />;
}
