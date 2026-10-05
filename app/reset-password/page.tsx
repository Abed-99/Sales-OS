"use client";

import Link from "next/link";
import {
  Suspense,
  useEffect,
  useMemo,
  useState,
} from "react";

import {
  useRouter,
  useSearchParams,
} from "next/navigation";

import { createClient } from "@/lib/supabase/client";

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={<ResetPasswordShell />}>
      <ResetPasswordForm />
    </Suspense>
  );
}

function ResetPasswordForm() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const supabase = useMemo(
    () => createClient(),
    []
  );

  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [busy, setBusy] = useState(false);

  const [
    checkingSession,
    setCheckingSession,
  ] = useState(true);

  const [
    sessionValid,
    setSessionValid,
  ] = useState(false);

  const [message, setMessage] = useState("");
  const [invite, setInvite] = useState(false);

  useEffect(() => {
    let active = true;

    async function verifySession() {
      const {
        data: { user },
        error,
      } = await supabase.auth.getUser();

      if (!active) return;

      if (error || !user) {
        setSessionValid(false);

        setMessage(
          "رابط الاستعادة غير صالح أو انتهت صلاحيته. اطلب رابط استعادة جديدًا."
        );

        setCheckingSession(false);
        return;
      }

      const requestedInvite =
        searchParams.get("invite") === "1";

      const invitedCompanyId =
        user.user_metadata?.invited_company_id;

      setInvite(
        requestedInvite &&
          Boolean(invitedCompanyId)
      );

      setSessionValid(true);
      setCheckingSession(false);
    }

    void verifySession();

    return () => {
      active = false;
    };
  }, [searchParams, supabase]);

  async function submit(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (busy) return;

    setMessage("");

    if (!sessionValid) {
      setMessage(
        "رابط الاستعادة غير صالح أو انتهت صلاحيته."
      );
      return;
    }

    if (password.length < 8) {
      setMessage(
        "كلمة السر لازم تكون 8 أحرف على الأقل."
      );
      return;
    }

    if (password !== repeat) {
      setMessage("كلمتين السر مش متطابقين.");
      return;
    }

    setBusy(true);

    try {
      const { error } =
        await supabase.auth.updateUser({
          password,
        });

      if (error) {
        const text = error.message.toLowerCase();
        setMessage(
          text.includes("different from the old")
            ? "كلمة السر الجديدة لازم تكون غير القديمة."
            : text.includes("weak") || text.includes("characters")
              ? "كلمة السر ضعيفة. استعمل أحرف وأرقام وطوّلها شوي."
              : "تعذر حفظ كلمة السر الجديدة. اطلب رابط استعادة جديدًا وحاول مرة أخرى."
        );
        return;
      }

      if (invite) {
        router.replace("/");
        router.refresh();
        return;
      }

      const { error: signOutError } =
        await supabase.auth.signOut();

      if (signOutError) {
        setMessage(
          "تم تغيير كلمة السر، لكن تعذر تسجيل الخروج تلقائيًا. أغلق الصفحة ثم سجّل الدخول بكلمة السر الجديدة."
        );
        return;
      }

      router.replace("/login");
      router.refresh();
    } catch {
      setMessage(
        "حدث خطأ أثناء حفظ كلمة السر. حاول مرة أخرى."
      );
    } finally {
      setBusy(false);
    }
  }

  if (checkingSession) {
    return <ResetPasswordShell />;
  }

  if (!sessionValid) {
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

          <span className="eyebrow">
            أمان الحساب
          </span>

          <h1>
            تعذر فتح رابط الاستعادة
          </h1>

          <div
            className="toastError"
            role="alert"
            aria-live="polite"
          >
            {message}
          </div>

          <Link
            className="authBackLink"
            href="/forgot-password"
          >
            طلب رابط استعادة جديد
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main className="loginPage">
      <section className="authCard">
        <div className="brand">
          <div className="brandMark">S</div>

          <div>
            <strong>Sales OS</strong>

            <span>
              {invite
                ? "دعوة الفريق"
                : "الأمان"}
            </span>
          </div>
        </div>

        <span className="eyebrow">
          {invite
            ? "تفعيل حساب الموظف"
            : "أمان الحساب"}
        </span>

        <h1>
          {invite
            ? "أنشئ كلمة السر تبعك"
            : "كلمة سر جديدة"}
        </h1>

        <p>
          {invite
            ? "تمت دعوتك إلى فريق Sales OS. اختر كلمة سر قوية للدخول إلى الشركة حسب الصلاحيات الممنوحة لك."
            : "اختر كلمة سر قوية ولا تستخدم كلمة السر نفسها في حسابات أخرى."}
        </p>

        <form
          className="authForm"
          onSubmit={submit}
        >
          <label className="field">
            <span>
              كلمة السر الجديدة
            </span>

            <input
              required
              type="password"
              minLength={8}
              dir="ltr"
              autoComplete="new-password"
              value={password}
              onChange={(event) =>
                setPassword(event.target.value)
              }
            />
          </label>

          <label className="field">
            <span>
              تأكيد كلمة السر
            </span>

            <input
              required
              type="password"
              minLength={8}
              dir="ltr"
              autoComplete="new-password"
              value={repeat}
              onChange={(event) =>
                setRepeat(event.target.value)
              }
            />
          </label>

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
            disabled={busy}
          >
            {busy
              ? "جارٍ الحفظ..."
              : invite
                ? "تفعيل الحساب والدخول"
                : "حفظ كلمة السر"}
          </button>
        </form>
      </section>
    </main>
  );
}

function ResetPasswordShell() {
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

        <span className="eyebrow">
          أمان الحساب
        </span>

        <h1>
          كلمة سر جديدة
        </h1>

        <p>
          جارٍ التحقق من رابط الاستعادة...
        </p>
      </section>
    </main>
  );
}
