import { Icons } from "@/components/icons";
import {
  PurchasesClient,
  type CashboxOption,
  type ProductOption,
  type PurchaseInvoiceRow,
  type PurchaseNeed,
  type SupplierOption,
  type SupplierPaymentRow,
  type SupplierPriceOption,
} from "@/components/purchases/purchases-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { searchKeyCondition, cleanSearch, firstParam } from "@/lib/search";

type ServerClient = Awaited<ReturnType<typeof createClient>>;

/** "1,500" أو "1500.5" → رقم، وإلا null. */
function searchAmount(term: string) {
  const value = Number(term.replace(/[\s,]/g, ""));
  return term && Number.isFinite(value) ? value : null;
}

/** موردين اسمهم أو اسم الشخص المسؤول فيه كلمة البحث. */
async function supplierIdsMatching(supabase: ServerClient, companyId: string, term: string) {
  const pattern = `%${term}%`;
  const { data } = await supabase
    .from("suppliers")
    .select("id")
    .eq("company_id", companyId)
    .or(searchKeyCondition(term) || `name.ilike.${pattern}`)
    .limit(200);
  return (data ?? []).map((row) => row.id as string);
}

/** فواتير شراء فيها صنف اسمه أو كوده أو ماركته فيها كلمة البحث. */
async function invoiceIdsWithProduct(supabase: ServerClient, companyId: string, term: string) {
  const pattern = `%${term}%`;
  const { data: products } = await supabase
    .from("products")
    .select("id")
    .eq("company_id", companyId)
    .or([searchKeyCondition(term), `sku.ilike.${pattern}`].filter(Boolean).join(","))
    .limit(200);
  const productIds = (products ?? []).map((row) => row.id as string);
  if (!productIds.length) return [];
  const { data: items } = await supabase
    .from("purchase_invoice_items")
    .select("invoice_id")
    .eq("company_id", companyId)
    .in("product_id", productIds)
    .limit(500);
  return [...new Set((items ?? []).map((row) => row.invoice_id as string))];
}

export default async function PurchasesPage({
  searchParams,
}: {
  searchParams: Promise<
    Record<string, string | string[] | undefined>
  >;
}) {
  const context =
    await getCurrentContext();

  const params =
    await searchParams;

  const canView =
    hasPermission(
      context.permissions,
      "purchases.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="المشتريات"
          subtitle="احتياجات الشراء، فواتير الموردين والدفعات"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />

              <h3>
                لا تملك صلاحية عرض المشتريات
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

  const canCreateInvoice =
    hasPermission(
      context.permissions,
      "purchase_invoices.create",
      context.isOwner
    );

  const canCancelInvoice =
    hasPermission(
      context.permissions,
      "purchase_invoices.cancel",
      context.isOwner
    );

  const canPaySupplier =
    hasPermission(
      context.permissions,
      "payments.supplier_create",
      context.isOwner
    );

  const canReversePayment =
    hasPermission(
      context.permissions,
      "payments.supplier_reverse",
      context.isOwner
    );

  const canViewPayments =
    hasAnyPermission(
      context.permissions,
      [
        "payments.supplier_view",
        "payments.supplier_create",
        "payments.supplier_reverse",
        "suppliers.view_finance",
        "reports.finance",
      ],
      context.isOwner
    );

  const invoiceSearch =
    cleanSearch(
      firstParam(params.iq)
    );

  const rawInvoiceStatus =
    firstParam(
      params.istatus
    );

  const invoiceStatus =
    rawInvoiceStatus === "posted" ||
    rawInvoiceStatus === "cancelled"
      ? rawInvoiceStatus
      : "all";

  const invoicePage =
    Math.max(
      1,
      Number.parseInt(
        firstParam(params.ipage),
        10
      ) || 1
    );

  const paymentSearch =
    cleanSearch(
      firstParam(params.pq)
    );

  const rawPaymentStatus =
    firstParam(
      params.pstatus
    );

  const paymentStatus =
    rawPaymentStatus === "posted" ||
    rawPaymentStatus === "reversed"
      ? rawPaymentStatus
      : "all";

  const paymentPage =
    Math.max(
      1,
      Number.parseInt(
        firstParam(params.ppage),
        10
      ) || 1
    );

  const pageSize = 50;

  const invoiceFrom =
    (invoicePage - 1) *
    pageSize;

  const invoiceTo =
    invoiceFrom +
    pageSize -
    1;

  const paymentFrom =
    (paymentPage - 1) *
    pageSize;

  const paymentTo =
    paymentFrom +
    pageSize -
    1;

  const supabase =
    await createClient();

  const [
    needsResult,
    summaryResult,
  ] =
    await Promise.all([
      supabase.rpc(
        "get_purchase_needs",
        {
          target_company:
            context.companyId,
        }
      ),

      supabase.rpc(
        "get_purchases_summary",
        {
          target_company:
            context.companyId,
        }
      ),
    ]);

  let initialError:
    string | null =
      null;

  if (needsResult.error) {
    initialError =
      "تعذر تحميل احتياجات الشراء.";
  }

  if (summaryResult.error) {
    initialError ??=
      "تعذر تحميل ملخص المشتريات.";
  }

  let invoiceQuery =
    supabase
      .from("purchase_invoices")
      .select(
        `
          id,
          invoice_number,
          supplier_invoice_number,
          status,
          payment_status,
          currency,
          invoice_date,
          due_date,
          total,
          paid_total,
          balance_due,
          cancellation_reason,
          created_at,
          suppliers(
            id,
            name
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
        "invoice_date",
        {
          ascending: false,
        }
      )
      .order(
        "created_at",
        {
          ascending: false,
        }
      )
      .range(
        invoiceFrom,
        invoiceTo
      );

  if (
    invoiceStatus !==
    "all"
  ) {
    invoiceQuery =
      invoiceQuery.eq(
        "status",
        invoiceStatus
      );
  }

  // البحث بكل شي: رقم الفاتورة، اسم المورد، اسم الصنف، أو المبلغ.
  if (invoiceSearch) {
    const pattern =
      `%${invoiceSearch}%`;

    const [supplierIds, productInvoiceIds] =
      await Promise.all([
        supplierIdsMatching(supabase, context.companyId, invoiceSearch),
        invoiceIdsWithProduct(supabase, context.companyId, invoiceSearch),
      ]);

    const amount = searchAmount(invoiceSearch);

    const conditions = [
      `invoice_number.ilike.${pattern}`,
      `supplier_invoice_number.ilike.${pattern}`,
      `notes.ilike.${pattern}`,
    ];

    if (supplierIds.length) {
      conditions.push(`supplier_id.in.(${supplierIds.join(",")})`);
    }

    if (productInvoiceIds.length) {
      conditions.push(`id.in.(${productInvoiceIds.join(",")})`);
    }

    if (amount != null) {
      conditions.push(
        `total.eq.${amount}`,
        `balance_due.eq.${amount}`,
        `paid_total.eq.${amount}`
      );
    }

    invoiceQuery =
      invoiceQuery.or(
        conditions.join(",")
      );
  }

  const invoicesResult =
    await invoiceQuery;

  if (invoicesResult.error) {
    initialError ??=
      "تعذر تحميل فواتير الشراء.";
  }

  let suppliers:
    SupplierOption[] = [];

  let products:
    ProductOption[] = [];

  let supplierPrices:
    SupplierPriceOption[] = [];

  // الموردين بيلزموا لفاتورة الشراء ولدفعة المورد (الصندوق ممكن يدفع بدون ما يعمل فواتير).
  if (canCreateInvoice || canPaySupplier) {
    const [
      suppliersResult,
      productsResult,
      pricesResult,
    ] =
      await Promise.all([
        supabase
          .from("suppliers")
          .select(
            "id,name,active"
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

        supabase
          .from("products")
          .select(
            "id,name,sku,unit,active,pack_size,pack_unit"
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

        supabase
          .from(
            "supplier_prices"
          )
          .select(
            "supplier_id,product_id,purchase_price,available"
          )
          .eq(
            "company_id",
            context.companyId
          )
          .eq(
            "available",
            true
          ),
      ]);

    if (
      suppliersResult.error ||
      productsResult.error ||
      pricesResult.error
    ) {
      initialError ??=
        "تعذر تحميل بيانات إنشاء فاتورة الشراء.";
    } else {
      suppliers =
        (suppliersResult.data ??
          []) as SupplierOption[];

      products =
        (productsResult.data ??
          []) as ProductOption[];

      supplierPrices =
        (pricesResult.data ??
          []) as SupplierPriceOption[];
    }
  }

  let cashboxes:
    CashboxOption[] = [];

  if (canPaySupplier) {
    const result =
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

    if (result.error) {
      initialError ??=
        "تعذر تحميل صناديق الدفع.";
    } else {
      cashboxes =
        (result.data ??
          []) as CashboxOption[];
    }
  }

  let payments:
    SupplierPaymentRow[] = [];

  let paymentCount = 0;

  if (canViewPayments) {
    let paymentQuery =
      supabase
        .from(
          "supplier_payments"
        )
        .select(
          `
            id,
            supplier_id,
            cashbox_id,
            payment_number,
            status,
            payment_date,
            amount,
            allocated_total,
            unallocated_total,
            payment_currency,
            exchange_rate_to_base,
            base_amount,
            payment_method,
            reference_number,
            notes,
            reversal_reason,
            created_at,
            suppliers(
              id,
              name
            ),
            cashboxes(
              id,
              name,
              currency
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
          "payment_date",
          {
            ascending: false,
          }
        )
        .order(
          "created_at",
          {
            ascending: false,
          }
        )
        .range(
          paymentFrom,
          paymentTo
        );

    if (
      paymentStatus !==
      "all"
    ) {
      paymentQuery =
        paymentQuery.eq(
          "status",
          paymentStatus
        );
    }

    // البحث بكل شي: رقم الدفعة، المرجع، اسم المورد، أو المبلغ.
    if (paymentSearch) {
      const pattern =
        `%${paymentSearch}%`;

      const supplierIds =
        await supplierIdsMatching(supabase, context.companyId, paymentSearch);

      const amount = searchAmount(paymentSearch);

      const conditions = [
        `payment_number.ilike.${pattern}`,
        `reference_number.ilike.${pattern}`,
        `notes.ilike.${pattern}`,
      ];

      if (supplierIds.length) {
        conditions.push(`supplier_id.in.(${supplierIds.join(",")})`);
      }

      if (amount != null) {
        conditions.push(
          `amount.eq.${amount}`,
          `base_amount.eq.${amount}`
        );
      }

      paymentQuery =
        paymentQuery.or(
          conditions.join(",")
        );
    }

    const result =
      await paymentQuery;

    if (result.error) {
      initialError ??=
        "تعذر تحميل دفعات الموردين.";
    } else {
      payments =
        (result.data ??
          []) as SupplierPaymentRow[];

      paymentCount =
        result.count ?? 0;
    }
  }

  const summaryRaw =
    Array.isArray(
      summaryResult.data
    )
      ? summaryResult.data[0]
      : summaryResult.data;

  const summary =
    summaryRaw as
      | Record<
          string,
          unknown
        >
      | null;

  const needs =
    (needsResult.data ??
      []) as PurchaseNeed[];

  const remainingUnits =
    needs.reduce(
      (sum, need) =>
        sum +
        Number(
          need.remaining_quantity ??
            0
        ),
      0
    );

  return (
    <>
      <Topbar
        title="المشتريات"
        subtitle="احتياجات الشراء، فواتير الموردين والدفعات"
        companyName={
          context.companyName
        }
      />

      <PurchasesClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        needs={
          needs
        }
        suppliers={
          suppliers
        }
        products={
          products
        }
        supplierPrices={
          supplierPrices
        }
        initialInvoices={
          (invoicesResult.data ??
            []) as PurchaseInvoiceRow[]
        }
        cashboxes={
          cashboxes
        }
        initialPayments={
          payments
        }
        initialError={
          initialError
        }
        initialStats={{
          needCount:
            needs.length,

          remainingUnits,

          invoiceCount:
            Number(
              summary?.invoice_count ??
                0
            ),

          outstandingTotal:
            Number(
              summary?.outstanding_total ??
                0
            ),

          supplierCreditTotal:
            Number(
              summary?.supplier_credit_total ??
                0
            ),
        }}
        invoiceTotalCount={
          invoicesResult.count ??
          0
        }
        invoicePage={
          invoicePage
        }
        paymentTotalCount={
          paymentCount
        }
        paymentPage={
          paymentPage
        }
        pageSize={
          pageSize
        }
        invoiceSearchQuery={
          invoiceSearch
        }
        invoiceStatusFilter={
          invoiceStatus
        }
        paymentSearchQuery={
          paymentSearch
        }
        paymentStatusFilter={
          paymentStatus
        }
        canCreateInvoice={
          canCreateInvoice
        }
        canCancelInvoice={
          canCancelInvoice
        }
        canPaySupplier={
          canPaySupplier
        }
        canViewPayments={
          canViewPayments
        }
        canReversePayment={
          canReversePayment
        }
      />
    </>
  );
}