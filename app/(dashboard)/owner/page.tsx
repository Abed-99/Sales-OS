import { redirect } from "next/navigation";

import { Topbar } from "@/components/topbar";
import {
  OwnerClient,
  type TeamMember,
  type TeamPermission,
  type TeamRole,
} from "@/components/owner/owner-client";
import { getCurrentContext } from "@/lib/current-context";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type RoleRow = {
  id: string;
  name: string;
  description: string | null;
  is_owner: boolean;
  is_protected: boolean;
  active: boolean;
};

type PermissionRow = {
  code: string;
  module: string;
  action: string;
  label: string;
  description: string | null;
  sort_order: number;
};

type RolePermissionRow = {
  role_id: string;
  permission_code: string;
};

type MemberRow = {
  user_id: string;
  role_id: string;
  created_at: string;
};

type AuthUserSnapshot = {
  id: string;
  email: string | null;
  lastSignInAt: string | null;
  metadataName: string | null;
};

function metadataName(metadata: Record<string, unknown> | null | undefined) {
  const values = [metadata?.full_name, metadata?.name, metadata?.display_name];

  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }

  return null;
}

async function loadAuthUsers(userIds: readonly string[]) {
  const pending = new Set(userIds);
  const users = new Map<string, AuthUserSnapshot>();

  if (!pending.size) {
    return users;
  }

  const admin = createAdminClient();
  const perPage = 200;

  for (let page = 1; page <= 50 && pending.size; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) {
      throw new Error("تعذر قراءة حسابات الفريق.");
    }

    for (const user of data.users) {
      if (!pending.has(user.id)) continue;

      users.set(user.id, {
        id: user.id,
        email: user.email ?? null,
        lastSignInAt: user.last_sign_in_at ?? null,
        metadataName: metadataName(user.user_metadata),
      });
      pending.delete(user.id);
    }

    if (data.users.length < perPage) {
      break;
    }
  }

  return users;
}

export default async function OwnerPage() {
  const context = await getCurrentContext();

  if (!context.isOwner) {
    redirect("/");
  }

  const supabase = await createClient();

  const [rolesResult, permissionsResult, membersResult] = await Promise.all([
    supabase
      .from("company_roles")
      .select("id,name,description,is_owner,is_protected,active")
      .eq("company_id", context.companyId)
      .order("is_owner", { ascending: false })
      .order("name"),
    supabase
      .from("permissions")
      .select("code,module,action,label,description,sort_order")
      .order("module")
      .order("sort_order")
      .order("code"),
    supabase
      .from("company_members")
      .select("user_id,role_id,created_at")
      .eq("company_id", context.companyId)
      .order("created_at"),
  ]);

  if (rolesResult.error) throw new Error("تعذر تحميل صفات الفريق.");
  if (permissionsResult.error) throw new Error("تعذر تحميل صلاحيات النظام.");
  if (membersResult.error) throw new Error("تعذر تحميل أعضاء الفريق.");

  const roleRows = (rolesResult.data ?? []) as RoleRow[];
  const permissionRows = (permissionsResult.data ?? []) as PermissionRow[];
  const memberRows = (membersResult.data ?? []) as MemberRow[];
  const roleIds = roleRows.map((role) => role.id);
  const memberIds = memberRows.map((member) => member.user_id);

  const [rolePermissionsResult, authUsers] = await Promise.all([
    roleIds.length
      ? supabase
          .from("role_permissions")
          .select("role_id,permission_code")
          .in("role_id", roleIds)
      : Promise.resolve({ data: [] as RolePermissionRow[], error: null }),
    loadAuthUsers(memberIds),
  ]);

  if (rolePermissionsResult.error) {
    throw new Error("تعذر تحميل صلاحيات الصفات.");
  }

  const permissionCodesByRole = new Map<string, string[]>();

  for (const row of (rolePermissionsResult.data ?? []) as RolePermissionRow[]) {
    const current = permissionCodesByRole.get(row.role_id) ?? [];
    current.push(row.permission_code);
    permissionCodesByRole.set(row.role_id, current);
  }

  const roles: TeamRole[] = roleRows.map((role) => ({
    id: role.id,
    name: role.name,
    description: role.description,
    isOwner: role.is_owner,
    isProtected: role.is_protected,
    active: role.active,
    permissionCodes: permissionCodesByRole.get(role.id) ?? [],
  }));

  const permissions: TeamPermission[] = permissionRows.map((permission) => ({
    code: permission.code,
    module: permission.module,
    action: permission.action,
    label: permission.label,
    description: permission.description,
    sortOrder: permission.sort_order,
  }));

  const members: TeamMember[] = memberRows.map((member) => {
    const authUser = authUsers.get(member.user_id);
    const email = authUser?.email ?? "—";

    return {
      userId: member.user_id,
      email,
      name:
        authUser?.metadataName ??
        (email !== "—" ? email.split("@")[0] : "مستخدم"),
      roleId: member.role_id,
      createdAt: member.created_at,
      lastSignInAt: authUser?.lastSignInAt ?? null,
      isOwner: member.user_id === context.user.id,
    };
  });

  return (
    <>
      <Topbar
        title="إدارة الفريق"
        subtitle="الموظفون، الصفات والصلاحيات"
        companyName={context.companyName}
      />

      <OwnerClient
        companyId={context.companyId}
        members={members}
        roles={roles}
        permissions={permissions}
      />
    </>
  );
}

