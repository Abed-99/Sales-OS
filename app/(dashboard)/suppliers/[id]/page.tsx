import Link from "next/link";
import { notFound } from "next/navigation";
import { Topbar } from "@/components/topbar";
import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

type ProductRelation = {
  id: string;
  name: string;
  sku: string | null;
  unit: string | null;
  sale_price: number | null;
  active: boolean;
};

type HistoryProductRelation = {
  id: string;
  name: string;
  sku: string | null;
};

type CashboxRelation = {
  id: string;
  name: string;
  currency: string;
};

type SupplierPrice = {
  id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  last_checked_at: string | null;
  products:
    | ProductRelation
    | ProductRelation[]
    | null;
};

type PriceHistory = {
  id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  effective_at: string;
  products:
    | HistoryProductRelation
    | HistoryProductRelation[]
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
  notes: string | null;
  created_at: string;
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
  exchange_rate_to_base: number | null;
  base_amount: number | null;
  payment_method: string;
  reference_number: string | null;
  notes: string | null;
  reversal_reason: string | null;
  created_at: string;
  cashboxes:
    | CashboxRelation
    | CashboxRelation[]
    | null;
};

type LedgerRow = {
  id: string;
  date: string;
  type: "invoice" | "payment";
  reference: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
};

const paymentMethodLabels: Record<string, string> = {
  cash: "نقدي",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

function oneRelation<T>(value: T | T[] | null) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

export default async function SupplierDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: supplier, error: supplierError } =
    await supabase
      .from("suppliers")
      .select(
        "id,name,contact_name,phone,whatsapp,address,notes,active,created_at"
      )
      .eq("company_id", context.companyId)
      .eq("id", id)
      .maybeSingle();

  if (supplierError) {
    throw new Error(supplierError.message);
  }

  if (!supplier) {
    notFound();
  }

  const [
    pricesResult,
    historyResult,
    invoicesResult,
    paymentsResult,
  ] = await Promise.all([
    supabase
      .from("supplier_prices")
      .select(
        "id,product_id,purchase_price,available,notes,last_checked_at,products(id,name,sku,unit,sale_price,active)"
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("last_checked_at", {
        ascending: false,
      }),

    supabase
      .from("supplier_price_history")
      .select(
        "id,product_id,purchase_price,available,notes,effective_at,products(id,name,sku)"
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("effective_at", {
        ascending: false,
      })
      .limit(100),

    supabase
      .from("purchase_invoices")
      .select(
        "id,invoice_number,supplier_invoice_number,status,payment_status,currency,invoice_date,due_date,total,paid_total,balance_due,notes,created_at"
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("invoice_date", {
        ascending: false,
      })
      .order("created_at", {
        ascending: false,
      })
      .limit(100),

    supabase
      .from("supplier_payments")
      .select(
        "id,payment_number,status,payment_date,amount,allocated_total,unallocated_total,payment_currency,exchange_rate_to_base,base_amount,payment_method,reference_number,notes,reversal_reason,created_at,cashboxes(id,name,currency)"
      )
      .eq("company_id", context.companyId)
      .eq("supplier_id", id)
      .order("payment_date", {
        ascending: false,
      })
      .order("created_at", {
        ascending: false,
      })
      .limit(100),
  ]);

  if (pricesResult.error) {
    throw new Error(
      pricesResult.error.message
    );
  }

  if (historyResult.error) {
    throw new Error(
      historyResult.error.message
    );
  }

  if (invoicesResult.error) {
    throw new Error(
      invoicesResult.error.message
    );
  }

  if (paymentsResult.error) {
    throw new Error(
      paymentsResult.error.message
    );
  }

  const prices =
    (pricesResult.data ?? []) as SupplierPrice[];

  const history =
    (historyResult.data ?? []) as PriceHistory[];

  const invoices =
    (invoicesResult.data ?? []) as PurchaseInvoice[];

  const payments =
    (paymentsResult.data ?? []) as SupplierPayment[];

  const postedInvoices =
    invoices.filter(
      (invoice) =>
        invoice.status !== "cancelled"
    );

  const postedPayments =
    payments.filter(
      (payment) =>
        payment.status === "posted"
    );

  const totalPurchases =
    postedInvoices.reduce(
      (sum, invoice) =>
        sum +
        Number(invoice.total || 0),
      0
    );

  const totalPayments =
    postedPayments.reduce(
      (sum, payment) =>
        sum +
        Number(
          payment.base_amount ??
            Number(
              payment.amount || 0
            ) *
              Number(
                payment.exchange_rate_to_base ||
                  1
              )
        ),
      0
    );

  const invoiceBalance =
    postedInvoices.reduce(
      (sum, invoice) =>
        sum +
        Number(
          invoice.balance_due || 0
        ),
      0
    );

  const advanceCredit =
    postedPayments.reduce(
      (sum, payment) =>
        sum +
        Number(
          payment.unallocated_total || 0
        ) *
          Number(
            payment.exchange_rate_to_base ||
              1
          ),
      0
    );

  const netSupplierBalance =
    totalPurchases - totalPayments;

  const activeProducts =
    prices.filter(
      (price) => price.available
    ).length;

  const ledgerSource = [
    ...postedInvoices.map((invoice) => ({
      id: invoice.id,
      date: invoice.invoice_date,
      createdAt: invoice.created_at,
      type: "invoice" as const,
      reference:
        invoice.invoice_number,
      description:
        invoice.supplier_invoice_number
          ? `فاتورة مورد ${invoice.supplier_invoice_number}`
          : "فاتورة شراء",
      debit: Number(
        invoice.total || 0
      ),
      credit: 0,
    })),

    ...postedPayments.map((payment) => ({
      id: payment.id,
      date: payment.payment_date,
      createdAt: payment.created_at,
      type: "payment" as const,
      reference:
        payment.payment_number,
      description:
        payment.reference_number
          ? `دفعة - ${payment.reference_number}`
          : "دفعة للمورد",
      debit: 0,
      credit: Number(
        payment.base_amount ??
          Number(
            payment.amount || 0
          ) *
            Number(
              payment.exchange_rate_to_base ||
                1
            )
      ),
    })),
  ].sort((a, b) => {
    const dateCompare =
      a.date.localeCompare(b.date);

    if (dateCompare !== 0) {
      return dateCompare;
    }

    return a.createdAt.localeCompare(
      b.createdAt
    );
  });

  let runningBalance = 0;

  const ledger: LedgerRow[] =
    ledgerSource.map((row) => {
      runningBalance +=
        row.debit - row.credit;

      return {
        id: row.id,
        date: row.date,
        type: row.type,
        reference:
          row.reference,
        description:
          row.description,
        debit: row.debit,
        credit: row.credit,
        balance:
          runningBalance,
      };
    });

  const money = (value: number) =>
    `${Number(value || 0).toFixed(2)} ${context.currency}`;

  return (
    <>
      <Topbar
        title={supplier.name}
        subtitle="ملف المورد، الأسعار، الفواتير وكشف الحساب"
        companyName={context.companyName}
      />

      <div className="page">
        <div className="pageTitle">
          <div>
            <span className="eyebrow">
              ملف المورد
            </span>

            <h2>
              {supplier.name}
            </h2>

            <p className="muted">
              {supplier.contact_name ||
                "بدون شخص مسؤول"}
              {" • "}
              {supplier.active
                ? "نشط"
                : "مؤرشف"}
            </p>
          </div>

          <div className="rowActions">
            <Link
              className="softButton"
              href="/suppliers"
            >
              رجوع
            </Link>

            <Link
              className="primaryButton"
              href="/purchases"
            >
              <Icons.money size={14} />
              المشتريات والدفعات
            </Link>

            {supplier.phone ? (
              <a
                className="softButton"
                href={`tel:${supplier.phone}`}
              >
                <Icons.phone size={14} />
              </a>
            ) : null}

            {supplier.whatsapp ? (
              <a
                className="softButton"
                target="_blank"
                rel="noreferrer"
                href={`https://wa.me/${supplier.whatsapp.replace(
                  /\D/g,
                  ""
                )}`}
              >
                <Icons.whatsapp
                  size={14}
                />
              </a>
            ) : null}
          </div>
        </div>

        <section className="statsGrid">
          <Mini
            title="إجمالي المشتريات"
            value={money(
              totalPurchases
            )}
          />

          <Mini
            title="إجمالي الدفعات"
            value={money(
              totalPayments
            )}
          />

          <Mini
            title="مستحق بالفواتير"
            value={money(
              invoiceBalance
            )}
          />

          <Mini
            title="صافي حساب المورد"
            value={money(
              netSupplierBalance
            )}
          />
        </section>

        <section
          className="statsGrid"
          style={{ marginTop: 12 }}
        >
          <Mini
            title="دفعات مقدمة"
            value={money(
              advanceCredit
            )}
          />

          <Mini
            title="أصناف متوفرة"
            value={String(
              activeProducts
            )}
          />

          <Mini
            title="فواتير مثبتة"
            value={String(
              postedInvoices.length
            )}
          />

          <Mini
            title="دفعات مثبتة"
            value={String(
              postedPayments.length
            )}
          />
        </section>

        <div className="pageGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  كشف حساب المورد
                </h2>

                <p>
                  الفواتير مدينة
                  والدفعات دائنة.
                </p>
              </div>

              <div className="statValue">
                {money(
                  netSupplierBalance
                )}
              </div>
            </div>

            {!ledger.length ? (
              <div className="empty">
                <Icons.wallet
                  size={28}
                />

                <h3>
                  ما في حركة حساب
                </h3>

                <p>
                  أول فاتورة أو دفعة
                  رح تظهر هون.
                </p>
              </div>
            ) : (
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
                    {ledger.map(
                      (row) => (
                        <tr
                          key={`${row.type}-${row.id}`}
                        >
                          <td>
                            {row.date}
                          </td>

                          <td>
                            <strong>
                              {
                                row.reference
                              }
                            </strong>
                          </td>

                          <td>
                            <span
                              className={`chip ${
                                row.type ===
                                "invoice"
                                  ? "orange"
                                  : "green"
                              }`}
                            >
                              {row.type ===
                              "invoice"
                                ? "فاتورة"
                                : "دفعة"}
                            </span>

                            <div className="muted">
                              {
                                row.description
                              }
                            </div>
                          </td>

                          <td>
                            {row.debit > 0
                              ? money(
                                  row.debit
                                )
                              : "—"}
                          </td>

                          <td>
                            {row.credit > 0
                              ? money(
                                  row.credit
                                )
                              : "—"}
                          </td>

                          <td>
                            <strong>
                              {money(
                                row.balance
                              )}
                            </strong>
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  بيانات المورد
                </h2>
              </div>
            </div>

            <div className="quickList">
              <Info
                title="الشخص المسؤول"
                value={
                  supplier.contact_name
                }
              />

              <Info
                title="الهاتف"
                value={supplier.phone}
              />

              <Info
                title="واتساب"
                value={
                  supplier.whatsapp
                }
              />

              <Info
                title="العنوان"
                value={
                  supplier.address
                }
              />

              <Info
                title="الحالة"
                value={
                  supplier.active
                    ? "نشط"
                    : "مؤرشف"
                }
              />

              <Info
                title="تاريخ الإضافة"
                value={new Date(
                  supplier.created_at
                ).toLocaleDateString(
                  "ar-LB"
                )}
              />
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
                    <h2>
                      ملاحظات
                    </h2>
                  </div>
                </div>

                <p className="muted">
                  {supplier.notes}
                </p>
              </>
            ) : null}
          </aside>
        </div>

        <section
          className="panel panelPad"
          style={{ marginTop: 14 }}
        >
          <div className="panelHeader">
            <div>
              <h2>
                فواتير الشراء
              </h2>

              <p>
                الفواتير الحالية
                وحالة كل فاتورة.
              </p>
            </div>
          </div>

          {!invoices.length ? (
            <p className="muted">
              ما في فواتير شراء.
            </p>
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
                  {invoices.map(
                    (invoice) => (
                      <tr
                        key={
                          invoice.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              invoice.invoice_number
                            }
                          </strong>
                        </td>

                        <td>
                          {invoice.supplier_invoice_number ||
                            "—"}
                        </td>

                        <td>
                          {
                            invoice.invoice_date
                          }
                        </td>

                        <td>
                          {invoice.due_date ||
                            "—"}
                        </td>

                        <td>
                          {money(
                            invoice.total
                          )}
                        </td>

                        <td>
                          {money(
                            invoice.paid_total
                          )}
                        </td>

                        <td>
                          {money(
                            invoice.balance_due
                          )}
                        </td>

                        <td>
                          {invoice.status ===
                          "cancelled" ? (
                            <span className="chip gray">
                              ملغاة
                            </span>
                          ) : (
                            <span
                              className={`chip ${
                                invoice.payment_status ===
                                "paid"
                                  ? "green"
                                  : invoice.payment_status ===
                                      "partial"
                                    ? "orange"
                                    : "gray"
                              }`}
                            >
                              {invoice.payment_status ===
                              "paid"
                                ? "مدفوعة"
                                : invoice.payment_status ===
                                    "partial"
                                  ? "جزئي"
                                  : "غير مدفوعة"}
                            </span>
                          )}
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section
          className="panel panelPad"
          style={{ marginTop: 14 }}
        >
          <div className="panelHeader">
            <div>
              <h2>
                دفعات المورد
              </h2>

              <p>
                الدفعات المثبتة
                والمعكوسة والرصيد
                المقدم.
              </p>
            </div>
          </div>

          {!payments.length ? (
            <p className="muted">
              ما في دفعات مسجلة.
            </p>
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
                  {payments.map(
                    (payment) => {
                      const cashbox =
                        oneRelation(
                          payment.cashboxes
                        );

                      return (
                        <tr
                          key={
                            payment.id
                          }
                        >
                          <td>
                            <strong>
                              {
                                payment.payment_number
                              }
                            </strong>

                            <div className="muted">
                              {payment.reference_number ||
                                ""}
                            </div>
                          </td>

                          <td>
                            {
                              payment.payment_date
                            }
                          </td>

                          <td>
                            {Number(
                              payment.amount || 0
                            ).toFixed(2)}{" "}
                            {payment.payment_currency ||
                              cashbox?.currency ||
                              context.currency}

                            {payment.payment_currency &&
                            payment.payment_currency !==
                              context.currency &&
                            payment.base_amount != null ? (
                              <div className="muted">
                                ? {money(
                                  payment.base_amount
                                )}
                              </div>
                            ) : null}
                          </td>

                          <td>
                            {Number(
                              payment.allocated_total ||
                                0
                            ).toFixed(2)}{" "}
                            {payment.payment_currency ||
                              cashbox?.currency ||
                              context.currency}
                          </td>

                          <td>
                            {Number(
                              payment.unallocated_total ||
                                0
                            ).toFixed(2)}{" "}
                            {payment.payment_currency ||
                              cashbox?.currency ||
                              context.currency}
                          </td>

                          <td>
                            {paymentMethodLabels[
                              payment.payment_method
                            ] ||
                              payment.payment_method}
                          </td>

                          <td>
                            {cashbox?.name ||
                              "—"}
                          </td>

                          <td>
                            <span
                              className={`chip ${
                                payment.status ===
                                "posted"
                                  ? "green"
                                  : "gray"
                              }`}
                            >
                              {payment.status ===
                              "posted"
                                ? "مثبتة"
                                : "معكوسة"}
                            </span>

                            {payment.reversal_reason ? (
                              <div className="muted">
                                {
                                  payment.reversal_reason
                                }
                              </div>
                            ) : null}
                          </td>
                        </tr>
                      );
                    }
                  )}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <div className="pageGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  الأصناف والأسعار الحالية
                </h2>

                <p>
                  آخر سعر عند هذا المورد.
                </p>
              </div>
            </div>

            {!prices.length ? (
              <p className="muted">
                ما في أصناف مرتبطة.
              </p>
            ) : (
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
                    {prices.map(
                      (price) => {
                        const product =
                          oneRelation(
                            price.products
                          );

                        return (
                          <tr
                            key={
                              price.id
                            }
                          >
                            <td>
                              <strong>
                                {product?.name ||
                                  "—"}
                              </strong>

                              <div className="muted">
                                {product?.sku ||
                                  ""}
                              </div>
                            </td>

                            <td>
                              {money(
                                price.purchase_price
                              )}
                            </td>

                            <td>
                              {product?.sale_price !=
                              null
                                ? money(
                                    product.sale_price
                                  )
                                : "—"}
                            </td>

                            <td>
                              <span
                                className={`chip ${
                                  price.available
                                    ? "green"
                                    : "gray"
                                }`}
                              >
                                {price.available
                                  ? "متوفر"
                                  : "غير متوفر"}
                              </span>
                            </td>

                            <td>
                              {price.last_checked_at
                                ? new Date(
                                    price.last_checked_at
                                  ).toLocaleString(
                                    "ar-LB"
                                  )
                                : "—"}
                            </td>
                          </tr>
                        );
                      }
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  آخر تغييرات الأسعار
                </h2>

                <p>
                  السجل التاريخي لا
                  ينمسح.
                </p>
              </div>
            </div>

            {!history.length ? (
              <p className="muted">
                ما في تاريخ أسعار.
              </p>
            ) : (
              <div className="quickList">
                {history
                  .slice(0, 12)
                  .map((row) => {
                    const product =
                      oneRelation(
                        row.products
                      );

                    return (
                      <div
                        className="quickItem"
                        key={row.id}
                      >
                        <div>
                          <strong>
                            {product?.name ||
                              "—"}
                          </strong>

                          <span>
                            {new Date(
                              row.effective_at
                            ).toLocaleDateString(
                              "ar-LB"
                            )}
                          </span>
                        </div>

                        <div className="count">
                          {money(
                            row.purchase_price
                          )}
                        </div>
                      </div>
                    );
                  })}
              </div>
            )}
          </aside>
        </div>
      </div>
    </>
  );
}

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {title}
      </div>

      <div className="statValue">
        {value}
      </div>
    </div>
  );
}

function Info({
  title,
  value,
}: {
  title: string;
  value: string | null;
}) {
  return (
    <div className="quickItem">
      <div>
        <strong>{title}</strong>
        <span>{value || "—"}</span>
      </div>
    </div>
  );
}
