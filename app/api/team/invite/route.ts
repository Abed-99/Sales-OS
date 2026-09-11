import { NextRequest, NextResponse } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type InviteBody = {
  companyId?: unknown;
  email?: unknown;
  roleId?: unknown;
};

function asText(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

async function findAuthUserByEmail(email: string) {
  const admin = createAdminClient();
  const perPage = 200;

  for (let page = 1; page <= 50; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) throw error;

    const match = data.users.find(
      (user) => user.email?.toLowerCase() === email.toLowerCase()
    );

    if (match) return match;
    if (data.users.length < perPage) return null;
  }

  throw new Error("تعذر البحث في حسابات النظام.");
}

export async function POST(request: NextRequest) {
  try {
    const body = (await request.json()) as InviteBody;
    const companyId = asText(body.companyId);
    const email = asText(body.email).toLowerCase();
    const roleId = asText(body.roleId);

    if (!companyId || !email || !roleId) {
      return NextResponse.json(
        { error: "بيانات الموظف ناقصة." },
        { status: 400 }
      );
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json(
        { error: "البريد الإلكتروني غير صالح." },
        { status: 400 }
      );
    }

    const supabase = await createClient();
    const {
      data: { user: currentUser },
      error: currentUserError,
    } = await supabase.auth.getUser();

    if (currentUserError || !currentUser) {
      return NextResponse.json(
        { error: "يجب تسجيل الدخول أولًا." },
        { status: 401 }
      );
    }

    const { data: company, error: companyError } = await supabase
      .from("companies")
      .select("id,owner_user_id")
      .eq("id", companyId)
      .maybeSingle();

    if (companyError) {
      return NextResponse.json(
        { error: companyError.message },
        { status: 500 }
      );
    }

    if (!company || company.owner_user_id !== currentUser.id) {
      return NextResponse.json(
        { error: "هذه العملية متاحة لمالك الشركة فقط." },
        { status: 403 }
      );
    }

    const { data: role, error: roleError } = await supabase
      .from("company_roles")
      .select("id,is_owner,active")
      .eq("company_id", companyId)
      .eq("id", roleId)
      .maybeSingle();

    if (roleError) {
      return NextResponse.json({ error: roleError.message }, { status: 500 });
    }

    if (!role || role.is_owner || !role.active) {
      return NextResponse.json(
        { error: "صفة الموظف غير صالحة." },
        { status: 400 }
      );
    }

    const admin = createAdminClient();
    let targetUser = await findAuthUserByEmail(email);
    let newlyInvited = false;

    if (!targetUser) {
      const callbackUrl = new URL("/auth/callback", request.nextUrl.origin);
      callbackUrl.searchParams.set("next", "/reset-password?invite=1");

      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo: callbackUrl.toString(),
        data: {
          invited_company_id: companyId,
        },
      });

      if (error || !data.user) {
        return NextResponse.json(
          { error: error?.message || "تعذر إرسال الدعوة." },
          { status: 400 }
        );
      }

      targetUser = data.user;
      newlyInvited = true;
    }

    if (targetUser.id === currentUser.id) {
      return NextResponse.json(
        { error: "حساب المالك موجود أصلًا ضمن الشركة." },
        { status: 400 }
      );
    }

    const { error: membershipError } = await supabase.rpc(
      "assign_company_member_role",
      {
        target_company: companyId,
        target_user: targetUser.id,
        target_role: roleId,
      }
    );

    if (membershipError) {
      if (newlyInvited) {
        await admin.auth.admin.deleteUser(targetUser.id);
      }

      return NextResponse.json(
        { error: membershipError.message },
        { status: 400 }
      );
    }

    return NextResponse.json({
      ok: true,
      invited: newlyInvited,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "حدث خطأ غير متوقع.",
      },
      { status: 500 }
    );
  }
}
