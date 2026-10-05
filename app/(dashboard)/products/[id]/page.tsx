import Link from "next/link";
import { notFound } from "next/navigation";

import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { formatMoney as money, formatDateTime } from "@/lib/format";

type ProductRow = {
  id: string;
  category_id:
    | string
    | null;
  sku: string | null;
  name: string;
  brand: string | null;
  unit: string;
  sale_price:
    | number
    | null;
  minimum_sale_price:
    | number
    | null;
  image_url:
    | string
    | null;
  active: boolean;
  created_at: string;
  updated_at: string;
};

type StockRow = {
  warehouse_id: string;
  warehouse_name: string;
  on_hand: number;
  reserved: number;
  available: number;
  average_cost:
    | number
    | null;
};

type PriceRow = {
  id: string;
  supplier_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  last_checked_at: string;
};

function quantity(
  value: number
) {
  return new Intl.NumberFormat(
    "en-US",
    {
      maximumFractionDigits:
        3,
    }
  ).format(
    Number(value || 0)
  );
}

export default async function ProductDetailPage({
  params,
}: {
  params: Promise<{
    id: string;
  }>;
}) {
  const { id } =
    await params;

  const context =
    await getCurrentContext();

  const canView =
    hasPermission(
      context.permissions,
      "products.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="الصنف"
          subtitle="تفاصيل الصنف"
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
                لا تملك صلاحية عرض الأصناف
              </h3>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canViewSupplierCost =
    hasAnyPermission(
      context.permissions,
      [
        "products.view_cost",
        "products.update",
        "purchases.view",
        "purchases.create",
        "purchases.update",
        "purchase_invoices.view",
        "purchase_invoices.create",
        "suppliers.view_finance",
        "reports.profit",
        "reports.finance",
      ],
      context.isOwner
    );

  const canViewInventory =
    hasAnyPermission(
      context.permissions,
      [
        "inventory.view",
        "inventory.adjust",
        "inventory.returns",
        "purchases.view",
        "purchase_invoices.view",
        "reports.finance",
        "reports.profit",
      ],
      context.isOwner
    );

  const canViewInventoryCost =
    hasAnyPermission(
      context.permissions,
      [
        "products.view_cost",
        "suppliers.view_finance",
        "reports.finance",
        "reports.profit",
      ],
      context.isOwner
    );

  const supabase =
    await createClient();

  const productResult =
    await supabase
      .from("products")
      .select(
        "id,category_id,sku,name,brand,unit,sale_price,minimum_sale_price,reorder_level,image_url,active,created_at,updated_at"
      )
      .eq(
        "company_id",
        context.companyId
      )
      .eq("id", id)
      .maybeSingle();

  if (
    productResult.error
  ) {
    return (
      <>
        <Topbar
          title="الصنف"
          subtitle="تفاصيل الصنف"
          companyName={
            context.companyName
          }
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.box
                size={30}
              />

              <h3>
                تعذر تحميل بيانات الصنف
              </h3>

              <p>
                حاول تحديث الصفحة.
              </p>
            </div>
          </section>
        </div>
      </>
    );
  }

  if (
    !productResult.data
  ) {
    notFound();
  }

  const product =
    productResult.data as ProductRow;

  let categoryName =
    "—";

  let stock:
    StockRow[] = [];

  let prices:
    PriceRow[] = [];

  const warnings:
    string[] = [];

  if (
    product.category_id
  ) {
    const result =
      await supabase
        .from("categories")
        .select("name")
        .eq(
          "company_id",
          context.companyId
        )
        .eq(
          "id",
          product.category_id
        )
        .maybeSingle();

    if (result.error) {
      warnings.push(
        "تعذر تحميل فئة الصنف."
      );
    } else if (
      result.data
    ) {
      categoryName =
        result.data.name;
    }
  }

  if (
    canViewInventory
  ) {
    const result =
      await supabase
        .from(
          "inventory_summary"
        )
        .select(
          "warehouse_id,warehouse_name,on_hand,reserved,available,average_cost"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .eq(
          "product_id",
          product.id
        )
        .order(
          "warehouse_name"
        );

    if (result.error) {
      warnings.push(
        "تعذر تحميل المخزون."
      );
    } else {
      stock =
        (
          result.data ??
          []
        ).map(
          (row) => ({
            warehouse_id:
              String(
                row.warehouse_id
              ),

            warehouse_name:
              String(
                row.warehouse_name ??
                  "مستودع"
              ),

            on_hand:
              Number(
                row.on_hand ??
                  0
              ),

            reserved:
              Number(
                row.reserved ??
                  0
              ),

            available:
              Number(
                row.available ??
                  0
              ),

            average_cost:
              row.average_cost ==
              null
                ? null
                : Number(
                    row.average_cost
                  ),
          })
        );
    }
  }

  if (
    canViewSupplierCost
  ) {
    const result =
      await supabase
        .from(
          "supplier_prices"
        )
        .select(
          "id,supplier_id,purchase_price,available,notes,last_checked_at"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .eq(
          "product_id",
          product.id
        )
        .order(
          "purchase_price",
          {
            ascending: true,
          }
        );

    if (result.error) {
      warnings.push(
        "تعذر تحميل أسعار الموردين."
      );
    } else {
      prices =
        (result.data ??
          []) as PriceRow[];
    }
  }

  const supplierIds =
    [
      ...new Set(
        prices.map(
          (row) =>
            row.supplier_id
        )
      ),
    ];

  const supplierNames =
    new Map<
      string,
      string
    >();

  if (
    supplierIds.length
  ) {
    const result =
      await supabase
        .from("suppliers")
        .select("id,name")
        .eq(
          "company_id",
          context.companyId
        )
        .in(
          "id",
          supplierIds
        );

    if (result.error) {
      warnings.push(
        "تعذر تحميل أسماء الموردين."
      );
    } else {
      for (
        const row of
          result.data ?? []
      ) {
        supplierNames.set(
          row.id,
          row.name
        );
      }
    }
  }

  const totalStock =
    stock.reduce(
      (sum, row) =>
        sum +
        row.on_hand,
      0
    );

  const totalReserved =
    stock.reduce(
      (sum, row) =>
        sum +
        row.reserved,
      0
    );

  const totalAvailable =
    stock.reduce(
      (sum, row) =>
        sum +
        row.available,
      0
    );

  const cheapestPrice =
    prices.find(
      (row) =>
        row.available
    ) ?? null;


  // حركات الصنف (دخل/طلع، لمين، والرصيد بعد كل حركة).
  const movementsResult = canViewInventory
    ? await supabase.rpc("get_product_movements", {
        target_company: context.companyId,
        target_product: id,
        target_limit: 100,
      })
    : { data: null };
  const movements = (movementsResult.data ?? []) as {
    occurred_at: string;
    movement_type: string;
    quantity: number;
    balance: number;
    warehouse_name: string;
    reference: string | null;
    party_name: string | null;
    notes: string | null;
  }[];

  return (
    <>
      <Topbar
        title={
          product.name
        }
        subtitle="تفاصيل الصنف، المخزون وأسعار الموردين"
        companyName={
          context.companyName
        }
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
            {[
              ...new Set(
                warnings
              ),
            ].join(" ")}
          </div>
        ) : null}

        <div className="pageTitle">
          <div>
            <span className="eyebrow">
              ملف الصنف
            </span>

            <h2>
              {product.name}
            </h2>

            <p className="muted">
              {[
                product.brand,
                product.sku,
              ]
                .filter(
                  Boolean
                )
                .join(" • ") ||
                "بدون كود أو ماركة"}
            </p>
          </div>

          <Link
            className="softButton"
            href="/products"
          >
            رجوع للأصناف
          </Link>
        </div>

        <section className="statsGrid">
          <Mini
            title="سعر البيع"
            value={
              product.sale_price ==
              null
                ? "—"
                : money(
                    product.sale_price,
                    context.currency
                  )
            }
          />

          <Mini
            title="الحد الأدنى للبيع"
            value={
              product.minimum_sale_price ==
              null
                ? "—"
                : money(
                    product.minimum_sale_price,
                    context.currency
                  )
            }
          />

          <Mini
            title="المخزون"
            value={
              canViewInventory
                ? `${quantity(
                    totalStock
                  )} ${product.unit}`
                : "—"
            }
          />

          <Mini
            title="أرخص شراء"
            value={
              canViewSupplierCost &&
              cheapestPrice
                ? money(
                    cheapestPrice.purchase_price,
                    context.currency
                  )
                : "—"
            }
          />
        </section>

        <div className="pageGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  معلومات الصنف
                </h2>

                <p>
                  البيانات الأساسية للكتالوج
                </p>
              </div>
            </div>

            {product.image_url ? (
              <img
                className="productImage"
                src={product.image_url}
                alt={product.name}
              />
            ) : null}

            <div className="quickList">
              <Info
                title="الاسم"
                value={
                  product.name
                }
              />

              <Info
                title="الكود"
                value={
                  product.sku ||
                  "—"
                }
              />

              <Info
                title="الماركة"
                value={
                  product.brand ||
                  "—"
                }
              />

              <Info
                title="الفئة"
                value={
                  categoryName
                }
              />

              <Info
                title="الوحدة"
                value={
                  product.unit
                }
              />

              <Info
                title="الحالة"
                value={
                  product.active
                    ? "نشط"
                    : "مؤرشف"
                }
              />

              <Info
                title="آخر تحديث"
                value={
                  formatDateTime(
                    product.updated_at
                  )
                }
              />
            </div>

            {canViewInventory ? (
              <>
                <div
                  className="panelHeader"
                  style={{
                    marginTop: 22,
                  }}
                >
                  <div>
                    <h2>
                      المخزون حسب المستودع
                    </h2>

                    <p>
                      الرصيد الحالي والمحجوز والمتاح
                    </p>
                  </div>
                </div>

                <section className="statsGrid">
                  <Mini
                    title="على اليد"
                    value={`${quantity(
                      totalStock
                    )} ${product.unit}`}
                  />

                  <Mini
                    title="محجوز"
                    value={`${quantity(
                      totalReserved
                    )} ${product.unit}`}
                  />

                  <Mini
                    title="متاح"
                    value={`${quantity(
                      totalAvailable
                    )} ${product.unit}`}
                  />
                </section>

                {!stock.length ? (
                  <p className="muted">
                    لا يوجد رصيد مخزون مسجل لهذا الصنف.
                  </p>
                ) : (
                  <div className="quickList">
                    {stock.map(
                      (row) => (
                        <div
                          className="quickItem"
                          key={
                            row.warehouse_id
                          }
                        >
                          <div>
                            <strong>
                              {
                                row.warehouse_name
                              }
                            </strong>

                            <span>
                              محجوز{" "}
                              {quantity(
                                row.reserved
                              )}
                              {" • "}
                              متاح{" "}
                              {quantity(
                                row.available
                              )}

                              {canViewInventoryCost &&
                              row.average_cost !=
                                null
                                ? ` • متوسط الكلفة ${money(
                                    row.average_cost,
                                    context.currency
                                  )}`
                                : ""}
                            </span>
                          </div>

                          <div className="count">
                            {quantity(
                              row.on_hand
                            )}{" "}
                            {
                              product.unit
                            }
                          </div>
                        </div>
                      )
                    )}
                  </div>
                )}
              </>
            ) : (
              <div
                className="empty"
                style={{
                  marginTop: 22,
                }}
              >
                <Icons.shield
                  size={26}
                />

                <p>
                  لا تملك صلاحية عرض المخزون.
                </p>
              </div>
            )}
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  أسعار الموردين
                </h2>

                <p>
                  آخر أسعار الشراء المسجلة
                </p>
              </div>
            </div>

            {!canViewSupplierCost ? (
              <div className="empty">
                <Icons.shield
                  size={26}
                />

                <p>
                  لا تملك صلاحية عرض أسعار التكلفة.
                </p>
              </div>
            ) : !prices.length ? (
              <p className="muted">
                لا توجد أسعار موردين مسجلة لهذا الصنف.
              </p>
            ) : (
              <div className="quickList">
                {prices.map(
                  (price) => (
                    <div
                      className="quickItem"
                      key={
                        price.id
                      }
                    >
                      <div>
                        <strong>
                          {supplierNames.get(
                            price.supplier_id
                          ) ||
                            "مورد"}
                        </strong>

                        <span>
                          {price.available
                            ? "متوفر"
                            : "غير متوفر"}

                          {price.notes
                            ? ` • ${price.notes}`
                            : ""}

                          {" • "}
                          {formatDateTime(
                            price.last_checked_at
                          )}
                        </span>
                      </div>

                      <div className="count">
                        {money(
                          price.purchase_price,
                          context.currency
                        )}
                      </div>
                    </div>
                  )
                )}
              </div>
            )}
          </aside>
        </div>

        {canViewInventory ? (
          <section className="panel" style={{ marginTop: 14 }}>
            <div className="panelHeader panelPad">
              <div>
                <h2>حركات الصنف</h2>
                <p>إيمتى دخل وإيمتى طلع، ومن وين ولمين (آخر 100 حركة)</p>
              </div>
            </div>
            {!movements.length ? (
              <p className="muted panelPad">ما في حركات لهالصنف لسا.</p>
            ) : (
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>التاريخ</th>
                      <th>الحركة</th>
                      <th>الكمية</th>
                      <th>الرصيد بعدها</th>
                      <th>المستودع</th>
                      <th>لمين / من مين</th>
                      <th>المرجع</th>
                    </tr>
                  </thead>
                  <tbody>
                    {movements.map((row, index) => (
                      <tr key={index}>
                        <td>{formatDateTime(row.occurred_at)}</td>
                        <td>{movementLabels[row.movement_type] ?? row.movement_type}</td>
                        <td>
                          <strong className={Number(row.quantity) < 0 ? "kpiNegative" : "kpiPositive"}>
                            {Number(row.quantity) > 0 ? "+" : ""}
                            {Number(row.quantity).toLocaleString("en-US", { maximumFractionDigits: 3 })}
                          </strong>
                        </td>
                        <td>{Number(row.balance).toLocaleString("en-US", { maximumFractionDigits: 3 })}</td>
                        <td>{row.warehouse_name}</td>
                        <td>{row.party_name ?? "—"}</td>
                        <td>
                          {row.reference ?? ""}
                          {row.notes ? <div className="muted">{row.notes}</div> : null}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        ) : null}
      </div>
    </>
  );
}

const movementLabels: Record<string, string> = {
  opening: "رصيد أول",
  purchase_receipt: "استلام شراء",
  sales_delivery: "تسليم لزبون",
  sales_return: "مرتجع من زبون",
  purchase_return: "مرتجع لمورد",
  adjustment_in: "تسوية (زيادة)",
  adjustment_out: "تسوية (نقص)",
  transfer_in: "تحويل (دخل)",
  transfer_out: "تحويل (طلع)",
  damage: "تالف",
};

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
  value: string;
}) {
  return (
    <div className="quickItem">
      <div>
        <span>{title}</span>
        <strong>{value}</strong>
      </div>
    </div>
  );
}