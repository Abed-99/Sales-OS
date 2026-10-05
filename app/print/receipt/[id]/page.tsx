import { notFound } from "next/navigation";

import { PrintShell } from "@/components/print/print-shell";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { money } from "@/lib/print-format";
import { createClient } from "@/lib/supabase/server";
import { phoneText } from "@/lib/format";

// سند قبض (دفعة من زبون) أو سند دفع (?kind=supplier: دفعة لمورد).
type Party = { id: string; name: string; phone: string | null; whatsapp: string | null } | null;
type Allocation = {
  amount: number;
  invoice_currency: string | null;
  invoice: { invoice_number: string } | { invoice_number: string }[] | null;
};

const methodLabels: Record<string, string> = {
  cash: "نقدًا",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

const one = <T,>(value: T | T[] | null) => (Array.isArray(value) ? (value[0] ?? null) : value);

export default async function PrintReceipt({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ kind?: string }>;
}) {
  const { id } = await params;
  const supplierMode = (await searchParams).kind === "supplier";
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: payment } = supplierMode
    ? await supabase
        .from("supplier_payments")
        .select(
          "id,payment_number,payment_date,amount,payment_currency,payment_method,reference_number,notes,status,party:suppliers(id,name,phone,whatsapp),supplier_payment_allocations(amount,invoice_currency,invoice:purchase_invoices(invoice_number)),cashboxes(name,currency)",
        )
        .eq("company_id", context.companyId)
        .eq("id", id)
        .maybeSingle()
    : await supabase
        .from("customer_payments")
        .select(
          "id,payment_number,payment_date,amount,payment_currency,payment_method,reference_number,notes,status,party:traders(id,name,phone,whatsapp),customer_payment_allocations(amount,invoice_currency,invoice:sales_invoices(invoice_number)),cashboxes(name,currency)",
        )
        .eq("company_id", context.companyId)
        .eq("id", id)
        .maybeSingle();

  if (!payment) notFound();

  const row = payment as unknown as {
    payment_number: string;
    payment_date: string;
    amount: number;
    payment_currency: string | null;
    payment_method: string;
    reference_number: string | null;
    notes: string | null;
    status: string;
    party: Party | Party[];
    supplier_payment_allocations?: Allocation[];
    customer_payment_allocations?: Allocation[];
    cashboxes: { name: string; currency: string } | { name: string; currency: string }[] | null;
  };
  const party = one(row.party);
  const box = one(row.cashboxes);
  const currency = row.payment_currency || box?.currency || context.currency;
  const allocations =
    (supplierMode ? row.supplier_payment_allocations : row.customer_payment_allocations) ?? [];

  // الرصيد بعد الدفعة (بعملة الشركة).
  let balance: number | null = null;
  if (party) {
    if (supplierMode) {
      const { data } = await supabase.rpc("get_supplier_financial_summary", {
        target_company: context.companyId,
        target_supplier: party.id,
      });
      const summary = (data as { net_balance: number }[] | null)?.[0];
      balance = summary ? Number(summary.net_balance) : null;
    } else {
      const { data } = await supabase.rpc("get_trader_statement", {
        target_company: context.companyId,
        target_trader: party.id,
        target_from: null,
        target_to: null,
      });
      const rows = (data ?? []) as { balance: number }[];
      balance = rows.length ? Number(rows[rows.length - 1].balance) : 0;
    }
  }

  const company = await loadLetterhead(supabase, context.companyId, context.companyName);
  const title = supplierMode ? "سند دفع" : "سند قبض";
  const reversed = row.status === "reversed";

  return (
    <PrintShell
      company={company}
      fileName={`${supplierMode ? "Payment" : "Receipt"} ${row.payment_number}`}
      shareText={
        supplierMode
          ? `مرحبا ${party?.name ?? ""}، دفعنالكم ${money(row.amount, currency)} (سند ${row.payment_number}). ${company.name}`
          : `مرحبا ${party?.name ?? ""}، استلمنا منك ${money(row.amount, currency)} (سند ${row.payment_number}). شكرًا إلك 🌷 ${company.name}`
      }
      phone={party?.whatsapp || party?.phone}
      backHref={supplierMode ? `/suppliers/${party?.id ?? ""}` : `/customers/${party?.id ?? ""}`}
    >
      <div className="printTitle">
        <div>
          <h2>
            {title}
            {reversed ? <span className="printStamp">ملغى</span> : null}
          </h2>
          <div className="printMeta">
            الرقم: <strong>{row.payment_number}</strong>
            <br />
            التاريخ: {row.payment_date}
          </div>
        </div>
        <div className="printMeta">
          {supplierMode ? "دفعنا إلى" : "استلمنا من"}: <strong>{party?.name}</strong>
          {party?.phone ? (
            <>
              <br />
              {phoneText(party.phone)}
            </>
          ) : null}
        </div>
      </div>

      <div className="printTotals printAmount">
        <div className="grand">
          <span>المبلغ</span>
          <span>{money(row.amount, currency)}</span>
        </div>
      </div>

      <p className="printNote">
        طريقة الدفع: {methodLabels[row.payment_method] ?? row.payment_method}
        {box ? ` • الصندوق: ${box.name}` : ""}
        {row.reference_number ? ` • المرجع: ${row.reference_number}` : ""}
      </p>

      {allocations.length ? (
        <table className="printTable">
          <thead>
            <tr>
              <th>عن الفاتورة</th>
              <th className="num">المبلغ</th>
            </tr>
          </thead>
          <tbody>
            {allocations.map((item, index) => (
              <tr key={index}>
                <td>{one(item.invoice)?.invoice_number}</td>
                <td className="num">
                  {money(item.amount, item.invoice_currency || context.currency)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p className="printNote">دفعة على الحساب.</p>
      )}

      {balance != null && !reversed ? (
        <p className="printNote">
          {supplierMode
            ? balance > 0
              ? `الباقي علينا للمورد: ${money(balance, context.currency)}`
              : balance < 0
                ? `رصيد إلنا عند المورد: ${money(-balance, context.currency)}`
                : "الحساب مسدّد."
            : balance > 0
              ? `الباقي عليك: ${money(balance, context.currency)}`
              : balance < 0
                ? `رصيد إلك عنا: ${money(-balance, context.currency)}`
                : "حسابك مسدّد. شكرًا إلك."}
        </p>
      ) : null}

      {row.notes ? <p className="printNote">ملاحظات: {row.notes}</p> : null}

      <div className="printSigns">
        <span>توقيع المستلم</span>
        <span>توقيع المحاسب</span>
      </div>
    </PrintShell>
  );
}
