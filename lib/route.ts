export type LatLng = { lat: number; lng: number };
export type GeoPoint = LatLng & { id: string };

/** Straight-line distance in kilometres. */
export function distanceKm(a: LatLng, b: LatLng) {
  const R = 6371;
  const toRad = (x: number) => (x * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function pathLength(start: LatLng | undefined, stops: LatLng[]) {
  let total = 0;
  let current = start ?? stops[0];
  for (const stop of stops) {
    if (current) total += distanceKm(current, stop);
    current = stop;
  }
  return total;
}

/**
 * Orders stops into a short open route: nearest neighbour first, then 2-opt
 * to untangle crossings. Straight-line distances, so it is a close estimate,
 * not a road-traffic route.
 */
export function planRoute<T extends GeoPoint>(stops: T[], start?: LatLng) {
  const left = [...stops];
  const ordered: T[] = [];
  let current: LatLng | undefined = start;

  while (left.length) {
    let best = 0;
    if (current) {
      let bestDistance = Infinity;
      left.forEach((stop, index) => {
        const d = distanceKm(current!, stop);
        if (d < bestDistance) {
          bestDistance = d;
          best = index;
        }
      });
    }
    const [next] = left.splice(best, 1);
    ordered.push(next);
    current = next;
  }

  let improved = true;
  while (improved) {
    improved = false;
    for (let i = 0; i < ordered.length - 1; i += 1) {
      for (let j = i + 1; j < ordered.length; j += 1) {
        const candidate = [
          ...ordered.slice(0, i),
          ...ordered.slice(i, j + 1).reverse(),
          ...ordered.slice(j + 1),
        ];
        if (pathLength(start, candidate) + 1e-9 < pathLength(start, ordered)) {
          ordered.splice(0, ordered.length, ...candidate);
          improved = true;
        }
      }
    }
  }

  return { stops: ordered, totalKm: pathLength(start, ordered) };
}

/** Google Maps allows 9 waypoints per link, so longer routes are split into legs. */
const STOPS_PER_LINK = 10;

export function googleMapsRouteLinks(stops: LatLng[], start?: LatLng) {
  const format = (p: LatLng) => `${p.lat},${p.lng}`;
  const links: string[] = [];

  for (let i = 0; i < stops.length; i += STOPS_PER_LINK) {
    const leg = stops.slice(i, i + STOPS_PER_LINK);
    const origin = i === 0 ? start : stops[i - 1];
    const params = new URLSearchParams({
      api: "1",
      travelmode: "driving",
      destination: format(leg[leg.length - 1]),
    });
    // With no origin Google Maps starts from the phone's current location.
    if (origin) params.set("origin", format(origin));
    if (leg.length > 1) params.set("waypoints", leg.slice(0, -1).map(format).join("|"));
    links.push(`https://www.google.com/maps/dir/?${params.toString()}`);
  }

  return links;
}
