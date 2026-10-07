import type { LatLng } from "@/lib/route";

function valid(lat: number, lng: number): LatLng | null {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
    ? { lat: Number(lat.toFixed(7)), lng: Number(lng.toFixed(7)) }
    : null;
}

const NUM = "(-?\\d{1,3}\\.\\d+)";

/**
 * بيطلّع الإحداثيات من رابط Google Maps الطويل أو من نص متل "33.51, 36.31".
 * الرابط القصير (maps.app.goo.gl) بدو يتفتح أول — هاد شغل isShortMapLink + /api/geo/resolve.
 */
export function parseLatLng(text: string): LatLng | null {
  const value = decodeURIComponent(text.trim());
  const patterns = [
    // مكان محدد (الدبوس نفسو) — أدق من مركز الشاشة.
    new RegExp(`!3d${NUM}!4d${NUM}`),
    new RegExp(`[?&](?:q|query|ll|destination|daddr)=${NUM},\\s*${NUM}`),
    new RegExp(`/place/${NUM},\\s*${NUM}`),
    new RegExp(`@${NUM},${NUM}`),
    new RegExp(`^${NUM}\\s*[,،\\s]\\s*${NUM}$`),
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (match) return valid(Number(match[1]), Number(match[2]));
  }
  return null;
}

const SHORT_HOSTS = ["maps.app.goo.gl", "goo.gl", "g.co"];

export function isShortMapLink(text: string) {
  try {
    return SHORT_HOSTS.includes(new URL(text.trim()).hostname);
  } catch {
    return false;
  }
}

/** رابط بحث بخرائط Google باسم المحل (لما ما نعرف موقعو بالظبط). */
export function googleMapsSearchLink(name: string, area?: string | null) {
  const query = [name, area].filter(Boolean).join(" ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}
