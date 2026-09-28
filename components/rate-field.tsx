"use client";

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * خانة "1 USD = كم ليرة" لعملية بعملة غير الأساسية. بتتعبّى بآخر سعر، والموظف بيعدّلها
 * إذا السعر تغيّر. قبل ما تنحفظ العملية لازم تنادي `applyTransactionRate`.
 */
export function RateField({
  supabase,
  companyId,
  currency,
  baseCurrency,
  date,
  value,
  onChange,
}: {
  supabase: SupabaseClient;
  companyId: string;
  currency: string;
  baseCurrency: string;
  date: string;
  value: string;
  onChange: (value: string) => void;
}) {
  const [loadedFor, setLoadedFor] = useState("");
  const needed = Boolean(currency) && currency.toUpperCase() !== baseCurrency.toUpperCase();
  const key = `${currency}:${date}`;

  useEffect(() => {
    if (!needed || loadedFor === key) return;
    let cancelled = false;
    void supabase
      .rpc("get_units_per_base", {
        target_company: companyId,
        target_currency: currency,
        target_date: date || null,
      })
      .then(({ data }) => {
        if (cancelled) return;
        setLoadedFor(key);
        if (data != null && !value) onChange(String(Number(data)));
      });
    return () => {
      cancelled = true;
    };
  }, [needed, key, loadedFor, supabase, companyId, currency, date, value, onChange]);

  if (!needed) return null;

  return (
    <label className="field">
      <span>
        سعر الصرف الآن: 1 {baseCurrency} = كم {currency}؟
      </span>
      <input
        type="number"
        min="0"
        step="any"
        inputMode="decimal"
        dir="ltr"
        placeholder="مثلًا 13000"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
      <small className="helpText">العملية بتنسجّل بهالسعر بالذات.</small>
    </label>
  );
}

/** بيسجّل سعر العملية قبل حفظها. بيرجّع رسالة خطأ أو null. */
export async function applyTransactionRate(
  supabase: SupabaseClient,
  companyId: string,
  currency: string,
  baseCurrency: string,
  date: string,
  unitsPerBase: string,
) {
  if (!currency || currency.toUpperCase() === baseCurrency.toUpperCase()) return null;
  const units = Number(unitsPerBase);
  if (!Number.isFinite(units) || units <= 0) return "اكتب سعر الصرف الحالي.";
  const { error } = await supabase.rpc("set_transaction_rate", {
    target_company: companyId,
    target_currency: currency,
    target_date: date || null,
    target_units_per_base: units,
  });
  if (error) {
    return error.message.toLowerCase().includes("future")
      ? "ما فيك تسجّل سعر لتاريخ بالمستقبل."
      : "ما قدرنا نسجّل سعر الصرف.";
  }
  return null;
}
