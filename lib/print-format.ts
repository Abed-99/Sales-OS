// تنسيق المبالغ والكميات بصفحات الطباعة (بيشتغل عالسيرفر والمتصفح).

export function money(value: number | string | null | undefined, currency: string) {
  const amount = Number(value ?? 0);
  return `${amount.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
}

/** الكمية بالقطعة مع الكرتونة إذا في: "48 لفة (2 كرتونة)". */
export function quantityLabel(
  quantity: number | string,
  unit?: string | null,
  packSize?: number | null,
  packUnit?: string | null,
) {
  const qty = Number(quantity);
  const base = `${qty.toLocaleString("en-US", { maximumFractionDigits: 3 })} ${unit ?? ""}`.trim();
  if (!packSize || packSize <= 1 || qty < packSize) return base;
  const packs = Math.floor(qty / packSize);
  const rest = Number((qty - packs * packSize).toFixed(3));
  return `${base} (${packs} ${packUnit || "كرتونة"}${rest ? ` + ${rest}` : ""})`;
}
