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
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(initialMessage);
  const [success, setSuccess] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();

    if (loading) return;

    setLoading(true);
    setMessage("");
    setSuccess(false);

    try {
      if (mode === "signup") {
        if (name.trim().length < 2) {
          setMessage("يرجى إدخال الاسم بشكل صحيح.");
          return;
        }

        if (password.length < 8) {
          setMessage("كلمة المرور يجب أن تكون 8 محارف على الأقل.");
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
          setMessage(
            "تعذر إنشاء الحساب. تحقق من البيانات وحاول مرة أخرى."
          );
          return;
        }

        if (!data.session) {
          setSuccess(true);
          setMessage(
            "تم إنشاء الحساب. تحقق من بريدك الإلكتروني لإكمال تفعيل الحساب."
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
    } catch {
      setMessage("حدث خطأ أثناء الاتصال بالخادم. حاول مرة أخرى.");
    } finally {
      setLoading(false);
    }
  }

  function changeMode(nextMode: "login" | "signup") {
    setMode(nextMode);
    setMessage("");
    setSuccess(false);
    setPassword("");
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
          {mode === "login" ? "أهلًا بعودتك" : "أنشئ حسابك"}
        </h1>

        <p>
          التجار، الموردون، الطلبات، المشتريات، التوصيل والصندوق في نظام واحد.
        </p>

        <div className="authTabs">
          <button
            type="button"
            className={mode === "login" ? "active" : ""}
            onClick={() => changeMode("login")}
            disabled={loading}
          >
            تسجيل الدخول
          </button>

          <button
            type="button"
            className={mode === "signup" ? "active" : ""}
            onClick={() => changeMode("signup")}
            disabled={loading}
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
                autoComplete="name"
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
              required
              minLength={mode === "signup" ? 8 : 1}
              autoComplete={
                mode === "login" ? "current-password" : "new-password"
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
            disabled={loading}
          >
            {loading
              ? "جارٍ التنفيذ..."
              : mode === "login"
                ? "دخول إلى Sales OS"
                : "إنشاء الحساب"}
          </button>
        </form>
      </section>
    </main>
  );
}
