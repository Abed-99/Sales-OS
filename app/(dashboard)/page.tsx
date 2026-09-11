import Link from "next/link";
import type { ReactNode } from "react";

import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { createClient } from "@/lib/supabase/server";

type OrderRow = {
  id: string;
  total: number;
  status: string;
  payment_status: string;
  created_at: string;
};

type TraderRow = {
  id: string;
  name: string;
  area: string | null;
  status: string;
  phone: string | null;
  whatsapp: string | null;
  created_at: string;
};

export default async function DashboardPage() {
  const { userName, companyName, companyId, currency } =
    await getCurrentContext();

  const supabase = await createClient();

  const [
    tradersResult,
    productsResult,
    suppliersResult,
    ordersResult,
    recentResult,
  ] = await Promise.all([
    supabase.from("traders").select("*", { count: "exact", head: true }).eq("company_id", companyId),
    supabase.from("products").select("*", { count: "exact", head: true }).eq("company_id", companyId),
    supabase.from("suppliers").select("*", { count: "exact", head: true }).eq("company_id", companyId),
    supabase
      .from("sales_orders")
      .select("id,total,status,payment_status,created_at")
      .eq("company_id", companyId)
      .neq("status", "cancelled")
      .order("created_at", { ascending: false })
      .limit(250),
    supabase
      .from("traders")
      .select("id,name,area,status,phone,whatsapp,created_at")
      .eq("company_id", companyId)
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  if (ordersResult.error) throw new Error(ordersResult.error.message);
  if (recentResult.error) throw new Error(recentResult.error.message);

  const orders = (ordersResult.data ?? []) as OrderRow[];
  const recent = (recentResult.data ?? []) as TraderRow[];
  const today = new Date().toISOString().slice(0, 10);
  const todayOrders = orders.filter(
    (order) => String(order.created_at).slice(0, 10) === today
  );
  const todaySales = todayOrders.reduce(
    (sum, order) => sum + Number(order.total || 0),
    0
  );

  const openOrders = orders.filter(
    (order) => !["delivered", "cancelled"].includes(order.status)
  ).length;
  const unpaidOrders = orders.filter(
    (order) => order.payment_status !== "paid"
  ).length;
  const readyOrders = orders.filter((order) => order.status === "ready").length;
  const purchasingOrders = orders.filter((order) =>
    ["to_purchase", "purchasing"].includes(order.status)
  ).length;
  const deliveryOrders = orders.filter(
    (order) => order.status === "out_for_delivery"
  ).length;
  const deliveredOrders = orders.filter(
    (order) => order.status === "delivered"
  ).length;

  const fmt = (value: number) =>
    new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(value);

  return (
    <>
      <Topbar
        title="الرئيسية"
        subtitle={`أهلاً ${userName}، هاي نظرة سريعة على شغل اليوم.`}
        companyName={companyName}
      />

      <div className="page dashboardHome">
        <section className="dashboardWelcome">
          <div className="dashboardWelcomeText">
            <span className="eyebrow">Sales OS</span>
            <h2>كل شغل الشركة قدامك بمكان واحد</h2>
            <p>
              تابع المبيعات، العملاء، المشتريات والتوصيل بسرعة ومن دون
              ما تضيع بين الصفحات.
            </p>
          </div>

          <div className="dashboardWelcomeActions">
            <Link href="/orders" className="primaryButton">
              <Icons.plus size={16} />
              طلب جديد
            </Link>
            <Link href="/customers" className="softButton">
              <Icons.users size={16} />
              العملاء
            </Link>
            <Link href="/purchases" className="softButton">
              <Icons.store size={16} />
              المشتريات
            </Link>
          </div>
        </section>

        <section className="dashboardStats">
          <Stat
            icon={<Icons.money size={18} />}
            label="مبيعات اليوم"
            value={`${fmt(todaySales)} ${currency}`}
            trend={`${todayOrders.length} طلب اليوم`}
          />
          <Stat
            icon={<Icons.cart size={18} />}
            label="طلبات قيد التنفيذ"
            value={String(openOrders)}
            trend="تحتاج متابعة"
          />
          <Stat
            icon={<Icons.wallet size={18} />}
            label="طلبات غير مسددة"
            value={String(unpaidOrders)}
            trend="بانتظار التحصيل"
          />
          <Stat
            icon={<Icons.users size={18} />}
            label="إجمالي العملاء"
            value={String(tradersResult.count ?? 0)}
            trend="قاعدة العملاء"
          />
        </section>

        <div className="dashboardMainGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>حركة الطلبات</h2>
                <p>وضع الطلبات الحالية ضمن دورة العمل</p>
              </div>
              <Link href="/orders" className="softButton">
                عرض الطلبات
                <Icons.arrow size={13} />
              </Link>
            </div>

            <div className="orderFlowGrid">
              <FlowCard
                label="بانتظار الشراء"
                value={purchasingOrders}
                icon={<Icons.store size={18} />}
              />
              <FlowCard
                label="جاهزة"
                value={readyOrders}
                icon={<Icons.box size={18} />}
              />
              <FlowCard
                label="قيد التوصيل"
                value={deliveryOrders}
                icon={<Icons.truck size={18} />}
              />
              <FlowCard
                label="تم التسليم"
                value={deliveredOrders}
                icon={<Icons.check size={18} />}
              />
            </div>
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>اختصارات سريعة</h2>
                <p>أكثر الأقسام استخداماً</p>
              </div>
            </div>

            <div className="dashboardQuickGrid">
              <QuickLink href="/customers" icon={<Icons.users size={18} />} title="العملاء" value={String(tradersResult.count ?? 0)} />
              <QuickLink href="/products" icon={<Icons.box size={18} />} title="الأصناف" value={String(productsResult.count ?? 0)} />
              <QuickLink href="/suppliers" icon={<Icons.store size={18} />} title="الموردون" value={String(suppliersResult.count ?? 0)} />
              <QuickLink href="/orders" icon={<Icons.cart size={18} />} title="الطلبات" value={String(orders.length)} />
            </div>
          </aside>
        </div>

        <section className="panel panelPad dashboardRecent">
          <div className="panelHeader">
            <div>
              <h2>آخر العملاء المضافين</h2>
              <p>أحدث العملاء المسجلين بالنظام</p>
            </div>
            <Link href="/customers" className="softButton">
              كل العملاء
              <Icons.arrow size={13} />
            </Link>
          </div>

          {!recent.length ? (
            <div className="empty dashboardEmpty">
              <Icons.users size={30} />
              <h3>ما في عملاء لسا</h3>
              <p>أضف أول عميل لتبدأ دورة البيع.</p>
            </div>
          ) : (
            <div className="dashboardCustomerCards dashboardCustomerCardsAlways">
              {recent.map((trader) => (
                <Link
                  href={`/customers/${trader.id}`}
                  key={trader.id}
                  className="dashboardCustomerCard"
                >
                  <div className="merchantLogo">{trader.name?.charAt(0)}</div>
                  <div className="dashboardCustomerInfo">
                    <strong>{trader.name}</strong>
                    <span>
                      {trader.area || "بدون منطقة"} · {trader.phone || "بدون رقم"}
                    </span>
                  </div>
                  <span className="chip blue">{statusLabel(trader.status)}</span>
                </Link>
              ))}
            </div>
          )}
        </section>
      </div>
    </>
  );
}

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    new: "جديد",
    contacted: "تم التواصل",
    interested: "مهتم",
    customer: "عميل",
    inactive: "غير نشط",
  };
  return labels[status] ?? status;
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
        <span>{value} سجل</span>
      </div>
      <Icons.arrow size={14} />
    </Link>
  );
}
