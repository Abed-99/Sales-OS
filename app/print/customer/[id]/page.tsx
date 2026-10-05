import { notFound } from "next/navigation";

import { PrintNoAccess } from "@/components/print/no-access";
import { PrintShell } from "@/components/print/print-shell";
import { money } from "@/lib/print-format";
import { StatementRange } from "@/components/print/statement-range";
import { getCurrentContext } from "@/lib/current-context";
import { loadLetterhead } from "@/lib/letterhead";
import { createClient } from "@/lib/supabase/server";
import { todayDamascus } from "@/lib/format";

type Row = {
  event_date: string;
  row_type: string;
  reference: string | null;
  description: string;
  debit: number | null;
  credit: number | null;
  balance: number;
};

function validDate(value: string | undefined) {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

export default async function PrintCustomerStatement({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ from?: string; to?: string }>;
}) {
  const { id } = await params;
  const query = await searchParams;
  const context = await getCurrentContext();
  const supabase = await createClient();

  const today = todayDamascus();
  const from = validDate(query.from);
  const to = validDate(query.to) ?? today;

  const { data: trader } = await supabase
    .from("traders")
    .select("id,name,phone,whatsapp,address")
    .eq("company_id", context.companyId)
    .eq("id", id)
    .maybeSingle();

  if (!trader) notFound();

  const [{ data, error }, company] = await Promise.all([
    supabase.rpc("get_trader_statement", {
      target_company: context.companyId,
      target_trader: id,
      target_from: from,
      target_to: to,
    }),
    loadLetterhead(supabase, context.companyId, context.companyName),
  ]);

  if (error) {
    return (
      <PrintNoAccess
        backHref={`/customers/${trader.id}`}
        message="ما عندك صلاحية تشوف كشف حساب العميل. اطلبها من صاحب الشركة."
      />
    );
  }

  const rows = (data ?? []) as Row[];
  const closing = rows.length ? Number(rows[rows.length - 1].balance) : 0;
  const currency = context.currency;

  return (
    <PrintShell
      company={company}
      fileName={`كشف حساب ${trader.name}`}
      shareText={`مرحبا ${trader.name}، هاد كشف حسابك لغاية ${to}. الرصيد: ${money(closing, currency)}. ${company.name}`}
      phone={trader.whatsapp || trader.phone}
      backHref={`/customers/${trader.id}`}
      tools={<StatementRange from={from ?? ""} to={to} />}
    >
      <div className="printTitle">
        <div>
          <h2>كشف حساب عميل</h2>
          <div className="printMeta">
            العميل: <strong>{trader.name}</strong>
            {trader.phone ? ` • ${trader.phone}` : ""}
            <br />
            الفترة: {from ?? "من البداية"} ← {to}
          </div>
        </div>
        <div className="printMeta" style={{ textAlign: "left" }}>
          الرصيد النهائي
          <br />
          <strong style={{ fontSize: 18 }}>
            <bdi dir="ltr">{money(Math.abs(closing), currency)}</bdi>
          </strong>
          <br />
          {closing > 0
            ? "مطلوب من العميل"
            : closing < 0
              ? "رصيد للعميل عنا"
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
          {rows.map((row, index) => (
            <tr key={`${row.reference}-${index}`}>
              <td>
                {row.row_type === "opening" ? (from ?? "") : row.event_date}
              </td>
              <td>{row.description}</td>
              <td>{row.reference ?? ""}</td>
              <td className="num">
                {row.debit ? money(row.debit, currency) : ""}
              </td>
              <td className="num">
                {row.credit ? money(row.credit, currency) : ""}
              </td>
              <td className="num">
                <strong>{money(row.balance, currency)}</strong>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <p className="printNote">
        المبالغ بعملة الشركة ({currency}). الدفعات بالليرة محسوبة بسعر يومها.
      </p>
    </PrintShell>
  );
}
