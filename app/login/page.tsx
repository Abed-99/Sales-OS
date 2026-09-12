import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { LoginClient } from "@/components/auth/login-client";

type LoginPageProps = {
  searchParams: Promise<{
    error?: string | string[];
  }>;
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/");
  }

  const params = await searchParams;

  const errorCode = Array.isArray(params.error)
    ? params.error[0]
    : params.error;

  const initialMessage =
    errorCode === "auth_callback"
      ? "تعذر إكمال عملية المصادقة. قد يكون الرابط غير صالح أو منتهي الصلاحية."
      : "";

  return <LoginClient initialMessage={initialMessage} />;
}
