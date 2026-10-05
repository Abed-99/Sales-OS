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

export default async function PrintPurchaseOrder({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: order } = await supabase
    .from("purchase_orders")
    .select(
      "id,po_number,order_date,expected_date,currency,total,notes,suppliers(name,phone,whatsapp,contact_name)",
    )
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!order) notFound();

  const [{ data: items }, company] = await Promise.all([
    supabase
      .from("purchase_order_items")
      .select("id,quantity,unit_cost,line_total,notes,products(name,sku,unit,pack_size,pack_unit)")
      .eq("purchase_order_id", id)
      .order("created_at"),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  const supplier = (Array.isArray(order.suppliers) ? order.suppliers[0] : order.suppliers) as {
    name: string;
    phone: string | null;
    whatsapp: string | null;
    contact_name: string | null;
  } | null;

  return (
    <PrintShell
      company={company}
      fileName={`Purchase-Order ${order.po_number}`}
      shareText={`مرحبا ${supplier?.contact_name ?? supplier?.name ?? ""}، هاد أمر الشراء ${order.po_number} من ${company.name}. نرجو التأكيد.`}
      phone={supplier?.whatsapp || supplier?.phone}
      backHref="/purchase-orders"
    >
      <div className="printTitle">
        <div>
          <h2>أمر شراء</h2>
          <div className="printMeta">
            الرقم: <strong>{order.po_number}</strong>
            <br />
            التاريخ: {order.order_date}
            {order.expected_date ? (
              <>
                <br />
                الوصول المطلوب: {order.expected_date}
              </>
            ) : null}
          </div>
        </div>
        <div className="printMeta">
          إلى: <strong>{supplier?.name}</strong>
          {supplier?.contact_name ? (
            <>
              <br />
              {supplier.contact_name}
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
                <td className="num">{money(item.unit_cost, order.currency)}</td>
                <td className="num">{money(item.line_total, order.currency)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <div className="printTotals">
        <div className="grand">
          <span>الإجمالي التقريبي</span>
          <span>{money(order.total, order.currency)}</span>
        </div>
      </div>

      {order.notes ? <p className="printNote">ملاحظات: {order.notes}</p> : null}
    </PrintShell>
  );
}
