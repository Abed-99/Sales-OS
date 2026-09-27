import { Topbar } from "@/components/topbar";

import {
  InventoryClient,
  type InventoryCountRow,
  type InventoryProduct,
  type InventoryReceivableItem,
  type InventoryReceiptRow,
  type InventoryStockRow,
  type InventoryTransferRow,
  type InventoryWarehouse,
} from "@/components/inventory/inventory-client";

import { getCurrentContext } from "@/lib/current-context";
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

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
    .replace(
      /\s+/g,
      " "
    )
    .trim()
    .slice(
      0,
      100
    );
}

export default async function InventoryPage({
  searchParams,
}: {
  searchParams: Promise<
    Record<
      string,
      | string
      | string[]
      | undefined
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
      "inventory.view",
      context.isOwner
    );

  if (!canView) {
    return (
      <>
        <Topbar
          title="المخزون"
          subtitle="المستودعات وحركة البضاعة"
          companyName={
            context.companyName
          }
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <h3>
                لا تملك صلاحية عرض المخزون
              </h3>

              <p>
                تحتاج إلى صلاحية عرض المخزون للوصول لهذه الصفحة.
              </p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canAdjust =
    hasPermission(
      context.permissions,
      "inventory.adjust",
      context.isOwner
    );

  const canReceive =
    hasAnyPermission(
      context.permissions,
      [
        "inventory.adjust",
        "purchases.update",
      ],
      context.isOwner
    );

  const canReverseReceipt =
    canAdjust;

  const canViewCost =
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

  const searchQuery =
    cleanSearch(
      firstParam(
        params.q
      )
    );

  const warehouseFilter =
    firstParam(
      params.warehouse
    ) || "all";

  const page =
    Math.max(
      1,
      Number.parseInt(
        firstParam(
          params.page
        ),
        10
      ) || 1
    );

  const pageSize =
    50;

  const from =
    (page - 1) *
    pageSize;

  const to =
    from +
    pageSize -
    1;

  const supabase =
    await createClient();

  let stockQuery =
    supabase
      .from(
        "inventory_summary"
      )
      .select(
        `
          company_id,
          warehouse_id,
          warehouse_name,
          product_id,
          sku,
          product_name,
          unit,
          on_hand,
          reserved,
          available,
          average_cost,
          stock_value,
          updated_at
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
        "product_name"
      )
      .order(
        "warehouse_name"
      )
      .range(
        from,
        to
      );

  if (
    warehouseFilter !==
    "all"
  ) {
    stockQuery =
      stockQuery.eq(
        "warehouse_id",
        warehouseFilter
      );
  }

  if (searchQuery) {
    const pattern =
      `%${searchQuery}%`;

    stockQuery =
      stockQuery.or(
        [
          `product_name.ilike.${pattern}`,
          `sku.ilike.${pattern}`,
          `warehouse_name.ilike.${pattern}`,
        ].join(",")
      );
  }

  const [
    warehousesResult,
    stockResult,
    stockStatsResult,
    receiptsResult,
    transfersResult,
    countsResult,
  ] =
    await Promise.all([
      supabase
        .from(
          "warehouses"
        )
        .select(
          "id,code,name,address,is_default,active"
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
          "is_default",
          {
            ascending:
              false,
          }
        )
        .order(
          "name"
        ),

      stockQuery,

      supabase.rpc("get_inventory_stats", {

        target_company: context.companyId,

      }),

      supabase
        .from(
          "goods_receipts"
        )
        .select(
          `
            id,
            receipt_number,
            warehouse_id,
            purchase_invoice_id,
            status,
            receipt_date,
            notes,
            cancellation_reason,
            created_at
          `
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "created_at",
          {
            ascending:
              false,
          }
        )
        .limit(50),

      supabase
        .from(
          "inventory_transfers"
        )
        .select(
          `
            id,
            transfer_number,
            source_warehouse_id,
            destination_warehouse_id,
            status,
            transfer_date,
            notes,
            reversal_reason,
            created_at
          `
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "created_at",
          {
            ascending:
              false,
          }
        )
        .limit(50),

      supabase
        .from(
          "inventory_counts"
        )
        .select(
          `
            id,
            warehouse_id,
            count_number,
            count_date,
            status,
            notes,
            reversal_reason,
            created_at
          `
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "created_at",
          {
            ascending:
              false,
          }
        )
        .limit(50),
    ]);

  let initialError:
    string | null =
      null;

  const baseResults = [
    warehousesResult,
    stockResult,
    stockStatsResult,
    receiptsResult,
    transfersResult,
    countsResult,
  ];

  if (
    baseResults.some(
      (result) =>
        Boolean(
          result.error
        )
    )
  ) {
    initialError =
      "تعذر تحميل بعض بيانات المخزون.";
  }

  let products:
    InventoryProduct[] =
      [];

  if (canAdjust) {
    const result =
      await supabase
        .from(
          "products"
        )
        .select(
          "id,name,sku,unit,active"
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
          "name"
        );

    if (result.error) {
      initialError ??=
        "تعذر تحميل أصناف المخزون.";
    } else {
      products =
        (result.data ??
          []) as InventoryProduct[];
    }
  }

  let receivableItems:
    InventoryReceivableItem[] =
      [];

  if (canReceive) {
    const result =
      await supabase.rpc(
        "get_receivable_purchase_items",
        {
          target_company:
            context.companyId,
        }
      );

    if (result.error) {
      initialError ??=
        "تعذر تحميل المشتريات بانتظار الاستلام.";
    } else {
      receivableItems =
        (result.data ??
          []) as InventoryReceivableItem[];
    }
  }

  const statsRow = (
    Array.isArray(stockStatsResult.data)
      ? stockStatsResult.data[0]
      : stockStatsResult.data
  ) as {
    reserved_lines?: number;
    out_of_stock?: number;
    stock_value?: number | null;
  } | null;

  const stockStats = {
    reservedLines: Number(statsRow?.reserved_lines ?? 0),
    outOfStock: Number(statsRow?.out_of_stock ?? 0),
    stockValue: Number(statsRow?.stock_value ?? 0),
  };

  return (
    <>
      <Topbar
        title="المخزون"
        subtitle="المستودعات، الاستلام، التحويلات والجرد"
        companyName={
          context.companyName
        }
      />

      <InventoryClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        warehouses={
          (warehousesResult.data ??
            []) as InventoryWarehouse[]
        }
        stock={
          (stockResult.data ??
            []) as InventoryStockRow[]
        }
        stockTotalCount={
          stockResult.count ??
          0
        }
        stockPage={
          page
        }
        pageSize={
          pageSize
        }
        searchQuery={
          searchQuery
        }
        warehouseFilter={
          warehouseFilter
        }
        stockStats={{
          warehouseCount:
            (
              warehousesResult.data ??
              []
            ).length,

          reservedLines:
            stockStats.reservedLines,

          outOfStock:
            stockStats.outOfStock,

          stockValue:
            stockStats.stockValue,

          pendingReceiptInvoices:
            new Set(
              receivableItems.map(
                (row) =>
                  row.invoice_id
              )
            ).size,
        }}
        products={
          products
        }
        receivableItems={
          receivableItems
        }
        receipts={
          (receiptsResult.data ??
            []) as InventoryReceiptRow[]
        }
        transfers={
          (transfersResult.data ??
            []) as InventoryTransferRow[]
        }
        counts={
          (countsResult.data ??
            []) as InventoryCountRow[]
        }
        initialError={
          initialError
        }
        canReceive={
          canReceive
        }
        canReverseReceipt={
          canReverseReceipt
        }
        canAdjust={
          canAdjust
        }
        canViewCost={
          canViewCost
        }
      />
    </>
  );
}