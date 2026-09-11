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

    setBusy(true);
    setMessage("");
    setSuccess(false);

    try {
      const supabase = createClient();

      const redirectTo =
        `${window.location.origin}/auth/callback?next=/reset-password`;

      const { error } =
        await supabase.auth.resetPasswordForEmail(email.trim(), {
          redirectTo,
        });

      if (error) {
        setMessage(error.message);
        return;
      }

      setSuccess(true);
      setMessage(
        "أرسلنا رابط استعادة كلمة المرور إذا كان البريد مسجلًا لدينا."
      );
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
        <h1>نسيت كلمة المرور؟</h1>

        <p>
          اكتب بريدك الإلكتروني وسنرسل لك رابطًا لتعيين
          كلمة مرور جديدة.
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
            />
          </label>

          {message && (
            <div
              className={
                success ? "toastSuccess" : "toastError"
              }
            >
              {message}
            </div>
          )}

          <button
            className="primaryButton authSubmit"
            disabled={busy}
          >
            {busy ? "لحظة..." : "إرسال رابط الاستعادة"}
          </button>

          <Link className="authBackLink" href="/login">
            العودة إلى تسجيل الدخول
          </Link>
        </form>
      </section>
    </main>
  );
}