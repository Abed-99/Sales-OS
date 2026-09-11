import { Topbar } from "@/components/topbar";
import {
  ProductsClient,
  type Category,
  type Product,
  type Supplier,
  type SupplierPrice,
} from "@/components/products/products-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";

export default async function ProductsPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canCreate = hasPermission(
    context.permissions,
    "products.create",
    context.isOwner
  );
  const canUpdate = hasPermission(
    context.permissions,
    "products.update",
    context.isOwner
  );
  const canArchive = hasPermission(
    context.permissions,
    "products.archive",
    context.isOwner
  );
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

  const [productsResult, categoriesResult] = await Promise.all([
    supabase
      .from("products")
      .select(
        "id,category_id,sku,name,brand,unit,sale_price,minimum_sale_price,image_url,active,created_at"
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false }),
    supabase
      .from("categories")
      .select("id,name")
      .eq("company_id", context.companyId)
      .order("name"),
  ]);

  if (productsResult.error) throw new Error(productsResult.error.message);
  if (categoriesResult.error) throw new Error(categoriesResult.error.message);

  let suppliers: Supplier[] = [];
  let prices: SupplierPrice[] = [];

  if (canUpdate) {
    const suppliersResult = await supabase
      .from("suppliers")
      .select("id,name,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name");

    if (suppliersResult.error) throw new Error(suppliersResult.error.message);
    suppliers = (suppliersResult.data ?? []) as Supplier[];
  }

  if (canViewCost) {
    const pricesResult = await supabase
      .from("supplier_prices")
      .select(
        "id,supplier_id,product_id,purchase_price,available,notes,last_checked_at"
      )
      .eq("company_id", context.companyId);

    if (pricesResult.error) throw new Error(pricesResult.error.message);
    prices = (pricesResult.data ?? []) as SupplierPrice[];
  }

  return (
    <>
      <Topbar
        title="الأصناف"
        subtitle="الكتالوج، أسعار البيع وأسعار الموردين"
        companyName={context.companyName}
      />
      <ProductsClient
        companyId={context.companyId}
        currency={context.currency}
        initialProducts={(productsResult.data ?? []) as Product[]}
        initialCategories={(categoriesResult.data ?? []) as Category[]}
        suppliers={suppliers}
        initialPrices={prices}
        canCreate={canCreate}
        canUpdate={canUpdate}
        canArchive={canArchive}
        canViewCost={canViewCost}
      />
    </>
  );
}
