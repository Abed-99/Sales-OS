"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  normalizeSyrianMobile,
  syrianPhoneState,
} from "@/lib/phone";
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
}: {
  email: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
  initialName: string;
  company: Company;
}) {
  const [name, setName] = useState(initialName);
  const [companyName, setCompanyName] =
    useState(company.name);
  const [phone, setPhone] =
    useState(company.phone || "");
  const [whatsapp, setWhatsapp] =
    useState(company.whatsapp || "");
  const [currency, setCurrency] =
    useState(company.default_currency || "USD");

  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);

  const canManage = hasPermission(
    permissions,
    "settings.manage_company",
    isOwner
  );

  async function save(event: React.FormEvent) {
    event.preventDefault();

    setMessage("");
    setSuccess(false);

    if (!name.trim()) {
      setMessage("الاسم مطلوب.");
      return;
    }

    const normalizedPhone =
      phone.trim() ? normalizeSyrianMobile(phone) : null;

    const normalizedWhatsapp =
      whatsapp.trim()
        ? normalizeSyrianMobile(whatsapp)
        : null;

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

      const { error: profileError } =
        await supabase
          .from("profiles")
          .update({
            full_name: name.trim(),
          })
          .eq("id", user.id);

      if (profileError) {
        setMessage(profileError.message);
        return;
      }

      if (canManage) {
        if (!companyName.trim()) {
          setMessage("اسم الشركة مطلوب.");
          return;
        }

        const { error: companyError } =
          await supabase
            .from("companies")
            .update({
              name: companyName.trim(),
              phone: normalizedPhone,
              whatsapp: normalizedWhatsapp,
              default_currency: currency,
            })
            .eq("id", company.id);

        if (companyError) {
          setMessage(companyError.message);
          return;
        }
      }

      setSuccess(true);
      setMessage("تم حفظ الإعدادات بنجاح.");
    } finally {
      setBusy(false);
    }
  }

  function phoneStatus(value: string) {
    if (!value.trim()) return null;

    const state = syrianPhoneState(value);

    return (
      <small
        className={
          state === "valid"
            ? "validText"
            : "invalidText"
        }
      >
        {state === "valid"
          ? "✓ رقم صحيح"
          : "رقم غير صحيح"}
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
              <input
                value={name}
                onChange={(event) =>
                  setName(event.target.value)
                }
              />
            </label>

            <label className="field">
              <span>البريد الإلكتروني</span>
              <input
                value={email}
                readOnly
                dir="ltr"
                className="readOnlyInput"
              />
            </label>

            <label className="field">
              <span>الصلاحية</span>
              <input
                value={roleName}
                readOnly
                className="readOnlyInput"
              />
            </label>
          </div>
        </section>

        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الشركة</h2>
              <p>
                {canManage
                  ? "تعديل معلومات الشركة الحالية"
                  : "هذه المعلومات للعرض فقط"}
              </p>
            </div>
          </div>

          <div className="authForm">
            <label className="field">
              <span>اسم الشركة</span>
              <input
                value={companyName}
                readOnly={!canManage}
                className={
                  canManage ? "" : "readOnlyInput"
                }
                onChange={(event) =>
                  setCompanyName(event.target.value)
                }
              />
            </label>

            <label className="field">
              <span>الهاتف</span>
              <input
                dir="ltr"
                value={phone}
                readOnly={!canManage}
                className={
                  canManage ? "" : "readOnlyInput"
                }
                onChange={(event) =>
                  setPhone(event.target.value)
                }
              />
              {canManage && phoneStatus(phone)}
            </label>

            <label className="field">
              <span>واتساب</span>
              <input
                dir="ltr"
                value={whatsapp}
                readOnly={!canManage}
                className={
                  canManage ? "" : "readOnlyInput"
                }
                onChange={(event) =>
                  setWhatsapp(event.target.value)
                }
              />
              {canManage && phoneStatus(whatsapp)}
            </label>

            <label className="field">
              <span>العملة الأساسية</span>

              <select
                value={currency}
                disabled={!canManage}
                onChange={(event) =>
                  setCurrency(event.target.value)
                }
              >
                <option value="USD">USD - دولار</option>
                <option value="SYP">SYP - ليرة سورية</option>
              </select>
            </label>
          </div>
        </section>

        <div className="settingsActions">
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
            className="primaryButton"
            disabled={busy}
          >
            {busy ? "عم نحفظ..." : "حفظ الإعدادات"}
          </button>
        </div>
      </form>
    </div>
  );
}
