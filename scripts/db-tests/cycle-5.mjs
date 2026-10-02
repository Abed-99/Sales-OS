// Part 5: security. Uses the company from cycle-2 (full data) as "company A".
// 1) The owner of another company (B) sees none of A's rows in any table.
// 2) A sales employee in A: no costs, purchases, payroll, partners, journals, cash; can't do owner/accounting work.
// 3) A view-only employee in A: can't create or change anything, and can't see balances.
import { admin, newUserClient } from "./local-supabase.mjs";

let failures = 0;
const log = (s) => console.log(s);
function ok(label, cond, detail = "") {
  if (!cond) failures++;
  log(`   ${cond ? "✅" : "❌"} ${label}${cond ? "" : `  ${detail}`}`);
}
async function refused(label, promise) {
  const r = await promise;
  ok(label, !!r.error || (Array.isArray(r.data) && r.data.length === 0) || r.count === 0, JSON.stringify(r.data ?? r).slice(0, 160));
}
async function login(email) {
  const client = newUserClient();
  const { error } = await client.auth.signInWithPassword({ email, password: "Passw0rd!x" });
  if (error) throw error;
  return client;
}

// ---------------------------------------------------------------- setup
const { data: users } = await admin.auth.admin.listUsers({ perPage: 1000 });
const ownerAEmail = users.users.map((x) => x.email).filter((e) => e?.startsWith("cycle2")).sort().pop();
if (!ownerAEmail) throw new Error("شغّل cycle-2 أول");
const ownerA = await login(ownerAEmail);
const ownerAId = users.users.find((x) => x.email === ownerAEmail).id;
const companyA = (await admin.from("companies").select("id").eq("owner_user_id", ownerAId).single()).data.id;
const role = async (name) => (await ownerA.from("company_roles").select("id").eq("company_id", companyA).eq("name", name).single()).data.id;

async function member(prefix, roleName) {
  const email = `${prefix}${Date.now()}@test.local`;
  const { data } = await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
  const r = await ownerA.rpc("assign_company_member_role", { target_company: companyA, target_user: data.user.id, target_role: await role(roleName) });
  if (r.error) throw r.error;
  return login(email);
}
const sales = await member("sales", "مبيعات");
const viewer = await member("viewer", "مشاهدة");

const ownerBEmail = `cycle5${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email: ownerBEmail, password: "Passw0rd!x", email_confirm: true });
const ownerB = await login(ownerBEmail);
await ownerB.from("companies").insert({ name: "شركة غريبة", default_currency: "USD" });

const tables = ["approval_requests", "asset_depreciation_entries", "audit_logs", "cash_transactions", "cashbox_gl_accounts", "cashboxes", "catalog_links", "categories", "company_members", "company_owner_pins", "company_roles", "customer_payment_allocations", "customer_payment_releases", "customer_payments", "deliveries", "delivery_items", "employee_loan_disbursements", "employee_loan_repayments", "employee_loans", "employees", "expenses", "finance_accounts", "finance_exchange_rates", "finance_periods", "finance_trial_balance", "fixed_asset_summary", "fixed_assets", "goods_receipts", "import_shipment_allocations", "import_shipment_costs", "import_shipment_measures", "import_shipments", "inventory_counts", "inventory_reservations", "inventory_summary", "inventory_transfers", "journal_entries", "journal_lines", "owner_overrides", "partner_summary", "partner_transactions", "partners", "payroll_items", "payroll_payments", "payroll_runs", "price_levels", "product_level_prices", "product_serials", "products", "purchase_invoice_item_sources", "purchase_invoice_items", "purchase_invoices", "purchase_order_items", "purchase_orders", "sales_invoice_delivery_links", "sales_invoice_items", "sales_invoices", "sales_orders", "sales_quotes", "sales_return_items", "sales_returns", "supplier_payment_allocations", "supplier_payments", "supplier_price_history", "supplier_prices", "suppliers", "trader_visits", "traders", "warehouses", "warranty_claims", "whatsapp_outbox"];

// ---------------------------------------------------------------- 1. other company
log("1️⃣  صاحب شركة تانية ما بيشوف شي من شركتنا");
let leaked = [];
for (const table of tables) {
  const { count, error } = await ownerB.from(table).select("*", { count: "exact", head: true }).eq("company_id", companyA);
  if (!error && count > 0) leaked.push(`${table}:${count}`);
}
ok(`ولا جدول من ${tables.length} بيبيّن شي`, leaked.length === 0, leaked.join(", "));
const orderIds = (await admin.from("sales_orders").select("id").eq("company_id", companyA)).data.map((r) => r.id);
const { data: soi } = await ownerB.from("sales_order_items").select("id").in("order_id", orderIds.slice(0, 50));
ok("بنود طلبيات شركتنا مخفية", (soi ?? []).length === 0);
const productA = (await admin.from("products").select("id, sale_price").eq("company_id", companyA).limit(1).single()).data;
const upd = await ownerB.from("products").update({ sale_price: 1 }).eq("id", productA.id).select("id");
ok("ما بيقدر يعدّل سعر صنف عنا", !upd.error ? (upd.data ?? []).length === 0 : true);
const stillPrice = (await admin.from("products").select("sale_price").eq("id", productA.id).single()).data.sale_price;
ok("السعر ما تغيّر", Number(stillPrice) === Number(productA.sale_price));
const del = await ownerB.from("traders").delete().eq("company_id", companyA).select("id");
ok("ما بيقدر يحذف زبائننا", !del.error ? (del.data ?? []).length === 0 : true);
const upload = await ownerB.storage.from("product-images").upload(`${companyA}/hack.jpg`, new Blob(["x"], { type: "image/jpeg" }), { contentType: "image/jpeg" });
ok("ما بيقدر يرفع صور لمجلد شركتنا", !!upload.error);

// ---------------------------------------------------------------- 2. sales employee
log("\n2️⃣  موظف المبيعات");
const hidden = ["supplier_prices", "supplier_price_history", "purchase_invoices", "purchase_invoice_items", "supplier_payments", "journal_lines", "journal_entries", "employees", "payroll_items", "payroll_runs", "employee_loans", "partners", "partner_transactions", "expenses", "fixed_assets", "import_shipment_costs", "import_shipment_allocations", "audit_logs", "company_owner_pins"];
const seen = [];
for (const table of hidden) {
  const { count, error } = await sales.from(table).select("*", { count: "exact", head: true }).eq("company_id", companyA);
  if (!error && count > 0) seen.push(`${table}:${count}`);
}
ok(`ما بيشوف الكلفة والمشتريات والرواتب والشركاء والقيود (${hidden.length} جدول)`, seen.length === 0, seen.join(", "));
const { data: cashRows } = await sales.from("cash_transactions").select("type, customer_payment_id").eq("company_id", companyA);
ok("من حركات الصندوق بيشوف قبض الزبائن بس", (cashRows ?? []).every((r) => r.customer_payment_id), JSON.stringify((cashRows ?? []).filter((r) => !r.customer_payment_id).map((r) => r.type)));
const { data: inv } = await sales.from("inventory_summary").select("average_cost, stock_value").eq("company_id", companyA);
ok("بيشوف المخزون بس بلا كلفة", (inv ?? []).length > 0 && inv.every((r) => r.average_cost == null && r.stock_value == null), JSON.stringify(inv?.[0]));
const stockCost = await sales.from("inventory_stock").select("average_cost").eq("company_id", companyA).limit(1);
ok("ما بيقرا كلفة المخزون مباشرة", !!stockCost.error || (stockCost.data ?? []).every((r) => r.average_cost == null));
const quoteCost = await sales.from("sales_quote_items").select("reference_cost_snapshot").limit(1);
ok("ما بيقرا الكلفة المحفوظة بعروض الأسعار", !!quoteCost.error || (quoteCost.data ?? []).every((r) => r.reference_cost_snapshot == null));
const ov = (await sales.rpc("get_owner_overview", { target_company: companyA })).data ?? {};
ok("لوحة الرئيسية بلا صندوق ولا أرباح ولا ديون موردين", ov.cash === undefined && ov.month_profit === undefined && ov.payables === undefined, Object.keys(ov).join(","));
await refused("ما بيشوف التقرير المالي", sales.rpc("get_financial_report", { target_company: companyA, target_start: "2026-01-01", target_end: "2026-12-31" }));
await refused("ما بيشوف أرصدة الصناديق", sales.rpc("get_cashbox_balances", { target_company: companyA }));
const usdBox = (await admin.from("cashboxes").select("id").eq("company_id", companyA).limit(1).single()).data.id;
await refused("ما بيسجّل مصروف", sales.rpc("record_expense", { target_company: companyA, target_cashbox: usdBox, expense_category: "rent", expense_amount: 10, expense_notes: null }));
const supplierA = (await admin.from("suppliers").select("id").eq("company_id", companyA).limit(1).single()).data.id;
await refused("ما بيعمل فاتورة شراء", sales.rpc("create_purchase_invoice", { target_company: companyA, target_supplier: supplierA, target_supplier_invoice_number: null, target_invoice_date: null, target_due_date: null, target_notes: null, items_payload: [{ product_id: productA.id, quantity: 1, unit_cost: 1 }] }));
await refused("ما بيسكّر الشهر", sales.rpc("close_finance_month", { target_company: companyA, target_year: 2020, target_month: 1 }));
await refused("ما بيغيّر صلاحيات حدا", sales.rpc("assign_company_member_role", { target_company: companyA, target_user: users.users[0].id, target_role: await role("المالك") }));
await refused("ما بيحط رمز المالك", sales.rpc("set_owner_pin", { target_company: companyA, target_pin: "1111" }));
const trader = (await admin.from("traders").select("id, credit_limit").eq("company_id", companyA).limit(1).single()).data;
const credit = await sales.from("traders").update({ credit_limit: 999999 }).eq("id", trader.id).select("id");
const creditAfter = (await admin.from("traders").select("credit_limit").eq("id", trader.id).single()).data.credit_limit;
ok("ما بيغيّر سقف دين الزبون", !!credit.error || Number(creditAfter ?? -1) === Number(trader.credit_limit ?? -1));
const price = await sales.from("products").update({ sale_price: 0.01 }).eq("id", productA.id).select("id");
ok("ما بيغيّر سعر البيع", !!price.error || (price.data ?? []).length === 0);

// ---------------------------------------------------------------- 3. view-only
log("\n3️⃣  موظف مشاهدة بس");
await refused("ما بيعمل طلبية", viewer.rpc("create_sales_order_v2", { target_company: companyA, target_trader: trader.id, target_notes: null, items_payload: [{ product_id: productA.id, quantity: 1, sale_unit_price: 5 }], target_source_quote: null }));
await refused("ما بيشوف كشف حساب الزبون", viewer.rpc("get_trader_statement", { target_company: companyA, target_trader: trader.id, target_from: null, target_to: null }));
const addTrader = await viewer.from("traders").insert({ company_id: companyA, name: "زبون من المشاهد" }).select("id");
ok("ما بيضيف زبون", !!addTrader.error);
await refused("ما بيعمل رابط كتالوج", viewer.rpc("save_catalog_link", { target_company: companyA, target_link: null, settings: {} }));
const invoices = await viewer.from("sales_invoices").select("id", { count: "exact", head: true }).eq("company_id", companyA);
ok("ما بيشوف فواتير البيع (مبالغ)", !!invoices.error || invoices.count === 0);
const dash = (await viewer.rpc("get_dashboard_summary", { target_company: companyA })).data ?? {};
ok("الرئيسية بلا مبيعات اليوم ولا الفواتير غير المسددة", dash.today_sales == null && dash.unpaid_invoices == null && dash.open_orders != null, JSON.stringify(dash).slice(0, 160));
const salesDash = (await sales.rpc("get_dashboard_summary", { target_company: companyA })).data ?? {};
ok("موظف المبيعات بيشوف مبيعات اليوم بالرئيسية", salesDash.today_sales != null);

log(failures ? `\n❌ ${failures} مشكلة` : "\n✅ كل الفحوصات نجحت");
process.exit(failures ? 1 : 0);
