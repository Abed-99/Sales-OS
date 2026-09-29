"use client";

import { useState } from "react";
import type { ComponentType } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

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

const primaryNav: readonly NavItem[] = [
  { href: "/", label: "الرئيسية", icon: Icons.grid, permission: "dashboard.view" },
  { href: "/orders", label: "المبيعات", icon: Icons.cart, permission: "orders.view" },
  { href: "/customers", label: "العملاء", icon: Icons.users, permission: "traders.view" },
  { href: "/purchases", label: "المشتريات", icon: Icons.store, permission: "purchases.view" },
];

const moreNav: readonly NavItem[] = [
  { href: "/quick-sale", label: "بيع سريع", icon: Icons.cart, permission: "sales.quick_sale" },
  { href: "/quotes", label: "عروض الأسعار", icon: Icons.money, permission: "orders.view" },
  {
    href: "/purchase-orders",
    label: "أوامر الشراء",
    icon: Icons.store,
    permission: "purchases.view",
  },
  { href: "/imports", label: "الاستيراد", icon: Icons.truck, permission: "purchases.view" },
  { href: "/products", label: "الأصناف", icon: Icons.box, permission: "products.view" },
  { href: "/suppliers", label: "الموردون", icon: Icons.store, permission: "suppliers.view" },
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
  {
    href: "/whatsapp",
    label: "واتساب",
    icon: Icons.whatsapp,
    anyPermissions: ["traders.view", "orders.view"],
  },
  { href: "/owner", label: "الفريق", icon: Icons.shield, ownerOnly: true },
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

function canSee(item: NavItem, permissions: readonly string[], isOwner: boolean) {
  if (item.ownerOnly) return isOwner;
  if (item.anyPermissions?.length) {
    return hasAnyPermission(permissions, item.anyPermissions, isOwner);
  }
  if (item.permission) {
    return hasPermission(permissions, item.permission, isOwner);
  }
  return false;
}

export function MobileNav({
  permissions,
  isOwner,
  waPending = 0,
}: {
  permissions: string[];
  isOwner: boolean;
  waPending?: number;
}) {
  const path = usePathname();
  const [moreOpen, setMoreOpen] = useState(false);

  const primary = primaryNav.filter((item) => canSee(item, permissions, isOwner));
  const more = moreNav.filter((item) => canSee(item, permissions, isOwner));
  const moreActive = more.some((item) =>
    item.href === "/" ? path === "/" : path.startsWith(item.href),
  );

  return (
    <>
      {moreOpen ? (
        <div className="mobileMoreBackdrop" onClick={() => setMoreOpen(false)}>
          <div className="mobileMoreSheet" onClick={(event) => event.stopPropagation()}>
            <div className="mobileMoreHeader">
              <div>
                <strong>كل الأقسام</strong>
                <span>اختار القسم يلي بدك تفتحه</span>
              </div>
              <button
                type="button"
                className="mobileMoreClose"
                onClick={() => setMoreOpen(false)}
                aria-label="إغلاق"
              >
                ×
              </button>
            </div>

            <div className="mobileMoreGrid">
              {more.map(({ href, label, icon: Icon }) => {
                const active = href === "/" ? path === "/" : path.startsWith(href);
                return (
                  <Link
                    key={href}
                    href={href}
                    className={active ? "active" : ""}
                    onClick={() => setMoreOpen(false)}
                  >
                    <Icon size={21} />
                    <span>{label}</span>
                    {href === "/whatsapp" && waPending > 0 ? (
                      <span className="navBadge">{waPending}</span>
                    ) : null}
                  </Link>
                );
              })}
            </div>
          </div>
        </div>
      ) : null}

      <nav className="mobileNav" aria-label="التنقل الرئيسي">
        {primary.map(({ href, label, icon: Icon }) => {
          const active = href === "/" ? path === "/" : path.startsWith(href);
          return (
            <Link key={href} href={href} className={active ? "active" : ""}>
              <Icon size={19} />
              <span>{label}</span>
            </Link>
          );
        })}

        <button
          type="button"
          className={moreActive || moreOpen ? "active" : ""}
          onClick={() => setMoreOpen(true)}
        >
          <Icons.dots size={19} />
          <span>المزيد</span>
          {waPending > 0 ? <span className="navBadge navBadgeFloat">{waPending}</span> : null}
        </button>
      </nav>
    </>
  );
}
