"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { ReportExport } from "@/components/reports/report-export";
import { formatDate, formatMoney as money, formatNumber, formatQty } from "@/lib/format";

function num(value: unknown) {
  const n = Number(value || 0);

  return Number.isFinite(n) ? n : 0;
}

export type FinancialReport = {
  currency: string;
  start_date: string;
  end_date: string;

  profit_loss: {
    revenue: number;
    cost_of_goods_sold: number;
    gross_profit: number;
    operating_expenses: number;
    net_profit: number;
  };

  balance_sheet: {
    assets: number;
    liabilities: number;
    equity_posted: number;
    current_earnings: number;
    equity_with_current_earnings: number;
  };

  cash_flow: {
    cash_in: number;
    cash_out: number;
    net_cash_flow: number;
  };

  working_capital: {
    accounts_receivable: number;
    accounts_payable: number;
    inventory_value: number;
  };
};

export type ReceivableAging = {
  trader_id: string;
  trader_name: string;
  current_amount: number;
  days_1_30: number;
  days_31_60: number;
  days_61_90: number;
  over_90: number;
  total_due: number;
};

export type PayableAging = {
  supplier_id: string;
  supplier_name: string;
  current_amount: number;
  days_1_30: number;
  days_31_60: number;
  days_61_90: number;
  over_90: number;
  total_due: number;
};

export type InventoryValuation = {
  warehouse_id: string;
  warehouse_name: string;
  product_id: string;
  product_name: string;
  sku: string | null;
  on_hand: number;
  reserved: number;
  available: number;
  average_cost: number;
  stock_value: number;
};

export type SalesMonthlyReport = {
  month_start: string;
  invoice_count: number;
  gross_sales: number;
  sales_returns: number;
  net_sales: number;
  collected: number;
  outstanding: number;
};

export type PurchaseMonthlyReport = {
  month_start: string;
  invoice_count: number;
  gross_purchases: number;
  purchase_returns: number;
  net_purchases: number;
  paid: number;
  outstanding: number;
};

export type ReportPayrollRun = {
  id: string;
  period_start: string;
  period_end: string;
  pay_date: string | null;
  status: string;
  currency: string;
  total_gross: number;
  total_deductions: number;
  total_net: number;
  total_paid: number;
  created_at: string;
};

export type ReportAsset = {
  id: string;
  asset_number: string;
  name: string;
  category: string | null;
  currency: string;
  purchase_cost: number;
  accumulated_depreciation: number;
  book_value: number;
  monthly_depreciation: number;
  status: string;
  in_service_date: string;
  useful_life_months: number;
};

export type ReportPartner = {
  id: string;
  partner_number: string | null;
  name: string;
  ownership_percent: number;
  profit_share_percent: number;
  active: boolean;
  capital_contributions: number;
  drawings: number;
  partner_loan_balance: number;
  profit_distributions: number;
};

type Tab =
  | "overview"
  | "profit"
  | "balance"
  | "cash"
  | "receivables"
  | "payables"
  | "inventory"
  | "sales"
  | "purchases"
  | "payroll"
  | "assets"
  | "partners"
  | "team";

type TeamPerformance = {
  reps: {
    id: string;
    full_name: string;
    commission_rate: number;
    customers: number;
    sales: number;
    returns: number;
    net_sales: number;
    collected: number;
    commission: number;
  }[];
  drivers: {
    id: string;
    full_name: string;
    delivered: number;
    failed: number;
    open: number;
  }[];
};

export function ReportsClient({
  baseCurrency,
  from,
  to,
  financialReport,
  receivables,
  payables,
  inventory,
  inventoryValue,
  inventoryLines,
  salesMonthly,
  purchaseMonthly,
  payrollRuns,
  assets,
  partners,
  canFinance,
  canSales,
  canPurchases,
  canInventoryCost,
  canPayroll,
  canAssets,
  canPartners,
  team = null,
}: {
  baseCurrency: string;
  from: string;
  to: string;
  financialReport: FinancialReport | null;
  receivables: ReceivableAging[];
  payables: PayableAging[];
  inventory: InventoryValuation[];
  inventoryValue?: number | null;
  inventoryLines?: number | null;
  salesMonthly: SalesMonthlyReport[];
  purchaseMonthly: PurchaseMonthlyReport[];
  payrollRuns: ReportPayrollRun[];
  assets: ReportAsset[];
  partners: ReportPartner[];
  canFinance: boolean;
  canSales: boolean;
  canPurchases: boolean;
  canInventoryCost: boolean;
  canPayroll: boolean;
  canAssets: boolean;
  canPartners: boolean;
  team?: TeamPerformance | null;
}) {
  const router = useRouter();

  const firstTab: Tab = canFinance
    ? "overview"
    : canSales
      ? "sales"
      : canPurchases
        ? "purchases"
        : canInventoryCost
          ? "inventory"
          : canPayroll
            ? "payroll"
            : canAssets
              ? "assets"
              : "partners";

  const [tab, setTab] = useState<Tab>(firstTab);
  const reportRef = useRef<HTMLDivElement>(null);

  const [startDate, setStartDate] = useState(from);

  const [endDate, setEndDate] = useState(to);

  function applyDates() {
    if (!startDate || !endDate) {
      return;
    }

    const query = new URLSearchParams({
      from: startDate,
      to: endDate,
    });

    router.push(`/reports?${query.toString()}`);
  }
  const inventoryTotal =
    inventoryValue ??
    inventory.reduce((sum, row) => sum + num(row.stock_value), 0);

  const totalSales = salesMonthly.reduce(
    (sum, row) => sum + num(row.net_sales),
    0,
  );

  const totalPurchases = purchaseMonthly.reduce(
    (sum, row) => sum + num(row.net_purchases),
    0,
  );

  const totalPayroll = payrollRuns
    .filter((run) => run.status !== "cancelled")
    .reduce((sum, row) => sum + num(row.total_net), 0);

  const payrollCurrencies = [
    ...new Set(
      payrollRuns
        .filter((run) => run.status !== "cancelled")
        .map((run) => run.currency.trim().toUpperCase()),
    ),
  ];

  const mixedPayrollCurrencies = payrollCurrencies.length > 1;

  const assetCurrencies = [
    ...new Set(assets.map((asset) => asset.currency.trim().toUpperCase())),
  ];

  const mixedAssetCurrencies = assetCurrencies.length > 1;

  // الأصول المبيوعة أو المشطوبة ما بتنحسب بالمجموع.
  const ownedAssets = assets.filter((asset) => asset.status !== "disposed");

  const assetCost = ownedAssets.reduce(
    (sum, row) => sum + num(row.purchase_cost),
    0,
  );

  const assetBookValue = ownedAssets.reduce(
    (sum, row) => sum + num(row.book_value),
    0,
  );

  const partnerCapital = partners.reduce(
    (sum, row) => sum + num(row.capital_contributions),
    0,
  );

  const availableTabs = useMemo(() => {
    const rows: {
      key: Tab;
      label: string;
    }[] = [];

    if (canFinance) {
      rows.push(
        {
          key: "overview",
          label: "الملخص",
        },
        {
          key: "profit",
          label: "الأرباح والخسائر",
        },
        {
          key: "balance",
          label: "الميزانية",
        },
        {
          key: "cash",
          label: "التدفق النقدي",
        },
        {
          key: "receivables",
          label: "ذمم العملاء",
        },
        {
          key: "payables",
          label: "ذمم الموردين",
        },
      );
    }

    if (canInventoryCost) {
      rows.push({
        key: "inventory",
        label: "تقييم المخزون",
      });
    }

    if (canSales) {
      rows.push({
        key: "sales",
        label: "المبيعات",
      });
    }

    if (canPurchases) {
      rows.push({
        key: "purchases",
        label: "المشتريات",
      });
    }

    if (canPayroll) {
      rows.push({
        key: "payroll",
        label: "الرواتب",
      });
    }

    if (canAssets) {
      rows.push({
        key: "assets",
        label: "الأصول",
      });
    }

    if (canPartners) {
      rows.push({
        key: "partners",
        label: "الشركاء",
      });
    }

    if (team) {
      rows.push({
        key: "team",
        label: "المندوبين والسائقين",
      });
    }

    return rows;
  }, [
    canFinance,
    canInventoryCost,
    canSales,
    canPurchases,
    canPayroll,
    canAssets,
    canPartners,
    team,
  ]);

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">التقارير</span>

          <h2>مركز التقارير</h2>

          <p className="muted">
            الأرقام المالية مأخوذة من القيود المحاسبية والحركات الفعلية للنظام.
          </p>
        </div>
      </div>

      <section className="panel panelPad">
        <div className="formGrid">
          <label className="field">
            <span>من تاريخ</span>

            <input
              type="date"
              value={startDate}
              onChange={(event) => setStartDate(event.target.value)}
            />
          </label>

          <label className="field">
            <span>إلى تاريخ</span>

            <input
              type="date"
              value={endDate}
              onChange={(event) => setEndDate(event.target.value)}
            />
          </label>
        </div>

        <div
          className="rowActions"
          style={{
            marginTop: 12,
          }}
        >
          <button type="button" className="primaryButton" onClick={applyDates}>
            <Icons.search size={14} />
            تحديث التقرير
          </button>
        </div>
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {availableTabs.map((item) => (
          <button
            type="button"
            key={item.key}
            className={tab === item.key ? "primaryButton" : "softButton"}
            onClick={() => setTab(item.key)}
          >
            {item.label}
          </button>
        ))}
      </div>

      <div style={{ marginTop: 10 }}>
        <ReportExport
          target={reportRef}
          fileName={`Report ${tab} ${from} ${to}`}
          title={`${availableTabs.find((item) => item.key === tab)?.label ?? "تقرير"}`}
          subtitle={`${formatDate(from)} ← ${formatDate(to)}`}
        />
      </div>

      <div ref={reportRef}>
        {tab === "overview" && financialReport && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="صافي المبيعات / الإيرادات"
                value={money(financialReport.profit_loss.revenue, baseCurrency)}
              />

              <Mini
                title="مجمل الربح"
                value={money(
                  financialReport.profit_loss.gross_profit,
                  baseCurrency,
                )}
              />

              <Mini
                title="صافي الربح"
                value={money(
                  financialReport.profit_loss.net_profit,
                  baseCurrency,
                )}
              />

              <Mini
                title="صافي التدفق النقدي"
                value={money(
                  financialReport.cash_flow.net_cash_flow,
                  baseCurrency,
                )}
              />
            </section>

            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ذمم العملاء"
                value={money(
                  financialReport.working_capital.accounts_receivable,
                  baseCurrency,
                )}
              />

              <Mini
                title="ذمم الموردين"
                value={money(
                  financialReport.working_capital.accounts_payable,
                  baseCurrency,
                )}
              />

              <Mini
                title="قيمة المخزون"
                value={money(
                  financialReport.working_capital.inventory_value,
                  baseCurrency,
                )}
              />

              <Mini
                title="الأصول المحاسبية"
                value={money(
                  financialReport.balance_sheet.assets,
                  baseCurrency,
                )}
              />
            </section>

            <div
              className="pageGrid"
              style={{
                marginTop: 14,
              }}
            >
              <section className="panel panelPad">
                <div className="panelHeader">
                  <div>
                    <h2>الربحية</h2>
                    <p>للفترة المختارة</p>
                  </div>
                </div>

                <ReportLines
                  currency={baseCurrency}
                  rows={[
                    ["الإيرادات", financialReport.profit_loss.revenue],
                    [
                      "تكلفة البضاعة المباعة",
                      financialReport.profit_loss.cost_of_goods_sold,
                    ],
                    ["مجمل الربح", financialReport.profit_loss.gross_profit],
                    [
                      "المصاريف التشغيلية",
                      financialReport.profit_loss.operating_expenses,
                    ],
                    ["صافي الربح", financialReport.profit_loss.net_profit],
                  ]}
                />
              </section>

              <section className="panel panelPad">
                <div className="panelHeader">
                  <div>
                    <h2>المركز المالي</h2>
                    <p>كما في {formatDate(to)}</p>
                  </div>
                </div>

                <ReportLines
                  currency={baseCurrency}
                  rows={[
                    ["الأصول", financialReport.balance_sheet.assets],
                    ["الالتزامات", financialReport.balance_sheet.liabilities],
                    [
                      "حقوق الملكية المرحلة",
                      financialReport.balance_sheet.equity_posted,
                    ],
                    [
                      "الأرباح الحالية",
                      financialReport.balance_sheet.current_earnings,
                    ],
                    [
                      "حقوق الملكية مع الأرباح",
                      financialReport.balance_sheet
                        .equity_with_current_earnings,
                    ],
                  ]}
                />
              </section>
            </div>
          </>
        )}

        {tab === "profit" && financialReport && (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>قائمة الأرباح والخسائر</h2>

                <p>
                  {formatDate(from)} → {formatDate(to)}
                </p>
              </div>
            </div>

            <ReportLines
              currency={baseCurrency}
              rows={[
                ["الإيرادات", financialReport.profit_loss.revenue],
                [
                  "تكلفة البضاعة المباعة",
                  -num(financialReport.profit_loss.cost_of_goods_sold),
                ],
                ["مجمل الربح", financialReport.profit_loss.gross_profit],
                [
                  "المصاريف التشغيلية",
                  -num(financialReport.profit_loss.operating_expenses),
                ],
                ["صافي الربح", financialReport.profit_loss.net_profit],
              ]}
              emphasizeLast
            />
          </section>
        )}

        {tab === "balance" && financialReport && (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>الميزانية العمومية</h2>

                <p>كما في {formatDate(to)}</p>
              </div>
            </div>

            <ReportLines
              currency={baseCurrency}
              rows={[
                ["إجمالي الأصول", financialReport.balance_sheet.assets],
                [
                  "إجمالي الالتزامات",
                  financialReport.balance_sheet.liabilities,
                ],
                [
                  "حقوق الملكية المرحلة",
                  financialReport.balance_sheet.equity_posted,
                ],
                [
                  "أرباح الفترة والحالية",
                  financialReport.balance_sheet.current_earnings,
                ],
                [
                  "حقوق الملكية الإجمالية",
                  financialReport.balance_sheet.equity_with_current_earnings,
                ],
              ]}
            />
          </section>
        )}

        {tab === "cash" && financialReport && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="التدفقات الداخلة"
                value={money(financialReport.cash_flow.cash_in, baseCurrency)}
              />

              <Mini
                title="التدفقات الخارجة"
                value={money(financialReport.cash_flow.cash_out, baseCurrency)}
              />

              <Mini
                title="صافي التدفق"
                value={money(
                  financialReport.cash_flow.net_cash_flow,
                  baseCurrency,
                )}
              />
            </section>

            <section
              className="panel panelPad"
              style={{
                marginTop: 14,
              }}
            >
              <ReportLines
                currency={baseCurrency}
                rows={[
                  ["النقد الداخل", financialReport.cash_flow.cash_in],
                  ["النقد الخارج", -num(financialReport.cash_flow.cash_out)],
                  ["صافي حركة النقد", financialReport.cash_flow.net_cash_flow],
                ]}
                emphasizeLast
              />
            </section>
          </>
        )}

        {tab === "receivables" && (
          <AgingTable
            type="customer"
            rows={receivables}
            currency={baseCurrency}
          />
        )}

        {tab === "payables" && (
          <AgingTable type="supplier" rows={payables} currency={baseCurrency} />
        )}

        {tab === "inventory" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="قيمة المخزون"
                value={money(inventoryTotal, baseCurrency)}
              />

              <Mini
                title="عدد الأصناف بالمستودعات"
                value={formatQty(inventoryLines ?? inventory.length)}
              />
            </section>

            <section
              className="panel"
              style={{
                marginTop: 14,
              }}
            >
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>المستودع</th>
                      <th>المنتج</th>
                      <th>SKU</th>
                      <th>موجود</th>
                      <th>محجوز</th>
                      <th>متاح</th>
                      <th>متوسط التكلفة</th>
                      <th>قيمة المخزون</th>
                    </tr>
                  </thead>

                  <tbody>
                    {inventory.map((row) => (
                      <tr key={`${row.warehouse_id}-${row.product_id}`}>
                        <td>{row.warehouse_name}</td>

                        <td>
                          <strong>{row.product_name}</strong>
                        </td>

                        <td>{row.sku || "—"}</td>

                        <td>{formatQty(num(row.on_hand))}</td>

                        <td>{formatQty(num(row.reserved))}</td>

                        <td>{formatQty(num(row.available))}</td>

                        <td>{formatNumber(num(row.average_cost), 4)}</td>

                        <td>
                          <strong>
                            {money(row.stock_value, baseCurrency)}
                          </strong>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

        {tab === "sales" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="صافي المبيعات"
                value={money(totalSales, baseCurrency)}
              />

              <Mini title="عدد الأشهر" value={formatQty(salesMonthly.length)} />
            </section>

            <MonthlySalesTable rows={salesMonthly} currency={baseCurrency} />
          </>
        )}

        {tab === "purchases" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="صافي المشتريات"
                value={money(totalPurchases, baseCurrency)}
              />

              <Mini title="عدد الأشهر" value={formatQty(purchaseMonthly.length)} />
            </section>

            <MonthlyPurchaseTable
              rows={purchaseMonthly}
              currency={baseCurrency}
            />
          </>
        )}

        {tab === "payroll" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="صافي الرواتب"
                value={
                  mixedPayrollCurrencies
                    ? "حسب العملة"
                    : money(totalPayroll, payrollCurrencies[0] ?? baseCurrency)
                }
              />

              <Mini title="عدد المسيرات" value={formatQty(payrollRuns.length)} />
            </section>

            <section
              className="panel"
              style={{
                marginTop: 14,
              }}
            >
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الفترة</th>
                      <th>الحالة</th>
                      <th>الإجمالي</th>
                      <th>الخصومات</th>
                      <th>الصافي</th>
                      <th>المدفوع</th>
                      <th>المتبقي</th>
                    </tr>
                  </thead>

                  <tbody>
                    {payrollRuns.map((run) => (
                      <tr key={run.id}>
                        <td>
                          <strong>{run.period_start}</strong>
                          {" → "}
                          {run.period_end}
                        </td>

                        <td>{payrollStatus(run.status)}</td>

                        <td>{money(run.total_gross, run.currency)}</td>

                        <td>{money(run.total_deductions, run.currency)}</td>

                        <td>
                          <strong>{money(run.total_net, run.currency)}</strong>
                        </td>

                        <td>{money(run.total_paid, run.currency)}</td>

                        <td>
                          {money(
                            Math.max(
                              num(run.total_net) - num(run.total_paid),
                              0,
                            ),
                            run.currency,
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

        {tab === "assets" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="تكلفة الأصول"
                value={
                  mixedAssetCurrencies
                    ? "حسب العملة"
                    : money(assetCost, assetCurrencies[0] ?? baseCurrency)
                }
              />

              <Mini
                title="القيمة الدفترية"
                value={
                  mixedAssetCurrencies
                    ? "حسب العملة"
                    : money(assetBookValue, assetCurrencies[0] ?? baseCurrency)
                }
              />

              <Mini title="عدد الأصول" value={formatQty(assets.length)} />
            </section>

            <section
              className="panel"
              style={{
                marginTop: 14,
              }}
            >
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الأصل</th>
                      <th>التصنيف</th>
                      <th>التكلفة</th>
                      <th>الإهلاك المتراكم</th>
                      <th>القيمة الدفترية</th>
                      <th>إهلاك شهري</th>
                      <th>الحالة</th>
                    </tr>
                  </thead>

                  <tbody>
                    {assets.map((asset) => (
                      <tr key={asset.id}>
                        <td>
                          <strong>{asset.name}</strong>

                          <div className="muted">{asset.asset_number}</div>
                        </td>

                        <td>{asset.category || "—"}</td>

                        <td>{money(asset.purchase_cost, asset.currency)}</td>

                        <td>
                          {money(
                            asset.accumulated_depreciation,
                            asset.currency,
                          )}
                        </td>

                        <td>
                          <strong>
                            {money(asset.book_value, asset.currency)}
                          </strong>
                        </td>

                        <td>
                          {money(asset.monthly_depreciation, asset.currency)}
                        </td>

                        <td>{assetStatus(asset.status)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

        {tab === "team" && team ? (
          <>
            <section className="panel" style={{ marginTop: 14 }}>
              <div className="panelHeader panelPad">
                <div>
                  <h2>المندوبين</h2>
                  <p>صافي مبيعات زبائن كل مندوب بالفترة وعمولتو</p>
                </div>
              </div>
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>المندوب</th>
                      <th>الزبائن</th>
                      <th>المبيعات</th>
                      <th>المرتجعات</th>
                      <th>الصافي</th>
                      <th>المحصّل</th>
                      <th>العمولة</th>
                    </tr>
                  </thead>
                  <tbody>
                    {team.reps.map((rep) => (
                      <tr key={rep.id}>
                        <td>
                          <strong>{rep.full_name}</strong>
                          <div className="muted">
                            {Number(rep.commission_rate)}%
                          </div>
                        </td>
                        <td>{rep.customers}</td>
                        <td>{money(rep.sales, baseCurrency)}</td>
                        <td>{money(rep.returns, baseCurrency)}</td>
                        <td>{money(rep.net_sales, baseCurrency)}</td>
                        <td>{money(rep.collected, baseCurrency)}</td>
                        <td>
                          <strong>{money(rep.commission, baseCurrency)}</strong>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {!team.reps.length ? (
                  <p className="muted panelPad">
                    ما في مندوبين. علّم الموظف «مندوب مبيعات» من صفحة الرواتب
                    وعيّنو للزبائن.
                  </p>
                ) : null}
              </div>
            </section>

            <section className="panel" style={{ marginTop: 14 }}>
              <div className="panelHeader panelPad">
                <div>
                  <h2>السائقين</h2>
                  <p>التوصيلات بالفترة</p>
                </div>
              </div>
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>السائق</th>
                      <th>انسلّمت</th>
                      <th>فشلت</th>
                      <th>بالطريق</th>
                    </tr>
                  </thead>
                  <tbody>
                    {team.drivers.map((driver) => (
                      <tr key={driver.id}>
                        <td>
                          <strong>{driver.full_name}</strong>
                        </td>
                        <td>{driver.delivered}</td>
                        <td>{driver.failed}</td>
                        <td>{driver.open}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {!team.drivers.length ? (
                  <p className="muted panelPad">
                    ما في سائقين. علّم الموظف «سائق» من صفحة الرواتب.
                  </p>
                ) : null}
              </div>
            </section>
          </>
        ) : null}

        {tab === "partners" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="إجمالي رأس المال المدخل"
                value={money(partnerCapital, baseCurrency)}
              />

              <Mini
                title="عدد الشركاء"
                value={formatQty(
                  partners.filter((partner) => partner.active).length,
                )}
              />
            </section>

            <section
              className="panel"
              style={{
                marginTop: 14,
              }}
            >
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الشريك</th>
                      <th>الملكية</th>
                      <th>حصة الربح</th>
                      <th>رأس المال</th>
                      <th>المسحوبات</th>
                      <th>رصيد القرض</th>
                      <th>توزيعات الأرباح</th>
                    </tr>
                  </thead>

                  <tbody>
                    {partners.map((partner) => (
                      <tr key={partner.id}>
                        <td>
                          <strong>{partner.name}</strong>
                        </td>

                        <td>{formatNumber(num(partner.ownership_percent))}%</td>

                        <td>{formatNumber(num(partner.profit_share_percent))}%</td>

                        <td>
                          {money(partner.capital_contributions, baseCurrency)}
                        </td>

                        <td>{money(partner.drawings, baseCurrency)}</td>

                        <td>
                          {money(partner.partner_loan_balance, baseCurrency)}
                        </td>

                        <td>
                          {money(partner.profit_distributions, baseCurrency)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
      </div>
    </div>
  );
}

function AgingTable({
  type,
  rows,
  currency,
}: {
  type: "customer" | "supplier";
  rows: ReceivableAging[] | PayableAging[];
  currency: string;
}) {
  const total = rows.reduce((sum, row) => sum + num(row.total_due), 0);

  return (
    <>
      <section
        className="statsGrid"
        style={{
          marginTop: 14,
        }}
      >
        <Mini
          title={
            type === "customer" ? "إجمالي ذمم العملاء" : "إجمالي ذمم الموردين"
          }
          value={money(total, currency)}
        />

        <Mini
          title={type === "customer" ? "عملاء عليهم رصيد" : "موردين عليهم رصيد"}
          value={formatQty(rows.length)}
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>{type === "customer" ? "العميل" : "المورد"}</th>
                <th>حالي</th>
                <th>1-30</th>
                <th>31-60</th>
                <th>61-90</th>
                <th>أكثر من 90</th>
                <th>الإجمالي</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => {
                const name =
                  type === "customer"
                    ? (row as ReceivableAging).trader_name
                    : (row as PayableAging).supplier_name;

                const id =
                  type === "customer"
                    ? (row as ReceivableAging).trader_id
                    : (row as PayableAging).supplier_id;

                return (
                  <tr key={id}>
                    <td>
                      <strong>{name}</strong>
                    </td>

                    <td>{money(row.current_amount, currency)}</td>

                    <td>{money(row.days_1_30, currency)}</td>

                    <td>{money(row.days_31_60, currency)}</td>

                    <td>{money(row.days_61_90, currency)}</td>

                    <td>{money(row.over_90, currency)}</td>

                    <td>
                      <strong>{money(row.total_due, currency)}</strong>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}

function MonthlySalesTable({
  rows,
  currency,
}: {
  rows: SalesMonthlyReport[];
  currency: string;
}) {
  return (
    <section
      className="panel"
      style={{
        marginTop: 14,
      }}
    >
      <div className="tableWrap">
        <table className="dataTable">
          <thead>
            <tr>
              <th>الشهر</th>
              <th>الفواتير</th>
              <th>إجمالي المبيعات</th>
              <th>المرتجعات</th>
              <th>صافي المبيعات</th>
              <th>المحصل</th>
              <th>المتبقي</th>
            </tr>
          </thead>

          <tbody>
            {rows.map((row) => (
              <tr key={row.month_start}>
                <td>
                  <strong>{row.month_start.slice(0, 7)}</strong>
                </td>

                <td>{formatQty(row.invoice_count)}</td>

                <td>{money(row.gross_sales, currency)}</td>

                <td>{money(row.sales_returns, currency)}</td>

                <td>
                  <strong>{money(row.net_sales, currency)}</strong>
                </td>

                <td>{money(row.collected, currency)}</td>

                <td>{money(row.outstanding, currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function MonthlyPurchaseTable({
  rows,
  currency,
}: {
  rows: PurchaseMonthlyReport[];
  currency: string;
}) {
  return (
    <section
      className="panel"
      style={{
        marginTop: 14,
      }}
    >
      <div className="tableWrap">
        <table className="dataTable">
          <thead>
            <tr>
              <th>الشهر</th>
              <th>الفواتير</th>
              <th>إجمالي المشتريات</th>
              <th>المرتجعات</th>
              <th>صافي المشتريات</th>
              <th>المدفوع</th>
              <th>المتبقي</th>
            </tr>
          </thead>

          <tbody>
            {rows.map((row) => (
              <tr key={row.month_start}>
                <td>
                  <strong>{row.month_start.slice(0, 7)}</strong>
                </td>

                <td>{formatQty(row.invoice_count)}</td>

                <td>{money(row.gross_purchases, currency)}</td>

                <td>{money(row.purchase_returns, currency)}</td>

                <td>
                  <strong>{money(row.net_purchases, currency)}</strong>
                </td>

                <td>{money(row.paid, currency)}</td>

                <td>{money(row.outstanding, currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function ReportLines({
  rows,
  currency,
  emphasizeLast = false,
}: {
  rows: [string, number][];
  currency: string;
  emphasizeLast?: boolean;
}) {
  return (
    <div className="quickList" data-lines>
      {rows.map(([label, value], index) => (
        <div className="quickItem" key={label}>
          <div>
            <strong>{label}</strong>
          </div>

          <div
            className="count"
            style={
              emphasizeLast && index === rows.length - 1
                ? {
                    fontWeight: 800,
                  }
                : undefined
            }
          >
            {money(value, currency)}
          </div>
        </div>
      ))}
    </div>
  );
}

function payrollStatus(status: string) {
  if (status === "draft") {
    return "مسودة";
  }

  if (status === "posted") {
    return "مرحّل";
  }

  if (status === "partial") {
    return "دفع جزئي";
  }

  if (status === "paid") {
    return "مدفوع";
  }

  return "ملغى";
}

function assetStatus(status: string) {
  if (status === "active") {
    return "نشط";
  }

  if (status === "fully_depreciated") {
    return "مستهلك بالكامل";
  }

  return "مستبعد";
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>

      <div className="statValue">{value}</div>
    </div>
  );
}
