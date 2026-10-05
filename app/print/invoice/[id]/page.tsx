import { notFound } from "next/navigation";

import { PrintShell } from "@/components/print/print-shell";
import { money, quantityLabel } from "@/lib/print-format";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { createClient } from "@/lib/supabase/server";
import { phoneText } from "@/lib/format";

type Item = {
  id: string;
  description: string;
  unit: string | null;
  quantity: number;
  unit_price: number;
  line_total: number;
  products: { pack_size: number | null; pack_unit: string | null } | null;
};

export default async function PrintInvoicePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: invoice } = await supabase
    .from("sales_invoices")
    .select(
      "id,invoice_number,invoice_date,due_date,currency,subtotal,discount_total,tax_total,total,paid_total,balance_due,status,notes,order_id,traders(name,phone,whatsapp,address),sales_orders(order_number)",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!invoice) notFound();

  const [{ data: items }, company] = await Promise.all([
    supabase
      .from("sales_invoice_items")
      .select("id,description,unit,quantity,unit_price,line_total,products(pack_size,pack_unit)")
      .eq("invoice_id", id)
      .order("created_at"),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  const trader = (Array.isArray(invoice.traders) ? invoice.traders[0] : invoice.traders) as {
    name: string;
    phone: string | null;
    whatsapp: string | null;
    address: string | null;
  } | null;
  const order = (
    Array.isArray(invoice.sales_orders) ? invoice.sales_orders[0] : invoice.sales_orders
  ) as {
    order_number: string | null;
  } | null;
  const currency = invoice.currency;

  return (
    <PrintShell
      company={company}
      fileName={`فاتورة ${invoice.invoice_number}`}
      shareText={`مرحبا ${trader?.name ?? ""}، هي فاتورتك رقم ${invoice.invoice_number} بقيمة ${money(invoice.total, currency)}. ${company.name}`}
      phone={trader?.whatsapp || trader?.phone}
      backHref={`/orders?order=${invoice.order_id}`}
    >
      <div className="printTitle">
        <div>
          <h2>فاتورة مبيع</h2>
          <div className="printMeta">
            رقم الفاتورة: <strong>{invoice.invoice_number}</strong>
            <br />
            التاريخ: {invoice.invoice_date}
            {invoice.due_date ? (
              <>
                <br />
                تاريخ الاستحقاق: {invoice.due_date}
              </>
            ) : null}
            {order?.order_number ? (
              <>
                <br />
                رقم الطلبية: {order.order_number}
              </>
            ) : null}
            {invoice.status === "cancelled" ? <span className="printStamp">ملغاة</span> : null}
          </div>
        </div>
        <div className="printMeta">
          العميل: <strong>{trader?.name}</strong>
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
                <td>{item.description}</td>
                <td>
                  {quantityLabel(item.quantity, item.unit, product?.pack_size, product?.pack_unit)}
                </td>
                <td className="num">{money(item.unit_price, currency)}</td>
                <td className="num">{money(item.line_total, currency)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <div className="printTotals">
        {Number(invoice.discount_total) > 0 ? (
          <>
            <div>
              <span>المجموع</span>
              <span>{money(invoice.subtotal, currency)}</span>
            </div>
            <div>
              <span>الخصم</span>
              <span>{money(invoice.discount_total, currency)}</span>
            </div>
          </>
        ) : null}
        {Number(invoice.tax_total) > 0 ? (
          <div>
            <span>{company.tax_label ?? "الضريبة"}</span>

            <span>{money(invoice.tax_total, currency)}</span>
          </div>
        ) : null}
        <div className="grand">
          <span>الإجمالي</span>
          <span>{money(invoice.total, currency)}</span>
        </div>
        <div>
          <span>المدفوع</span>
          <span>{money(invoice.paid_total, currency)}</span>
        </div>
        <div>
          <span>الباقي</span>
          <span>{money(invoice.balance_due, currency)}</span>
        </div>
      </div>

      {invoice.notes ? <p className="printNote">ملاحظات: {invoice.notes}</p> : null}
      <p className="printNote">شكرًا لتعاملكم معنا.</p>
    </PrintShell>
  );
}
