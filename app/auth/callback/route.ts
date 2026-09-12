import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function safeNext(value: string | null) {
  const requested = value || "/";

  if (
    !requested.startsWith("/") ||
    requested.startsWith("//")
  ) {
    return "/";
  }

  return requested;
}

export async function GET(request: NextRequest) {
  const url = new URL(request.url);

  const code = url.searchParams.get("code");

  const next = safeNext(
    url.searchParams.get("next")
  );

  if (!code) {
    return NextResponse.redirect(
      new URL(
        "/login?error=auth_callback",
        request.nextUrl.origin
      )
    );
  }

  const supabase = await createClient();

  const { error } =
    await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      new URL(
        "/login?error=auth_callback",
        request.nextUrl.origin
      )
    );
  }

  return NextResponse.redirect(
    new URL(next, request.nextUrl.origin)
  );
}
