import { notFound } from "next/navigation";

import { PrintNoAccess } from "@/components/print/no-access";
import { PrintShell } from "@/components/print/print-shell";
import { money } from "@/lib/print-format";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { createClient } from "@/lib/supabase/server";
import { todayDamascus, formatDate } from "@/lib/format";

type Row = {
  source_id: string;
  event_date: string;
  event_created_at: string;
  row_type: string;
  reference: string | null;
  description: string | null;
  debit: number;
  credit: number;
  balance: number;
  currency: string | null;
};

const typeLabels: Record<string, string> = {
  invoice: "فاتورة شراء",
  payment: "دفعة",
  return: "مرتجع",
};

export default async function PrintSupplierStatement({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const { data: supplier } = await supabase
    .from("suppliers")
    .select("id,name,phone,whatsapp")
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!supplier) notFound();

  const [{ data, error }, company] = await Promise.all([
    supabase.rpc("get_supplier_ledger", {
      target_company: context.companyId,
      target_supplier: id,
      target_limit: 200,
    }),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  if (error) {
    return (
      <PrintNoAccess
        backHref={`/suppliers/${supplier.id}`}
        message="ما عندك صلاحية تشوف كشف حساب المورد. اطلبها من صاحب الشركة."
      />
    );
  }

  // الدالة بترجّع الأحدث أول؛ الكشف بينقرا من الأقدم للأحدث.
  const rows = [...((data ?? []) as Row[])].sort((a, b) =>
    `${a.event_date}${a.event_created_at}`.localeCompare(
      `${b.event_date}${b.event_created_at}`,
    ),
  );
  const closing = rows.length ? Number(rows[rows.length - 1].balance) : 0;
  const currency =
    rows.find((row) => row.currency)?.currency ?? context.currency;
  const today = todayDamascus();

  return (
    <PrintShell
      company={company}
      fileName={`Supplier-Statement ${todayDamascus()}`}
      shareText={`مرحبا، هاد كشف حسابنا عندكم لغاية ${today}. الرصيد: ${money(closing, currency)}. ${company.name}`}
      phone={supplier.whatsapp || supplier.phone}
      backHref={`/suppliers/${supplier.id}`}
    >
      <div className="printTitle">
        <div>
          <h2>كشف حساب مورد</h2>
          <div className="printMeta">
            المورد: <strong>{supplier.name}</strong>
            <br />
            لغاية: {today}
          </div>
        </div>
        <div className="printMeta" style={{ textAlign: "left" }}>
          الرصيد
          <br />
          <strong style={{ fontSize: 18 }}>
            <bdi dir="ltr">{money(Math.abs(closing), currency)}</bdi>
          </strong>
          <br />
          {closing > 0
            ? "علينا للمورد"
            : closing < 0
              ? "إلنا عند المورد"
              : "مسدّد"}
        </div>
      </div>

      <table className="printTable">
        <thead>
          <tr>
            <th>التاريخ</th>
            <th>البيان</th>
            <th>المرجع</th>
            <th className="num">مدين</th>
            <th className="num">دائن</th>
            <th className="num">الرصيد</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={`${row.row_type}-${row.source_id}`}>
              <td>{formatDate(row.event_date)}</td>
              <td>
                {row.description || typeLabels[row.row_type] || row.row_type}
              </td>
              <td>{row.reference ?? ""}</td>
              <td className="num">
                {Number(row.debit) ? money(row.debit, currency) : ""}
              </td>
              <td className="num">
                {Number(row.credit) ? money(row.credit, currency) : ""}
              </td>
              <td className="num">
                <strong>{money(row.balance, currency)}</strong>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </PrintShell>
  );
}
