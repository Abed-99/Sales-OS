import Link from "next/link";
import { notFound } from "next/navigation";
import { Topbar } from "@/components/topbar";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission } from "@/lib/permissions";

type ProductRow = {
  id: string;
  category_id: string | null;
  sku: string | null;
  name: string;
  brand: string | null;
  unit: string;
  sale_price: number | null;
  minimum_sale_price: number | null;
  image_url: string | null;
  active: boolean;
  created_at: string;
  updated_at: string;
};

type StockRow = {
  warehouse_id: string;
  on_hand: number;
  average_cost: number;
};

type PriceRow = {
  id: string;
  supplier_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  last_checked_at: string;
};

export default async function ProductDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canViewCost = hasAnyPermission(
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

  const canViewInventory = hasAnyPermission(
    context.permissions,
    [
      "inventory.view",
      "inventory.manage",
      "inventory.count",
      "inventory.transfer",
      "purchases.view",
      "products.update",
    ],
    context.isOwner
  );

  const productResult = await supabase
    .from("products")
    .select(
      "id,category_id,sku,name,brand,unit,sale_price,minimum_sale_price,image_url,active,created_at,updated_at"
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (productResult.error) {
    throw new Error(productResult.error.message);
  }

  if (!productResult.data) {
    notFound();
  }

  const product = productResult.data as ProductRow;

  const [categoryResult, stockResult, pricesResult] = await Promise.all([
    product.category_id
      ? supabase
          .from("categories")
          .select("id,name")
          .eq("company_id", context.companyId)
          .eq("id", product.category_id)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),

    canViewInventory
      ? supabase
          .from("inventory_stock")
          .select("warehouse_id,on_hand,average_cost")
          .eq("company_id", context.companyId)
          .eq("product_id", product.id)
      : Promise.resolve({ data: [], error: null }),

    canViewCost
      ? supabase
          .from("supplier_prices")
          .select(
            "id,supplier_id,purchase_price,available,notes,last_checked_at"
          )
          .eq("company_id", context.companyId)
          .eq("product_id", product.id)
          .order("purchase_price", { ascending: true })
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (categoryResult.error) {
    throw new Error(categoryResult.error.message);
  }

  if (stockResult.error) {
    throw new Error(stockResult.error.message);
  }

  if (pricesResult.error) {
    throw new Error(pricesResult.error.message);
  }

  const stock = (stockResult.data ?? []) as StockRow[];
  const prices = (pricesResult.data ?? []) as PriceRow[];

  const warehouseIds = stock.map((row) => row.warehouse_id);
  const supplierIds = prices.map((row) => row.supplier_id);

  const [warehousesResult, suppliersResult] = await Promise.all([
    warehouseIds.length
      ? supabase
          .from("warehouses")
          .select("id,name")
          .eq("company_id", context.companyId)
          .in("id", warehouseIds)
      : Promise.resolve({ data: [], error: null }),

    supplierIds.length
      ? supabase
          .from("suppliers")
          .select("id,name")
          .eq("company_id", context.companyId)
          .in("id", supplierIds)
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (warehousesResult.error) {
    throw new Error(warehousesResult.error.message);
  }

  if (suppliersResult.error) {
    throw new Error(suppliersResult.error.message);
  }

  const warehouseNames = new Map(
    (warehousesResult.data ?? []).map((row) => [row.id, row.name])
  );

  const supplierNames = new Map(
    (suppliersResult.data ?? []).map((row) => [row.id, row.name])
  );

  const totalStock = stock.reduce(
    (sum, row) => sum + Number(row.on_hand || 0),
    0
  );

  const cheapestPrice = prices.find((row) => row.available) ?? null;

  return (
    <>
      <Topbar
        title={product.name}
        subtitle="تفاصيل الصنف، المخزون وأسعار الموردين"
        companyName={context.companyName}
      />

      <div className="page">
        <div className="pageTitle">
          <div>
            <span className="eyebrow">ملف الصنف</span>
            <h2>{product.name}</h2>
            <p className="muted">
              {[product.brand, product.sku].filter(Boolean).join(" • ") || "بدون كود أو ماركة"}
            </p>
          </div>

          <Link className="softButton" href="/products">
            رجوع للأصناف
          </Link>
        </div>

        <section className="statsGrid">
          <Mini
            title="سعر البيع"
            value={
              product.sale_price == null
                ? "—"
                : `${Number(product.sale_price).toFixed(2)} ${context.currency}`
            }
          />

          <Mini
            title="الحد الأدنى للبيع"
            value={
              product.minimum_sale_price == null
                ? "—"
                : `${Number(product.minimum_sale_price).toFixed(2)} ${context.currency}`
            }
          />

          <Mini
            title="المخزون"
            value={canViewInventory ? `${totalStock} ${product.unit}` : "—"}
          />

          <Mini
            title="أرخص شراء"
            value={
              canViewCost && cheapestPrice
                ? `${Number(cheapestPrice.purchase_price).toFixed(2)} ${context.currency}`
                : "—"
            }
          />
        </section>

        <div className="pageGrid">
          <section className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>معلومات الصنف</h2>
                <p>البيانات الأساسية للكتالوج</p>
              </div>
            </div>

            <div className="quickList">
              <Info title="الاسم" value={product.name} />
              <Info title="الكود" value={product.sku || "—"} />
              <Info title="الماركة" value={product.brand || "—"} />
              <Info
                title="الفئة"
                value={
                  (categoryResult.data as { name?: string } | null)?.name || "—"
                }
              />
              <Info title="الوحدة" value={product.unit} />
              <Info
                title="الحالة"
                value={product.active ? "نشط" : "مؤرشف"}
              />
            </div>

            {canViewInventory && (
              <>
                <div className="panelHeader" style={{ marginTop: 22 }}>
                  <div>
                    <h2>المخزون حسب المستودع</h2>
                    <p>الرصيد الفعلي الحالي</p>
                  </div>
                </div>

                {!stock.length ? (
                  <p className="muted">ما في رصيد مخزون مسجل لهالصنف.</p>
                ) : (
                  <div className="quickList">
                    {stock.map((row) => (
                      <div className="quickItem" key={row.warehouse_id}>
                        <div>
                          <strong>
                            {warehouseNames.get(row.warehouse_id) || "مستودع"}
                          </strong>
                          <span>
                            {canViewCost
                              ? `متوسط الكلفة ${Number(row.average_cost).toFixed(2)} ${context.currency}`
                              : "رصيد المخزون"}
                          </span>
                        </div>
                        <div className="count">
                          {Number(row.on_hand)} {product.unit}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
          </section>

          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>أسعار الموردين</h2>
                <p>آخر أسعار الشراء المسجلة</p>
              </div>
            </div>

            {!canViewCost ? (
              <p className="muted">ما عندك صلاحية عرض أسعار التكلفة.</p>
            ) : !prices.length ? (
              <p className="muted">ما في أسعار موردين مسجلة لهالصنف.</p>
            ) : (
              <div className="quickList">
                {prices.map((price) => (
                  <div className="quickItem" key={price.id}>
                    <div>
                      <strong>
                        {supplierNames.get(price.supplier_id) || "مورد"}
                      </strong>
                      <span>
                        {price.available ? "متوفر" : "غير متوفر"}
                        {price.notes ? ` • ${price.notes}` : ""}
                      </span>
                    </div>
                    <div className="count">
                      {Number(price.purchase_price).toFixed(2)} {context.currency}
                    </div>
                  </div>
                ))}
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
      <div className="statLabel">{title}</div>
      <div className="statValue">{value}</div>
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
        <strong>{title}</strong>
        <span>{value}</span>
      </div>
    </div>
  );
}
