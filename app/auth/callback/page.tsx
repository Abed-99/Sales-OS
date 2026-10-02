"use client";

import { useEffect } from "react";

import { createClient } from "@/lib/supabase/client";

function safeNext(value: string | null) {
  const requested = value || "/";
  if (!requested.startsWith("/") || requested.startsWith("//")) return "/";
  return requested;
}

/**
 * صفحة رجعة روابط الإيميل (دعوة موظف، نسيت كلمة السر).
 * رابط "نسيت كلمة السر" بيرجع بـ ?code=، بس رابط الدعوة بيرجع بمعلومات الدخول بعد علامة #،
 * وهي ما بتوصل للسيرفر أبدًا؛ لهيك الصفحة بتشتغل بالمتصفح وبتقرأ الحالتين.
 */
export default function AuthCallbackPage() {
  useEffect(() => {
    void (async () => {
      const url = new URL(window.location.href);
      const next = safeNext(url.searchParams.get("next"));
      const hash = new URLSearchParams(url.hash.slice(1));
      const supabase = createClient();

      const code = url.searchParams.get("code");
      const accessToken = hash.get("access_token");
      const refreshToken = hash.get("refresh_token");

      let ok = false;
      if (accessToken && refreshToken) {
        // رابط دعوة: معلومات الدخول بالرابط نفسو، ومنقدّمها على أي جلسة قديمة بالمتصفح.
        ok = !(
          await supabase.auth.setSession({ access_token: accessToken, refresh_token: refreshToken })
        ).error;
      } else {
        // المكتبة بتستعمل ?code= لحالها أول ما تشتغل (والرمز بيمشي مرة وحدة)،
        // فمنستنى تخلص؛ ومنجرّب بإيدنا بس إذا ما طلعت جلسة.
        ok = Boolean((await supabase.auth.getSession()).data.session);
        if (!ok && code) ok = !(await supabase.auth.exchangeCodeForSession(code)).error;
      }

      window.location.replace(ok ? next : "/login?error=auth_callback");
    })();
  }, []);

  return (
    <main className="loginPage">
      <section className="authCard">
        <p>لحظة، عم نجهّز حسابك...</p>
      </section>
    </main>
  );
}
