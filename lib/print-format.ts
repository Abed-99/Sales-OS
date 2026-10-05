// تنسيق المبالغ والكميات بصفحات الطباعة (بيشتغل عالسيرفر والمتصفح).

import { formatMoney, formatQty } from "@/lib/format";

export const money = formatMoney;

/** الكمية بالقطعة مع الكرتونة إذا في: "48 لفة (2 كرتونة)". */
export function quantityLabel(
  quantity: number | string,
  unit?: string | null,
  packSize?: number | null,
  packUnit?: string | null,
) {
  const qty = Number(quantity);
  const base = `${formatQty(qty)} ${unit ?? ""}`.trim();
  if (!packSize || packSize <= 1 || qty < packSize) return base;
  const packs = Math.floor(qty / packSize);
  const rest = Number((qty - packs * packSize).toFixed(3));
  return `${base} (${formatQty(packs)} ${packUnit || "كرتونة"}${rest ? ` + ${formatQty(rest)}` : ""})`;
}
