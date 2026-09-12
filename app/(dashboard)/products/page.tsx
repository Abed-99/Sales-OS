import { Icons } from "@/components/icons";
import {
  ProductsClient,
  type Category,
  type Product,
  type Supplier,
  type SupplierPrice,
} from "@/components/products/products-client";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

type ProductFilter =
  | "all"
  | "active"
  | "archived";

function firstParam(
  value: string | string[] | undefined
) {
  return Array.isArray(value)
    ? value[0] ?? ""
    : value ?? "";
}

function cleanSearch(value: string) {
  return value
    .replace(/[(),"'\\%_]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
}

export default async function ProductsPage({
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
      "products.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="الأصناف"
          subtitle="الكتالوج والأسعار"
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
      "products.create",
      context.isOwner
    );

  const canUpdate =
    hasPermission(
      context.permissions,
      "products.update",
      context.isOwner
    );

  const canArchive =
    hasPermission(
      context.permissions,
      "products.archive",
      context.isOwner
    );

  const canViewCost =
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

  const search =
    cleanSearch(
      firstParam(params.q)
    );

  const rawStatus =
    firstParam(
      params.status
    );

  const statusFilter:
    ProductFilter =
      rawStatus === "active" ||
      rawStatus === "archived"
        ? rawStatus
        : "all";

  const categoryFilter =
    firstParam(
      params.category
    ).trim();

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

  let productsQuery =
    supabase
      .from("products")
      .select(
        "id,category_id,sku,name,brand,unit,sale_price,minimum_sale_price,image_url,active,created_at",
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
    statusFilter ===
    "active"
  ) {
    productsQuery =
      productsQuery.eq(
        "active",
        true
      );
  }

  if (
    statusFilter ===
    "archived"
  ) {
    productsQuery =
      productsQuery.eq(
        "active",
        false
      );
  }

  if (categoryFilter) {
    productsQuery =
      productsQuery.eq(
        "category_id",
        categoryFilter
      );
  }

  if (search) {
    const pattern =
      `%${search}%`;

    productsQuery =
      productsQuery.or(
        [
          `name.ilike.${pattern}`,
          `sku.ilike.${pattern}`,
          `brand.ilike.${pattern}`,
        ].join(",")
      );
  }

  const [
    productsResult,
    categoriesResult,
    allResult,
    activeResult,
    archivedResult,
  ] =
    await Promise.all([
      productsQuery,

      supabase
        .from("categories")
        .select("id,name")
        .eq(
          "company_id",
          context.companyId
        )
        .order("name"),

      supabase
        .from("products")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq(
          "company_id",
          context.companyId
        ),

      supabase
        .from("products")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq(
          "company_id",
          context.companyId
        )
        .eq("active", true),

      supabase
        .from("products")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq(
          "company_id",
          context.companyId
        )
        .eq("active", false),
    ]);

  const products =
    (productsResult.data ??
      []) as Product[];

  const categories =
    (categoriesResult.data ??
      []) as Category[];

  let suppliers:
    Supplier[] = [];

  if (
    canUpdate ||
    canViewCost
  ) {
    const result =
      await supabase
        .from("suppliers")
        .select(
          "id,name,active"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order("name");

    if (!result.error) {
      suppliers =
        (result.data ??
          []) as Supplier[];
    }
  }

  let prices:
    SupplierPrice[] = [];

  const productIds =
    products.map(
      (product) =>
        product.id
    );

  if (
    canViewCost &&
    productIds.length
  ) {
    const result =
      await supabase
        .from(
          "supplier_prices"
        )
        .select(
          "id,supplier_id,product_id,purchase_price,available,notes,last_checked_at"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .in(
          "product_id",
          productIds
        );

    if (!result.error) {
      prices =
        (result.data ??
          []) as SupplierPrice[];
    }
  }

  const statsError =
    Boolean(
      allResult.error
    ) ||
    Boolean(
      activeResult.error
    ) ||
    Boolean(
      archivedResult.error
    );

  const mainError =
    Boolean(
      productsResult.error
    ) ||
    Boolean(
      categoriesResult.error
    );

  return (
    <>
      <Topbar
        title="الأصناف"
        subtitle="الكتالوج، أسعار البيع وأسعار الموردين"
        companyName={
          context.companyName
        }
      />

      <ProductsClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        initialProducts={
          products
        }
        initialCategories={
          categories
        }
        suppliers={
          suppliers
        }
        initialPrices={
          prices
        }
        initialError={
          mainError
            ? "تعذر تحميل بعض بيانات الأصناف. حاول تحديث الصفحة."
            : null
        }
        stats={
          statsError
            ? null
            : {
                all:
                  allResult.count ??
                  0,
                active:
                  activeResult.count ??
                  0,
                archived:
                  archivedResult.count ??
                  0,
              }
        }
        totalCount={
          productsResult.count ??
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
        categoryFilter={
          categoryFilter
        }
        canCreate={
          canCreate
        }
        canUpdate={
          canUpdate
        }
        canArchive={
          canArchive
        }
        canViewCost={
          canViewCost
        }
      />
    </>
  );
}