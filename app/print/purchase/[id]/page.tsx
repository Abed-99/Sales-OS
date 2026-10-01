import { notFound } from "next/navigation";

import { PrintShell } from "@/components/print/print-shell";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { money, quantityLabel } from "@/lib/print-format";
import { createClient } from "@/lib/supabase/server";

type Item = {
  id: string;
  quantity: number;
  unit_cost: number;
  discount_amount: number;
  line_total: number;
  notes: string | null;
  products: {
    name: string;
    sku: string | null;
    unit: string | null;
    pack_size: number | null;
    pack_unit: string | null;
  } | null;
};

export default async function PrintPurchaseInvoice({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: invoice } = await supabase
    .from("purchase_invoices")
    .select(
      "id,invoice_number,supplier_invoice_number,invoice_date,due_date,currency,subtotal,discount_total,tax_total,total,paid_total,balance_due,status,notes,suppliers(name,phone,whatsapp,contact_name)",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!invoice) notFound();

  const [{ data: items }, company] = await Promise.all([
    supabase
      .from("purchase_invoice_items")
      .select(
        "id,quantity,unit_cost,discount_amount,line_total,notes,products(name,sku,unit,pack_size,pack_unit)",
      )
      .eq("invoice_id", id)
      .order("created_at"),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  const supplier = (
    Array.isArray(invoice.suppliers) ? invoice.suppliers[0] : invoice.suppliers
  ) as {
    name: string;
    phone: string | null;
    whatsapp: string | null;
    contact_name: string | null;
  } | null;
  const cur = invoice.currency;

  return (
    <PrintShell
      company={company}
      fileName={`فاتورة شراء ${invoice.invoice_number}`}
      shareText={`مرحبا ${supplier?.contact_name ?? supplier?.name ?? ""}، هي فاتورة الشراء ${invoice.supplier_invoice_number ?? invoice.invoice_number} بقيمة ${money(invoice.total, cur)} كما سجّلناها عنا. ${company.name}`}
      phone={supplier?.whatsapp || supplier?.phone}
      backHref="/purchases"
    >
      <div className="printTitle">
        <div>
          <h2>
            فاتورة شراء
            {invoice.status === "cancelled" ? " (ملغاة)" : ""}
          </h2>
          <div className="printMeta">
            الرقم: <strong>{invoice.invoice_number}</strong>
            {invoice.supplier_invoice_number ? (
              <>
                <br />
                رقم فاتورة المورد: {invoice.supplier_invoice_number}
              </>
            ) : null}
            <br />
            التاريخ: {invoice.invoice_date}
            {invoice.due_date ? (
              <>
                <br />
                الاستحقاق: {invoice.due_date}
              </>
            ) : null}
          </div>
        </div>
        <div className="printMeta">
          المورد: <strong>{supplier?.name}</strong>
          {supplier?.phone ? (
            <>
              <br />
              {supplier.phone}
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
            <th className="num">الكلفة</th>
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
                  {item.notes ? (
                    <div style={{ fontSize: 11, color: "#555" }}>{item.notes}</div>
                  ) : null}
                </td>
                <td>
                  {quantityLabel(
                    item.quantity,
                    product?.unit,
                    product?.pack_size,
                    product?.pack_unit,
                  )}
                </td>
                <td className="num">{money(item.unit_cost, cur)}</td>
                <td className="num">{money(item.line_total, cur)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <div className="printTotals">
        {Number(invoice.discount_total) > 0 ? (
          <div>
            <span>الحسم</span>
            <span>{money(invoice.discount_total, cur)}</span>
          </div>
        ) : null}
        {Number(invoice.tax_total) > 0 ? (
          <div>
            <span>الضريبة</span>
            <span>{money(invoice.tax_total, cur)}</span>
          </div>
        ) : null}
        <div className="grand">
          <span>الإجمالي</span>
          <span>{money(invoice.total, cur)}</span>
        </div>
        <div>
          <span>المدفوع</span>
          <span>{money(invoice.paid_total, cur)}</span>
        </div>
        <div>
          <span>الباقي</span>
          <span>{money(invoice.balance_due, cur)}</span>
        </div>
      </div>

      {invoice.notes ? <p className="printNote">ملاحظات: {invoice.notes}</p> : null}
    </PrintShell>
  );
}
