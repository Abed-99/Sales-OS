import { Topbar } from "@/components/topbar";
import { InventoryReversalPanel } from "@/components/inventory/inventory-reversal-panel";

import {
  InventoryClient,
  type InventoryCountRow,
  type InventoryProduct,
  type InventoryPurchaseInvoice,
  type InventoryReceiptItem,
  type InventoryReceiptRow,
  type InventoryStockRow,
  type InventoryTransferRow,
  type InventoryWarehouse,
} from "@/components/inventory/inventory-client";

import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";

import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";

export default async function InventoryPage() {
  const context =
    await getCurrentContext();

  const supabase =
    await createClient();

  const canView =
    hasPermission(
      context.permissions,
      "inventory.view",
      context.isOwner
    );

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
        "purchase_invoices.create",
      ],
      context.isOwner
    );

  const canViewCost =
    hasAnyPermission(
      context.permissions,
      [
        "products.view_cost",
        "suppliers.view_finance",
        "reports.profit",
        "purchase_invoices.view",
      ],
      context.isOwner
    );

  if (
    !canView &&
    !canReceive &&
    !canAdjust
  ) {
    return (
      <>
        <Topbar
          title="Ø§Ù„Ù…Ø®Ø²ÙˆÙ†"
          subtitle="Ø§Ù„Ù…Ø³ØªÙˆØ¯Ø¹Ø§Øª ÙˆØ­Ø±ÙƒØ© Ø§Ù„Ø¨Ø¶Ø§Ø¹Ø©"
          companyName={
            context.companyName
          }
        />

        <div className="page">
          <section className="panel panelPad">
            Ù…Ø§ Ø¹Ù†Ø¯Ùƒ ØµÙ„Ø§Ø­ÙŠØ© Ù„Ø¹Ø±Ø¶ Ø§Ù„Ù…Ø®Ø²ÙˆÙ†.
          </section>
        </div>
      </>
    );
  }

  const [
    warehousesResult,
    stockResult,
    productsResult,
    invoicesResult,
    receiptItemsResult,
    receiptsResult,
    transfersResult,
    countsResult,
  ] =
    await Promise.all([
      supabase
        .from("warehouses")
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
            ascending: false,
          }
        )
        .order("name"),

      supabase
        .from(
          "inventory_summary"
        )
        .select(
          "company_id,warehouse_id,warehouse_name,product_id,sku,product_name,unit,on_hand,reserved,available,average_cost,stock_value,updated_at"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "product_name"
        ),

      supabase
        .from("products")
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
        .order("name"),

      supabase
        .from(
          "purchase_invoices"
        )
        .select(`
          id,
          supplier_id,
          invoice_number,
          supplier_invoice_number,
          currency,
          invoice_date,
          total,
          status,
          suppliers(
            id,
            name
          ),
          purchase_invoice_items(
            id,
            product_id,
            description,
            quantity,
            unit_cost,
            products(
              name,
              sku,
              unit
            )
          )
        `)
        .eq(
          "company_id",
          context.companyId
        )
        .eq(
          "status",
          "posted"
        )
        .order(
          "invoice_date",
          {
            ascending: false,
          }
        )
        .limit(100),

      supabase
        .from(
          "goods_receipt_items"
        )
        .select(`
          id,
          purchase_invoice_item_id,
          quantity,
          goods_receipts(
            id,
            status
          )
        `)
        .eq(
          "company_id",
          context.companyId
        ),

      supabase
        .from(
          "goods_receipts"
        )
        .select(
          "id,receipt_number,warehouse_id,purchase_invoice_id,status,receipt_date,notes,created_at"
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
        .limit(30),

      

      supabase
        .from(
          "inventory_transfers"
        )
        .select(
          "id,transfer_number,source_warehouse_id,destination_warehouse_id,status,transfer_date,notes,created_at"
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
        .limit(30),

      supabase
        .from(
          "inventory_counts"
        )
        .select(
          "id,warehouse_id,count_number,count_date,status,notes,created_at"
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
        .limit(30),
    ]);

  const results = [
    warehousesResult,
    stockResult,
    productsResult,
    invoicesResult,
    receiptItemsResult,
    receiptsResult,
    transfersResult,
    countsResult,
  ];

  for (
    const result of results
  ) {
    if (result.error) {
      throw new Error(
        result.error.message
      );
    }
  }

  return (
    <>
      <Topbar
        title="Ø§Ù„Ù…Ø®Ø²ÙˆÙ†"
        subtitle="Ø§Ù„Ù…Ø³ØªÙˆØ¯Ø¹Ø§ØªØŒ Ø§Ù„Ø§Ø³ØªÙ„Ø§Ù…ØŒ Ø§Ù„ØªØ­ÙˆÙŠÙ„Ø§Øª ÙˆØ§Ù„Ø¬Ø±Ø¯"
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
            []) as unknown as InventoryWarehouse[]
        }
        stock={
          (stockResult.data ??
            []) as unknown as InventoryStockRow[]
        }
        products={
          (productsResult.data ??
            []) as unknown as InventoryProduct[]
        }
        purchaseInvoices={
          (invoicesResult.data ??
            []) as unknown as InventoryPurchaseInvoice[]
        }
        receiptItems={
          (receiptItemsResult.data ??
            []) as unknown as InventoryReceiptItem[]
        }
        receipts={
          (receiptsResult.data ??
            []) as unknown as InventoryReceiptRow[]
        }
        transfers={
          (transfersResult.data ??
            []) as unknown as InventoryTransferRow[]
        }
        counts={
          (countsResult.data ??
            []) as unknown as InventoryCountRow[]
        }
        canReceive={
          canReceive
        }
        canReverseReceipt={
          hasAnyPermission(
            context.permissions,
            [
              "inventory.adjust",
              "purchase_invoices.cancel",
            ],
            context.isOwner
          )
        }
        canAdjust={
          canAdjust
        }
        canViewCost={
          canViewCost
        }
      />

      <InventoryReversalPanel
        companyId={
          context.companyId
        }
        warehouses={
          (warehousesResult.data ?? []) as unknown as InventoryWarehouse[]
        }
        receipts={
          (receiptsResult.data ?? []) as unknown as InventoryReceiptRow[]
        }
        transfers={
          (transfersResult.data ?? []) as unknown as InventoryTransferRow[]
        }
        counts={
          (countsResult.data ?? []) as unknown as InventoryCountRow[]
        }
        canReverseReceipt={
          hasAnyPermission(
            context.permissions,
            [
              "inventory.adjust",
              "purchase_invoices.cancel",
            ],
            context.isOwner
          )
        }
        canAdjust={
          canAdjust
        }
      />
    </>
  );
}
