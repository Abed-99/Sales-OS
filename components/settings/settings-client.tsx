"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { anyPhoneState, normalizeAnyPhone } from "@/lib/phone";
import { hasPermission } from "@/lib/permissions";

type Company = {
  id: string;
  name: string;
  phone: string | null;
  whatsapp: string | null;
  default_currency: string;
};

export function SettingsClient({
  email,
  roleName,
  isOwner,
  permissions,
  initialName,
  company,
  currencyLocked,
  hasOwnerPin = false,
}: {
  email: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
  initialName: string;
  company: Company;
  currencyLocked: boolean;
  hasOwnerPin?: boolean;
}) {
  const router = useRouter();
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordMessage, setPasswordMessage] = useState("");
  const [passwordOk, setPasswordOk] = useState(false);

  const [ownerPin, setOwnerPin] = useState("");
  const [pinMessage, setPinMessage] = useState("");
  const [pinOk, setPinOk] = useState(false);

  async function saveOwnerPin() {
    setPinMessage("");
    setPinOk(false);
    if (!/^[0-9]{4,8}$/.test(ownerPin)) {
      setPinMessage("الرمز لازم يكون من 4 لـ 8 أرقام.");
      return;
    }
    setBusy(true);
    const { error } = await createClient().rpc("set_owner_pin", {
      target_company: company.id,
      target_pin: ownerPin,
    });
    setBusy(false);
    if (error) {
      setPinMessage("ما قدرنا نحفظ الرمز.");
      return;
    }
    setOwnerPin("");
    setPinOk(true);
    setPinMessage("انحفظ رمز الموافقة.");
  }

  async function changePassword() {
    setPasswordMessage("");
    setPasswordOk(false);
    if (newPassword.length < 8) {
      setPasswordMessage("كلمة السر لازم تكون 8 أحرف على الأقل.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordMessage("كلمتين السر مو متطابقين.");
      return;
    }
    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password: newPassword });
    setBusy(false);
    if (error) {
      setPasswordMessage(
        error.message.toLowerCase().includes("different")
          ? "كلمة السر الجديدة لازم تكون غير القديمة."
          : "تعذر تغيير كلمة السر. جرّب مرة تانية.",
      );
      return;
    }
    setNewPassword("");
    setConfirmPassword("");
    setPasswordOk(true);
    setPasswordMessage("تغيّرت كلمة السر.");
  }

  const [name, setName] = useState(initialName);
  const [companyName, setCompanyName] = useState(company.name);
  const [phone, setPhone] = useState(company.phone || "");
  const [whatsapp, setWhatsapp] = useState(company.whatsapp || "");
  const [currency, setCurrency] = useState(company.default_currency || "USD");

  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);

  const canManage = hasPermission(permissions, "settings.manage_company", isOwner);

  async function save(event: React.FormEvent) {
    event.preventDefault();

    setMessage("");
    setSuccess(false);

    if (!name.trim()) {
      setMessage("الاسم مطلوب.");
      return;
    }

    const normalizedPhone = phone.trim() ? normalizeAnyPhone(phone) : null;

    const normalizedWhatsapp = whatsapp.trim() ? normalizeAnyPhone(whatsapp) : null;

    if (phone && !normalizedPhone) {
      setMessage("رقم الشركة غير صحيح.");
      return;
    }

    if (whatsapp && !normalizedWhatsapp) {
      setMessage("رقم واتساب غير صحيح.");
      return;
    }

    setBusy(true);

    try {
      const supabase = createClient();

      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        setMessage("انتهت الجلسة. سجل دخولك من جديد.");
        return;
      }

      const { error: profileError } = await supabase
        .from("profiles")
        .update({
          full_name: name.trim(),
        })
        .eq("id", user.id);

      if (profileError) {
        setMessage("تعذر تحديث بيانات الحساب.");
        return;
      }

      if (canManage) {
        if (!companyName.trim()) {
          setMessage("اسم الشركة مطلوب.");
          return;
        }

        const { error: companyError } = await supabase
          .from("companies")
          .update({
            name: companyName.trim(),
            phone: normalizedPhone,
            whatsapp: normalizedWhatsapp,
            ...(currencyLocked ? {} : { default_currency: currency.trim().toUpperCase() }),
          })
          .eq("id", company.id);

        if (companyError) {
          setMessage(
            companyError.message.includes("cannot change after accounting history")
              ? "ما فيك تغيّر العملة الأساسية بعد ما صار في حركات مالية."
              : "تعذر تحديث بيانات الشركة. تحقق من الصلاحيات.",
          );
          return;
        }
      }

      setSuccess(true);
      setMessage("تم حفظ الإعدادات بنجاح.");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  function phoneStatus(value: string) {
    if (!value.trim()) return null;

    const state = anyPhoneState(value);

    return (
      <small className={state === "valid" ? "validText" : "invalidText"}>
        {state === "valid" ? "✓ رقم صحيح" : "رقم غير صحيح"}
      </small>
    );
  }

  return (
    <div className="page">
      <form className="settingsGrid" onSubmit={save}>
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الحساب</h2>
              <p>معلومات المستخدم الحالي</p>
            </div>
          </div>

          <div className="authForm">
            <label className="field">
              <span>الاسم</span>
              <input value={name} onChange={(event) => setName(event.target.value)} />
            </label>

            <label className="field">
              <span>البريد الإلكتروني</span>
              <input value={email} readOnly dir="ltr" className="readOnlyInput" />
            </label>

            <label className="field">
              <span>الصلاحية</span>
              <input value={roleName} readOnly className="readOnlyInput" />
            </label>
          </div>
        </section>

        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الشركة</h2>
              <p>{canManage ? "تعديل معلومات الشركة الحالية" : "هذه المعلومات للعرض فقط"}</p>
            </div>
          </div>

          <div className="authForm">
            <label className="field">
              <span>اسم الشركة</span>
              <input
                value={companyName}
                readOnly={!canManage}
                className={canManage ? "" : "readOnlyInput"}
                onChange={(event) => setCompanyName(event.target.value)}
              />
            </label>

            <label className="field">
              <span>الهاتف</span>
              <input
                dir="ltr"
                value={phone}
                readOnly={!canManage}
                className={canManage ? "" : "readOnlyInput"}
                onChange={(event) => setPhone(event.target.value)}
              />
              {canManage && phoneStatus(phone)}
            </label>

            <label className="field">
              <span>واتساب</span>
              <input
                dir="ltr"
                value={whatsapp}
                readOnly={!canManage}
                className={canManage ? "" : "readOnlyInput"}
                onChange={(event) => setWhatsapp(event.target.value)}
              />
              {canManage && phoneStatus(whatsapp)}
            </label>

            <label className="field">
              <span>العملة الأساسية</span>

              <select
                value={currency}
                disabled={!canManage || currencyLocked}
                onChange={(event) => setCurrency(event.target.value)}
              >
                <option value="USD">USD - دولار</option>
                <option value="SYP">SYP - ليرة سورية</option>
              </select>
              {currencyLocked ? (
                <small className="helpText">
                  ما بتتغيّر بعد أول حركة مالية، لأنو كل الحسابات مكتوبة على أساسها.
                </small>
              ) : null}
            </label>
          </div>
        </section>

        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>كلمة السر</h2>
              <p>غيّر كلمة السر تبع حسابك</p>
            </div>
          </div>

          <div className="authForm">
            <label className="field">
              <span>كلمة السر الجديدة</span>
              <input
                type="password"
                dir="ltr"
                autoComplete="new-password"
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
              />
            </label>

            <label className="field">
              <span>أعد كتابتها</span>
              <input
                type="password"
                dir="ltr"
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
              />
            </label>

            {passwordMessage ? (
              <div className={passwordOk ? "toastSuccess" : "toastError"}>{passwordMessage}</div>
            ) : null}

            <button
              type="button"
              className="softButton"
              disabled={busy || !newPassword}
              onClick={() => void changePassword()}
            >
              تغيير كلمة السر
            </button>
          </div>
        </section>

        {isOwner ? (
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>رمز موافقة المالك</h2>
                <p>
                  رمز أرقام بتكتبو قدام الموظف ليمشّي عملية حساسة (بيع تحت الكلفة، تجاوز حد الدين،
                  إلغاء فاتورة، عكس دفعة أو مرتجع) لمرة وحدة.
                </p>
              </div>
            </div>

            <div className="authForm">
              <label className="field">
                <span>{hasOwnerPin ? "رمز جديد (بيبدّل القديم)" : "الرمز"}</span>
                <input
                  type="password"
                  inputMode="numeric"
                  autoComplete="new-password"
                  dir="ltr"
                  maxLength={8}
                  placeholder="4 لـ 8 أرقام"
                  value={ownerPin}
                  onChange={(event) => setOwnerPin(event.target.value.replace(/\D/g, ""))}
                />
              </label>

              {pinMessage ? (
                <div className={pinOk ? "toastSuccess" : "toastError"}>{pinMessage}</div>
              ) : null}

              <button
                type="button"
                className="softButton"
                disabled={busy || ownerPin.length < 4}
                onClick={() => void saveOwnerPin()}
              >
                حفظ الرمز
              </button>
            </div>
          </section>
        ) : null}

        <div className="settingsActions">
          {message && <div className={success ? "toastSuccess" : "toastError"}>{message}</div>}

          <button className="primaryButton" disabled={busy}>
            {busy ? "عم نحفظ..." : "حفظ الإعدادات"}
          </button>
        </div>
      </form>
    </div>
  );
}
