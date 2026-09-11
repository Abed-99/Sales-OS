"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={<ResetPasswordShell busy />}>
      <ResetPasswordForm />
    </Suspense>
  );
}

function ResetPasswordForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const isInvite = searchParams.get("invite") === "1";

  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");

    if (password.length < 8) {
      setMessage("كلمة المرور لازم تكون 8 محارف على الأقل.");
      return;
    }

    if (password !== repeat) {
      setMessage("كلمتا المرور غير متطابقتين.");
      return;
    }

    setBusy(true);

    try {
      const supabase = createClient();
      const { error } = await supabase.auth.updateUser({ password });

      if (error) {
        setMessage(error.message);
        return;
      }

      if (isInvite) {
        router.replace("/");
        router.refresh();
        return;
      }

      await supabase.auth.signOut();
      router.replace("/login");
      router.refresh();
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
            <span>{isInvite ? "دعوة الفريق" : "الأمان"}</span>
          </div>
        </div>

        <span className="eyebrow">
          {isInvite ? "تفعيل حساب الموظف" : "أمان الحساب"}
        </span>
        <h1>{isInvite ? "أنشئ كلمة مرورك" : "كلمة مرور جديدة"}</h1>

        <p>
          {isInvite
            ? "تمت دعوتك إلى فريق Sales OS. اختر كلمة مرور قوية للدخول إلى الشركة حسب الصلاحيات الممنوحة لك."
            : "اختر كلمة مرور قوية ولا تستخدم نفس كلمة المرور بحسابات أخرى."}
        </p>

        <form className="authForm" onSubmit={submit}>
          <label className="field">
            <span>كلمة المرور الجديدة</span>
            <input
              required
              type="password"
              minLength={8}
              dir="ltr"
              autoComplete="new-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>

          <label className="field">
            <span>تأكيد كلمة المرور</span>
            <input
              required
              type="password"
              minLength={8}
              dir="ltr"
              autoComplete="new-password"
              value={repeat}
              onChange={(event) => setRepeat(event.target.value)}
            />
          </label>

          {message ? <div className="toastError">{message}</div> : null}

          <button className="primaryButton authSubmit" disabled={busy}>
            {busy
              ? "عم نحفظ..."
              : isInvite
                ? "تفعيل الحساب والدخول"
                : "حفظ كلمة المرور"}
          </button>
        </form>
      </section>
    </main>
  );
}

function ResetPasswordShell({ busy }: { busy: boolean }) {
  return (
    <main className="loginPage">
      <section className="authCard">
        <div className="brand">
          <div className="brandMark">S</div>
          <div>
            <strong>Sales OS</strong>
            <span>الأمان</span>
          </div>
        </div>
        <span className="eyebrow">أمان الحساب</span>
        <h1>كلمة مرور جديدة</h1>
        <p>{busy ? "عم نجهز الصفحة..." : ""}</p>
      </section>
    </main>
  );
}
