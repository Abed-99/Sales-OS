"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { createClient } from "@/lib/supabase/client";

type LoginClientProps = {
  initialMessage?: string;
};

export function LoginClient({
  initialMessage = "",
}: LoginClientProps) {
  const router = useRouter();
  const [supabase] = useState(() => createClient());

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(initialMessage);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (loading) return;

    setLoading(true);
    setMessage("");

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) {
        setMessage("البريد الإلكتروني أو كلمة المرور غير صحيحة.");
        return;
      }

      router.replace("/");
      router.refresh();
    } catch {
      setMessage("حدث خطأ أثناء الاتصال بالخادم. حاول مرة أخرى.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="loginPage">
      <section className="authCard">
        <div className="brand">
          <div className="brandMark">S</div>
          <div>
            <strong>Sales OS</strong>
            <span>Distribution Suite</span>
          </div>
        </div>

        <span className="eyebrow">
          نظام إدارة المبيعات والتوزيع
        </span>

        <h1>أهلًا بعودتك</h1>

        <p>
          التجار، الموردون، الطلبات، المشتريات، التوصيل والصندوق في نظام واحد.
        </p>

        <form className="authForm" onSubmit={submit}>
          <label className="field">
            <span>البريد الإلكتروني</span>
            <input
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="name@email.com"
              dir="ltr"
            />
          </label>

          <label className="field">
            <span>كلمة المرور</span>
            <input
              type="password"
              required
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="••••••••"
              dir="ltr"
            />
          </label>

          <div className="authHelperRow">
            <Link href="/forgot-password">
              نسيت كلمة المرور؟
            </Link>
          </div>

          {message && (
            <div
              className="toastError"
              role="alert"
              aria-live="polite"
            >
              {message}
            </div>
          )}

          <button
            type="submit"
            className="primaryButton authSubmit"
            disabled={loading}
          >
            {loading ? "جارٍ التنفيذ..." : "دخول إلى Sales OS"}
          </button>

          <p className="muted">
            ما عندك حساب؟ الحسابات بتنعمل بدعوة من مدير الشركة.
          </p>
        </form>
      </section>
    </main>
  );
}
