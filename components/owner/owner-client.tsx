"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";
import styles from "./owner-client.module.css";

export type TeamRole = {
  id: string;
  name: string;
  description: string | null;
  isOwner: boolean;
  isProtected: boolean;
  active: boolean;
  permissionCodes: string[];
};

export type TeamPermission = {
  code: string;
  module: string;
  action: string;
  label: string;
  description: string | null;
  sortOrder: number;
};

export type TeamMember = {
  userId: string;
  email: string;
  name: string;
  roleId: string;
  createdAt: string;
  lastSignInAt: string | null;
  isOwner: boolean;
};

type Notice = {
  kind: "success" | "error";
  text: string;
} | null;

const moduleLabels: Record<string, string> = {
  dashboard: "لوحة التحكم",
  team: "الفريق والصلاحيات",
  traders: "التجار",
  visits: "الزيارات",
  suppliers: "الموردون",
  products: "الأصناف",
  inventory: "المخزون",
  orders: "الطلبات والمبيعات",
  purchases: "المشتريات",
  deliveries: "التوصيل",
  payments: "الدفعات والتحصيل",
  finance: "المالية",
  returns: "المرتجعات",
  reports: "التقارير",
  map: "الخريطة",
  whatsapp: "واتساب",
  settings: "الإعدادات",
  audit: "سجل التدقيق",
};

const teamErrorLabels: Record<string, string> = {
  "Not allowed": "ما عندك صلاحية لتنفيذ هالعملية.",
  "Role name is required": "اسم الصفة مطلوب.",
  "Invalid permission": "في صلاحية غير صالحة ضمن الاختيارات.",
  "Role name already exists": "في صفة بنفس الاسم أصلًا.",
  "Protected role cannot be edited": "الصفة المحمية ما فينا نعدلها.",
  "Protected role cannot be deleted": "الصفة المحمية ما فينا نحذفها.",
  "Role is assigned to employees": "ما فينا نحذف الصفة لأنها مستخدمة عند موظف. غيّر صفته أولًا.",
  "Role not found": "الصفة غير موجودة.",
  "Role is inactive": "الصفة غير مفعلة.",
  "Company owner must keep owner role": "لا يمكن تغيير صفة مالك الشركة.",
  "Owner role cannot be assigned to an employee": "صفة المالك محجوزة لمالك الشركة فقط.",
  "Company owner cannot be removed": "لا يمكن إزالة مالك الشركة.",
};

function readableError(message: string) {
  for (const [needle, label] of Object.entries(teamErrorLabels)) {
    if (message.includes(needle)) return label;
  }

  return "تعذر تنفيذ العملية. حاول مرة أخرى.";
}

function formatDate(value: string | null) {
  if (!value) return "—";

  return new Intl.DateTimeFormat("ar-SY", {
    timeZone: "Asia/Damascus",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function randomPassword() {
  const letters = "abcdefghjkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(9));
  return Array.from(bytes, (byte) => letters[byte % letters.length]).join("");
}

export function OwnerClient({
  companyId,
  members,
  roles,
  permissions,
}: {
  companyId: string;
  members: TeamMember[];
  roles: TeamRole[];
  permissions: TeamPermission[];
}) {
  const router = useRouter();
  const [supabase] = useState(() => createClient());
  const [notice, setNotice] = useState<Notice>(null);

  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteName, setInviteName] = useState("");
  // "password" = المالك بيحط كلمة السر وبيبعتها للموظف (أضمن من الإيميل).
  const [inviteMode, setInviteMode] = useState<"password" | "email">("password");
  const [invitePassword, setInvitePassword] = useState("");
  const [createdLogin, setCreatedLogin] = useState<{ email: string; password: string } | null>(
    null,
  );
  const [inviteRoleId, setInviteRoleId] = useState("");
  const [inviting, setInviting] = useState(false);

  const [roleOpen, setRoleOpen] = useState(false);
  const [editingRole, setEditingRole] = useState<TeamRole | null>(null);
  const [roleName, setRoleName] = useState("");
  const [roleDescription, setRoleDescription] = useState("");
  const [selectedPermissions, setSelectedPermissions] = useState<Set<string>>(() => new Set());
  const [savingRole, setSavingRole] = useState(false);
  const [busyKey, setBusyKey] = useState<string | null>(null);

  const assignableRoles = useMemo(
    () => roles.filter((role) => !role.isOwner && role.active),
    [roles],
  );

  const groupedPermissions = useMemo(() => {
    const groups = new Map<string, TeamPermission[]>();

    for (const permission of permissions) {
      const current = groups.get(permission.module) ?? [];
      current.push(permission);
      groups.set(permission.module, current);
    }

    return [...groups.entries()];
  }, [permissions]);

  const roleById = useMemo(() => new Map(roles.map((role) => [role.id, role] as const)), [roles]);

  function showNotice(kind: "success" | "error", text: string) {
    setNotice({ kind, text });
    window.setTimeout(() => setNotice(null), 4500);
  }

  function openInvite() {
    setInviteEmail("");
    setInviteName("");
    setInviteMode("password");
    setInvitePassword(randomPassword());
    setInviteRoleId(assignableRoles[0]?.id ?? "");
    setInviteOpen(true);
  }

  function openNewRole() {
    setEditingRole(null);
    setRoleName("");
    setRoleDescription("");
    setSelectedPermissions(new Set());
    setRoleOpen(true);
  }

  function openEditRole(role: TeamRole) {
    if (role.isOwner || role.isProtected) return;

    setEditingRole(role);
    setRoleName(role.name);
    setRoleDescription(role.description ?? "");
    setSelectedPermissions(new Set(role.permissionCodes));
    setRoleOpen(true);
  }

  function togglePermission(code: string) {
    setSelectedPermissions((current) => {
      const next = new Set(current);

      if (next.has(code)) next.delete(code);
      else next.add(code);

      return next;
    });
  }

  function setModulePermissions(modulePermissions: readonly TeamPermission[], enabled: boolean) {
    setSelectedPermissions((current) => {
      const next = new Set(current);

      for (const permission of modulePermissions) {
        if (enabled) next.add(permission.code);
        else next.delete(permission.code);
      }

      return next;
    });
  }

  async function inviteEmployee(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const email = inviteEmail.trim().toLowerCase();

    if (!email || !inviteRoleId) {
      showNotice("error", "اكتب البريد واختر صفة الموظف.");
      return;
    }

    if (inviteMode === "password" && invitePassword.trim().length < 8) {
      showNotice("error", "كلمة السر لازم تكون 8 أحرف على الأقل.");
      return;
    }

    setInviting(true);

    try {
      const response = await fetch("/api/team/invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          companyId,
          email,
          roleId: inviteRoleId,
          fullName: inviteName.trim() || null,
          password: inviteMode === "password" ? invitePassword.trim() : null,
        }),
      });

      const result = (await response.json()) as {
        ok?: boolean;
        invited?: boolean;
        created?: boolean;
        error?: string;
      };

      if (!response.ok || !result.ok) {
        throw new Error(result.error || "تعذر إضافة الموظف.");
      }

      setInviteOpen(false);
      if (result.created) {
        setCreatedLogin({ email, password: invitePassword.trim() });
      }
      showNotice(
        "success",
        result.created
          ? "انعمل حساب الموظف. ابعتلو معلومات الدخول."
          : result.invited
            ? "تمت إضافة الموظف وإرسال دعوة إلى بريده."
            : "الحساب موجود؛ تم ربطه بالشركة وتحديد صفته.",
      );
      router.refresh();
    } catch (error) {
      showNotice(
        "error",
        readableError(error instanceof Error ? error.message : "تعذر إضافة الموظف."),
      );
    } finally {
      setInviting(false);
    }
  }

  async function saveRole(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!roleName.trim()) {
      showNotice("error", "اسم الصفة مطلوب.");
      return;
    }

    setSavingRole(true);

    const { error } = await supabase.rpc("save_company_role", {
      target_company: companyId,
      target_role: editingRole?.id ?? null,
      role_name: roleName.trim(),
      role_description: roleDescription.trim() || null,
      permission_codes: [...selectedPermissions],
    });

    setSavingRole(false);

    if (error) {
      showNotice("error", readableError(error.message));
      return;
    }

    setRoleOpen(false);
    showNotice("success", editingRole ? "تم تحديث الصفة والصلاحيات." : "تم إنشاء الصفة.");
    router.refresh();
  }

  async function deleteRole(role: TeamRole) {
    if (role.isOwner || role.isProtected) return;

    if (!window.confirm(`حذف صفة "${role.name}"؟ لا يمكن حذفها إذا كانت مستخدمة عند موظف.`)) {
      return;
    }

    setBusyKey(`role:${role.id}`);

    const { error } = await supabase.rpc("delete_company_role", {
      target_company: companyId,
      target_role: role.id,
    });

    setBusyKey(null);

    if (error) {
      showNotice("error", readableError(error.message));
      return;
    }

    showNotice("success", "تم حذف الصفة.");
    router.refresh();
  }

  async function changeMemberRole(userId: string, roleId: string) {
    setBusyKey(`member:${userId}`);

    const { error } = await supabase.rpc("assign_company_member_role", {
      target_company: companyId,
      target_user: userId,
      target_role: roleId,
    });

    setBusyKey(null);

    if (error) {
      showNotice("error", readableError(error.message));
      router.refresh();
      return;
    }

    showNotice("success", "تم تحديث صفة الموظف.");
    router.refresh();
  }

  async function removeMember(member: TeamMember) {
    if (member.isOwner) return;

    if (!window.confirm(`إزالة ${member.name} من فريق الشركة؟`)) {
      return;
    }

    setBusyKey(`member:${member.userId}`);

    const { error } = await supabase.rpc("remove_company_member", {
      target_company: companyId,
      target_user: member.userId,
    });

    setBusyKey(null);

    if (error) {
      showNotice("error", readableError(error.message));
      return;
    }

    showNotice("success", "تمت إزالة الموظف من الفريق.");
    router.refresh();
  }

  const employeeCount = members.filter((member) => !member.isOwner).length;
  const roleCount = roles.filter((role) => !role.isOwner).length;

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">إدارة المالك</span>
          <h2>الفريق والصلاحيات</h2>
          <p className="muted">كل موظف يأخذ صفة وصلاحيات محددة بدون إعطائه وصولًا أوسع من حاجته.</p>
        </div>

        <div className="rowActions">
          <button className="softButton" type="button" onClick={openNewRole}>
            <Icons.plus size={14} />
            صفة جديدة
          </button>
          <button
            className="primaryButton"
            type="button"
            onClick={openInvite}
            disabled={!assignableRoles.length}
          >
            <Icons.users size={14} />
            إضافة موظف
          </button>
        </div>
      </div>

      {notice ? (
        <div className={notice.kind === "error" ? "toastError" : styles.success} role="status">
          {notice.text}
        </div>
      ) : null}

      <section className="statsGrid">
        <div className="statCard">
          <div className="statLabel">الموظفون</div>
          <div className="statValue">{employeeCount}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">الصفات المتاحة</div>
          <div className="statValue">{roleCount}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">صلاحيات النظام</div>
          <div className="statValue">{permissions.length}</div>
        </div>
        <div className="statCard">
          <div className="statLabel">حساب المالك</div>
          <div className={styles.protectedValue}>محمي</div>
        </div>
      </section>

      <div className={styles.ownerGrid}>
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>أعضاء الفريق</h2>
              <p>غيّر الصفة أو أزل الموظف من الشركة</p>
            </div>
          </div>

          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الموظف</th>
                  <th>الصفة</th>
                  <th>آخر دخول</th>
                  <th>تاريخ الإضافة</th>
                  <th>إجراء</th>
                </tr>
              </thead>
              <tbody>
                {members.map((member) => {
                  const currentRole = roleById.get(member.roleId);
                  const memberBusy = busyKey === `member:${member.userId}`;

                  return (
                    <tr key={member.userId}>
                      <td>
                        <div className={styles.memberCell}>
                          <div className={styles.memberAvatar}>
                            {member.name.charAt(0).toUpperCase() || "م"}
                          </div>
                          <div>
                            <strong>
                              {member.name}
                              {member.isOwner ? (
                                <span className={styles.ownerBadge}>المالك</span>
                              ) : null}
                            </strong>
                            <span dir="ltr">{member.email}</span>
                          </div>
                        </div>
                      </td>
                      <td>
                        {member.isOwner ? (
                          <span className="chip green">{currentRole?.name ?? "المالك"}</span>
                        ) : (
                          <select
                            className={styles.roleSelect}
                            value={member.roleId}
                            disabled={memberBusy}
                            onChange={(event) =>
                              void changeMemberRole(member.userId, event.target.value)
                            }
                          >
                            {assignableRoles.map((role) => (
                              <option key={role.id} value={role.id}>
                                {role.name}
                              </option>
                            ))}
                          </select>
                        )}
                      </td>
                      <td>{formatDate(member.lastSignInAt)}</td>
                      <td>{formatDate(member.createdAt)}</td>
                      <td>
                        {member.isOwner ? (
                          <span className={styles.lockedText}>محمي</span>
                        ) : (
                          <button
                            type="button"
                            className="dangerButton"
                            disabled={memberBusy}
                            onClick={() => void removeMember(member)}
                          >
                            <Icons.trash size={13} />
                            إزالة
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>الصفات</h2>
              <p>كل صفة لها صلاحيات مستقلة</p>
            </div>
          </div>

          <div className={styles.roleList}>
            {roles.map((role) => {
              const roleBusy = busyKey === `role:${role.id}`;

              return (
                <div className={styles.roleCard} key={role.id}>
                  <div className={styles.roleCardTop}>
                    <div>
                      <strong>{role.name}</strong>
                      <span>
                        {role.isOwner ? "صفة المالك الأساسية" : role.description || "بدون وصف"}
                      </span>
                    </div>

                    <span className="chip blue">{role.permissionCodes.length} صلاحية</span>
                  </div>

                  {!role.isOwner && !role.isProtected ? (
                    <div className={styles.roleActions}>
                      <button
                        type="button"
                        className="softButton"
                        onClick={() => openEditRole(role)}
                      >
                        <Icons.edit size={13} />
                        تعديل
                      </button>
                      <button
                        type="button"
                        className="dangerButton"
                        disabled={roleBusy}
                        aria-label={`حذف صفة ${role.name}`}
                        onClick={() => void deleteRole(role)}
                      >
                        <Icons.trash size={13} />
                      </button>
                    </div>
                  ) : (
                    <div className={styles.protectedRole}>صفة محمية</div>
                  )}
                </div>
              );
            })}
          </div>
        </aside>
      </div>

      {inviteOpen ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">موظف جديد</span>
                <h2>إضافة موظف</h2>
              </div>
              <button
                className="closeButton"
                type="button"
                onClick={() => setInviteOpen(false)}
                aria-label="إغلاق"
              >
                ×
              </button>
            </div>

            <form onSubmit={inviteEmployee}>
              <div className="rowActions" style={{ marginBottom: 12 }}>
                <button
                  type="button"
                  className={inviteMode === "password" ? "primaryButton" : "softButton"}
                  onClick={() => setInviteMode("password")}
                >
                  أنا بحط كلمة السر
                </button>
                <button
                  type="button"
                  className={inviteMode === "email" ? "primaryButton" : "softButton"}
                  onClick={() => setInviteMode("email")}
                >
                  دعوة عالإيميل
                </button>
              </div>

              <div className="formGrid">
                <label className="field">
                  <span>اسم الموظف</span>
                  <input
                    value={inviteName}
                    onChange={(event) => setInviteName(event.target.value)}
                    placeholder="مثلًا: سامر"
                  />
                </label>

                <label className="field">
                  <span>البريد الإلكتروني</span>
                  <input
                    type="email"
                    autoComplete="email"
                    required
                    dir="ltr"
                    value={inviteEmail}
                    onChange={(event) => setInviteEmail(event.target.value)}
                    placeholder="employee@example.com"
                  />
                </label>

                <label className="field">
                  <span>الصفة</span>
                  <select
                    required
                    value={inviteRoleId}
                    onChange={(event) => setInviteRoleId(event.target.value)}
                  >
                    {assignableRoles.map((role) => (
                      <option key={role.id} value={role.id}>
                        {role.name}
                      </option>
                    ))}
                  </select>
                </label>

                {inviteMode === "password" ? (
                  <label className="field">
                    <span>كلمة السر</span>
                    <input
                      dir="ltr"
                      value={invitePassword}
                      onChange={(event) => setInvitePassword(event.target.value)}
                    />
                  </label>
                ) : null}

                <div className={`${styles.inviteHint} field full`}>
                  {inviteMode === "password"
                    ? "بينعمل الحساب فورًا، وبعدها بتبعت للموظف الإيميل وكلمة السر عالواتساب. إذا الحساب موجود أصلًا بينربط بالشركة وكلمة سرو ما بتتغير."
                    : "بيوصلو إيميل فيه رابط ليحط كلمة سرو (الإيميلات ممكن تتأخر أو تروح عالـ spam)."}
                </div>
              </div>

              <div className="modalActions">
                <button className="softButton" type="button" onClick={() => setInviteOpen(false)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={inviting}>
                  {inviting ? "عم نضيف..." : "إضافة الموظف"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {createdLogin
        ? (() => {
            const origin = typeof window === "undefined" ? "" : window.location.origin;
            const text = `رابط الدخول: ${origin}/login\nالإيميل: ${createdLogin.email}\nكلمة السر: ${createdLogin.password}`;
            return (
              <div className="modalOverlay">
                <section className="modal" role="dialog" aria-modal="true">
                  <div className="modalHeader">
                    <div>
                      <span className="eyebrow">معلومات الدخول</span>
                      <h2>ابعتها للموظف</h2>
                    </div>
                    <button
                      className="closeButton"
                      type="button"
                      onClick={() => setCreatedLogin(null)}
                      aria-label="إغلاق"
                    >
                      ×
                    </button>
                  </div>
                  <pre style={{ whiteSpace: "pre-wrap", fontSize: 14 }}>{text}</pre>
                  <p className="muted">بعد ما يفوت، فيه يغيّر كلمة السر من «الإعدادات».</p>
                  <div className="modalActions">
                    <button
                      className="softButton"
                      type="button"
                      onClick={() => {
                        void navigator.clipboard?.writeText(text);
                        showNotice("success", "انسخت معلومات الدخول.");
                      }}
                    >
                      نسخ
                    </button>
                    <a
                      className="primaryButton"
                      target="_blank"
                      rel="noreferrer"
                      href={`https://wa.me/?text=${encodeURIComponent(text)}`}
                    >
                      إرسال عالواتساب
                    </a>
                  </div>
                </section>
              </div>
            );
          })()
        : null}

      {roleOpen ? (
        <div className="modalOverlay">
          <section className={`modal ${styles.roleModal}`} role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">الصفة والصلاحيات</span>
                <h2>{editingRole ? `تعديل ${editingRole.name}` : "صفة جديدة"}</h2>
              </div>
              <button
                className="closeButton"
                type="button"
                onClick={() => setRoleOpen(false)}
                aria-label="إغلاق"
              >
                ×
              </button>
            </div>

            <form onSubmit={saveRole}>
              <div className="formGrid">
                <label className="field">
                  <span>اسم الصفة</span>
                  <input
                    required
                    value={roleName}
                    onChange={(event) => setRoleName(event.target.value)}
                    placeholder="مثال: مندوب مبيعات بيروت"
                  />
                </label>

                <label className="field">
                  <span>وصف مختصر</span>
                  <input
                    value={roleDescription}
                    onChange={(event) => setRoleDescription(event.target.value)}
                    placeholder="مسؤوليات هذه الصفة"
                  />
                </label>
              </div>

              <div className={styles.permissionHeader}>
                <div>
                  <strong>الصلاحيات</strong>
                  <span>
                    محدد {selectedPermissions.size} من {permissions.length}
                  </span>
                </div>
                <div className="rowActions">
                  <button
                    className="softButton"
                    type="button"
                    onClick={() =>
                      setSelectedPermissions(
                        new Set(permissions.map((permission) => permission.code)),
                      )
                    }
                  >
                    تحديد الكل
                  </button>
                  <button
                    className="softButton"
                    type="button"
                    onClick={() => setSelectedPermissions(new Set())}
                  >
                    إلغاء الكل
                  </button>
                </div>
              </div>

              <div className={styles.permissionGroups}>
                {groupedPermissions.map(([module, modulePermissions]) => {
                  const selectedCount = modulePermissions.filter((permission) =>
                    selectedPermissions.has(permission.code),
                  ).length;
                  const allSelected =
                    modulePermissions.length > 0 && selectedCount === modulePermissions.length;

                  return (
                    <section className={styles.permissionModule} key={module}>
                      <div className={styles.permissionModuleHeader}>
                        <div>
                          <strong>{moduleLabels[module] ?? module}</strong>
                          <span>
                            {selectedCount}/{modulePermissions.length}
                          </span>
                        </div>
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => setModulePermissions(modulePermissions, !allSelected)}
                        >
                          {allSelected ? "إلغاء القسم" : "تحديد القسم"}
                        </button>
                      </div>

                      <div className={styles.permissionList}>
                        {modulePermissions.map((permission) => (
                          <label className={styles.permissionItem} key={permission.code}>
                            <input
                              type="checkbox"
                              checked={selectedPermissions.has(permission.code)}
                              onChange={() => togglePermission(permission.code)}
                            />
                            <span>
                              <strong>{permission.label}</strong>
                              <small>{permission.description || permission.code}</small>
                            </span>
                          </label>
                        ))}
                      </div>
                    </section>
                  );
                })}
              </div>

              <div className="modalActions">
                <button className="softButton" type="button" onClick={() => setRoleOpen(false)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={savingRole}>
                  {savingRole ? "عم نحفظ..." : "حفظ الصفة والصلاحيات"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}
