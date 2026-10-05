"use client";

import { useLayoutEffect, useRef, type InputHTMLAttributes } from "react";

import { cleanNumberText, groupDigits, parseNumber } from "@/lib/format";

type NumberInputProps = Omit<
  InputHTMLAttributes<HTMLInputElement>,
  "type" | "value" | "defaultValue" | "onChange" | "min" | "max" | "step"
> & {
  value: string | number | null | undefined;
  /** بيوصل الرقم بلا فواصل ("26000.5")، متل خانة الأرقام العادية. */
  onChange: (event: { target: { value: string } }) => void;
  min?: string | number;
  max?: string | number;
  step?: string | number;
};

/**
 * خانة رقم بتحط فواصل الآلاف وإنت عم تكتب (26000 → 26,000)، وبتقبل الأرقام العربية (٢٦٠٠٠).
 * القيمة يلي بتطلع منها نظيفة بلا فواصل، فالحسابات ما بتتغيّر.
 */
export function NumberInput({ value, onChange, min, max, step, ...rest }: NumberInputProps) {
  const ref = useRef<HTMLInputElement>(null);
  // كم رقم كان قبل المؤشر، مشان ما يقفز المؤشر لآخر الخانة بعد ما تنضاف فاصلة.
  const caret = useRef<number | null>(null);

  const allowNegative = min === undefined || min === "" || Number(min) < 0;
  const wholeOnly = step !== undefined && step !== "any" && Number.isInteger(Number(step));
  const clean = cleanNumberText(String(value ?? ""), allowNegative);
  const display = groupDigits(clean);

  useLayoutEffect(() => {
    const input = ref.current;
    if (!input) return;

    // الحد الأدنى والأعلى (خانة النص ما بتفحصهن لحالها متل خانة الأرقام).
    const number = parseNumber(clean);
    let problem = "";
    if (clean !== "" && Number.isFinite(number)) {
      if (min !== undefined && min !== "" && number < Number(min)) {
        problem = `أقل قيمة مسموحة ${groupDigits(String(min))}`;
      } else if (max !== undefined && max !== "" && number > Number(max)) {
        problem = `أكبر قيمة مسموحة ${groupDigits(String(max))}`;
      }
    }
    input.setCustomValidity(problem);

    if (caret.current === null || document.activeElement !== input) return;
    let digits = caret.current;
    let position = 0;
    while (position < display.length && digits > 0) {
      if (display[position] !== ",") digits -= 1;
      position += 1;
    }
    input.setSelectionRange(position, position);
    caret.current = null;
  });

  return (
    <input
      {...rest}
      ref={ref}
      type="text"
      inputMode={wholeOnly ? "numeric" : "decimal"}
      autoComplete="off"
      value={display}
      onChange={(event) => {
        const typed = event.target.value;
        const at = event.target.selectionStart ?? typed.length;
        caret.current = cleanNumberText(typed.slice(0, at), allowNegative).length;
        let next = cleanNumberText(typed, allowNegative);
        if (wholeOnly) next = next.replace(/\..*$/, "");
        onChange({ target: { value: next } });
      }}
    />
  );
}
