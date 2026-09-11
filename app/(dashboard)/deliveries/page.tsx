import { Topbar } from "@/components/topbar";
import {
  DeliveriesClient,
  type DeliveryAllocation,
  type DeliveryOrder,
} from "@/components/deliveries/deliveries-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";

export default async function DeliveriesPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canUpdate = hasPermission(
    context.permissions,
    "deliveries.update",
    context.isOwner
  );

  const [
    ordersResult,
    allocationsResult,
  ] = await Promise.all([
    supabase
      .from("sales_orders")
      .select(`
        id,
        status,
        payment_status,
        total,
        created_at,
        traders(
          id,
          name,
          area,
          address,
          phone,
          whatsapp,
          latitude,
          longitude
        ),
        sales_order_items(
          id,
          product_id,
          quantity,
          sale_unit_price,
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
      .in(
        "status",
        [
          "ready",
          "out_for_delivery",
        ]
      )
      .order(
        "created_at",
        {
          ascending: true,
        }
      )
      .limit(200),

    supabase
      .from("delivery_items")
      .select(`
        id,
        sales_order_item_id,
        quantity,
        delivery_id,
        deliveries(
          id,
          order_id,
          status,
          delivery_number,
          created_at,
          delivered_at
        )
      `)
      .eq(
        "company_id",
        context.companyId
      ),
  ]);

  if (ordersResult.error) {
    throw new Error(
      ordersResult.error.message
    );
  }

  if (allocationsResult.error) {
    throw new Error(
      allocationsResult.error.message
    );
  }

  return (
    <>
      <Topbar
        title="التوصيل"
        subtitle="جهّز التسليمات الكاملة أو الجزئية وتابعها حتى التسليم"
        companyName={
          context.companyName
        }
      />

      <DeliveriesClient
        companyId={
          context.companyId
        }
        currency={
          context.currency
        }
        initialOrders={
          (ordersResult.data ??
            []) as unknown as DeliveryOrder[]
        }
        initialAllocations={
          (allocationsResult.data ??
            []) as unknown as DeliveryAllocation[]
        }
        canUpdate={
          canUpdate
        }
      />
    </>
  );
}