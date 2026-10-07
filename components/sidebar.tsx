"use client";

import { useEffect, useState, type ComponentType } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { AccountMenu } from "@/components/account-menu";
import { Icons } from "@/components/icons";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";

type IconComponent = ComponentType<{
  size?: number;
  className?: string;
}>;

type GroupKey = "sales" | "purchases" | "goods" | "people" | "money" | "admin";

type NavItem = {
  href: string;
  label: string;
  icon: IconComponent;
  /** بدون مجموعة = ظاهر دايمًا فوق (الشغل اليومي). */
  group?: GroupKey;
  /** ظاهر لحالو تحت المجموعات. */
  bottom?: boolean;
  permission?: string;
  anyPermissions?: readonly string[];
  ownerOnly?: boolean;
};

const groups: readonly { key: GroupKey; label: string; icon: IconComponent }[] = [
  { key: "sales", label: "المبيعات", icon: Icons.cart },
  { key: "purchases", label: "المشتريات", icon: Icons.store },
  { key: "goods", label: "البضاعة", icon: Icons.box },
  { key: "people", label: "الناس", icon: Icons.users },
  { key: "money", label: "المصاري", icon: Icons.wallet },
  { key: "admin", label: "الإدارة", icon: Icons.shield },
];

const nav: readonly NavItem[] = [
  { href: "/", label: "الرئيسية", icon: Icons.grid, permission: "dashboard.view" },
  { href: "/quick-sale", label: "بيع سريع", icon: Icons.cart, permission: "sales.quick_sale" },

  { href: "/orders", label: "المبيعات", icon: Icons.cart, group: "sales", permission: "orders.view" },
  { href: "/quotes", label: "عروض الأسعار", icon: Icons.money, group: "sales", permission: "orders.view" },
  { href: "/deliveries", label: "التوصيل", icon: Icons.truck, group: "sales", permission: "deliveries.view" },
  {
    href: "/returns",
    label: "المرتجعات",
    icon: Icons.box,
    group: "sales",
    anyPermissions: ["returns.view", "returns.create", "inventory.returns"],
  },
  { href: "/warranty", label: "الضمان", icon: Icons.shield, group: "sales", permission: "orders.view" },

  { href: "/purchases", label: "المشتريات", icon: Icons.store, group: "purchases", permission: "purchases.view" },
  {
    href: "/purchase-orders",
    label: "أوامر الشراء",
    icon: Icons.store,
    group: "purchases",
    permission: "purchases.view",
  },
  { href: "/imports", label: "الاستيراد", icon: Icons.truck, group: "purchases", permission: "purchases.view" },

  { href: "/products", label: "الأصناف", icon: Icons.box, group: "goods", permission: "products.view" },
  { href: "/inventory", label: "المخزون", icon: Icons.box, group: "goods", permission: "inventory.view" },
  {
    href: "/catalog",
    label: "الكتالوج",
    icon: Icons.box,
    group: "goods",
    anyPermissions: ["orders.create", "products.update"],
  },

  { href: "/customers", label: "العملاء", icon: Icons.users, group: "people", permission: "traders.view" },
  { href: "/suppliers", label: "الموردون", icon: Icons.store, group: "people", permission: "suppliers.view" },
  { href: "/map", label: "الخريطة", icon: Icons.map, group: "people", permission: "map.view" },
  {
    href: "/whatsapp",
    label: "واتساب",
    icon: Icons.whatsapp,
    group: "people",
    anyPermissions: ["traders.view", "orders.view"],
  },

  { href: "/cashbox", label: "الصندوق", icon: Icons.wallet, group: "money", permission: "finance.cashbox_view" },
  {
    href: "/finance",
    label: "المالية",
    icon: Icons.money,
    group: "money",
    anyPermissions: ["finance.accounts_view", "finance.cashbox_view", "reports.finance"],
  },
  {
    href: "/reports",
    label: "التقارير",
    icon: Icons.chart,
    group: "money",
    anyPermissions: ["reports.view", "reports.sales", "reports.profit", "reports.finance", "reports.team"],
  },
  {
    href: "/payroll",
    label: "الرواتب",
    icon: Icons.users,
    group: "money",
    anyPermissions: ["payroll.view", "payroll.manage_employees", "payroll.process", "payroll.pay", "payroll.reports"],
  },
  { href: "/assets", label: "الأصول", icon: Icons.box, group: "money", permission: "assets.view" },
  { href: "/partners", label: "الشركاء", icon: Icons.users, group: "money", permission: "partners.view" },

  {
    href: "/approvals",
    label: "الموافقات",
    icon: Icons.check,
    group: "admin",
    anyPermissions: ["approvals.view", "approvals.resolve"],
  },
  { href: "/owner", label: "إدارة الفريق", icon: Icons.shield, group: "admin", ownerOnly: true },
  { href: "/settings", label: "الإعدادات", icon: Icons.dots, group: "admin", permission: "settings.view" },

  { href: "/visits", label: "جولة الزيارات", icon: Icons.route, bottom: true, permission: "traders.view" },
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

function isActive(href: string, path: string) {
  return href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
}

const OPEN_KEY = "sales_os_nav_open";

function Chevron({ open }: { open: boolean }) {
  return (
    <svg
      className={`navChevron${open ? " open" : ""}`}
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="m15 6-6 6 6 6" />
    </svg>
  );
}

export function Sidebar({
  userName,
  email,
  roleName,
  isOwner,
  permissions,
  companyId,
  memberships,
  waPending = 0,
  approvalsPending = 0,
}: {
  userName: string;
  email: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
  companyId: string;
  memberships: Membership[];
  waPending?: number;
  approvalsPending?: number;
}) {
  const path = usePathname();
  const visibleNav = nav.filter((item) => canSeeNavItem(item, permissions, isOwner));
  const activeGroup = visibleNav.find((item) => isActive(item.href, path))?.group;

  // المجموعات اللي فتحها المستخدم بإيدو (بتنحفظ بالمتصفح). مجموعة الصفحة الحالية مفتوحة دايمًا.
  const [opened, setOpened] = useState<GroupKey[]>([]);

  useEffect(() => {
    try {
      const saved = JSON.parse(window.localStorage.getItem(OPEN_KEY) ?? "[]");
      if (Array.isArray(saved)) setOpened(saved.filter((key) => groups.some((g) => g.key === key)));
    } catch {
      // التخزين مقفول (مثلًا تصفّح خاص): بتشتغل بدون تذكّر.
    }
  }, []);

  function toggle(key: GroupKey) {
    setOpened((current) => {
      const isOpen = current.includes(key) || key === activeGroup;
      const next = isOpen ? current.filter((item) => item !== key) : [...current, key];
      try {
        window.localStorage.setItem(OPEN_KEY, JSON.stringify(next));
      } catch {
        // ما في تخزين: عادي.
      }
      return next;
    });
  }

  const badgeFor = (href: string) =>
    href === "/whatsapp" ? waPending : href === "/approvals" ? approvalsPending : 0;

  function renderItem({ href, label, icon: Icon, group }: NavItem) {
    const badge = badgeFor(href);
    return (
      <Link
        key={href}
        href={href}
        className={`navItem${group ? " navSubItem" : ""}${isActive(href, path) ? " active" : ""}`}
        aria-current={isActive(href, path) ? "page" : undefined}
      >
        <Icon size={group ? 16 : 18} />
        <span>{label}</span>
        {badge > 0 ? (
          <span className="navBadge" title={href === "/whatsapp" ? "رسائل جاهزة للإرسال" : "طلبات ناطرة موافقتك"}>
            {badge}
          </span>
        ) : null}
      </Link>
    );
  }

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
        {visibleNav.filter((item) => !item.group && !item.bottom).map(renderItem)}

        {groups.map(({ key, label, icon: Icon }) => {
          const items = visibleNav.filter((item) => item.group === key);
          if (!items.length) return null;

          const open = opened.includes(key) || key === activeGroup;
          const badge = items.reduce((sum, item) => sum + badgeFor(item.href), 0);

          return (
            <div key={key} className="navGroup">
              <button
                type="button"
                className={`navItem navGroupHead${key === activeGroup ? " current" : ""}`}
                aria-expanded={open}
                aria-controls={`nav-group-${key}`}
                onClick={() => toggle(key)}
              >
                <Icon size={18} />
                <span>{label}</span>
                {!open && badge > 0 ? <span className="navBadge">{badge}</span> : null}
                <Chevron open={open} />
              </button>

              {open ? (
                <div id={`nav-group-${key}`} className="navGroupItems">
                  {items.map(renderItem)}
                </div>
              ) : null}
            </div>
          );
        })}

        {visibleNav.some((item) => item.bottom) ? <div className="navDivider" role="separator" /> : null}
        {visibleNav.filter((item) => item.bottom).map(renderItem)}
      </nav>

      <div className="sidebarSpacer" />

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
