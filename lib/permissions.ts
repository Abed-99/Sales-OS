export type PermissionCode = string;

export function hasPermission(
  permissions: readonly string[],
  permission: PermissionCode,
  isOwner = false
) {
  return isOwner || permissions.includes(permission);
}

export function hasAnyPermission(
  permissions: readonly string[],
  required: readonly PermissionCode[],
  isOwner = false
) {
  return (
    isOwner ||
    required.some((permission) => permissions.includes(permission))
  );
}
