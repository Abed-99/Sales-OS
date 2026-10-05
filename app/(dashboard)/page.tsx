import Link from "next/link";
import type { ReactNode } from "react";

import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { formatQty } from "@/lib/format";

type RecentCustomer = {
  id: string;
  name: string;
  area: string | null;
  phone: string | null;
  created_at: string;
};

type DashboardSummary = {
  business_date: string;
  currency: string;

  /** false إذا المستخدم ما بيحق لو يشوف مبالغ الفواتير. */
  can_view_invoices: boolean;
  today_sales: number;
  today_invoice_count: number;

  open_orders: number;
  purchasing_orders: number;
  ready_orders: number;
  delivery_orders: number;
  delivered_today: number;

  unpaid_invoices: number;

  customer_count: number;
  active_product_count: number;
  active_supplier_count: number;
  order_count: number;

  recent_customers: RecentCustomer[];
};

type OwnerOverview = {
  cash?: { currency: string; balance: number }[];
  month_revenue?: number;
  month_profit?: number;
  receivables?: number;
  overdue_receivables?: number;
  overdue_invoices?: number;
  payables?: number;
  overdue_payables?: number;
  alerts?: {
    low_stock?: number | null;
    pending_approvals?: number | null;
    loans_to_disburse?: number | null;
    ready_to_deliver?: number | null;
    catalog_orders?: number | null;
  };
};

function toSafeNumber(value: unknown) {
  const parsed = Number(value ?? 0);

  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeSummary(
  data: unknown,
  fallbackCurrency: string,
): DashboardSummary {
  const raw =
    data && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {};

  const recentCustomers = Array.isArray(raw.recent_customers)
    ? (raw.recent_customers as RecentCustomer[]).filter(
        (customer) =>
          customer &&
          typeof customer.id === "string" &&
          typeof customer.name === "string",
      )
    : [];

  return {
    business_date:
      typeof raw.business_date === "string" ? raw.business_date : "",

    currency:
      typeof raw.currency === "string" ? raw.currency : fallbackCurrency,

    can_view_invoices:
      raw.today_sales !== null && raw.today_sales !== undefined,

    today_sales: toSafeNumber(raw.today_sales),

    today_invoice_count: toSafeNumber(raw.today_invoice_count),

    open_orders: toSafeNumber(raw.open_orders),

    purchasing_orders: toSafeNumber(raw.purchasing_orders),

    ready_orders: toSafeNumber(raw.ready_orders),

    delivery_orders: toSafeNumber(raw.delivery_orders),

    delivered_today: toSafeNumber(raw.delivered_today),

    unpaid_invoices: toSafeNumber(raw.unpaid_invoices),

    customer_count: toSafeNumber(raw.customer_count),

    active_product_count: toSafeNumber(raw.active_product_count),

    active_supplier_count: toSafeNumber(raw.active_supplier_count),

    order_count: toSafeNumber(raw.order_count),

    recent_customers: recentCustomers,
  };
}

export default async function DashboardPage() {
  const context = await getCurrentContext();

  const canViewDashboard = hasPermission(
    context.permissions,
    "dashboard.view",
    context.isOwner,
  );

  if (!canViewDashboard) {
    return (
      <>
        <Topbar
          title="الرئيسية"
          subtitle="لوحة التحكم"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />

              <h3>لا تملك صلاحية عرض لوحة التحكم</h3>

              <p>
                تواصل مع مالك الشركة أو مدير الصلاحيات إذا كنت تحتاج إلى الوصول
                لهذه الصفحة.
              </p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const supabase = await createClient();

  const [{ data, error }, overviewResult] = await Promise.all([
    supabase.rpc("get_dashboard_summary", {
      target_company: context.companyId,
    }),
    supabase.rpc("get_owner_overview", { target_company: context.companyId }),
  ]);

  const overview = (overviewResult.data ?? {}) as OwnerOverview;

  if (error) {
    console.error("Dashboard summary failed:", error);

    return (
      <>
        <Topbar
          title="الرئيسية"
          subtitle="لوحة التحكم"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.grid size={32} />

              <h3>تعذر تحميل لوحة التحكم</h3>

              <p>حدث خطأ أثناء تحميل ملخص الشركة. حاول تحديث الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const summary = normalizeSummary(data, context.currency);

  const canViewOrders = hasPermission(
    context.permissions,
    "orders.view",
    context.isOwner,
  );

  const canCreateOrders = hasPermission(
    context.permissions,
    "orders.create",
    context.isOwner,
  );

  const canViewCustomers = hasPermission(
    context.permissions,
    "traders.view",
    context.isOwner,
  );

  const canViewPurchases = hasPermission(
    context.permissions,
    "purchases.view",
    context.isOwner,
  );

  const canViewProducts = hasPermission(
    context.permissions,
    "products.view",
    context.isOwner,
  );

  const canViewSuppliers = hasPermission(
    context.permissions,
    "suppliers.view",
    context.isOwner,
  );

  const hasWelcomeActions =
    (canViewOrders && canCreateOrders) || canViewCustomers || canViewPurchases;

  const hasQuickLinks =
    canViewCustomers || canViewProducts || canViewSuppliers || canViewOrders;

  const fmt = (value: number) =>
    new Intl.NumberFormat("en-US", {
      maximumFractionDigits: 2,
    }).format(value);

  return (
    <>
      <Topbar
        title="الرئيسية"
        subtitle={`مرحباً ${context.userName}، هذه نظرة سريعة على أعمال اليوم.`}
        companyName={context.companyName}
      />

      <div className="page dashboardHome">
        <OwnerPanel overview={overview} currency={summary.currency} fmt={fmt} />

        <section className="dashboardWelcome">
          <div className="dashboardWelcomeText">
            <span className="eyebrow">Sales OS</span>

            <h2>كل أعمال الشركة أمامك في مكان واحد</h2>

            <p>
              تابع المبيعات والعملاء والمشتريات والتوصيل بسرعة ومن دون التنقل
              بين صفحات متعددة.
            </p>
          </div>

          {hasWelcomeActions ? (
            <div className="dashboardWelcomeActions">
              {canViewOrders && canCreateOrders ? (
                <Link href="/orders" className="primaryButton">
                  <Icons.plus size={16} />
                  طلب جديد
                </Link>
              ) : null}

              {canViewCustomers ? (
                <Link href="/customers" className="softButton">
                  <Icons.users size={16} />
                  العملاء
                </Link>
              ) : null}

              {canViewPurchases ? (
                <Link href="/purchases" className="softButton">
                  <Icons.store size={16} />
                  المشتريات
                </Link>
              ) : null}
            </div>
          ) : null}
        </section>

        <section className="dashboardStats">
          {summary.can_view_invoices ? (
            <Stat
              icon={<Icons.money size={18} />}
              label="المبيعات المفوترة اليوم"
              value={`${fmt(summary.today_sales)} ${summary.currency}`}
              trend={`${summary.today_invoice_count} فاتورة اليوم`}
            />
          ) : null}

          <Stat
            icon={<Icons.cart size={18} />}
            label="طلبات قيد التنفيذ"
            value={formatQty(summary.open_orders)}
            trend="تحتاج متابعة"
          />

          {summary.can_view_invoices ? (
            <Stat
              icon={<Icons.wallet size={18} />}
              label="فواتير غير مسددة"
              value={formatQty(summary.unpaid_invoices)}
              trend="بانتظار التحصيل"
            />
          ) : null}

          <Stat
            icon={<Icons.users size={18} />}
            label="إجمالي العملاء"
            value={formatQty(summary.customer_count)}
            trend="العملاء الفعليون"
          />
        </section>

        <div className="dashboardMainGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>حركة الطلبات</h2>

                <p>حالة الطلبات ضمن دورة العمل الحالية</p>
              </div>

              {canViewOrders ? (
                <Link href="/orders" className="softButton">
                  عرض الطلبات
                  <Icons.arrow size={13} />
                </Link>
              ) : null}
            </div>

            <div className="orderFlowGrid">
              <FlowCard
                label="بانتظار/قيد الشراء"
                value={summary.purchasing_orders}
                icon={<Icons.store size={18} />}
              />

              <FlowCard
                label="جاهزة"
                value={summary.ready_orders}
                icon={<Icons.box size={18} />}
              />

              <FlowCard
                label="قيد التوصيل"
                value={summary.delivery_orders}
                icon={<Icons.truck size={18} />}
              />

              <FlowCard
                label="تم التسليم اليوم"
                value={summary.delivered_today}
                icon={<Icons.check size={18} />}
              />
            </div>
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>اختصارات سريعة</h2>

                <p>الأقسام المتاحة حسب صلاحياتك</p>
              </div>
            </div>

            {hasQuickLinks ? (
              <div className="dashboardQuickGrid">
                {canViewCustomers ? (
                  <QuickLink
                    href="/customers"
                    icon={<Icons.users size={18} />}
                    title="العملاء"
                    value={`${summary.customer_count} عميل`}
                  />
                ) : null}

                {canViewProducts ? (
                  <QuickLink
                    href="/products"
                    icon={<Icons.box size={18} />}
                    title="الأصناف"
                    value={`${summary.active_product_count} صنف نشط`}
                  />
                ) : null}

                {canViewSuppliers ? (
                  <QuickLink
                    href="/suppliers"
                    icon={<Icons.store size={18} />}
                    title="الموردون"
                    value={`${summary.active_supplier_count} مورد نشط`}
                  />
                ) : null}

                {canViewOrders ? (
                  <QuickLink
                    href="/orders"
                    icon={<Icons.cart size={18} />}
                    title="الطلبات"
                    value={`${summary.order_count} طلب غير ملغى`}
                  />
                ) : null}
              </div>
            ) : (
              <div className="dashboardEmpty">
                <p>لا توجد أقسام إضافية متاحة ضمن صلاحياتك الحالية.</p>
              </div>
            )}
          </aside>
        </div>

        {canViewCustomers ? (
          <section className="panel panelPad dashboardRecent">
            <div className="panelHeader">
              <div>
                <h2>آخر العملاء المضافين</h2>

                <p>أحدث العملاء الفعليين المسجلين في النظام</p>
              </div>

              <Link href="/customers" className="softButton">
                كل العملاء
                <Icons.arrow size={13} />
              </Link>
            </div>

            {!summary.recent_customers.length ? (
              <div className="empty dashboardEmpty">
                <Icons.users size={30} />

                <h3>لا يوجد عملاء حتى الآن</h3>

                <p>عند إضافة أول عميل فعلي سيظهر هنا تلقائياً.</p>
              </div>
            ) : (
              <div className="dashboardCustomerCards dashboardCustomerCardsAlways">
                {summary.recent_customers.map((customer) => (
                  <Link
                    href={`/customers/${customer.id}`}
                    key={customer.id}
                    className="dashboardCustomerCard"
                  >
                    <div className="merchantLogo">
                      {customer.name.charAt(0)}
                    </div>

                    <div className="dashboardCustomerInfo">
                      <strong>{customer.name}</strong>

                      <span>
                        {customer.area || "بدون منطقة"}
                        {" · "}
                        {customer.phone || "بدون رقم"}
                      </span>
                    </div>

                    <span className="chip green">عميل</span>
                  </Link>
                ))}
              </div>
            )}
          </section>
        ) : null}
      </div>
    </>
  );
}

function OwnerPanel({
  overview,
  currency,
  fmt,
}: {
  overview: OwnerOverview;
  currency: string;
  fmt: (value: number) => string;
}) {
  const alerts = [
    {
      count: overview.alerts?.pending_approvals,
      text: "طلب موافقة بانتظارك",
      href: "/approvals",
    },
    {
      count: overview.overdue_invoices,
      text: `فاتورة متأخرة الدفع (${fmt(toSafeNumber(overview.overdue_receivables))} ${currency})`,
      href: "/orders",
    },
    {
      count: overview.alerts?.low_stock,
      text: "صنف وصل للحد الأدنى بالمخزون",
      href: "/inventory",
    },
    {
      count: overview.alerts?.catalog_orders,
      text: "طلب جديد من الكتالوج",
      href: "/quotes?status=draft",
    },
    {
      count: overview.alerts?.ready_to_deliver,
      text: "طلبية جاهزة للتوصيل",
      href: "/deliveries",
    },
    {
      count: overview.alerts?.loans_to_disburse,
      text: "سلفة بانتظار الصرف",
      href: "/payroll",
    },
  ].filter((alert) => toSafeNumber(alert.count) > 0);

  const hasMoney =
    overview.cash !== undefined ||
    overview.month_profit !== undefined ||
    overview.receivables !== undefined ||
    overview.payables !== undefined;

  if (!hasMoney && !alerts.length) return null;

  return (
    <section className="panel panelPad" style={{ marginBottom: 14 }}>
      {hasMoney ? (
        <div className="statsGrid">
          {overview.cash !== undefined ? (
            <div className="statCard">
              <div className="statLabel">المصاري بالصناديق</div>
              <div className="statValue">
                {overview.cash.length
                  ? overview.cash.map((row) => (
                      <div key={row.currency}>
                        {fmt(toSafeNumber(row.balance))} {row.currency}
                      </div>
                    ))
                  : `0 ${currency}`}
              </div>
            </div>
          ) : null}

          {overview.month_profit !== undefined ? (
            <div className="statCard">
              <div className="statLabel">ربح هالشهر</div>
              <div
                className={`statValue ${toSafeNumber(overview.month_profit) >= 0 ? "kpiPositive" : "kpiNegative"}`}
              >
                {fmt(toSafeNumber(overview.month_profit))} {currency}
              </div>
              <div className="muted">
                المبيعات والإيرادات: {fmt(toSafeNumber(overview.month_revenue))}{" "}
                {currency}
              </div>
            </div>
          ) : null}

          {overview.receivables !== undefined ? (
            <div className="statCard">
              <div className="statLabel">ديون عند الزبائن</div>
              <div className="statValue">
                {fmt(toSafeNumber(overview.receivables))} {currency}
              </div>
              {toSafeNumber(overview.overdue_receivables) > 0 ? (
                <div className="muted kpiNegative">
                  متأخر: {fmt(toSafeNumber(overview.overdue_receivables))}{" "}
                  {currency}
                </div>
              ) : null}
            </div>
          ) : null}

          {overview.payables !== undefined ? (
            <div className="statCard">
              <div className="statLabel">ديون علينا للموردين</div>
              <div className="statValue">
                {fmt(toSafeNumber(overview.payables))} {currency}
              </div>
              {toSafeNumber(overview.overdue_payables) > 0 ? (
                <div className="muted kpiNegative">
                  مستحق: {fmt(toSafeNumber(overview.overdue_payables))}{" "}
                  {currency}
                </div>
              ) : null}
            </div>
          ) : null}
        </div>
      ) : null}

      {alerts.length ? (
        <div className="quickList" style={{ marginTop: hasMoney ? 14 : 0 }}>
          {alerts.map((alert) => (
            <Link
              href={alert.href}
              className="quickItem"
              key={alert.href}
              style={{ textDecoration: "none", color: "inherit" }}
            >
              <div className="quickIcon">
                <Icons.bell size={15} />
              </div>
              <div>
                <strong>
                  {fmt(toSafeNumber(alert.count))} {alert.text}
                </strong>
              </div>
              <Icons.arrow size={13} />
            </Link>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function Stat({
  icon,
  label,
  value,
  trend,
}: {
  icon: ReactNode;
  label: string;
  value: string;
  trend: string;
}) {
  return (
    <div className="dashboardStatCard">
      <div className="dashboardStatTop">
        <div className="dashboardStatIcon">{icon}</div>

        <span>{trend}</span>
      </div>

      <div className="dashboardStatLabel">{label}</div>

      <div className="dashboardStatValue">{value}</div>
    </div>
  );
}

function FlowCard({
  label,
  value,
  icon,
}: {
  label: string;
  value: number;
  icon: ReactNode;
}) {
  return (
    <div className="orderFlowCard">
      <div className="orderFlowIcon">{icon}</div>

      <div>
        <strong>{value}</strong>

        <span>{label}</span>
      </div>
    </div>
  );
}

function QuickLink({
  href,
  icon,
  title,
  value,
}: {
  href: string;
  icon: ReactNode;
  title: string;
  value: string;
}) {
  return (
    <Link href={href} className="dashboardQuickLink">
      <div className="quickIcon">{icon}</div>

      <div>
        <strong>{title}</strong>

        <span>{value}</span>
      </div>

      <Icons.arrow size={14} />
    </Link>
  );
}
