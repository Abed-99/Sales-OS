"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function LoginClient() {
  const router = useRouter();

  const [supabase] = useState(() => createClient());
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();

    setLoading(true);
    setMessage("");
    setSuccess(false);

    try {
      if (mode === "signup") {
        if (password.length < 8) {
          setMessage("كلمة المرور لازم تكون 8 محارف على الأقل.");
          return;
        }

        const redirectTo =
          `${window.location.origin}/auth/callback?next=/`;

        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            emailRedirectTo: redirectTo,
            data: {
              full_name: name.trim(),
            },
          },
        });

        if (error) {
          setMessage(error.message);
          return;
        }

        if (!data.session) {
          setSuccess(true);
          setMessage(
            "تم إنشاء الحساب. افتح رسالة التأكيد في بريدك الإلكتروني، وبعد التأكيد سجل دخولك."
          );
          return;
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });

        if (error) {
          setMessage("البريد الإلكتروني أو كلمة المرور غير صحيحة.");
          return;
        }
      }

      router.replace("/");
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  function changeMode(nextMode: "login" | "signup") {
    setMode(nextMode);
    setMessage("");
    setSuccess(false);
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

        <h1>
          {mode === "login"
            ? "أهلًا بعودتك"
            : "أنشئ حسابك"}
        </h1>

        <p>
          التجار، الموردين، الطلبات، المشتريات،
          التوصيل والصندوق في نظام واحد.
        </p>

        <div className="authTabs">
          <button
            type="button"
            className={mode === "login" ? "active" : ""}
            onClick={() => changeMode("login")}
          >
            تسجيل الدخول
          </button>

          <button
            type="button"
            className={mode === "signup" ? "active" : ""}
            onClick={() => changeMode("signup")}
          >
            حساب جديد
          </button>
        </div>

        <form className="authForm" onSubmit={submit}>
          {mode === "signup" && (
            <label className="field">
              <span>الاسم</span>
              <input
                required
                minLength={2}
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="الاسم الكامل"
              />
            </label>
          )}

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
              minLength={mode === "signup" ? 8 : 6}
              required
              autoComplete={
                mode === "login"
                  ? "current-password"
                  : "new-password"
              }
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="••••••••"
              dir="ltr"
            />
          </label>

          {mode === "login" && (
            <div className="authHelperRow">
              <Link href="/forgot-password">
                نسيت كلمة المرور؟
              </Link>
            </div>
          )}

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
            disabled={loading}
          >
            {loading
              ? "لحظة..."
              : mode === "login"
                ? "دخول إلى Sales OS"
                : "إنشاء الحساب"}
          </button>
        </form>
      </section>
    </main>
  );
}