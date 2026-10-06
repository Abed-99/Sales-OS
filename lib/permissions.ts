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

/** مين بيقدر يضيف زبون أو مورد أو صنف من جوّا الفاتورة ("+ ضيف جديد"). */
export function quickAddRights(permissions: readonly string[], isOwner = false) {
  return {
    trader: hasPermission(permissions, "traders.create", isOwner),
    supplier: hasPermission(permissions, "suppliers.create", isOwner),
    product: hasPermission(permissions, "products.create", isOwner),
  };
}
