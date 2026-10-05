import type { SupabaseClient } from "@supabase/supabase-js";

import type { PickerOption } from "@/components/search-picker";
import { normalizeAnyPhone } from "@/lib/phone";
import { searchKeyCondition } from "@/lib/search";

const LIMIT = 30;

function pattern(term: string) {
  // الفاصلة والأقواس بتخرب فلتر `or` تبع PostgREST.
  return `%${term.replace(/[%_,()"'\\]/g, " ").trim()}%`;
}

export type TraderPick = { id: string; name: string; area: string | null; phone?: string | null };

export async function searchTraders(
  supabase: SupabaseClient,
  companyId: string,
  term: string,
): Promise<PickerOption<TraderPick>[]> {
  const like = pattern(term);
  const conditions = [searchKeyCondition(term), `phone.ilike.${like}`].filter(Boolean);
  const phone = normalizeAnyPhone(term);
  if (phone) conditions.push(`phone.eq.${phone}`, `whatsapp.eq.${phone}`);

  const { data } = await supabase
    .from("traders")
    .select("id,name,area,phone")
    .eq("company_id", companyId)
    .neq("status", "inactive")
    .or(conditions.join(","))
    .order("name")
    .limit(LIMIT);

  return (data ?? []).map((row) => ({
    id: row.id,
    label: row.name,
    hint: [row.area, row.phone].filter(Boolean).join(" • ") || null,
    data: row,
  }));
}

export type ProductPick = {
  id: string;
  name: string;
  sku: string | null;
  unit: string | null;
  sale_price: number | null;
  active?: boolean;
  pack_size?: number | null;
  pack_unit?: string | null;
  barcode?: string | null;
};

export async function searchProducts(
  supabase: SupabaseClient,
  companyId: string,
  term: string,
): Promise<PickerOption<ProductPick>[]> {
  const like = pattern(term);
  const code = term.replace(/[%_,()"'\\\s]/g, "");
  const { data } = await supabase
    .from("products")
    .select("id,name,sku,unit,sale_price,active,pack_size,pack_unit,barcode")
    .eq("company_id", companyId)
    .eq("active", true)
    .or(
      [searchKeyCondition(term), `sku.ilike.${like}`, code ? `barcode.eq.${code}` : ""]
        .filter(Boolean)
        .join(","),
    )
    .order("name")
    .limit(LIMIT);

  return (data ?? []).map((row) => productOption(row));
}

export function productOption(row: ProductPick): PickerOption<ProductPick> {
  return {
    id: row.id,
    label: row.name,
    hint: [row.sku, row.unit].filter(Boolean).join(" • ") || null,
    code: row.barcode || row.sku,
    data: row,
  };
}

export type SupplierPick = { id: string; name: string };

export async function searchSuppliers(
  supabase: SupabaseClient,
  companyId: string,
  term: string,
): Promise<PickerOption<SupplierPick>[]> {
  const like = pattern(term);
  const { data } = await supabase
    .from("suppliers")
    .select("id,name,contact_name")
    .eq("company_id", companyId)
    .eq("active", true)
    .or(searchKeyCondition(term) || `name.ilike.${like}`)
    .order("name")
    .limit(LIMIT);

  return (data ?? []).map((row) => ({
    id: row.id,
    label: row.name,
    hint: row.contact_name,
    data: row,
  }));
}
