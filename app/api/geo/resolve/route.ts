import { NextResponse } from "next/server";

import { parseLatLng } from "@/lib/geo-link";
import { createClient } from "@/lib/supabase/server";

// بس روابط خرائط Google، لحتى ما ينستعمل السيرفر لفتح أي رابط عالنت.
const ALLOWED_HOSTS = new Set([
  "maps.app.goo.gl",
  "goo.gl",
  "g.co",
  "maps.google.com",
  "google.com",
  "www.google.com",
]);

function allowed(url: URL) {
  return url.protocol === "https:" && (ALLOWED_HOSTS.has(url.hostname) || /^www\.google\.[a-z.]+$/.test(url.hostname));
}

/** بيفتح رابط Google Maps القصير (maps.app.goo.gl/...) وبيرجّع الإحداثيات اللي فيه. */
export async function POST(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  let current: URL;
  try {
    const body = await request.json();
    current = new URL(String(body?.url ?? "").trim());
  } catch {
    return NextResponse.json({ error: "Invalid link" }, { status: 400 });
  }

  for (let hop = 0; hop < 5; hop += 1) {
    if (!allowed(current)) return NextResponse.json({ error: "Not a Google Maps link" }, { status: 400 });

    const found = parseLatLng(current.toString());
    if (found) return NextResponse.json(found);

    const response = await fetch(current, { redirect: "manual", signal: AbortSignal.timeout(8000) });
    const next = response.headers.get("location");
    if (!next) {
      // آخر صفحة: أحيانًا الإحداثيات بس جوّا الصفحة نفسها.
      const html = response.ok ? (await response.text()).slice(0, 200_000) : "";
      const inPage = parseLatLng(html.match(/https:\/\/www\.google\.[^"'\s]*\/maps[^"'\s]*/)?.[0] ?? "");
      return inPage
        ? NextResponse.json(inPage)
        : NextResponse.json({ error: "No location in link" }, { status: 404 });
    }
    current = new URL(next, current);
  }

  return NextResponse.json({ error: "Too many redirects" }, { status: 400 });
}
