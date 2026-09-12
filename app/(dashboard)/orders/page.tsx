import {
  OrdersClient,
  type OrderCashbox,
  type OrderFilter,
  type OrderProduct,
  type OrderRow,
  type OrderSalesInvoice,
  type OrderStats,
  type OrderTrader,
} from "@/components/orders/orders-client";
import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

const validStatuses = new Set([
  "draft",
  "new",
  "to_purchase",
  "purchasing",
  "ready",
  "out_for_delivery",
  "delivered",
  "cancelled",
]);

function firstParam(
  value:
    | string
    | string[]
    | undefined
) {
  return Array.isArray(value)
    ? value[0] ?? ""
    : value ?? "";
}

function cleanSearch(
  value: string
) {
  return value
    .replace(
      /[%_(),"'\\]/g,
      " "
    )
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
}

export default async function OrdersPage({
  searchParams,
}: {
  searchParams: Promise<
    Record<
      string,
      string | string[] | undefined
    >
  >;
}) {
  const context =
    await getCurrentContext();

  const params =
    await searchParams;

  const canView =
    hasPermission(
      context.permissions,
      "orders.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="المبيعات"
          subtitle="الطلبات، الفواتير والتحصيل من العملاء"
          companyName={
            context.companyName
          }
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield
                size={32}
              />

              <h3>
                لا تملك صلاحية عرض الطلبات
              </h3>

              <p>
                تواصل مع مالك الشركة أو مدير الصلاحيات إذا كنت تحتاج إلى الوصول لهذه الصفحة.
              </p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canCreate =
    hasPermission(
      context.permissions,
      "orders.create",
      context.isOwner
    );

  const canCancel =
    hasPermission(
      context.permissions,
      "orders.cancel",
      context.isOwner
    );

  const canCollect =
    hasPermission(
      context.permissions,
      "payments.sales_create",
      context.isOwner
    );

  const canViewDeliveries =
    hasPermission(
      context.permissions,
      "deliveries.view",
      context.isOwner
    );

  const search =
    cleanSearch(
      firstParam(params.q)
    );

  const rawStatus =
    firstParam(
      params.status
    );

  const statusFilter:
    OrderFilter =
      validStatuses.has(
        rawStatus
      )
        ? (rawStatus as OrderFilter)
        : "all";

  const requestedPage =
    Math.max(
      1,
      Number.parseInt(
        firstParam(
          params.page
        ),
        10
      ) || 1
    );

  const pageSize = 50;

  const from =
    (requestedPage - 1) *
    pageSize;

  const to =
    from +
    pageSize -
    1;

  const supabase =
    await createClient();

  let ordersQuery =
    supabase
      .from("sales_orders")
      .select(
        `
          id,
          trader_id,
          status,
          payment_status,
          subtotal,
          total,
          notes,
          created_at,
          delivered_at,
          cancelled_at,
          cancellation_reason,
          traders!inner(
            name,
            area,
            phone,
            whatsapp
          ),
          sales_order_items(
            id,
            product_id,
            quantity,
            sale_unit_price,
            line_total,
            products(
              name,
              sku
            )
          )
        `,
        {
          count: "exact",
        }
      )
      .eq(
        "company_id",
        context.companyId
      )
      .order(
        "created_at",
        {
          ascending: false,
        }
      )
      .range(
        from,
        to
      );

  if (
    statusFilter !==
    "all"
  ) {
    ordersQuery =
      ordersQuery.eq(
        "status",
        statusFilter
      );
  }

  if (search) {
    ordersQuery =
      ordersQuery.ilike(
        "traders.name",
        `%${search}%`
      );
  }

  const [
    ordersResult,
    summaryResult,
  ] =
    await Promise.all([
      ordersQuery,

      supabase.rpc(
        "get_orders_summary",
        {
          target_company:
            context.companyId,
        }
      ),
    ]);

  let initialError:
    string | null =
      ordersResult.error
        ? "تعذر تحميل الطلبات. حاول تحديث الصفحة."
        : null;

  let stats:
    OrderStats | null =
      null;

  if (
    !summaryResult.error
  ) {
    const raw =
      Array.isArray(
        summaryResult.data
      )
        ? summaryResult
            .data[0]
        : summaryResult.data;

    if (raw) {
      const row =
        raw as Record<
          string,
          unknown
        >;

      stats = {
        total:
          Number(
            row.total_count ??
              0
          ),

        active:
          Number(
            row.active_count ??
              0
          ),

        new:
          Number(
            row.new_count ??
              0
          ),

        ready:
          Number(
            row.ready_delivery_count ??
              0
          ),

        totalValue:
          Number(
            row.total_active_value ??
              0
          ),
      };
    }
  }

  const orders =
    (ordersResult.data ??
      []) as unknown as OrderRow[];

  let traders:
    OrderTrader[] = [];

  let products:
    OrderProduct[] = [];

  if (canCreate) {
    const [
      tradersResult,
      productsResult,
    ] =
      await Promise.all([
        supabase
          .from("traders")
          .select(
            "id,name,area,status"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .neq(
            "status",
            "inactive"
          )
          .order("name"),

        supabase
          .from("products")
          .select(
            "id,name,sku,sale_price,minimum_sale_price,unit,active"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .eq(
            "active",
            true
          )
          .order("name"),
      ]);

    if (
      tradersResult.error ||
      productsResult.error
    ) {
      initialError ??=
        "تعذر تحميل بيانات إنشاء الطلبية.";
    } else {
      traders =
        (tradersResult.data ??
          []) as OrderTrader[];

      products =
        (productsResult.data ??
          []) as OrderProduct[];
    }
  }

  let invoices:
    OrderSalesInvoice[] = [];

  let cashboxes:
    OrderCashbox[] = [];

  const orderIds =
    orders.map(
      (order) =>
        order.id
    );

  if (canCollect) {
    const cashboxResult =
      await supabase
        .from("cashboxes")
        .select(
          "id,name,currency,active"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .eq(
          "active",
          true
        )
        .order(
          "created_at"
        );

    if (
      cashboxResult.error
    ) {
      initialError ??=
        "تعذر تحميل صناديق القبض.";
    } else {
      cashboxes =
        (cashboxResult.data ??
          []) as OrderCashbox[];
    }

    if (
      orderIds.length
    ) {
      const invoiceResult =
        await supabase
          .from(
            "sales_invoices"
          )
          .select(
            "id,order_id,trader_id,invoice_number,invoice_date,currency,total,paid_total,balance_due,payment_status,status"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .eq(
            "status",
            "posted"
          )
          .in(
            "order_id",
            orderIds
          )
          .order(
            "invoice_date",
            {
              ascending: true,
            }
          );

      if (
        invoiceResult.error
      ) {
        initialError ??=
          "تعذر تحميل فواتير الطلبات.";
      } else {
        invoices =
          (invoiceResult.data ??
            []) as OrderSalesInvoice[];
      }
    }
  }

  return (
    <>
      <Topbar
        title="المبيعات"
        subtitle="الطلبات، الفواتير والتحصيل من العملاء"
        companyName={
          context.companyName
        }
      />

      <OrdersClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        initialOrders={
          orders
        }
        traders={
          traders
        }
        products={
          products
        }
        invoices={
          invoices
        }
        cashboxes={
          cashboxes
        }
        initialStats={
          stats
        }
        initialError={
          initialError
        }
        totalCount={
          ordersResult.count ??
          0
        }
        page={
          requestedPage
        }
        pageSize={
          pageSize
        }
        searchQuery={
          search
        }
        statusFilter={
          statusFilter
        }
        canCreate={
          canCreate
        }
        canCancel={
          canCancel
        }
        canCollect={
          canCollect
        }
        canViewDeliveries={
          canViewDeliveries
        }
      />
    </>
  );
}