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
import {
  hasAnyPermission,
  hasPermission,
} from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

function validDate(
  value: string | undefined
) {
  return Boolean(
    value &&
      /^\d{4}-\d{2}-\d{2}$/.test(value)
  );
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{
    from?: string;
    to?: string;
  }>;
}) {
  const params =
    await searchParams;

  const context =
    await getCurrentContext();

  const supabase =
    await createClient();

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
    context.isOwner
  );

  if (!canView) {
    return (
      <>
        <Topbar
          title="التقارير"
          subtitle="تقارير النظام"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            ما عندك صلاحية لعرض التقارير.
          </section>
        </div>
      </>
    );
  }

  const now =
    new Date();

  const year =
    now.getFullYear();

  const defaultFrom =
    `${year}-01-01`;

  const defaultTo =
    now.toISOString().slice(0, 10);

  const from =
    validDate(params.from)
      ? params.from!
      : defaultFrom;

  const to =
    validDate(params.to)
      ? params.to!
      : defaultTo;

  const canFinance =
    hasAnyPermission(
      context.permissions,
      [
        "reports.finance",
        "reports.profit",
        "finance.accounts_view",
      ],
      context.isOwner
    );

  const canSales =
    hasAnyPermission(
      context.permissions,
      [
        "reports.sales",
        "reports.profit",
        "reports.finance",
      ],
      context.isOwner
    );

  const canPurchases =
    hasAnyPermission(
      context.permissions,
      [
        "purchases.view",
        "reports.profit",
        "reports.finance",
      ],
      context.isOwner
    );

  const canInventoryCost =
    hasAnyPermission(
      context.permissions,
      [
        "reports.finance",
        "reports.profit",
        "products.view_cost",
        "suppliers.view_finance",
      ],
      context.isOwner
    );

  const canPayroll =
    hasAnyPermission(
      context.permissions,
      [
        "payroll.reports",
        "payroll.view",
      ],
      context.isOwner
    );

  const canAssets =
    hasPermission(
      context.permissions,
      "assets.view",
      context.isOwner
    );

  const canPartners =
    hasPermission(
      context.permissions,
      "partners.view",
      context.isOwner
    );

  let financialReport:
    FinancialReport | null =
    null;

  let receivables:
    ReceivableAging[] = [];

  let payables:
    PayableAging[] = [];

  let inventory:
    InventoryValuation[] = [];

  let salesMonthly:
    SalesMonthlyReport[] = [];

  let purchaseMonthly:
    PurchaseMonthlyReport[] = [];

  let payrollRuns:
    ReportPayrollRun[] = [];

  let assets:
    ReportAsset[] = [];

  let partners:
    ReportPartner[] = [];

  if (canFinance) {
    const [
      financialResult,
      receivableResult,
      payableResult,
    ] = await Promise.all([
      supabase.rpc(
        "get_financial_report",
        {
          target_company:
            context.companyId,
          target_start:
            from,
          target_end:
            to,
        }
      ),

      supabase.rpc(
        "get_receivables_aging",
        {
          target_company:
            context.companyId,
          target_as_of:
            to,
        }
      ),

      supabase.rpc(
        "get_payables_aging",
        {
          target_company:
            context.companyId,
          target_as_of:
            to,
        }
      ),
    ]);

    if (financialResult.error) {
      throw new Error(
        financialResult.error.message
      );
    }

    if (receivableResult.error) {
      throw new Error(
        receivableResult.error.message
      );
    }

    if (payableResult.error) {
      throw new Error(
        payableResult.error.message
      );
    }

    financialReport =
      financialResult.data as unknown as FinancialReport;

    receivables =
      (receivableResult.data ??
        []) as unknown as ReceivableAging[];

    payables =
      (payableResult.data ??
        []) as unknown as PayableAging[];
  }

  if (canSales) {
    const { data, error } =
      await supabase.rpc(
        "get_sales_monthly_report",
        {
          target_company:
            context.companyId,
          target_start:
            from,
          target_end:
            to,
        }
      );

    if (error) {
      throw new Error(
        error.message
      );
    }

    salesMonthly =
      (data ??
        []) as unknown as SalesMonthlyReport[];
  }

  if (canPurchases) {
    const { data, error } =
      await supabase.rpc(
        "get_purchase_monthly_report",
        {
          target_company:
            context.companyId,
          target_start:
            from,
          target_end:
            to,
        }
      );

    if (error) {
      throw new Error(
        error.message
      );
    }

    purchaseMonthly =
      (data ??
        []) as unknown as PurchaseMonthlyReport[];
  }

  if (canInventoryCost) {
    const { data, error } =
      await supabase.rpc(
        "get_inventory_valuation",
        {
          target_company:
            context.companyId,
        }
      );

    if (error) {
      throw new Error(
        error.message
      );
    }

    inventory =
      (data ??
        []) as unknown as InventoryValuation[];
  }

  if (canPayroll) {
    const { data, error } =
      await supabase
        .from("payroll_runs")
        .select(
          "id,period_start,period_end,pay_date,status,currency,total_gross,total_deductions,total_net,total_paid,created_at"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .gte(
          "period_end",
          from
        )
        .lte(
          "period_start",
          to
        )
        .order(
          "period_start",
          {
            ascending: false,
          }
        );

    if (error) {
      throw new Error(
        error.message
      );
    }

    payrollRuns =
      (data ??
        []) as unknown as ReportPayrollRun[];
  }

  if (canAssets) {
    const { data, error } =
      await supabase
        .from(
          "fixed_asset_summary"
        )
        .select(
          "id,asset_number,name,category,currency,purchase_cost,accumulated_depreciation,book_value,monthly_depreciation,status,in_service_date,useful_life_months"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "asset_number"
        );

    if (error) {
      throw new Error(
        error.message
      );
    }

    assets =
      (data ??
        []) as unknown as ReportAsset[];
  }

  if (canPartners) {
    const { data, error } =
      await supabase
        .from(
          "partner_summary"
        )
        .select(
          "id,partner_number,name,ownership_percent,profit_share_percent,active,capital_contributions,drawings,partner_loan_balance,profit_distributions"
        )
        .eq(
          "company_id",
          context.companyId
        )
        .order(
          "name"
        );

    if (error) {
      throw new Error(
        error.message
      );
    }

    partners =
      (data ??
        []) as unknown as ReportPartner[];
  }

  return (
    <>
      <Topbar
        title="التقارير"
        subtitle="التقارير المالية والتشغيلية"
        companyName={context.companyName}
      />

      <ReportsClient
        baseCurrency={
          context.currency
        }
        from={from}
        to={to}
        financialReport={
          financialReport
        }
        receivables={
          receivables
        }
        payables={
          payables
        }
        inventory={
          inventory
        }
        salesMonthly={
          salesMonthly
        }
        purchaseMonthly={
          purchaseMonthly
        }
        payrollRuns={
          payrollRuns
        }
        assets={
          assets
        }
        partners={
          partners
        }
        canFinance={
          canFinance
        }
        canSales={
          canSales
        }
        canPurchases={
          canPurchases
        }
        canInventoryCost={
          canInventoryCost
        }
        canPayroll={
          canPayroll
        }
        canAssets={
          canAssets
        }
        canPartners={
          canPartners
        }
      />
    </>
  );
}