import type { SupabaseClient } from "@supabase/supabase-js";

import type { Letterhead } from "@/components/print/print-shell";

export async function loadLetterhead(
  supabase: SupabaseClient,
  companyId: string,
  fallbackName: string,
): Promise<Letterhead> {
  const { data } = await supabase
    .from("companies")
    .select("name,phone,whatsapp,address,logo_url")
    .eq("id", companyId)
    .maybeSingle();

  return {
    name: data?.name ?? fallbackName,
    phone: data?.phone ?? null,
    whatsapp: data?.whatsapp ?? null,
    address: data?.address ?? null,
    logo_url: data?.logo_url ?? null,
  };
}

export function printDate(value: string | null | undefined) {
  return value ? value.slice(0, 10) : "";
}
