import type { SupabaseClient } from "@supabase/supabase-js";

/** "base" = القطعة (الوحدة الأساسية بالمخزون)، "pack" = الكرتونة. */
export type UnitMode = "base" | "pack";

function factor(mode: UnitMode | undefined, packSize: number | null | undefined) {
  return mode === "pack" && packSize && packSize > 1 ? packSize : 1;
}

/** الكمية بالوحدة الأساسية (المخزون والفواتير دايمًا بالقطعة). */
export function toBaseQuantity(quantity: number, mode?: UnitMode, packSize?: number | null) {
  return Number((quantity * factor(mode, packSize)).toFixed(3));
}

/** سعر القطعة من سعر الوحدة المختارة. */
export function toBasePrice(price: number, mode?: UnitMode, packSize?: number | null) {
  return Number((price / factor(mode, packSize)).toFixed(4));
}

/** لما تبدّل بين قطعة وكرتونة، السعر المعروض بيتحوّل معها. */
export function convertPrice(
  price: string,
  from: UnitMode | undefined,
  to: UnitMode,
  packSize?: number | null,
) {
  const value = Number(price);
  if (price.trim() === "" || !Number.isFinite(value)) return price;
  const base = value / factor(from, packSize);
  const next = base * factor(to, packSize);
  return String(Number(next.toFixed(to === "pack" ? 2 : 4)));
}

/** سعر كل صنف لهالزبون حسب مستوى سعره (أو السعر العادي). */
export async function traderPrices(
  supabase: SupabaseClient,
  companyId: string,
  traderId: string,
  productIds: string[],
) {
  const prices = new Map<string, number>();
  if (!traderId || !productIds.length) return prices;
  const { data } = await supabase.rpc("get_trader_product_prices", {
    target_company: companyId,
    target_trader: traderId,
    target_products: productIds,
  });
  for (const row of (data ?? []) as { product_id: string; price: number | null }[]) {
    if (row.price != null) prices.set(row.product_id, Number(row.price));
  }
  return prices;
}
