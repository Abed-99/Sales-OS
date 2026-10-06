"use client";

import { NumberInput } from "@/components/number-input";

export type DeliveryFeeMode = "none" | "customer" | "company";

export type DeliveryFeeValue = {
  mode: DeliveryFeeMode;
  amount: string;
  cashboxId: string;
};

export type DeliveryFeeCashbox = {
  id: string;
  name: string;
  currency: string;
};

export function emptyDeliveryFee(cashboxId = ""): DeliveryFeeValue {
  return { mode: "none", amount: "", cashboxId };
}

/** مدخلات الدالة بقاعدة البيانات، أو رسالة غلط إذا في شي ناقص. */
export function deliveryFeeParams(value: DeliveryFeeValue):
  | {
      ok: true;
      params: {
        target_delivery_fee: number;
        target_delivery_cost: number;
        target_cost_cashbox: string | null;
      };
    }
  | { ok: false; message: string } {
  if (value.mode === "none") {
    return {
      ok: true,
      params: { target_delivery_fee: 0, target_delivery_cost: 0, target_cost_cashbox: null },
    };
  }

  const amount = Number(value.amount);

  if (!Number.isFinite(amount) || amount <= 0) {
    return { ok: false, message: "اكتب مبلغ أجرة التوصيل." };
  }

  if (value.mode === "customer") {
    return {
      ok: true,
      params: { target_delivery_fee: amount, target_delivery_cost: 0, target_cost_cashbox: null },
    };
  }

  if (!value.cashboxId) {
    return { ok: false, message: "اختر الصندوق اللي طلعت منو أجرة التوصيل." };
  }

  return {
    ok: true,
    params: { target_delivery_fee: 0, target_delivery_cost: amount, target_cost_cashbox: value.cashboxId },
  };
}

/**
 * أجرة التوصيل: يا على الزبون (بتنضاف عالفاتورة)، يا علينا (مصروف من الصندوق وما بتبين للزبون).
 * "علينا" بتبين بس لمين عندو صلاحية المصاريف (allowCompany).
 */
export function DeliveryFeeFields({
  value,
  onChange,
  currency,
  cashboxes = [],
  allowCompany = false,
}: {
  value: DeliveryFeeValue;
  onChange: (value: DeliveryFeeValue) => void;
  currency: string;
  cashboxes?: DeliveryFeeCashbox[];
  allowCompany?: boolean;
}) {
  const choices: { mode: DeliveryFeeMode; label: string }[] = [
    { mode: "none", label: "بدون أجرة" },
    { mode: "customer", label: "على الزبون" },
    ...(allowCompany && cashboxes.length ? [{ mode: "company" as const, label: "علينا" }] : []),
  ];

  const box = cashboxes.find((item) => item.id === value.cashboxId);
  const amountCurrency = value.mode === "company" ? box?.currency || currency : currency;

  return (
    <div className="field full deliveryFee">
      <span>أجرة التوصيل</span>

      <div className="feeChoices" role="radiogroup" aria-label="أجرة التوصيل">
        {choices.map((choice) => (
          <button
            key={choice.mode}
            type="button"
            role="radio"
            aria-checked={value.mode === choice.mode}
            className={value.mode === choice.mode ? "softButton active" : "softButton"}
            onClick={() => onChange({ ...value, mode: choice.mode })}
          >
            {choice.label}
          </button>
        ))}
      </div>

      {value.mode !== "none" ? (
        <div className="feeRow">
          <label className="field">
            <span>المبلغ ({amountCurrency})</span>
            <NumberInput
              value={value.amount}
              min="0"
              onChange={(event) => onChange({ ...value, amount: event.target.value })}
              placeholder="0"
              required
            />
          </label>

          {value.mode === "company" ? (
            <label className="field">
              <span>من صندوق</span>
              <select
                value={value.cashboxId}
                onChange={(event) => onChange({ ...value, cashboxId: event.target.value })}
                required
              >
                <option value="">اختر الصندوق</option>
                {cashboxes.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name} ({item.currency})
                  </option>
                ))}
              </select>
            </label>
          ) : null}
        </div>
      ) : null}

      <small className="helpText">
        {value.mode === "customer"
          ? "بتنضاف سطر لحالها بالفاتورة وعلى حساب الزبون."
          : value.mode === "company"
            ? "ما بتبين للزبون. بتنسجّل مصروف توصيل من الصندوق."
            : "ما في أجرة توصيل على هالفاتورة."}
      </small>
    </div>
  );
}
