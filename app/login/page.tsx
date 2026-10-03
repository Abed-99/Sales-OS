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
    errorCode === "link_used"
      ? "هالرابط انستعمل قبل أو انتهت صلاحيتو (الرابط بيشتغل مرة وحدة، وإذا انبعتلك رابط أحدث بيبطل القديم). إذا حطيت كلمة سرك قبل، فوت فيها عادي. وإلا اطلب دعوة جديدة من صاحب الشركة، أو كبّس «نسيت كلمة المرور»."
      : errorCode === "auth_callback"
        ? "تعذر إكمال الدخول من الرابط. جرّب تفتح آخر رسالة وصلتك، أو كبّس «نسيت كلمة المرور»."
        : "";

  return <LoginClient initialMessage={initialMessage} />;
}
