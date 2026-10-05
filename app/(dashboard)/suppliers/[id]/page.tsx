import Link from "next/link";
import { notFound } from "next/navigation";

import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { formatMoney as money, formatQty, formatDate, formatDateTime, phoneText } from "@/lib/format";

type ProductRelation = {
  id: string;
  name: string;
  sku: string | null;
  unit: string | null;
  sale_price: number | null;
  active: boolean;
};

type SupplierPrice = {
  id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  last_checked_at: string | null;
  products: ProductRelation | ProductRelation[] | null;
};

type PriceHistory = {
  id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  effective_at: string;
  products:
    | {
        id: string;
        name: string;
        sku: string | null;
      }
    | {
        id: string;
        name: string;
        sku: string | null;
      }[]
    | null;
};

type PurchaseInvoice = {
  id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  status: string;
  payment_status: string;
  currency: string;
  invoice_date: string;
  due_date: string | null;
  total: number;
  paid_total: number;
  balance_due: number;
};

type CashboxRelation = {
  id: string;
  name: string;
  currency: string;
};

type SupplierPayment = {
  id: string;
  payment_number: string;
  status: string;
  payment_date: string;
  amount: number;
  allocated_total: number;
  unallocated_total: number;
  payment_currency: string | null;
  base_amount: number | null;
  payment_method: string;
  reference_number: string | null;
  reversal_reason: string | null;
  cashboxes: CashboxRelation | CashboxRelation[] | null;
};

type FinancialSummary = {
  total_purchases: number;
  total_payments: number;
  invoice_balance: number;
  advance_credit: number;
  net_balance: number;
  invoice_count: number;
  payment_count: number;
  available_products: number;
  currency: string;
};

type LedgerRow = {
  source_id: string;
  event_date: string;
  event_created_at: string;
  row_type: string;
  reference: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
  total_count: number;
  currency: string;
};

const paymentMethodLabels: Record<string, string> = {
  cash: "نقدي",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

function oneRelation<T>(value: T | T[] | null) {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function firstRpcRow<T>(value: T[] | T | null): T | null {
  if (!value) {
    return null;
  }

  return Array.isArray(value) ? (value[0] ?? null) : value;
}

const supplierTypeLabels: Record<string, string> = {
  factory: "مصنع",
  agent: "وكيل",
  wholesaler: "تاجر جملة",
  local: "مورد محلي",
  other: "غير ذلك",
};

export default async function SupplierDetailPage({
  params,
}: {
  params: Promise<{
    id: string;
  }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();

  const canView = hasPermission(context.permissions, "suppliers.view", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar title="المورد" subtitle="ملف المورد" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />

              <h3>لا تملك صلاحية عرض الموردين</h3>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canViewFinance = hasAnyPermission(
    context.permissions,
    ["suppliers.view_finance", "payments.supplier_view", "reports.finance"],
    context.isOwner,
  );

  const canViewInvoices = hasAnyPermission(
    context.permissions,
    [
      "purchase_invoices.view",
      "purchases.view",
      "payments.supplier_view",
      "suppliers.view_finance",
      "reports.finance",
      "reports.profit",
    ],
    context.isOwner,
  );

  const canViewPayments = hasAnyPermission(
    context.permissions,
    [
      "payments.supplier_view",
      "suppliers.view_finance",
      "finance.cashbox_view",
      "finance.accounts_view",
      "reports.finance",
    ],
    context.isOwner,
  );

  const canViewPrices =
    context.isOwner ||
    hasPermission(context.permissions, "purchases.view") ||
    hasPermission(context.permissions, "reports.profit") ||
    (hasPermission(context.permissions, "products.view") &&
      hasPermission(context.permissions, "products.view_cost"));

  const canViewPriceHistory =
    context.isOwner ||
    hasPermission(context.permissions, "purchases.view") ||
    (hasPermission(context.permissions, "products.view") &&
      hasPermission(context.permissions, "products.view_cost"));

  const canOpenPurchases = hasPermission(context.permissions, "purchases.view", context.isOwner);

  const supabase = await createClient();

  const supplierResult = await supabase
    .from("suppliers")
    .select(
      "id,name,contact_name,phone,whatsapp,address,notes,active,payment_terms_days,supplier_type,country,currency,created_at,updated_at",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (supplierResult.error) {
    return (
      <>
        <Topbar title="المورد" subtitle="ملف المورد" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.store size={30} />

              <h3>تعذر تحميل بيانات المورد</h3>

              <p>حاول تحديث الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  if (!supplierResult.data) {
    notFound();
  }

  const supplier = supplierResult.data;

  let prices: SupplierPrice[] = [];
  let pricesCount = 0;

  let history: PriceHistory[] = [];
  let historyCount = 0;

  let invoices: PurchaseInvoice[] = [];
  let invoiceListCount = 0;

  let payments: SupplierPayment[] = [];
  let paymentListCount = 0;

  let summary: FinancialSummary | null = null;

  let ledger: LedgerRow[] = [];

  let ledgerCount = 0;

  const warnings: string[] = [];

  if (canViewPrices) {
    const result = await supabase
      .from("supplier_prices")
      .select(
        "id,product_id,purchase_price,available,notes,last_checked_at,products(id,name,sku,unit,sale_price,active)",
        {
          count: "exact",
        },
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("last_checked_at", {
        ascending: false,
      })
      .limit(100);

    if (result.error) {
      warnings.push("تعذر تحميل أسعار المورد.");
    } else {
      prices = (result.data ?? []) as SupplierPrice[];

      pricesCount = result.count ?? 0;
    }
  }

  if (canViewPriceHistory) {
    const result = await supabase
      .from("supplier_price_history")
      .select("id,product_id,purchase_price,available,notes,effective_at,products(id,name,sku)", {
        count: "exact",
      })
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("effective_at", {
        ascending: false,
      })
      .limit(12);

    if (result.error) {
      warnings.push("تعذر تحميل تاريخ الأسعار.");
    } else {
      history = (result.data ?? []) as PriceHistory[];

      historyCount = result.count ?? 0;
    }
  }

  if (canViewInvoices) {
    const result = await supabase
      .from("purchase_invoices")
      .select(
        "id,invoice_number,supplier_invoice_number,status,payment_status,currency,invoice_date,due_date,total,paid_total,balance_due",
        {
          count: "exact",
        },
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("invoice_date", {
        ascending: false,
      })
      .order("created_at", {
        ascending: false,
      })
      .limit(50);

    if (result.error) {
      warnings.push("تعذر تحميل فواتير المورد.");
    } else {
      invoices = (result.data ?? []) as PurchaseInvoice[];

      invoiceListCount = result.count ?? 0;
    }
  }

  if (canViewPayments) {
    const result = await supabase
      .from("supplier_payments")
      .select(
        "id,payment_number,status,payment_date,amount,allocated_total,unallocated_total,payment_currency,base_amount,payment_method,reference_number,reversal_reason,cashboxes(id,name,currency)",
        {
          count: "exact",
        },
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("payment_date", {
        ascending: false,
      })
      .order("created_at", {
        ascending: false,
      })
      .limit(50);

    if (result.error) {
      warnings.push("تعذر تحميل دفعات المورد.");
    } else {
      payments = (result.data ?? []) as SupplierPayment[];

      paymentListCount = result.count ?? 0;
    }
  }

  if (canViewFinance) {
    const [summaryResult, ledgerResult] = await Promise.all([
      supabase.rpc("get_supplier_financial_summary", {
        target_company: context.companyId,
        target_supplier: id,
      }),

      supabase.rpc("get_supplier_ledger", {
        target_company: context.companyId,
        target_supplier: id,
        target_limit: 100,
      }),
    ]);

    if (summaryResult.error) {
      warnings.push("تعذر تحميل الملخص المالي.");
    } else {
      const row = firstRpcRow(summaryResult.data);

      if (row) {
        const value = row as Record<string, unknown>;

        summary = {
          total_purchases: Number(value.total_purchases ?? 0),

          total_payments: Number(value.total_payments ?? 0),

          invoice_balance: Number(value.invoice_balance ?? 0),

          advance_credit: Number(value.advance_credit ?? 0),

          net_balance: Number(value.net_balance ?? 0),

          invoice_count: Number(value.invoice_count ?? 0),

          payment_count: Number(value.payment_count ?? 0),

          available_products: Number(value.available_products ?? 0),

          currency: String(value.currency ?? context.currency),
        };
      }
    }

    if (ledgerResult.error) {
      warnings.push("تعذر تحميل كشف حساب المورد.");
    } else {
      ledger = (ledgerResult.data ?? []).map((item: Record<string, unknown>) => ({
        source_id: String(item.source_id),

        event_date: String(item.event_date),

        event_created_at: String(item.event_created_at),

        row_type: String(item.row_type),

        reference: String(item.reference ?? ""),

        description: String(item.description ?? ""),

        debit: Number(item.debit ?? 0),

        credit: Number(item.credit ?? 0),

        balance: Number(item.balance ?? 0),

        total_count: Number(item.total_count ?? 0),

        currency: String(item.currency ?? context.currency),
      }));

      ledgerCount = ledger[0]?.total_count ?? 0;
    }
  }

  const baseCurrency = summary?.currency ?? context.currency;

  return (
    <>
      <Topbar
        title={supplier.name}
        subtitle="ملف المورد، الأسعار، الفواتير وكشف الحساب"
        companyName={context.companyName}
      />

      <div className="page">
        {warnings.length ? (
          <div
            className="toastError"
            role="alert"
            style={{
              marginBottom: 14,
            }}
          >
            {[...new Set(warnings)].join(" ")}
          </div>
        ) : null}

        <div className="pageTitle">
          <div>
            <span className="eyebrow">ملف المورد</span>

            <h2>{supplier.name}</h2>

            <p className="muted">
              {supplier.contact_name || "بدون شخص مسؤول"}
              {" • "}
              {supplier.active ? "نشط" : "موقوف"}
            </p>
          </div>

          <div className="rowActions">
            <Link className="softButton" href="/suppliers">
              رجوع
            </Link>

            {canOpenPurchases ? (
              <Link className="primaryButton" href="/purchases">
                <Icons.money size={14} />
                المشتريات
              </Link>
            ) : null}

            {canViewFinance ? (
              <Link className="softButton" href={`/print/supplier/${supplier.id}`}>
                <Icons.whatsapp size={14} />
                كشف حساب
              </Link>
            ) : null}

            {supplier.phone ? (
              <a className="softButton" href={`tel:${supplier.phone}`} aria-label="اتصال بالمورد">
                <Icons.phone size={14} />
              </a>
            ) : null}

            {supplier.whatsapp ? (
              <a
                className="softButton"
                target="_blank"
                rel="noreferrer"
                href={`https://wa.me/${supplier.whatsapp.replace(/\D/g, "")}`}
                aria-label="فتح واتساب المورد"
              >
                <Icons.whatsapp size={14} />
              </a>
            ) : null}
          </div>
        </div>

        {canViewFinance && summary ? (
          <>
            <section className="statsGrid">
              <Mini title="إجمالي المشتريات" value={money(summary.total_purchases, baseCurrency)} />

              <Mini title="إجمالي الدفعات" value={money(summary.total_payments, baseCurrency)} />

              <Mini
                title="المستحق بالفواتير"
                value={money(summary.invoice_balance, baseCurrency)}
              />

              <Mini title="صافي حساب المورد" value={money(summary.net_balance, baseCurrency)} />
            </section>

            <section
              className="statsGrid"
              style={{
                marginTop: 12,
              }}
            >
              <Mini title="دفعات مقدمة" value={money(summary.advance_credit, baseCurrency)} />

              <Mini title="أصناف متوفرة" value={formatQty(summary.available_products)} />

              <Mini title="فواتير مثبتة" value={formatQty(summary.invoice_count)} />

              <Mini title="دفعات مثبتة" value={formatQty(summary.payment_count)} />
            </section>
          </>
        ) : null}

        <div className="pageGrid">
          {canViewFinance ? (
            <section className="panel panelPad">
              <div className="panelHeader">
                <div>
                  <h2>كشف حساب المورد</h2>

                  <p>الرصيد محسوب على كامل التاريخ، حتى لو كان المعروض آخر 100 حركة فقط.</p>
                </div>

                {summary ? (
                  <div className="statValue">{money(summary.net_balance, baseCurrency)}</div>
                ) : null}
              </div>

              {!ledger.length ? (
                <div className="empty">
                  <Icons.wallet size={28} />

                  <h3>لا توجد حركة حساب</h3>
                </div>
              ) : (
                <>
                  {ledgerCount > ledger.length ? (
                    <p className="muted">
                      يعرض أحدث {ledger.length} من {ledgerCount} حركة.
                    </p>
                  ) : null}

                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>التاريخ</th>
                          <th>المرجع</th>
                          <th>البيان</th>
                          <th>مدين</th>
                          <th>دائن</th>
                          <th>الرصيد</th>
                        </tr>
                      </thead>

                      <tbody>
                        {ledger.map((row) => (
                          <tr key={`${row.row_type}-${row.source_id}`}>
                            <td>{formatDate(row.event_date)}</td>

                            <td>
                              <strong>{row.reference}</strong>
                            </td>

                            <td>
                              <span
                                className={`chip ${
                                  row.row_type === "invoice"
                                    ? "orange"
                                    : row.row_type === "return"
                                      ? "blue"
                                      : "green"
                                }`}
                              >
                                {row.row_type === "invoice"
                                  ? "فاتورة"
                                  : row.row_type === "return"
                                    ? "مرتجع"
                                    : "دفعة"}
                              </span>

                              <div className="muted">{row.description}</div>
                            </td>

                            <td>{row.debit > 0 ? money(row.debit, row.currency) : "—"}</td>

                            <td>{row.credit > 0 ? money(row.credit, row.currency) : "—"}</td>

                            <td>
                              <strong>{money(row.balance, row.currency)}</strong>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </>
              )}
            </section>
          ) : (
            <section className="panel panelPad">
              <div className="empty">
                <Icons.shield size={28} />

                <h3>المعلومات المالية مخفية</h3>

                <p>تحتاج إلى صلاحية مالية لعرض كشف الحساب.</p>
              </div>
            </section>
          )}

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>بيانات المورد</h2>
              </div>
            </div>

            <div className="quickList">
              <Info title="الشخص المسؤول" value={supplier.contact_name} />

              <Info
                title="النوع والبلد"
                value={
                  [
                    supplierTypeLabels[supplier.supplier_type ?? ""] ?? null,
                    supplier.country,
                    supplier.currency ? `يتعامل بـ ${supplier.currency}` : null,
                  ]
                    .filter(Boolean)
                    .join(" • ") || null
                }
              />

              <Info title="الهاتف" value={phoneText(supplier.phone)} />

              <Info title="واتساب" value={phoneText(supplier.whatsapp)} />

              <Info title="العنوان" value={supplier.address} />

              <Info
                title="شروط الدفع"
                value={
                  supplier.payment_terms_days > 0 ? `${supplier.payment_terms_days} يوم` : "نقدي"
                }
              />

              <Info title="الحالة" value={supplier.active ? "نشط" : "موقوف"} />

              <Info title="تاريخ الإضافة" value={formatDate(supplier.created_at)} />
            </div>

            {supplier.notes ? (
              <>
                <div
                  className="panelHeader"
                  style={{
                    marginTop: 20,
                  }}
                >
                  <div>
                    <h2>ملاحظات</h2>
                  </div>
                </div>

                <p className="muted">{supplier.notes}</p>
              </>
            ) : null}
          </aside>
        </div>

        {canViewInvoices ? (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>فواتير الشراء</h2>

                <p>أحدث 50 فاتورة. الإجماليات بالأعلى محسوبة على كامل السجل.</p>
              </div>

              <div className="resultCount">{invoiceListCount} فاتورة</div>
            </div>

            {!invoices.length ? (
              <p className="muted">لا توجد فواتير شراء.</p>
            ) : (
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الفاتورة</th>
                      <th>رقم المورد</th>
                      <th>التاريخ</th>
                      <th>الاستحقاق</th>
                      <th>الإجمالي</th>
                      <th>المدفوع</th>
                      <th>المتبقي</th>
                      <th>الحالة</th>
                    </tr>
                  </thead>

                  <tbody>
                    {invoices.map((invoice) => (
                      <tr key={invoice.id}>
                        <td>
                          <strong>{invoice.invoice_number}</strong>
                        </td>

                        <td>{invoice.supplier_invoice_number || "—"}</td>

                        <td>{formatDate(invoice.invoice_date)}</td>

                        <td>{formatDate(invoice.due_date)}</td>

                        <td>{money(invoice.total, invoice.currency)}</td>

                        <td>{money(invoice.paid_total, invoice.currency)}</td>

                        <td>{money(invoice.balance_due, invoice.currency)}</td>

                        <td>
                          {invoice.status === "cancelled" ? (
                            <span className="chip gray">ملغاة</span>
                          ) : invoice.status === "draft" ? (
                            <span className="chip blue">مسودة</span>
                          ) : (
                            <span
                              className={`chip ${
                                invoice.payment_status === "paid"
                                  ? "green"
                                  : invoice.payment_status === "partial"
                                    ? "orange"
                                    : "gray"
                              }`}
                            >
                              {invoice.payment_status === "paid"
                                ? "مدفوعة"
                                : invoice.payment_status === "partial"
                                  ? "مدفوعة جزئياً"
                                  : "غير مدفوعة"}
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        ) : null}

        {canViewPayments ? (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>دفعات المورد</h2>

                <p>أحدث 50 دفعة مع عملة كل عملية.</p>
              </div>

              <div className="resultCount">{paymentListCount} دفعة</div>
            </div>

            {!payments.length ? (
              <p className="muted">لا توجد دفعات مسجلة.</p>
            ) : (
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الدفعة</th>
                      <th>التاريخ</th>
                      <th>المبلغ</th>
                      <th>موزع</th>
                      <th>مقدم</th>
                      <th>الطريقة</th>
                      <th>الصندوق</th>
                      <th>الحالة</th>
                    </tr>
                  </thead>

                  <tbody>
                    {payments.map((payment) => {
                      const cashbox = oneRelation(payment.cashboxes);

                      const paymentCurrency =
                        payment.payment_currency || cashbox?.currency || context.currency;

                      return (
                        <tr key={payment.id}>
                          <td>
                            <strong>{payment.payment_number}</strong>

                            {payment.reference_number ? (
                              <div className="muted">{payment.reference_number}</div>
                            ) : null}
                          </td>

                          <td>{formatDate(payment.payment_date)}</td>

                          <td>
                            {money(payment.amount, paymentCurrency)}

                            {paymentCurrency !== context.currency && payment.base_amount != null ? (
                              <div className="muted">
                                ≈ {money(payment.base_amount, context.currency)}
                              </div>
                            ) : null}
                          </td>

                          <td>{money(payment.allocated_total, paymentCurrency)}</td>

                          <td>{money(payment.unallocated_total, paymentCurrency)}</td>

                          <td>{paymentMethodLabels[payment.payment_method] || "أخرى"}</td>

                          <td>{cashbox?.name || "—"}</td>

                          <td>
                            <span
                              className={`chip ${payment.status === "posted" ? "green" : "gray"}`}
                            >
                              {payment.status === "posted" ? "مثبتة" : "معكوسة"}
                            </span>

                            {payment.reversal_reason ? (
                              <div className="muted">{payment.reversal_reason}</div>
                            ) : null}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        ) : null}

        {canViewPrices ? (
          <div className="pageGrid">
            <section className="panel panelPad">
              <div className="panelHeader">
                <div>
                  <h2>الأصناف والأسعار الحالية</h2>

                  <p>أسعار الشراء الحالية عند هذا المورد.</p>
                </div>

                <div className="resultCount">{pricesCount} صنف</div>
              </div>

              {!prices.length ? (
                <p className="muted">لا توجد أصناف مرتبطة.</p>
              ) : (
                <>
                  {pricesCount > prices.length ? (
                    <p className="muted">
                      يعرض أحدث {prices.length} من {pricesCount} صنف.
                    </p>
                  ) : null}

                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>الصنف</th>
                          <th>سعر الشراء</th>
                          <th>سعر البيع</th>
                          <th>الحالة</th>
                          <th>آخر تحديث</th>
                        </tr>
                      </thead>

                      <tbody>
                        {prices.map((price) => {
                          const product = oneRelation(price.products);

                          return (
                            <tr key={price.id}>
                              <td>
                                <strong>{product?.name || "صنف غير متاح"}</strong>

                                <div className="muted">{product?.sku || ""}</div>
                              </td>

                              <td>{money(price.purchase_price, context.currency)}</td>

                              <td>
                                {product?.sale_price != null
                                  ? money(product.sale_price, context.currency)
                                  : "—"}
                              </td>

                              <td>
                                <span className={`chip ${price.available ? "green" : "gray"}`}>
                                  {price.available ? "متوفر" : "غير متوفر"}
                                </span>
                              </td>

                              <td>{formatDateTime(price.last_checked_at)}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </>
              )}
            </section>

            {canViewPriceHistory ? (
              <aside className="panel panelPad">
                <div className="panelHeader">
                  <div>
                    <h2>آخر تغييرات الأسعار</h2>

                    <p>السجل التاريخي محفوظ ولا يُحذف.</p>
                  </div>
                </div>

                {!history.length ? (
                  <p className="muted">لا يوجد تاريخ أسعار.</p>
                ) : (
                  <>
                    {historyCount > history.length ? (
                      <p className="muted">
                        يعرض أحدث {history.length} من {historyCount} تغيير.
                      </p>
                    ) : null}

                    <div className="quickList">
                      {history.map((row) => {
                        const product = oneRelation(row.products);

                        return (
                          <div className="quickItem" key={row.id}>
                            <div>
                              <strong>{product?.name || "صنف غير متاح"}</strong>

                              <span>{formatDateTime(row.effective_at)}</span>
                            </div>

                            <div className="count">
                              {money(row.purchase_price, context.currency)}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </>
                )}
              </aside>
            ) : null}
          </div>
        ) : null}
      </div>
    </>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>

      <div className="statValue">{value}</div>
    </div>
  );
}

function Info({ title, value }: { title: string; value: string | null }) {
  return (
    <div className="quickItem">
      <div>
        <span>{title}</span>
        <strong>{value || "—"}</strong>
      </div>
    </div>
  );
}
