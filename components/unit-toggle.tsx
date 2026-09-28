"use client";

import type { UnitMode } from "@/lib/units";

/** زر صغير بيبدّل السطر بين القطعة والكرتونة، مع توضيح الكمية بالقطعة. */
export function UnitToggle({
  mode,
  unit,
  packUnit,
  packSize,
  quantity,
  onChange,
}: {
  mode?: UnitMode;
  unit?: string | null;
  packUnit?: string | null;
  packSize?: number | null;
  quantity?: string;
  onChange: (mode: UnitMode) => void;
}) {
  if (!packSize || packSize <= 1) {
    return unit ? <span className="muted unitTag">{unit}</span> : null;
  }

  const isPack = mode === "pack";
  const qty = Number(quantity);

  return (
    <span className="unitToggle">
      <button
        type="button"
        className="softButton"
        title={`1 ${packUnit || "كرتونة"} = ${packSize} ${unit || "قطعة"}`}
        onClick={() => onChange(isPack ? "base" : "pack")}
      >
        {isPack ? packUnit || "كرتونة" : unit || "قطعة"} ⇄
      </button>
      {isPack && Number.isFinite(qty) && qty > 0 ? (
        <small className="muted">
          = {Number((qty * packSize).toFixed(3))} {unit || "قطعة"}
        </small>
      ) : null}
    </span>
  );
}
