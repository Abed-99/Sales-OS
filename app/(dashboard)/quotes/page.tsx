import { Topbar } from "@/components/topbar";
import {
  QuotesClient,
  type QuoteProduct,
  type QuoteRow,
  type QuoteTrader,
} from "@/components/quotes/quotes-client";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function QuotesPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasPermission(
    context.permissions,
    "orders.view",
    context.isOwner
  );
  const canCreate = hasPermission(
    context.permissions,
    "orders.create",
    context.isOwner
  );
  const canUpdate = hasPermission(
    context.permissions,
    "orders.update",
    context.isOwner
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="عروض الأسعار"
          subtitle="إدارة عروض الأسعار قبل تحويلها لطلبات"
          companyName={context.companyName}
        />
        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض عروض الأسعار.
          </section>
        </div>
      </>
    );
  }

  const [quotesResult, tradersResult, productsResult] = await Promise.all([
    supabase
      .from("sales_quotes")
      .select(`
        id,
        trader_id,
        quote_number,
        quote_date,
        valid_until,
        status,
        currency,
        subtotal,
        total,
        notes,
        accepted_at,
        converted_order_id,
        created_at,
        traders(name,area),
        sales_quote_items(
          id,
          product_id,
          quantity,
          sale_unit_price,
          line_total,
          minimum_sale_price_snapshot,
          reference_cost_snapshot,
          products(name,sku,unit)
        )
      `)
      .eq("company_id", context.companyId)
      .order("quote_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(200),

    supabase
      .from("traders")
      .select("id,name,area,status")
      .eq("company_id", context.companyId)
      .neq("status", "inactive")
      .order("name"),

    supabase
      .from("products")
      .select("id,name,sku,sale_price,minimum_sale_price,unit,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("name"),
  ]);

  if (quotesResult.error) throw new Error(quotesResult.error.message);
  if (tradersResult.error) throw new Error(tradersResult.error.message);
  if (productsResult.error) throw new Error(productsResult.error.message);

  return (
    <>
      <Topbar
        title="عروض الأسعار"
        subtitle="أنشئ العرض، تابع حالته، وحوّله لطلبية عند الاعتماد"
        companyName={context.companyName}
      />
      <QuotesClient
        companyId={context.companyId}
        currency={context.currency}
        initialQuotes={(quotesResult.data ?? []) as unknown as QuoteRow[]}
        traders={(tradersResult.data ?? []) as QuoteTrader[]}
        products={(productsResult.data ?? []) as QuoteProduct[]}
        canCreate={canCreate}
        canUpdate={canUpdate}
      />
    </>
  );
}
