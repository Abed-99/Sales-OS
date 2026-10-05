import { notFound } from "next/navigation";

import { PrintShell } from "@/components/print/print-shell";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { money, quantityLabel } from "@/lib/print-format";
import { createClient } from "@/lib/supabase/server";
import { phoneText, formatDate } from "@/lib/format";

type Item = {
  id: string;
  quantity: number;
  sale_unit_price: number;
  line_total: number;
  products: {
    name: string;
    sku: string | null;
    unit: string | null;
    pack_size: number | null;
    pack_unit: string | null;
  } | null;
};

export default async function PrintQuote({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: quote } = await supabase
    .from("sales_quotes")
    .select(
      "id,quote_number,quote_date,valid_until,currency,subtotal,total,notes,traders(name,phone,whatsapp,address)",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!quote) notFound();

  const [{ data: items }, company] = await Promise.all([
    supabase
      .from("sales_quote_items")
      .select("id,quantity,sale_unit_price,line_total,products(name,sku,unit,pack_size,pack_unit)")
      .eq("quote_id", id)
      .order("created_at"),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  const trader = (Array.isArray(quote.traders) ? quote.traders[0] : quote.traders) as {
    name: string;
    phone: string | null;
    whatsapp: string | null;
    address: string | null;
  } | null;

  return (
    <PrintShell
      company={company}
      fileName={`Quote ${quote.quote_number}`}
      shareText={`مرحبا ${trader?.name ?? ""}، هاد عرض السعر رقم ${quote.quote_number} بقيمة ${money(quote.total, quote.currency)}${quote.valid_until ? `، صالح لغاية ${quote.valid_until}` : ""}. ${company.name}`}
      phone={trader?.whatsapp || trader?.phone}
      backHref="/quotes"
    >
      <div className="printTitle">
        <div>
          <h2>عرض سعر</h2>
          <div className="printMeta">
            الرقم: <strong>{quote.quote_number}</strong>
            <br />
            التاريخ: {formatDate(quote.quote_date)}
            {quote.valid_until ? (
              <>
                <br />
                صالح لغاية: {quote.valid_until}
              </>
            ) : null}
          </div>
        </div>
        <div className="printMeta">
          إلى: <strong>{trader?.name}</strong>
          {trader?.phone ? (
            <>
              <br />
              {phoneText(trader.phone)}
            </>
          ) : null}
          {trader?.address ? (
            <>
              <br />
              {trader.address}
            </>
          ) : null}
        </div>
      </div>

      <table className="printTable">
        <thead>
          <tr>
            <th>#</th>
            <th>الصنف</th>
            <th>الكمية</th>
            <th className="num">السعر</th>
            <th className="num">المجموع</th>
          </tr>
        </thead>
        <tbody>
          {((items ?? []) as unknown as Item[]).map((item, index) => {
            const product = Array.isArray(item.products) ? item.products[0] : item.products;
            return (
              <tr key={item.id}>
                <td>{index + 1}</td>
                <td>
                  {product?.name}
                  {product?.sku ? ` (${product.sku})` : ""}
                </td>
                <td>
                  {quantityLabel(
                    item.quantity,
                    product?.unit,
                    product?.pack_size,
                    product?.pack_unit,
                  )}
                </td>
                <td className="num">{money(item.sale_unit_price, quote.currency)}</td>
                <td className="num">{money(item.line_total, quote.currency)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <div className="printTotals">
        <div className="grand">
          <span>الإجمالي</span>
          <span>{money(quote.total, quote.currency)}</span>
        </div>
      </div>

      {quote.notes ? <p className="printNote">ملاحظات: {quote.notes}</p> : null}
      <p className="printNote">الأسعار حسب توفر البضاعة وقت التأكيد.</p>
    </PrintShell>
  );
}
