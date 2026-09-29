"use client";

import type { ComponentType } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { AccountMenu } from "@/components/account-menu";
import { Icons } from "@/components/icons";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";

type IconComponent = ComponentType<{
  size?: number;
  className?: string;
}>;

type NavItem = {
  href: string;
  label: string;
  icon: IconComponent;
  permission?: string;
  anyPermissions?: readonly string[];
  ownerOnly?: boolean;
};

const nav: readonly NavItem[] = [
  { href: "/", label: "الرئيسية", icon: Icons.grid, permission: "dashboard.view" },
  { href: "/orders", label: "المبيعات", icon: Icons.cart, permission: "orders.view" },
  { href: "/quick-sale", label: "بيع سريع", icon: Icons.cart, permission: "sales.quick_sale" },
  { href: "/quotes", label: "عروض الأسعار", icon: Icons.money, permission: "orders.view" },
  { href: "/purchases", label: "المشتريات", icon: Icons.store, permission: "purchases.view" },
  {
    href: "/purchase-orders",
    label: "أوامر الشراء",
    icon: Icons.store,
    permission: "purchases.view",
  },
  { href: "/customers", label: "العملاء", icon: Icons.users, permission: "traders.view" },
  { href: "/suppliers", label: "الموردون", icon: Icons.store, permission: "suppliers.view" },
  { href: "/products", label: "الأصناف", icon: Icons.box, permission: "products.view" },
  { href: "/deliveries", label: "التوصيل", icon: Icons.truck, permission: "deliveries.view" },
  { href: "/warranty", label: "الضمان", icon: Icons.shield, permission: "orders.view" },
  {
    href: "/inventory",
    label: "المخزون",
    icon: Icons.box,
    permission: "inventory.view",
  },
  {
    href: "/finance",
    label: "المالية",
    icon: Icons.money,
    anyPermissions: ["finance.accounts_view", "finance.cashbox_view", "reports.finance"],
  },
  {
    href: "/payroll",
    label: "الرواتب",
    icon: Icons.users,
    anyPermissions: [
      "payroll.view",
      "payroll.manage_employees",
      "payroll.process",
      "payroll.pay",
      "payroll.reports",
    ],
  },
  {
    href: "/assets",
    label: "الأصول",
    icon: Icons.box,
    permission: "assets.view",
  },
  {
    href: "/partners",
    label: "الشركاء",
    icon: Icons.users,
    permission: "partners.view",
  },
  { href: "/cashbox", label: "الصندوق", icon: Icons.wallet, permission: "finance.cashbox_view" },
  { href: "/map", label: "الخريطة", icon: Icons.map, permission: "map.view" },
  {
    href: "/reports",
    label: "التقارير",
    icon: Icons.chart,
    anyPermissions: [
      "reports.view",
      "reports.sales",
      "reports.profit",
      "reports.finance",
      "reports.team",
    ],
  },
  { href: "/whatsapp", label: "مركز واتساب", icon: Icons.whatsapp, permission: "whatsapp.view" },
  { href: "/owner", label: "إدارة الفريق", icon: Icons.shield, ownerOnly: true },
  {
    href: "/returns",
    label: "المرتجعات",
    icon: Icons.box,
    anyPermissions: ["returns.view", "returns.create", "inventory.returns"],
  },
  {
    href: "/approvals",
    label: "الموافقات",
    icon: Icons.check,
    anyPermissions: ["approvals.view", "approvals.resolve"],
  },
  { href: "/settings", label: "الإعدادات", icon: Icons.dots, permission: "settings.view" },
];

type Membership = {
  companyId: string;
  companyName: string;
  currency: string;
  roleId: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
};

function canSeeNavItem(item: NavItem, permissions: readonly string[], isOwner: boolean) {
  if (item.ownerOnly) return isOwner;
  if (item.anyPermissions?.length) {
    return hasAnyPermission(permissions, item.anyPermissions, isOwner);
  }
  if (item.permission) {
    return hasPermission(permissions, item.permission, isOwner);
  }
  return false;
}

export function Sidebar({
  userName,
  email,
  roleName,
  isOwner,
  permissions,
  companyId,
  memberships,
}: {
  userName: string;
  email: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
  companyId: string;
  memberships: Membership[];
}) {
  const path = usePathname();
  const visibleNav = nav.filter((item) => canSeeNavItem(item, permissions, isOwner));

  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brandMark">S</div>
        <div>
          <strong>Sales OS</strong>
          <span>إدارة الأعمال</span>
        </div>
      </div>

      <nav className="navList" aria-label="القائمة الرئيسية">
        {visibleNav.map(({ href, label, icon: Icon }) => {
          const active = href === "/" ? path === "/" : path.startsWith(href);
          return (
            <Link key={href} href={href} className={`navItem ${active ? "active" : ""}`}>
              <Icon size={18} />
              <span>{label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="sidebarSpacer" />

      <div className="sidebarCard">
        <Icons.spark size={18} />
        <strong>Sales OS</strong>
        <p>المبيعات والمشتريات والعملاء والمالية ضمن نظام واحد مرتب.</p>
      </div>

      <AccountMenu
        userName={userName}
        email={email}
        roleName={roleName}
        isOwner={isOwner}
        companyId={companyId}
        memberships={memberships}
      />
    </aside>
  );
}
