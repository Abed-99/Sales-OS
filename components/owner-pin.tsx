"use client";

import { useCallback, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export type OwnerAction =
  | "approve"
  | "below_min"
  | "credit_limit"
  | "cancel_invoice"
  | "reverse_payment"
  | "reverse_return";

type Pending = { action: OwnerAction; reason: string; resolve: (ok: boolean) => void };

/**
 * نافذة "رمز المالك": العملية الحساسة بتوقف، المالك بيكتب رمزو قدام الموظف،
 * وبتنفتح العملية لمرة وحدة. `ask` بترجّع true إذا الرمز صح.
 */
export function useOwnerPin(supabase: SupabaseClient, companyId: string) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [pin, setPin] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const pendingRef = useRef<Pending | null>(null);

  const ask = useCallback((action: OwnerAction, reason: string) => {
    return new Promise<boolean>((resolve) => {
      const next = { action, reason, resolve };
      pendingRef.current = next;
      setPin("");
      setError("");
      setPending(next);
    });
  }, []);

  function close(ok: boolean) {
    pendingRef.current?.resolve(ok);
    pendingRef.current = null;
    setPending(null);
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!pending) return;
    setBusy(true);
    setError("");
    const { data, error: rpcError } = await supabase.rpc("unlock_owner_override", {
      target_company: companyId,
      target_action: pending.action,
      target_pin: pin.trim(),
    });
    setBusy(false);
    if (rpcError) {
      const message = rpcError.message.toLowerCase();
      setError(
        message.includes("too many")
          ? "غلطت كتير. استنى 10 دقايق وجرّب."
          : message.includes("not set")
            ? "المالك لسا ما حط رمز موافقة (من الإعدادات)."
            : "ما قدرنا نتحقق من الرمز.",
      );
      return;
    }
    if (!data) {
      setError("الرمز غلط.");
      setPin("");
      return;
    }
    close(true);
  }

  const modal = pending ? (
    <div className="modalOverlay" style={{ zIndex: 1300 }}>
      <section className="modal" role="dialog" aria-modal="true" style={{ maxWidth: 420 }}>
        <div className="modalHeader">
          <div>
            <span className="eyebrow">موافقة المالك</span>
            <h2>بدها رمز المالك</h2>
            <p className="muted">{pending.reason}</p>
          </div>
          <button type="button" className="closeButton" onClick={() => close(false)}>
            ×
          </button>
        </div>
        <form onSubmit={submit}>
          <label className="field">
            <span>المالك بيكتب رمزو هون</span>
            <input
              type="password"
              inputMode="numeric"
              autoComplete="off"
              autoFocus
              dir="ltr"
              maxLength={8}
              value={pin}
              onChange={(event) => setPin(event.target.value.replace(/\D/g, ""))}
            />
          </label>
          {error ? <div className="toastError">{error}</div> : null}
          <div className="modalActions">
            <button type="button" className="softButton" onClick={() => close(false)}>
              إلغاء
            </button>
            <button className="primaryButton" disabled={busy || pin.length < 4}>
              {busy ? "عم نتحقق..." : "موافقة"}
            </button>
          </div>
        </form>
      </section>
    </div>
  ) : null;

  return { ask, modal };
}

/**
 * سعر تحت الكلفة انرفع لطلب موافقة: إذا المالك موجود بيكتب رمزو وبتنعمل الطلبية فورًا.
 * بترجّع true إذا انعملت.
 */
export async function approveWithOwnerPin(
  supabase: SupabaseClient,
  companyId: string,
  ask: (action: OwnerAction, reason: string) => Promise<boolean>,
  approvalId: string,
) {
  const unlocked = await ask(
    "approve",
    "في صنف سعرو تحت الكلفة أو تحت أقل سعر. إذا المالك موجود بيكتب رمزو وبتنعمل الطلبية هلق، وإلا بتضل بانتظار الموافقة.",
  );
  if (!unlocked) return false;
  const { error } = await supabase.rpc("resolve_approval_request", {
    target_company: companyId,
    target_request: approvalId,
    target_decision: "approved",
    target_notes: "موافقة برمز المالك",
  });
  return !error;
}
