import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SetupCompanyClient } from "@/components/auth/setup-company-client";

export default async function SetupCompanyPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: membership } = await supabase
    .from("company_members")
    .select("company_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();

  if (membership) {
    redirect("/");
  }

  return <SetupCompanyClient />;
}