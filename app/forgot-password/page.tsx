"use client";

import Link from "next/link";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();

    if (busy) return;

    setBusy(true);
    setMessage("");
    setSuccess(false);

    try {
      const supabase = createClient();

      const redirectTo =
        `${window.location.origin}/auth/callback?next=/reset-password`;

      const { error } = await supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        {
          redirectTo,
        }
      );

      if (error) {
        setMessage(
          "تعذر إرسال رابط الاستعادة الآن. حاول مرة أخرى بعد قليل."
        );
        return;
      }

      setSuccess(true);

      setMessage(
        "إذا كان البريد مسجلًا لدينا، فستصلك رسالة تحتوي على رابط لتعيين كلمة سر جديدة."
      );
    } catch {
      setMessage("تعذر الاتصال بالخادم. حاول مرة أخرى.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="loginPage">
      <section className="authCard">
        <div className="brand">
          <div className="brandMark">S</div>

          <div>
            <strong>Sales OS</strong>
            <span>استعادة الحساب</span>
          </div>
        </div>

        <span className="eyebrow">أمان الحساب</span>

        <h1>نسيت كلمة السر؟</h1>

        <p>
          أدخل بريدك الإلكتروني وسنرسل لك رابطًا لتعيين كلمة سر جديدة.
        </p>

        <form className="authForm" onSubmit={submit}>
          <label className="field">
            <span>البريد الإلكتروني</span>

            <input
              required
              type="email"
              dir="ltr"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="name@email.com"
            />
          </label>

          {message && (
            <div
              className={success ? "toastSuccess" : "toastError"}
              role={success ? "status" : "alert"}
              aria-live="polite"
            >
              {message}
            </div>
          )}

          <button
            type="submit"
            className="primaryButton authSubmit"
            disabled={busy}
          >
            {busy ? "جارٍ الإرسال..." : "إرسال رابط الاستعادة"}
          </button>

          <Link className="authBackLink" href="/login">
            العودة إلى تسجيل الدخول
          </Link>
        </form>
      </section>
    </main>
  );
}
