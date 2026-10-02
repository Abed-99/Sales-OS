import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type RolePermissionRow = {
  permission_code: string;
};

type RoleRow = {
  id: string;
  name: string;
  is_owner?: boolean | null;
  role_permissions?: RolePermissionRow[] | null;
};

type CompanyRow = {
  id: string;
  name: string;
  owner_user_id: string;
  default_currency: string | null;
};

type MembershipRow = {
  role_id: string;
  companies: CompanyRow | CompanyRow[] | null;
  company_roles: RoleRow | RoleRow[] | null;
};

export type CompanyMembership = {
  companyId: string;
  companyName: string;
  currency: string;
  roleId: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
};

export async function getCurrentContext() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [{ data: profile }, membershipsResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("full_name")
      .eq("id", user.id)
      .maybeSingle(),

    supabase
      .from("company_members")
      .select(`
        role_id,
        companies(
          id,
          name,
          owner_user_id,
          phone,
          whatsapp,
          default_currency
        ),
        company_roles(
          id,
          name,
          is_owner,
          role_permissions(
            permission_code
          )
        )
      `)
      .eq("user_id", user.id),
  ]);

  if (membershipsResult.error) {
    throw new Error(membershipsResult.error.message);
  }

  const rawMemberships =
    (membershipsResult.data ?? []) as unknown as MembershipRow[];

  const memberships: CompanyMembership[] = rawMemberships.flatMap((row) => {
    const company = Array.isArray(row.companies)
      ? row.companies[0]
      : row.companies;

    const role = Array.isArray(row.company_roles)
      ? row.company_roles[0]
      : row.company_roles;

    if (!company || !role) {
      return [];
    }

    const permissions = (role.role_permissions ?? [])
      .map((item) => item.permission_code)
      .filter(Boolean);

    return [
      {
        companyId: company.id,
        companyName: company.name,
        currency: company.default_currency || "USD",
        roleId: role.id,
        roleName: role.name,
        // المالك الأول أو أي شريك صفتو "المالك".
        isOwner: company.owner_user_id === user.id || Boolean(role.is_owner),
        permissions,
      },
    ];
  });

  if (!memberships.length) {
    redirect("/setup-company");
  }

  const cookieStore = await cookies();
  const requestedCompanyId =
    cookieStore.get("sales_os_company")?.value;

  const membership =
    memberships.find(
      (item) => item.companyId === requestedCompanyId
    ) ?? memberships[0];

  const userName =
    profile?.full_name?.trim() ||
    user.user_metadata?.full_name ||
    user.email?.split("@")[0] ||
    "مستخدم";

  return {
    user,
    email: user.email || "",
    userName,
    memberships,
    companyId: membership.companyId,
    companyName: membership.companyName,
    currency: membership.currency,
    roleId: membership.roleId,
    roleName: membership.roleName,
    isOwner: membership.isOwner,
    permissions: membership.permissions,
  };
}
