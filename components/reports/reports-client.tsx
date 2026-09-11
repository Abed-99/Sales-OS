"use client";

import {
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";

function num(
  value: unknown
) {
  const n =
    Number(value || 0);

  return Number.isFinite(n)
    ? n
    : 0;
}

function money(
  value: unknown,
  currency: string
) {
  return `${num(value).toFixed(
    2
  )} ${currency}`;
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
  | "partners";

export function ReportsClient({
  baseCurrency,
  from,
  to,
  financialReport,
  receivables,
  payables,
  inventory,
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
}: {
  baseCurrency: string;
  from: string;
  to: string;
  financialReport: FinancialReport | null;
  receivables: ReceivableAging[];
  payables: PayableAging[];
  inventory: InventoryValuation[];
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
}) {
  const router =
    useRouter();

  const firstTab: Tab =
    canFinance
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

  const [tab, setTab] =
    useState<Tab>(
      firstTab
    );

  const [startDate, setStartDate] =
    useState(from);

  const [endDate, setEndDate] =
    useState(to);

  function applyDates() {
    if (
      !startDate ||
      !endDate
    ) {
      return;
    }

    const query =
      new URLSearchParams({
        from: startDate,
        to: endDate,
      });

    router.push(
      `/reports?${query.toString()}`
    );
  }
const inventoryTotal =
    inventory.reduce(
      (sum, row) =>
        sum +
        num(
          row.stock_value
        ),
      0
    );

  const totalSales =
    salesMonthly.reduce(
      (sum, row) =>
        sum +
        num(
          row.net_sales
        ),
      0
    );

  const totalPurchases =
    purchaseMonthly.reduce(
      (sum, row) =>
        sum +
        num(
          row.net_purchases
        ),
      0
    );

  const totalPayroll =
    payrollRuns
      .filter(
        (run) =>
          run.status !==
          "cancelled"
      )
      .reduce(
        (sum, row) =>
          sum +
          num(
            row.total_net
          ),
        0
      );

  const assetCost =
    assets.reduce(
      (sum, row) =>
        sum +
        num(
          row.purchase_cost
        ),
      0
    );

  const assetBookValue =
    assets.reduce(
      (sum, row) =>
        sum +
        num(
          row.book_value
        ),
      0
    );

  const partnerCapital =
    partners.reduce(
      (sum, row) =>
        sum +
        num(
          row.capital_contributions
        ),
      0
    );

  const availableTabs =
    useMemo(() => {
      const rows: {
        key: Tab;
        label: string;
      }[] = [];

      if (canFinance) {
        rows.push(
          {
            key: "overview",
            label: "Ø§Ù„Ù…Ù„Ø®Øµ",
          },
          {
            key: "profit",
            label: "Ø§Ù„Ø£Ø±Ø¨Ø§Ø­ ÙˆØ§Ù„Ø®Ø³Ø§Ø¦Ø±",
          },
          {
            key: "balance",
            label: "Ø§Ù„Ù…ÙŠØ²Ø§Ù†ÙŠØ©",
          },
          {
            key: "cash",
            label: "Ø§Ù„ØªØ¯ÙÙ‚ Ø§Ù„Ù†Ù‚Ø¯ÙŠ",
          },
          {
            key: "receivables",
            label: "Ø°Ù…Ù… Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡",
          },
          {
            key: "payables",
            label: "Ø°Ù…Ù… Ø§Ù„Ù…ÙˆØ±Ø¯ÙŠÙ†",
          }
        );
      }

      if (canInventoryCost) {
        rows.push({
          key: "inventory",
          label: "ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…Ø®Ø²ÙˆÙ†",
        });
      }

      if (canSales) {
        rows.push({
          key: "sales",
          label: "Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª",
        });
      }

      if (canPurchases) {
        rows.push({
          key: "purchases",
          label: "Ø§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª",
        });
      }

      if (canPayroll) {
        rows.push({
          key: "payroll",
          label: "Ø§Ù„Ø±ÙˆØ§ØªØ¨",
        });
      }

      if (canAssets) {
        rows.push({
          key: "assets",
          label: "Ø§Ù„Ø£ØµÙˆÙ„",
        });
      }

      if (canPartners) {
        rows.push({
          key: "partners",
          label: "Ø§Ù„Ø´Ø±ÙƒØ§Ø¡",
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
    ]);

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Business Intelligence
          </span>

          <h2>
            Ù…Ø±ÙƒØ² Ø§Ù„ØªÙ‚Ø§Ø±ÙŠØ±
          </h2>

          <p className="muted">
            Ø§Ù„Ø£Ø±Ù‚Ø§Ù… Ø§Ù„Ù…Ø§Ù„ÙŠØ© Ù…Ø£Ø®ÙˆØ°Ø© Ù…Ù† Ø§Ù„Ù‚ÙŠÙˆØ¯ Ø§Ù„Ù…Ø­Ø§Ø³Ø¨ÙŠØ© ÙˆØ§Ù„Ø­Ø±ÙƒØ§Øª Ø§Ù„ÙØ¹Ù„ÙŠØ© Ù„Ù„Ù†Ø¸Ø§Ù….
          </p>
        </div>
      </div>

      <section className="panel panelPad">
        <div className="formGrid">
          <label className="field">
            <span>
              Ù…Ù† ØªØ§Ø±ÙŠØ®
            </span>

            <input
              type="date"
              value={
                startDate
              }
              onChange={(
                event
              ) =>
                setStartDate(
                  event.target
                    .value
                )
              }
            />
          </label>

          <label className="field">
            <span>
              Ø¥Ù„Ù‰ ØªØ§Ø±ÙŠØ®
            </span>

            <input
              type="date"
              value={
                endDate
              }
              onChange={(
                event
              ) =>
                setEndDate(
                  event.target
                    .value
                )
              }
            />
          </label>
        </div>

        <div
          className="rowActions"
          style={{
            marginTop: 12,
          }}
        >
          <button
            type="button"
            className="primaryButton"
            onClick={
              applyDates
            }
          >
            <Icons.search
              size={14}
            />
            ØªØ­Ø¯ÙŠØ« Ø§Ù„ØªÙ‚Ø±ÙŠØ±
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
        {availableTabs.map(
          (item) => (
            <button
              type="button"
              key={
                item.key
              }
              className={
                tab ===
                item.key
                  ? "primaryButton"
                  : "softButton"
              }
              onClick={() =>
                setTab(
                  item.key
                )
              }
            >
              {
                item.label
              }
            </button>
          )
        )}
      </div>

      {tab ===
        "overview" &&
        financialReport && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª / Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯Ø§Øª"
                value={money(
                  financialReport
                    .profit_loss
                    .revenue,
                  baseCurrency
                )}
              />

              <Mini
                title="Ù…Ø¬Ù…Ù„ Ø§Ù„Ø±Ø¨Ø­"
                value={money(
                  financialReport
                    .profit_loss
                    .gross_profit,
                  baseCurrency
                )}
              />

              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„Ø±Ø¨Ø­"
                value={money(
                  financialReport
                    .profit_loss
                    .net_profit,
                  baseCurrency
                )}
              />

              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„ØªØ¯ÙÙ‚ Ø§Ù„Ù†Ù‚Ø¯ÙŠ"
                value={money(
                  financialReport
                    .cash_flow
                    .net_cash_flow,
                  baseCurrency
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
                title="Ø°Ù…Ù… Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡"
                value={money(
                  financialReport
                    .working_capital
                    .accounts_receivable,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø°Ù…Ù… Ø§Ù„Ù…ÙˆØ±Ø¯ÙŠÙ†"
                value={money(
                  financialReport
                    .working_capital
                    .accounts_payable,
                  baseCurrency
                )}
              />

              <Mini
                title="Ù‚ÙŠÙ…Ø© Ø§Ù„Ù…Ø®Ø²ÙˆÙ†"
                value={money(
                  financialReport
                    .working_capital
                    .inventory_value,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø§Ù„Ø£ØµÙˆÙ„ Ø§Ù„Ù…Ø­Ø§Ø³Ø¨ÙŠØ©"
                value={money(
                  financialReport
                    .balance_sheet
                    .assets,
                  baseCurrency
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
                    <h2>
                      Ø§Ù„Ø±Ø¨Ø­ÙŠØ©
                    </h2>
                    <p>
                      Ù„Ù„ÙØªØ±Ø© Ø§Ù„Ù…Ø®ØªØ§Ø±Ø©
                    </p>
                  </div>
                </div>

                <ReportLines
                  currency={
                    baseCurrency
                  }
                  rows={[
                    [
                      "Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯Ø§Øª",
                      financialReport
                        .profit_loss
                        .revenue,
                    ],
                    [
                      "ØªÙƒÙ„ÙØ© Ø§Ù„Ø¨Ø¶Ø§Ø¹Ø© Ø§Ù„Ù…Ø¨Ø§Ø¹Ø©",
                      financialReport
                        .profit_loss
                        .cost_of_goods_sold,
                    ],
                    [
                      "Ù…Ø¬Ù…Ù„ Ø§Ù„Ø±Ø¨Ø­",
                      financialReport
                        .profit_loss
                        .gross_profit,
                    ],
                    [
                      "Ø§Ù„Ù…ØµØ§Ø±ÙŠÙ Ø§Ù„ØªØ´ØºÙŠÙ„ÙŠØ©",
                      financialReport
                        .profit_loss
                        .operating_expenses,
                    ],
                    [
                      "ØµØ§ÙÙŠ Ø§Ù„Ø±Ø¨Ø­",
                      financialReport
                        .profit_loss
                        .net_profit,
                    ],
                  ]}
                />
              </section>

              <section className="panel panelPad">
                <div className="panelHeader">
                  <div>
                    <h2>
                      Ø§Ù„Ù…Ø±ÙƒØ² Ø§Ù„Ù…Ø§Ù„ÙŠ
                    </h2>
                    <p>
                      ÙƒÙ…Ø§ ÙÙŠ{" "}
                      {to}
                    </p>
                  </div>
                </div>

                <ReportLines
                  currency={
                    baseCurrency
                  }
                  rows={[
                    [
                      "Ø§Ù„Ø£ØµÙˆÙ„",
                      financialReport
                        .balance_sheet
                        .assets,
                    ],
                    [
                      "Ø§Ù„Ø§Ù„ØªØ²Ø§Ù…Ø§Øª",
                      financialReport
                        .balance_sheet
                        .liabilities,
                    ],
                    [
                      "Ø­Ù‚ÙˆÙ‚ Ø§Ù„Ù…Ù„ÙƒÙŠØ© Ø§Ù„Ù…Ø±Ø­Ù„Ø©",
                      financialReport
                        .balance_sheet
                        .equity_posted,
                    ],
                    [
                      "Ø§Ù„Ø£Ø±Ø¨Ø§Ø­ Ø§Ù„Ø­Ø§Ù„ÙŠØ©",
                      financialReport
                        .balance_sheet
                        .current_earnings,
                    ],
                    [
                      "Ø­Ù‚ÙˆÙ‚ Ø§Ù„Ù…Ù„ÙƒÙŠØ© Ù…Ø¹ Ø§Ù„Ø£Ø±Ø¨Ø§Ø­",
                      financialReport
                        .balance_sheet
                        .equity_with_current_earnings,
                    ],
                  ]}
                />
              </section>
            </div>
          </>
        )}

      {tab ===
        "profit" &&
        financialReport && (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>
                  Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„Ø£Ø±Ø¨Ø§Ø­ ÙˆØ§Ù„Ø®Ø³Ø§Ø¦Ø±
                </h2>

                <p>
                  {from} â†’{" "}
                  {to}
                </p>
              </div>
            </div>

            <ReportLines
              currency={
                baseCurrency
              }
              rows={[
                [
                  "Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯Ø§Øª",
                  financialReport
                    .profit_loss
                    .revenue,
                ],
                [
                  "ØªÙƒÙ„ÙØ© Ø§Ù„Ø¨Ø¶Ø§Ø¹Ø© Ø§Ù„Ù…Ø¨Ø§Ø¹Ø©",
                  -num(
                    financialReport
                      .profit_loss
                      .cost_of_goods_sold
                  ),
                ],
                [
                  "Ù…Ø¬Ù…Ù„ Ø§Ù„Ø±Ø¨Ø­",
                  financialReport
                    .profit_loss
                    .gross_profit,
                ],
                [
                  "Ø§Ù„Ù…ØµØ§Ø±ÙŠÙ Ø§Ù„ØªØ´ØºÙŠÙ„ÙŠØ©",
                  -num(
                    financialReport
                      .profit_loss
                      .operating_expenses
                  ),
                ],
                [
                  "ØµØ§ÙÙŠ Ø§Ù„Ø±Ø¨Ø­",
                  financialReport
                    .profit_loss
                    .net_profit,
                ],
              ]}
              emphasizeLast
            />
          </section>
        )}

      {tab ===
        "balance" &&
        financialReport && (
          <section
            className="panel panelPad"
            style={{
              marginTop: 14,
            }}
          >
            <div className="panelHeader">
              <div>
                <h2>
                  Ø§Ù„Ù…ÙŠØ²Ø§Ù†ÙŠØ© Ø§Ù„Ø¹Ù…ÙˆÙ…ÙŠØ©
                </h2>

                <p>
                  ÙƒÙ…Ø§ ÙÙŠ{" "}
                  {to}
                </p>
              </div>
            </div>

            <ReportLines
              currency={
                baseCurrency
              }
              rows={[
                [
                  "Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø£ØµÙˆÙ„",
                  financialReport
                    .balance_sheet
                    .assets,
                ],
                [
                  "Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø§Ù„ØªØ²Ø§Ù…Ø§Øª",
                  financialReport
                    .balance_sheet
                    .liabilities,
                ],
                [
                  "Ø­Ù‚ÙˆÙ‚ Ø§Ù„Ù…Ù„ÙƒÙŠØ© Ø§Ù„Ù…Ø±Ø­Ù„Ø©",
                  financialReport
                    .balance_sheet
                    .equity_posted,
                ],
                [
                  "Ø£Ø±Ø¨Ø§Ø­ Ø§Ù„ÙØªØ±Ø© ÙˆØ§Ù„Ø­Ø§Ù„ÙŠØ©",
                  financialReport
                    .balance_sheet
                    .current_earnings,
                ],
                [
                  "Ø­Ù‚ÙˆÙ‚ Ø§Ù„Ù…Ù„ÙƒÙŠØ© Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠØ©",
                  financialReport
                    .balance_sheet
                    .equity_with_current_earnings,
                ],
              ]}
            />
          </section>
        )}

      {tab ===
        "cash" &&
        financialReport && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="Ø§Ù„ØªØ¯ÙÙ‚Ø§Øª Ø§Ù„Ø¯Ø§Ø®Ù„Ø©"
                value={money(
                  financialReport
                    .cash_flow
                    .cash_in,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø§Ù„ØªØ¯ÙÙ‚Ø§Øª Ø§Ù„Ø®Ø§Ø±Ø¬Ø©"
                value={money(
                  financialReport
                    .cash_flow
                    .cash_out,
                  baseCurrency
                )}
              />

              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„ØªØ¯ÙÙ‚"
                value={money(
                  financialReport
                    .cash_flow
                    .net_cash_flow,
                  baseCurrency
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
                currency={
                  baseCurrency
                }
                rows={[
                  [
                    "Ø§Ù„Ù†Ù‚Ø¯ Ø§Ù„Ø¯Ø§Ø®Ù„",
                    financialReport
                      .cash_flow
                      .cash_in,
                  ],
                  [
                    "Ø§Ù„Ù†Ù‚Ø¯ Ø§Ù„Ø®Ø§Ø±Ø¬",
                    -num(
                      financialReport
                        .cash_flow
                        .cash_out
                    ),
                  ],
                  [
                    "ØµØ§ÙÙŠ Ø­Ø±ÙƒØ© Ø§Ù„Ù†Ù‚Ø¯",
                    financialReport
                      .cash_flow
                      .net_cash_flow,
                  ],
                ]}
                emphasizeLast
              />
            </section>
          </>
        )}

      {tab ===
        "receivables" && (
          <AgingTable
            type="customer"
            rows={
              receivables
            }
            currency={
              baseCurrency
            }
          />
        )}

      {tab ===
        "payables" && (
          <AgingTable
            type="supplier"
            rows={
              payables
            }
            currency={
              baseCurrency
            }
          />
        )}

      {tab ===
        "inventory" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="Ù‚ÙŠÙ…Ø© Ø§Ù„Ù…Ø®Ø²ÙˆÙ†"
                value={money(
                  inventoryTotal,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ø£ØµÙ†Ø§Ù Ø¨Ø§Ù„Ù…Ø³ØªÙˆØ¯Ø¹Ø§Øª"
                value={String(
                  inventory.length
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
                      <th>
                        Ø§Ù„Ù…Ø³ØªÙˆØ¯Ø¹
                      </th>
                      <th>
                        Ø§Ù„Ù…Ù†ØªØ¬
                      </th>
                      <th>
                        SKU
                      </th>
                      <th>
                        Ù…ÙˆØ¬ÙˆØ¯
                      </th>
                      <th>
                        Ù…Ø­Ø¬ÙˆØ²
                      </th>
                      <th>
                        Ù…ØªØ§Ø­
                      </th>
                      <th>
                        Ù…ØªÙˆØ³Ø· Ø§Ù„ØªÙƒÙ„ÙØ©
                      </th>
                      <th>
                        Ù‚ÙŠÙ…Ø© Ø§Ù„Ù…Ø®Ø²ÙˆÙ†
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {inventory.map(
                      (row) => (
                        <tr
                          key={`${row.warehouse_id}-${row.product_id}`}
                        >
                          <td>
                            {
                              row.warehouse_name
                            }
                          </td>

                          <td>
                            <strong>
                              {
                                row.product_name
                              }
                            </strong>
                          </td>

                          <td>
                            {row.sku ||
                              "â€”"}
                          </td>

                          <td>
                            {num(
                              row.on_hand
                            ).toFixed(
                              3
                            )}
                          </td>

                          <td>
                            {num(
                              row.reserved
                            ).toFixed(
                              3
                            )}
                          </td>

                          <td>
                            {num(
                              row.available
                            ).toFixed(
                              3
                            )}
                          </td>

                          <td>
                            {num(
                              row.average_cost
                            ).toFixed(
                              4
                            )}
                          </td>

                          <td>
                            <strong>
                              {money(
                                row.stock_value,
                                baseCurrency
                              )}
                            </strong>
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

      {tab ===
        "sales" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª"
                value={money(
                  totalSales,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ø£Ø´Ù‡Ø±"
                value={String(
                  salesMonthly.length
                )}
              />
            </section>

            <MonthlySalesTable
              rows={
                salesMonthly
              }
              currency={
                baseCurrency
              }
            />
          </>
        )}

      {tab ===
        "purchases" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª"
                value={money(
                  totalPurchases,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ø£Ø´Ù‡Ø±"
                value={String(
                  purchaseMonthly.length
                )}
              />
            </section>

            <MonthlyPurchaseTable
              rows={
                purchaseMonthly
              }
              currency={
                baseCurrency
              }
            />
          </>
        )}

      {tab ===
        "payroll" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ØµØ§ÙÙŠ Ø§Ù„Ø±ÙˆØ§ØªØ¨"
                value={money(
                  totalPayroll,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ù…Ø³ÙŠØ±Ø§Øª"
                value={String(
                  payrollRuns.length
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
                      <th>
                        Ø§Ù„ÙØªØ±Ø©
                      </th>
                      <th>
                        Ø§Ù„Ø­Ø§Ù„Ø©
                      </th>
                      <th>
                        Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ
                      </th>
                      <th>
                        Ø§Ù„Ø®ØµÙˆÙ…Ø§Øª
                      </th>
                      <th>
                        Ø§Ù„ØµØ§ÙÙŠ
                      </th>
                      <th>
                        Ø§Ù„Ù…Ø¯ÙÙˆØ¹
                      </th>
                      <th>
                        Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {payrollRuns.map(
                      (run) => (
                        <tr
                          key={
                            run.id
                          }
                        >
                          <td>
                            <strong>
                              {
                                run.period_start
                              }
                            </strong>
                            {" â†’ "}
                            {
                              run.period_end
                            }
                          </td>

                          <td>
                            {
                              payrollStatus(
                                run.status
                              )
                            }
                          </td>

                          <td>
                            {money(
                              run.total_gross,
                              run.currency
                            )}
                          </td>

                          <td>
                            {money(
                              run.total_deductions,
                              run.currency
                            )}
                          </td>

                          <td>
                            <strong>
                              {money(
                                run.total_net,
                                run.currency
                              )}
                            </strong>
                          </td>

                          <td>
                            {money(
                              run.total_paid,
                              run.currency
                            )}
                          </td>

                          <td>
                            {money(
                              Math.max(
                                num(
                                  run.total_net
                                ) -
                                  num(
                                    run.total_paid
                                  ),
                                0
                              ),
                              run.currency
                            )}
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

      {tab ===
        "assets" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="ØªÙƒÙ„ÙØ© Ø§Ù„Ø£ØµÙˆÙ„"
                value={money(
                  assetCost,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø§Ù„Ù‚ÙŠÙ…Ø© Ø§Ù„Ø¯ÙØªØ±ÙŠØ©"
                value={money(
                  assetBookValue,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ø£ØµÙˆÙ„"
                value={String(
                  assets.length
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
                      <th>
                        Ø§Ù„Ø£ØµÙ„
                      </th>
                      <th>
                        Ø§Ù„ØªØµÙ†ÙŠÙ
                      </th>
                      <th>
                        Ø§Ù„ØªÙƒÙ„ÙØ©
                      </th>
                      <th>
                        Ø§Ù„Ø¥Ù‡Ù„Ø§Ùƒ Ø§Ù„Ù…ØªØ±Ø§ÙƒÙ…
                      </th>
                      <th>
                        Ø§Ù„Ù‚ÙŠÙ…Ø© Ø§Ù„Ø¯ÙØªØ±ÙŠØ©
                      </th>
                      <th>
                        Ø¥Ù‡Ù„Ø§Ùƒ Ø´Ù‡Ø±ÙŠ
                      </th>
                      <th>
                        Ø§Ù„Ø­Ø§Ù„Ø©
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {assets.map(
                      (asset) => (
                        <tr
                          key={
                            asset.id
                          }
                        >
                          <td>
                            <strong>
                              {
                                asset.name
                              }
                            </strong>

                            <div className="muted">
                              {
                                asset.asset_number
                              }
                            </div>
                          </td>

                          <td>
                            {asset.category ||
                              "â€”"}
                          </td>

                          <td>
                            {money(
                              asset.purchase_cost,
                              asset.currency
                            )}
                          </td>

                          <td>
                            {money(
                              asset.accumulated_depreciation,
                              asset.currency
                            )}
                          </td>

                          <td>
                            <strong>
                              {money(
                                asset.book_value,
                                asset.currency
                              )}
                            </strong>
                          </td>

                          <td>
                            {money(
                              asset.monthly_depreciation,
                              asset.currency
                            )}
                          </td>

                          <td>
                            {assetStatus(
                              asset.status
                            )}
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}

      {tab ===
        "partners" && (
          <>
            <section
              className="statsGrid"
              style={{
                marginTop: 14,
              }}
            >
              <Mini
                title="Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø±Ø£Ø³ Ø§Ù„Ù…Ø§Ù„ Ø§Ù„Ù…Ø¯Ø®Ù„"
                value={money(
                  partnerCapital,
                  baseCurrency
                )}
              />

              <Mini
                title="Ø¹Ø¯Ø¯ Ø§Ù„Ø´Ø±ÙƒØ§Ø¡"
                value={String(
                  partners.filter(
                    (partner) =>
                      partner.active
                  ).length
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
                      <th>
                        Ø§Ù„Ø´Ø±ÙŠÙƒ
                      </th>
                      <th>
                        Ø§Ù„Ù…Ù„ÙƒÙŠØ©
                      </th>
                      <th>
                        Ø­ØµØ© Ø§Ù„Ø±Ø¨Ø­
                      </th>
                      <th>
                        Ø±Ø£Ø³ Ø§Ù„Ù…Ø§Ù„
                      </th>
                      <th>
                        Ø§Ù„Ù…Ø³Ø­ÙˆØ¨Ø§Øª
                      </th>
                      <th>
                        Ø±ØµÙŠØ¯ Ø§Ù„Ù‚Ø±Ø¶
                      </th>
                      <th>
                        ØªÙˆØ²ÙŠØ¹Ø§Øª Ø§Ù„Ø£Ø±Ø¨Ø§Ø­
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {partners.map(
                      (partner) => (
                        <tr
                          key={
                            partner.id
                          }
                        >
                          <td>
                            <strong>
                              {
                                partner.name
                              }
                            </strong>
                          </td>

                          <td>
                            {num(
                              partner.ownership_percent
                            ).toFixed(
                              2
                            )}
                            %
                          </td>

                          <td>
                            {num(
                              partner.profit_share_percent
                            ).toFixed(
                              2
                            )}
                            %
                          </td>

                          <td>
                            {money(
                              partner.capital_contributions,
                              baseCurrency
                            )}
                          </td>

                          <td>
                            {money(
                              partner.drawings,
                              baseCurrency
                            )}
                          </td>

                          <td>
                            {money(
                              partner.partner_loan_balance,
                              baseCurrency
                            )}
                          </td>

                          <td>
                            {money(
                              partner.profit_distributions,
                              baseCurrency
                            )}
                          </td>
                        </tr>
                      )
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
    </div>
  );
}

function AgingTable({
  type,
  rows,
  currency,
}: {
  type:
    | "customer"
    | "supplier";
  rows:
    | ReceivableAging[]
    | PayableAging[];
  currency: string;
}) {
  const total =
    rows.reduce(
      (sum, row) =>
        sum +
        num(
          row.total_due
        ),
      0
    );

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
            type ===
            "customer"
              ? "Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø°Ù…Ù… Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡"
              : "Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø°Ù…Ù… Ø§Ù„Ù…ÙˆØ±Ø¯ÙŠÙ†"
          }
          value={money(
            total,
            currency
          )}
        />

        <Mini
          title={
            type ===
            "customer"
              ? "Ø¹Ù…Ù„Ø§Ø¡ Ø¹Ù„ÙŠÙ‡Ù… Ø±ØµÙŠØ¯"
              : "Ù…ÙˆØ±Ø¯ÙŠÙ† Ø¹Ù„ÙŠÙ‡Ù… Ø±ØµÙŠØ¯"
          }
          value={String(
            rows.length
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
                <th>
                  {type ===
                  "customer"
                    ? "Ø§Ù„Ø¹Ù…ÙŠÙ„"
                    : "Ø§Ù„Ù…ÙˆØ±Ø¯"}
                </th>
                <th>
                  Ø­Ø§Ù„ÙŠ
                </th>
                <th>
                  1-30
                </th>
                <th>
                  31-60
                </th>
                <th>
                  61-90
                </th>
                <th>
                  Ø£ÙƒØ«Ø± Ù…Ù† 90
                </th>
                <th>
                  Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ
                </th>
              </tr>
            </thead>

            <tbody>
              {rows.map(
                (row) => {
                  const name =
                    type ===
                    "customer"
                      ? (
                          row as ReceivableAging
                        )
                          .trader_name
                      : (
                          row as PayableAging
                        )
                          .supplier_name;

                  const id =
                    type ===
                    "customer"
                      ? (
                          row as ReceivableAging
                        )
                          .trader_id
                      : (
                          row as PayableAging
                        )
                          .supplier_id;

                  return (
                    <tr
                      key={
                        id
                      }
                    >
                      <td>
                        <strong>
                          {
                            name
                          }
                        </strong>
                      </td>

                      <td>
                        {money(
                          row.current_amount,
                          currency
                        )}
                      </td>

                      <td>
                        {money(
                          row.days_1_30,
                          currency
                        )}
                      </td>

                      <td>
                        {money(
                          row.days_31_60,
                          currency
                        )}
                      </td>

                      <td>
                        {money(
                          row.days_61_90,
                          currency
                        )}
                      </td>

                      <td>
                        {money(
                          row.over_90,
                          currency
                        )}
                      </td>

                      <td>
                        <strong>
                          {money(
                            row.total_due,
                            currency
                          )}
                        </strong>
                      </td>
                    </tr>
                  );
                }
              )}
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
              <th>
                Ø§Ù„Ø´Ù‡Ø±
              </th>
              <th>
                Ø§Ù„ÙÙˆØ§ØªÙŠØ±
              </th>
              <th>
                Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
              </th>
              <th>
                Ø§Ù„Ù…Ø±ØªØ¬Ø¹Ø§Øª
              </th>
              <th>
                ØµØ§ÙÙŠ Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
              </th>
              <th>
                Ø§Ù„Ù…Ø­ØµÙ„
              </th>
              <th>
                Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ
              </th>
            </tr>
          </thead>

          <tbody>
            {rows.map(
              (row) => (
                <tr
                  key={
                    row.month_start
                  }
                >
                  <td>
                    <strong>
                      {row.month_start.slice(
                        0,
                        7
                      )}
                    </strong>
                  </td>

                  <td>
                    {
                      row.invoice_count
                    }
                  </td>

                  <td>
                    {money(
                      row.gross_sales,
                      currency
                    )}
                  </td>

                  <td>
                    {money(
                      row.sales_returns,
                      currency
                    )}
                  </td>

                  <td>
                    <strong>
                      {money(
                        row.net_sales,
                        currency
                      )}
                    </strong>
                  </td>

                  <td>
                    {money(
                      row.collected,
                      currency
                    )}
                  </td>

                  <td>
                    {money(
                      row.outstanding,
                      currency
                    )}
                  </td>
                </tr>
              )
            )}
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
              <th>
                Ø§Ù„Ø´Ù‡Ø±
              </th>
              <th>
                Ø§Ù„ÙÙˆØ§ØªÙŠØ±
              </th>
              <th>
                Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª
              </th>
              <th>
                Ø§Ù„Ù…Ø±ØªØ¬Ø¹Ø§Øª
              </th>
              <th>
                ØµØ§ÙÙŠ Ø§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª
              </th>
              <th>
                Ø§Ù„Ù…Ø¯ÙÙˆØ¹
              </th>
              <th>
                Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ
              </th>
            </tr>
          </thead>

          <tbody>
            {rows.map(
              (row) => (
                <tr
                  key={
                    row.month_start
                  }
                >
                  <td>
                    <strong>
                      {row.month_start.slice(
                        0,
                        7
                      )}
                    </strong>
                  </td>

                  <td>
                    {
                      row.invoice_count
                    }
                  </td>

                  <td>
                    {money(
                      row.gross_purchases,
                      currency
                    )}
                  </td>

                  <td>
                    {money(
                      row.purchase_returns,
                      currency
                    )}
                  </td>

                  <td>
                    <strong>
                      {money(
                        row.net_purchases,
                        currency
                      )}
                    </strong>
                  </td>

                  <td>
                    {money(
                      row.paid,
                      currency
                    )}
                  </td>

                  <td>
                    {money(
                      row.outstanding,
                      currency
                    )}
                  </td>
                </tr>
              )
            )}
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
  rows: [
    string,
    number
  ][];
  currency: string;
  emphasizeLast?: boolean;
}) {
  return (
    <div className="quickList">
      {rows.map(
        (
          [
            label,
            value,
          ],
          index
        ) => (
          <div
            className="quickItem"
            key={
              label
            }
          >
            <div>
              <strong>
                {
                  label
                }
              </strong>
            </div>

            <div
              className="count"
              style={
                emphasizeLast &&
                index ===
                  rows.length -
                    1
                  ? {
                      fontWeight:
                        800,
                    }
                  : undefined
              }
            >
              {money(
                value,
                currency
              )}
            </div>
          </div>
        )
      )}
    </div>
  );
}

function payrollStatus(
  status: string
) {
  if (
    status === "draft"
  ) {
    return "Ù…Ø³ÙˆØ¯Ø©";
  }

  if (
    status === "posted"
  ) {
    return "Ù…Ø±Ø­Ù‘Ù„";
  }

  if (
    status === "partial"
  ) {
    return "Ø¯ÙØ¹ Ø¬Ø²Ø¦ÙŠ";
  }

  if (
    status === "paid"
  ) {
    return "Ù…Ø¯ÙÙˆØ¹";
  }

  return "Ù…Ù„ØºÙ‰";
}

function assetStatus(
  status: string
) {
  if (
    status === "active"
  ) {
    return "Ù†Ø´Ø·";
  }

  if (
    status ===
    "fully_depreciated"
  ) {
    return "Ù…Ø³ØªÙ‡Ù„Ùƒ Ø¨Ø§Ù„ÙƒØ§Ù…Ù„";
  }

  return "Ù…Ø³ØªØ¨Ø¹Ø¯";
}

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {title}
      </div>

      <div className="statValue">
        {value}
      </div>
    </div>
  );
}
