import { Topbar } from "@/components/topbar";

import {
  ReportsClient,
  type FinancialReport,
  type ReceivableAging,
  type PayableAging,
  type InventoryValuation,
  type SalesMonthlyReport,
  type PurchaseMonthlyReport,
  type ReportPayrollRun,
  type ReportAsset,
  type ReportPartner,
} from "@/components/reports/reports-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

function damascusToday() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function validDate(value: string | undefined) {
  return Boolean(value && /^\d{4}-\d{2}-\d{2}$/.test(value));
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{
    from?: string;
    to?: string;
  }>;
}) {
  const params = await searchParams;

  const context = await getCurrentContext();

  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "reports.view",
      "reports.sales",
      "reports.profit",
      "reports.finance",
      "payroll.reports",
      "assets.view",
      "partners.view",
    ],
    context.isOwner,
  );

  if (!canView) {
    return (
      <>
        <Topbar title="التقارير" subtitle="تقارير النظام" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض التقارير.</section>
        </div>
      </>
    );
  }

  const defaultTo = damascusToday();

  const defaultFrom = `${defaultTo.slice(0, 4)}-01-01`;

  const from = validDate(params.from) ? params.from! : defaultFrom;

  const to = validDate(params.to) ? params.to! : defaultTo;

  const canFinance = hasAnyPermission(
    context.permissions,
    ["reports.finance", "reports.profit", "finance.accounts_view"],
    context.isOwner,
  );

  const canSales = hasAnyPermission(
    context.permissions,
    ["reports.sales", "reports.profit", "reports.finance"],
    context.isOwner,
  );

  const canPurchases = hasAnyPermission(
    context.permissions,
    ["purchases.view", "reports.profit", "reports.finance"],
    context.isOwner,
  );

  const canInventoryCost = hasAnyPermission(
    context.permissions,
    ["reports.finance", "reports.profit", "products.view_cost", "suppliers.view_finance"],
    context.isOwner,
  );

  const canPayroll = hasAnyPermission(
    context.permissions,
    ["payroll.reports", "payroll.view"],
    context.isOwner,
  );

  const canAssets = hasPermission(context.permissions, "assets.view", context.isOwner);

  const canPartners = hasPermission(context.permissions, "partners.view", context.isOwner);

  let financialReport: FinancialReport | null = null;

  let receivables: ReceivableAging[] = [];

  let payables: PayableAging[] = [];

  let inventory: InventoryValuation[] = [];

  // المجموع من القاعدة مباشرة (القائمة ممكن تنقص إذا الأسطر فوق الألف).
  let inventoryValue: number | null = null;

  let inventoryLines: number | null = null;

  let salesMonthly: SalesMonthlyReport[] = [];

  let purchaseMonthly: PurchaseMonthlyReport[] = [];

  let payrollRuns: ReportPayrollRun[] = [];

  let assets: ReportAsset[] = [];

  let partners: ReportPartner[] = [];

  const warnings: string[] = [];

  let team: unknown = null;

  if (
    hasAnyPermission(
      context.permissions,
      ["reports.sales", "reports.team", "reports.profit"],
      context.isOwner,
    )
  ) {
    const { data, error } = await supabase.rpc("get_team_performance", {
      target_company: context.companyId,
      target_from: from,
      target_to: to,
    });

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    } else {
      team = data;
    }
  }

  if (canFinance) {
    const [financialResult, receivableResult, payableResult] = await Promise.all([
      supabase.rpc("get_financial_report", {
        target_company: context.companyId,
        target_start: from,
        target_end: to,
      }),

      supabase.rpc("get_receivables_aging", {
        target_company: context.companyId,
        target_as_of: to,
      }),

      supabase.rpc("get_payables_aging", {
        target_company: context.companyId,
        target_as_of: to,
      }),
    ]);

    if (financialResult.error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    if (receivableResult.error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    if (payableResult.error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    financialReport = financialResult.data as unknown as FinancialReport;

    receivables = (receivableResult.data ?? []) as unknown as ReceivableAging[];

    payables = (payableResult.data ?? []) as unknown as PayableAging[];
  }

  if (canSales) {
    const { data, error } = await supabase.rpc("get_sales_monthly_report", {
      target_company: context.companyId,
      target_start: from,
      target_end: to,
    });

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    salesMonthly = (data ?? []) as unknown as SalesMonthlyReport[];
  }

  if (canPurchases) {
    const { data, error } = await supabase.rpc("get_purchase_monthly_report", {
      target_company: context.companyId,
      target_start: from,
      target_end: to,
    });

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    purchaseMonthly = (data ?? []) as unknown as PurchaseMonthlyReport[];
  }

  if (canInventoryCost) {
    const [{ data, error }, statsResult, linesResult] = await Promise.all([
      supabase.rpc("get_inventory_valuation", {
        target_company: context.companyId,
      }),
      supabase.rpc("get_inventory_stats", { target_company: context.companyId }),
      supabase
        .from("inventory_stock")
        .select("product_id", { count: "exact", head: true })
        .eq("company_id", context.companyId)
        .neq("on_hand", 0),
    ]);

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    inventory = (data ?? []) as unknown as InventoryValuation[];

    const stats = Array.isArray(statsResult.data) ? statsResult.data[0] : null;
    inventoryValue = stats?.stock_value == null ? null : Number(stats.stock_value);
    inventoryLines = linesResult.count ?? null;
  }

  if (canPayroll) {
    const { data, error } = await supabase
      .from("payroll_runs")
      .select(
        "id,period_start,period_end,pay_date,status,currency,total_gross,total_deductions,total_net,total_paid,created_at",
      )
      .eq("company_id", context.companyId)
      .gte("period_end", from)
      .lte("period_start", to)
      .order("period_start", {
        ascending: false,
      });

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    payrollRuns = (data ?? []) as unknown as ReportPayrollRun[];
  }

  if (canAssets) {
    const { data, error } = await supabase
      .from("fixed_asset_summary")
      .select(
        "id,asset_number,name,category,currency,purchase_cost,accumulated_depreciation,book_value,monthly_depreciation,status,in_service_date,useful_life_months",
      )
      .eq("company_id", context.companyId)
      .order("asset_number");

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    assets = (data ?? []) as unknown as ReportAsset[];
  }

  if (canPartners) {
    const { data, error } = await supabase
      .from("partner_summary")
      .select(
        "id,partner_number,name,ownership_percent,profit_share_percent,active,capital_contributions,drawings,partner_loan_balance,profit_distributions",
      )
      .eq("company_id", context.companyId)
      .order("name");

    if (error) {
      warnings.push("تعذر تحميل جزء من التقرير.");
    }

    partners = (data ?? []) as unknown as ReportPartner[];
  }

  return (
    <>
      <Topbar
        title="التقارير"
        subtitle="التقارير المالية والتشغيلية"
        companyName={context.companyName}
      />

      {warnings.length > 0 && (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض أقسام التقارير. البيانات المتاحة فقط هي الظاهرة.
          </div>
        </div>
      )}

      <ReportsClient
        baseCurrency={context.currency}
        from={from}
        to={to}
        financialReport={financialReport}
        receivables={receivables}
        payables={payables}
        inventory={inventory}
        inventoryValue={inventoryValue}
        inventoryLines={inventoryLines}
        salesMonthly={salesMonthly}
        purchaseMonthly={purchaseMonthly}
        payrollRuns={payrollRuns}
        assets={assets}
        partners={partners}
        canFinance={canFinance}
        canSales={canSales}
        canPurchases={canPurchases}
        canInventoryCost={canInventoryCost}
        canPayroll={canPayroll}
        canAssets={canAssets}
        canPartners={canPartners}
        team={team as never}
      />
    </>
  );
}
