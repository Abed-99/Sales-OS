"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { createClient } from "@/lib/supabase/client";

import {
  normalizeSyrianMobile,
  syrianPhoneState,
} from "@/lib/phone";

export function SetupCompanyClient() {
  const router = useRouter();

  const [name, setName] =
    useState("");

  const [phone, setPhone] =
    useState("");

  const [whatsapp, setWhatsapp] =
    useState("");

  const [currency, setCurrency] =
    useState("USD");

  const [loading, setLoading] =
    useState(false);

  const [message, setMessage] =
    useState("");

  function phoneHint(
    value: string
  ) {
    const state =
      syrianPhoneState(value);

    if (state === "valid") {
      return (
        <small className="validText">
          ✓ رقم سوري صحيح
        </small>
      );
    }

    if (state === "invalid") {
      return (
        <small className="invalidText">
          الرقم غير صحيح
        </small>
      );
    }

    return (
      <small className="helpText">
        مثال: 0944123456
      </small>
    );
  }

  async function submit(
    event: React.FormEvent
  ) {
    event.preventDefault();

    if (loading) return;

    setMessage("");

    if (name.trim().length < 2) {
      setMessage(
        "يرجى إدخال اسم الشركة بشكل صحيح."
      );
      return;
    }

    const normalizedPhone =
      phone.trim()
        ? normalizeSyrianMobile(phone)
        : null;

    const normalizedWhatsapp =
      whatsapp.trim()
        ? normalizeSyrianMobile(
            whatsapp
          )
        : null;

    if (
      phone.trim() &&
      !normalizedPhone
    ) {
      setMessage(
        "رقم الشركة غير صحيح."
      );
      return;
    }

    if (
      whatsapp.trim() &&
      !normalizedWhatsapp
    ) {
      setMessage(
        "رقم واتساب غير صحيح."
      );
      return;
    }

    setLoading(true);

    try {
      const supabase =
        createClient();

      const { error } =
        await supabase
          .from("companies")
          .insert({
            name: name.trim(),
            phone:
              normalizedPhone,
            whatsapp:
              normalizedWhatsapp,
            default_currency:
              currency,
          });

      if (error) {
        setMessage(
          "تعذر إنشاء الشركة. تحقق من البيانات وحاول مرة أخرى."
        );
        return;
      }

      router.replace("/");
      router.refresh();
    } catch {
      setMessage(
        "تعذر الاتصال بالخادم. حاول مرة أخرى."
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="setupPage">
      <section className="authCard">
        <div className="brand">
          <div className="brandMark">
            S
          </div>

          <div>
            <strong>
              Sales OS
            </strong>

            <span>
              إعداد الشركة
            </span>
          </div>
        </div>

        <span className="eyebrow">
          إعداد مساحة العمل
        </span>

        <h1>
          جهّز شركتك
        </h1>

        <p>
          هذه المعلومات تمثل الشركة
          الحالية ويمكن تعديلها لاحقًا
          من الإعدادات.
        </p>

        <form
          className="authForm"
          onSubmit={submit}
        >
          <label className="field">
            <span>
              اسم الشركة
            </span>

            <input
              required
              minLength={2}
              value={name}
              onChange={(event) =>
                setName(
                  event.target.value
                )
              }
              placeholder="مثال: عامر للتوزيع"
            />
          </label>

          <label className="field">
            <span>
              رقم الشركة
            </span>

            <input
              dir="ltr"
              value={phone}
              onChange={(event) =>
                setPhone(
                  event.target.value
                )
              }
              placeholder="0944123456"
            />

            {phoneHint(phone)}
          </label>

          <label className="field">
            <span>
              رقم واتساب
            </span>

            <input
              dir="ltr"
              value={whatsapp}
              onChange={(event) =>
                setWhatsapp(
                  event.target.value
                )
              }
              placeholder="0944123456"
            />

            {phoneHint(whatsapp)}
          </label>

          <label className="field">
            <span>
              العملة الأساسية
            </span>

            <select
              value={currency}
              onChange={(event) =>
                setCurrency(
                  event.target.value
                )
              }
            >
              <option value="USD">
                USD - دولار
              </option>

              <option value="SYP">
                SYP - ليرة سورية
              </option>
            </select>
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
            disabled={loading}
          >
            {loading
              ? "جارٍ تجهيز الشركة..."
              : "إنشاء الشركة والمتابعة"}
          </button>
        </form>
      </section>
    </main>
  );
}

