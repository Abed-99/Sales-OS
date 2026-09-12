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
          âœ“ Ø±Ù‚Ù… Ø³ÙˆØ±ÙŠ ØµØ­ÙŠØ­
        </small>
      );
    }

    if (state === "invalid") {
      return (
        <small className="invalidText">
          Ø§Ù„Ø±Ù‚Ù… ØºÙŠØ± ØµØ­ÙŠØ­
        </small>
      );
    }

    return (
      <small className="helpText">
        Ù…Ø«Ø§Ù„: 0944123456
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
        "ÙŠØ±Ø¬Ù‰ Ø¥Ø¯Ø®Ø§Ù„ Ø§Ø³Ù… Ø§Ù„Ø´Ø±ÙƒØ© Ø¨Ø´ÙƒÙ„ ØµØ­ÙŠØ­."
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
        "Ø±Ù‚Ù… Ø§Ù„Ø´Ø±ÙƒØ© ØºÙŠØ± ØµØ­ÙŠØ­."
      );
      return;
    }

    if (
      whatsapp.trim() &&
      !normalizedWhatsapp
    ) {
      setMessage(
        "Ø±Ù‚Ù… ÙˆØ§ØªØ³Ø§Ø¨ ØºÙŠØ± ØµØ­ÙŠØ­."
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
          "ØªØ¹Ø°Ø± Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø´Ø±ÙƒØ©. ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª ÙˆØ­Ø§ÙˆÙ„ Ù…Ø±Ø© Ø£Ø®Ø±Ù‰."
        );
        return;
      }

      router.replace("/");
      router.refresh();
    } catch {
      setMessage(
        "ØªØ¹Ø°Ø± Ø§Ù„Ø§ØªØµØ§Ù„ Ø¨Ø§Ù„Ø®Ø§Ø¯Ù…. Ø­Ø§ÙˆÙ„ Ù…Ø±Ø© Ø£Ø®Ø±Ù‰."
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
              Ø¥Ø¹Ø¯Ø§Ø¯ Ø§Ù„Ø´Ø±ÙƒØ©
            </span>
          </div>
        </div>

        <span className="eyebrow">
          Ø¥Ø¹Ø¯Ø§Ø¯ Ù…Ø³Ø§Ø­Ø© Ø§Ù„Ø¹Ù…Ù„
        </span>

        <h1>
          Ø¬Ù‡Ù‘Ø² Ø´Ø±ÙƒØªÙƒ
        </h1>

        <p>
          Ù‡Ø°Ù‡ Ø§Ù„Ù…Ø¹Ù„ÙˆÙ…Ø§Øª ØªÙ…Ø«Ù„ Ø§Ù„Ø´Ø±ÙƒØ©
          Ø§Ù„Ø­Ø§Ù„ÙŠØ© ÙˆÙŠÙ…ÙƒÙ† ØªØ¹Ø¯ÙŠÙ„Ù‡Ø§ Ù„Ø§Ø­Ù‚Ù‹Ø§
          Ù…Ù† Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª.
        </p>

        <form
          className="authForm"
          onSubmit={submit}
        >
          <label className="field">
            <span>
              Ø§Ø³Ù… Ø§Ù„Ø´Ø±ÙƒØ©
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
              placeholder="Ù…Ø«Ø§Ù„: Ø¹Ø§Ù…Ø± Ù„Ù„ØªÙˆØ²ÙŠØ¹"
            />
          </label>

          <label className="field">
            <span>
              Ø±Ù‚Ù… Ø§Ù„Ø´Ø±ÙƒØ©
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
              Ø±Ù‚Ù… ÙˆØ§ØªØ³Ø§Ø¨
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
              Ø§Ù„Ø¹Ù…Ù„Ø© Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ©
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
                USD - Ø¯ÙˆÙ„Ø§Ø±
              </option>

              <option value="SYP">
                SYP - Ù„ÙŠØ±Ø© Ø³ÙˆØ±ÙŠØ©
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
              ? "Ø¬Ø§Ø±Ù ØªØ¬Ù‡ÙŠØ² Ø§Ù„Ø´Ø±ÙƒØ©..."
              : "Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø´Ø±ÙƒØ© ÙˆØ§Ù„Ù…ØªØ§Ø¨Ø¹Ø©"}
          </button>
        </form>
      </section>
    </main>
  );
}

