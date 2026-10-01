// Part 4: several months + a large random run. A seeded random generator mixes hundreds of operations
// (purchases, receipts, sales and deliveries, quick sales, USD/SYP collections, supplier payments,
// returns, expenses, damage, transfers, reversals) and after every batch checks that the books still agree:
// trial balance, inventory account = stock value, receivables/payables/cash = their screens, no negative
// stock, and monthly P&L adds up to the whole period. Re-run with SEED=123 to reproduce a failure.
import { admin, newUserClient } from "./local-supabase.mjs";

const SEED = Number(process.env.SEED ?? 20261002);
const STEPS = Number(process.env.STEPS ?? 300);
const SYP = 13000;
const u = newUserClient();

let failures = 0;
let unexpected = 0;
const log = (s) => console.log(s);
function ok(label, cond, detail = "") {
  if (!cond) failures++;
  if (!cond || process.env.VERBOSE) log(`   ${cond ? "✅" : "❌"} ${label}${cond ? "" : `  ${detail}`}`);
  return cond;
}
const near = (a, b, tol = 0.05) => Math.abs(Number(a) - Number(b)) <= tol;

// mulberry32: نفس البذرة = نفس العمليات بالضبط.
let state = SEED >>> 0;
function rand() {
  state = (state + 0x6d2b79f5) >>> 0;
  let t = state;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (a, b) => a + Math.floor(rand() * (b - a + 1));
const pickOne = (list) => list[Math.floor(rand() * list.length)];
const round2 = (x) => Math.round(x * 100) / 100;

const dateIn = (monthsAgo, day) => {
  const d = new Date(new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" }) + "T12:00:00Z");
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() - monthsAgo);
  d.setUTCDate(day);
  return d.toISOString().slice(0, 10);
};
const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
const monthStart = (monthsAgo) => dateIn(monthsAgo, 1);
const monthEnd = (monthsAgo) => {
  const d = new Date(monthStart(monthsAgo) + "T12:00:00Z");
  d.setUTCMonth(d.getUTCMonth() + 1);
  d.setUTCDate(0);
  return d.toISOString().slice(0, 10);
};

async function call(label, fn, args, { expectFail = false } = {}) {
  const r = await u.rpc(fn, args);
  if (r.error && !expectFail) {
    unexpected++;
    log(`   ⚠️  ${label}: ${r.error.message}`);
  }
  if (!r.error && expectFail) {
    failures++;
    log(`   ❌ ${label}: كان لازم ينرفض بس انقبل`);
  }
  return r.error ? null : (r.data ?? true);
}

// ---------------------------------------------------------------- setup
log(`0️⃣  تجهيز (البذرة ${SEED}، ${STEPS} عملية)`);
const email = `cycle4${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
await u.auth.signInWithPassword({ email, password: "Passw0rd!x" });
await u.from("companies").insert({ name: "شركة الدورة 4", default_currency: "USD" });
const company = (await u.from("company_members").select("company_id").single()).data.company_id;
const usdBox = (await u.from("cashboxes").select("id").eq("company_id", company).single()).data.id;
const sypBox = (await u.from("cashboxes").insert({ company_id: company, name: "صندوق الليرة", currency: "SYP" }).select("id").single()).data.id;
const wh1 = (await u.from("warehouses").select("id").eq("company_id", company).single()).data.id;
const wh2 = await call("مستودع 2", "create_warehouse", { target_company: company, target_name: "مستودع 2", target_code: null, target_address: null, target_is_default: false });
for (const m of [3, 2, 1, 0]) {
  for (const day of [1, 10, 20, 28]) {
    await u.rpc("set_transaction_rate", { target_company: company, target_currency: "SYP", target_date: dateIn(m, day), target_units_per_base: SYP });
  }
}
await u.rpc("set_transaction_rate", { target_company: company, target_currency: "SYP", target_date: today, target_units_per_base: SYP });

const partner = await call("شريك", "save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "الشريك", target_phone: null, target_ownership_percent: 100, target_profit_share_percent: 100, target_notes: null, target_active: true });
await call("رأس مال قبل 3 أشهر", "record_partner_transaction", { target_company: company, target_partner: partner, target_type: "capital_contribution", target_amount: 200000, target_currency: "USD", target_cashbox: usdBox, target_date: dateIn(3, 2), target_notes: null });

const suppliers = [];
for (const name of ["مصنع نينغبو", "مورد محلي", "وكيل غوانزو"]) {
  suppliers.push((await u.from("suppliers").insert({ company_id: company, name }).select("id").single()).data.id);
}
const traders = [];
for (let i = 1; i <= 8; i++) {
  traders.push((await u.from("traders").insert({ company_id: company, name: `زبون ${i}`, status: "customer" }).select("id").single()).data.id);
}
const products = [];
for (const [name, cost] of [["كبل 2 مم", 18], ["كبل 4 مم", 31], ["لمبة 12 واط", 0.9], ["لمبة 20 واط", 1.4], ["مفتاح", 0.6], ["بريز", 0.85], ["قاطع 16A", 3.2], ["لوحة كهرباء", 22], ["سبوت", 2.7], ["شريط LED", 4.4]]) {
  const id = (await u.from("products").insert({ company_id: company, name, sale_price: round2(cost * 1.35) }).select("id").single()).data.id;
  products.push({ id, cost });
}

// ---------------------------------------------------------------- helpers
async function stockMap() {
  const { data } = await admin.from("inventory_stock").select("warehouse_id, product_id, on_hand, average_cost").eq("company_id", company);
  return data;
}
async function available(product, warehouse = wh1) {
  const rows = await stockMap();
  const onHand = rows.filter((r) => r.product_id === product && r.warehouse_id === warehouse).reduce((s, r) => s + Number(r.on_hand), 0);
  const { data: res } = await admin.from("inventory_reservations").select("quantity").eq("company_id", company).eq("product_id", product).eq("warehouse_id", warehouse).eq("status", "active");
  return onHand - (res ?? []).reduce((s, r) => s + Number(r.quantity), 0);
}
// القاعدة بترجّع 1000 سطر بالطلب كحد أقصى: منجيب صفحة صفحة.
async function fetchAll(build) {
  const rows = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await build().range(from, from + 999);
    if (error) throw error;
    rows.push(...data);
    if (data.length < 1000) return rows;
  }
}
async function gl(filter) {
  const data = await fetchAll(() =>
    filter(admin.from("journal_lines").select("id, base_debit, base_credit, finance_accounts!inner(code, system_key, company_id)").eq("finance_accounts.company_id", company)).order("id"),
  );
  return round2(data.reduce((s, l) => s + Number(l.base_debit) - Number(l.base_credit), 0));
}
const byKey = (key) => gl((q) => q.eq("finance_accounts.system_key", key));

async function buy(date, receiveDate = date) {
  const items = [];
  const chosen = new Set();
  for (let i = 0; i < int(1, 4); i++) chosen.add(pickOne(products));
  for (const p of chosen) items.push({ product_id: p.id, quantity: int(20, 300), unit_cost: round2(p.cost * (0.9 + rand() * 0.2)) });
  const inv = await call("فاتورة شراء", "create_purchase_invoice", { target_company: company, target_supplier: pickOne(suppliers), target_supplier_invoice_number: null, target_invoice_date: date, target_due_date: null, target_notes: null, items_payload: items });
  const invId = typeof inv === "string" ? inv : inv?.invoice_id ?? inv?.id;
  if (!invId) return null;
  const { data: lines } = await admin.from("purchase_invoice_items").select("id, quantity").eq("invoice_id", invId);
  const partial = rand() < 0.2;
  await call("استلام", "receive_purchase_invoice", { target_company: company, target_invoice: invId, target_warehouse: wh1, target_receipt_date: receiveDate, target_notes: null, items_payload: lines.map((l) => ({ purchase_invoice_item_id: l.id, quantity: partial ? Math.max(1, Math.floor(Number(l.quantity) / 2)) : Number(l.quantity) })) });
  return invId;
}

async function paySupplier(date) {
  const { data: open } = await admin.from("purchase_invoices").select("id, supplier_id, balance_due").eq("company_id", company).eq("status", "posted").gt("balance_due", 0).lte("invoice_date", date).limit(20);
  if (!open?.length) return;
  const inv = pickOne(open);
  const amount = round2(Math.min(Number(inv.balance_due), Number(inv.balance_due) * (0.3 + rand() * 0.8)));
  if (amount <= 0) return;
  await call("دفعة مورد", "record_supplier_payment", { target_company: company, target_supplier: inv.supplier_id, target_cashbox: usdBox, target_amount: amount, target_payment_date: date, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: inv.id, amount }] });
}

async function sell() {
  const items = [];
  for (const p of new Set([pickOne(products), pickOne(products), pickOne(products)])) {
    const avail = Math.floor(await available(p.id));
    if (avail < 2) continue;
    items.push({ product_id: p.id, quantity: int(1, Math.min(avail, 60)), sale_unit_price: round2(p.cost * (1.15 + rand() * 0.4)) });
  }
  if (!items.length) return;
  const order = await call("طلبية", "create_sales_order_v2", { target_company: company, target_trader: pickOne(traders), target_notes: null, items_payload: items, target_source_quote: null });
  const orderId = order?.order_id;
  if (!orderId) return;
  const { data: status } = await admin.from("sales_orders").select("status").eq("id", orderId).single();
  if (status.status === "pending_approval") return; // ممكن تنعرض للموافقة (حسم كبير...)
  const { data: lines } = await admin.from("sales_order_items").select("id, quantity").eq("order_id", orderId);
  const partial = rand() < 0.25;
  const first = lines.map((l) => ({ sales_order_item_id: l.id, quantity: partial ? Math.max(1, Math.floor(Number(l.quantity) / 2)) : Number(l.quantity) }));
  if (!(await call("خروج توصيلة", "create_order_delivery", { target_company: company, target_order: orderId, items_payload: first }))) return;
  await call("وصلت", "complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null });
  if (partial) {
    const rest = lines.map((l, i) => ({ sales_order_item_id: l.id, quantity: Number(l.quantity) - first[i].quantity })).filter((x) => x.quantity > 0);
    if (rest.length && (await call("توصيلة 2", "create_order_delivery", { target_company: company, target_order: orderId, items_payload: rest }))) {
      await call("وصلت 2", "complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null });
    }
  }
}

async function quickSale() {
  const p = pickOne(products);
  const avail = Math.floor(await available(p.id));
  if (avail < 1) return;
  const qty = int(1, Math.min(avail, 10));
  const price = round2(p.cost * 1.5);
  const total = round2(qty * price);
  await call("بيع سريع", "quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: p.id, quantity: qty, sale_unit_price: price }], target_cashbox: usdBox, target_paid_amount: total, target_cash_amount: total });
}

async function collect() {
  const { data: open } = await admin.from("sales_invoices").select("id, trader_id, balance_due").eq("company_id", company).eq("status", "posted").gt("balance_due", 0).limit(30);
  if (!open?.length) return;
  const inv = pickOne(open);
  const usd = round2(Math.min(Number(inv.balance_due), Number(inv.balance_due) * (0.2 + rand() * 0.9)));
  if (usd <= 0) return;
  if (rand() < 0.35) {
    await call("قبض ليرة", "record_customer_payment", { target_company: company, target_trader: inv.trader_id, target_cashbox: sypBox, target_amount: round2(usd * SYP), target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv.id, amount: usd }] });
  } else {
    await call("قبض دولار", "record_customer_payment", { target_company: company, target_trader: inv.trader_id, target_cashbox: usdBox, target_amount: usd, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv.id, amount: usd }] });
  }
}

async function salesReturn() {
  const { data: invs } = await admin.from("sales_invoices").select("id").eq("company_id", company).eq("status", "posted").limit(30);
  if (!invs?.length) return;
  const inv = pickOne(invs);
  const { data: lines } = await admin.from("sales_invoice_items").select("id, quantity").eq("invoice_id", inv.id);
  const { data: done } = await admin.from("sales_return_items").select("sales_invoice_item_id, quantity, sales_returns!inner(status)").in("sales_invoice_item_id", lines.map((l) => l.id)).eq("sales_returns.status", "posted");
  const line = pickOne(lines);
  const left = Number(line.quantity) - (done ?? []).filter((d) => d.sales_invoice_item_id === line.id).reduce((s, d) => s + Number(d.quantity), 0);
  if (left < 1) return;
  await call("مرتجع زبون", "create_sales_return", { target_company: company, target_invoice: inv.id, target_warehouse: wh1, target_date: today, target_notes: null, items_payload: [{ sales_invoice_item_id: line.id, quantity: int(1, Math.min(left, 5)) }] });
}

async function expense(date) {
  void date;
  await call("مصروف", "record_expense", { target_company: company, target_cashbox: usdBox, expense_category: pickOne(["rent", "transport", "utilities", "other"]), expense_amount: int(5, 120), expense_notes: null });
}

async function damage() {
  const p = pickOne(products);
  if ((await available(p.id)) < 3) return;
  await call("تالف", "record_damaged_goods", { target_company: company, target_warehouse: wh1, target_product: p.id, target_quantity: 1, target_reason: "كسر" });
}

async function transfer() {
  const p = pickOne(products);
  const from = rand() < 0.7 ? wh1 : wh2;
  const to = from === wh1 ? wh2 : wh1;
  const avail = Math.floor(await available(p.id, from));
  if (avail < 2) return;
  await call("تحويل", "post_inventory_transfer", { target_company: company, target_source_warehouse: from, target_destination_warehouse: to, target_transfer_date: today, target_notes: null, items_payload: [{ product_id: p.id, quantity: int(1, Math.min(avail, 20)) }] });
}

async function reversePayment() {
  const { data: pays } = await admin.from("customer_payments").select("id").eq("company_id", company).eq("status", "posted").limit(20);
  if (!pays?.length) return;
  await call("عكس قبض", "reverse_customer_payment", { target_company: company, target_payment: pickOne(pays).id, target_reason: "اختبار" });
}

// ---------------------------------------------------------------- invariants
// الكمية × الكلفة بالقروش، بأرقام صحيحة (BigInt) ومقرّبة متل Postgres (النص لفوق).
// الحساب العادي بالجافاسكربت بيغلط: 7 × 0.635 = 4.4449999 بدل 4.445.
function rowValueCents(onHand, averageCost) {
  const scaled = (value, digits) => {
    const [whole, frac = ""] = String(value).split(".");
    return BigInt(whole + frac.padEnd(digits, "0").slice(0, digits));
  };
  const product = scaled(onHand, 3) * scaled(averageCost, 4); // بوحدة 10^-7
  const sign = product < 0n ? -1n : 1n;
  const abs = product * sign;
  return Number(sign * ((abs + 50000n) / 100000n));
}

async function invariants(label) {
  let good = true;
  const lines = await fetchAll(() => admin.from("journal_lines").select("id, base_debit, base_credit, journal_entries!inner(company_id)").eq("journal_entries.company_id", company).order("id"));
  good &= ok(`${label}: ميزان المراجعة صفر`, near(lines.reduce((s, l) => s + Number(l.base_debit) - Number(l.base_credit), 0), 0, 0.01));

  const stock = await stockMap();
  good &= ok(`${label}: ما في مخزون سالب`, stock.every((r) => Number(r.on_hand) >= 0));
  // قيمة كل صنف بكل مستودع بالقروش، ومجموعها لازم يساوي حساب المخزون بالضبط.
  const stockValue = stock.reduce((s, r) => s + rowValueCents(r.on_hand, r.average_cost), 0) / 100;
  const invAccount = await byKey("inventory");
  good &= ok(`${label}: حساب المخزون = قيمة البضاعة بالقرش`, near(invAccount, stockValue, 0.001), `${invAccount} مقابل ${stockValue}`);

  const ov = (await u.rpc("get_owner_overview", { target_company: company })).data;
  const ar = await byKey("accounts_receivable");
  const ap = -(await byKey("accounts_payable"));
  good &= ok(`${label}: ديون الزبائن = الحسابات`, near(ov.receivables, ar), `${ov.receivables} مقابل ${ar}`);
  good &= ok(`${label}: ديون الموردين = الحسابات`, near(ov.payables, ap), `${ov.payables} مقابل ${ap}`);

  const { data: invs } = await admin.from("sales_invoices").select("balance_due").eq("company_id", company).eq("status", "posted");
  const due = round2((invs ?? []).reduce((s, i) => s + Number(i.balance_due), 0));
  // الرصيد اللي إلن عنا (مرتجع من فاتورة مدفوعة) بينزل من ديون الزبائن بالحسابات.
  const { data: credits } = await admin.from("customer_payments").select("unallocated_total, base_amount, amount").eq("company_id", company).eq("status", "posted").gt("unallocated_total", 0);
  void credits;
  good &= ok(`${label}: الفواتير المفتوحة ≥ ديون الزبائن بالحسابات`, due + 0.05 >= ar, `${due} مقابل ${ar}`);

  const { data: boxes } = await u.rpc("get_cashbox_balances", { target_company: company });
  const usd = (boxes ?? []).find((b) => b.cashbox_id === usdBox || b.id === usdBox);
  if (usd) {
    const glUsd = await gl((q) => q.eq("finance_accounts.code", "1110"));
    good &= ok(`${label}: صندوق الدولار = الحسابات`, near(usd.balance, glUsd), `${usd.balance} مقابل ${glUsd}`);
  }
  return good;
}

// ---------------------------------------------------------------- months 3,2,1 ago: purchasing history
log("\n1️⃣  تلات أشهر شراء ودفع للموردين (بتواريخ قديمة)");
for (const m of [3, 2, 1]) {
  for (let i = 0; i < 6; i++) await buy(dateIn(m, int(3, 25)));
  for (let i = 0; i < 4; i++) await paySupplier(dateIn(m, 27));
}
await invariants("بعد الأشهر القديمة");

log("\n2️⃣  إقفال الشهر قبل 3 أشهر");
const closeDate = new Date(monthStart(3) + "T12:00:00Z");
const cy = closeDate.getUTCFullYear(), cm = closeDate.getUTCMonth() + 1;
await call("إقفال", "close_finance_month", { target_company: company, target_year: cy, target_month: cm });
await call("فاتورة بتاريخ شهر مقفل", "create_purchase_invoice", { target_company: company, target_supplier: suppliers[0], target_supplier_invoice_number: null, target_invoice_date: dateIn(3, 15), target_due_date: null, target_notes: null, items_payload: [{ product_id: products[0].id, quantity: 1, unit_cost: 1 }] }, { expectFail: true });
await call("دفعة بتاريخ شهر مقفل", "record_partner_transaction", { target_company: company, target_partner: partner, target_type: "capital_contribution", target_amount: 10, target_currency: "USD", target_cashbox: usdBox, target_date: dateIn(3, 20), target_notes: null }, { expectFail: true });

log(`\n3️⃣  ${STEPS} عملية عشوائية (هالشهر)`);
const ops = [
  [sell, 26], [quickSale, 12], [collect, 22], [() => buy(today), 10], [() => paySupplier(today), 8],
  [salesReturn, 6], [() => expense(today), 6], [damage, 3], [transfer, 5], [reversePayment, 2],
];
const weightTotal = ops.reduce((s, [, w]) => s + w, 0);
for (let step = 1; step <= STEPS; step++) {
  let r = rand() * weightTotal;
  const op = ops.find(([, w]) => (r -= w) < 0)[0];
  await op();
  if (process.env.CHECK_EVERY && step % Number(process.env.CHECK_EVERY) === 0 && !(await invariants(`خطوة ${step}`))) {
    log(`   🛑 وقفنا عند الخطوة ${step} (الشركة ${company}) بعد: ${op.name || "عملية"}`);
    process.exit(1);
  }
  if (step % 50 === 0) {
    const good = await invariants(`بعد ${step} عملية`);
    log(`   ${good ? "✅" : "❌"} بعد ${step} عملية: كل الأرصدة متطابقة${good ? "" : " — في فرق"}`);
  }
}

log("\n4️⃣  التقارير على عدة أشهر");
const range = (await u.rpc("get_financial_report", { target_company: company, target_start: monthStart(3), target_end: today })).data;
let sumProfit = 0, sumRevenue = 0;
for (const m of [3, 2, 1, 0]) {
  const r = (await u.rpc("get_financial_report", { target_company: company, target_start: monthStart(m), target_end: m === 0 ? today : monthEnd(m) })).data;
  sumProfit += Number(r.profit_loss.net_profit);
  sumRevenue += Number(r.profit_loss.revenue);
  ok(`الميزانية متوازنة بآخر الشهر ${monthStart(m).slice(0, 7)}`, near(r.balance_sheet.assets, Number(r.balance_sheet.liabilities) + Number(r.balance_sheet.equity_with_current_earnings), 0.05));
}
ok("مجموع أرباح الأشهر = ربح الفترة كلها", near(sumProfit, range.profit_loss.net_profit, 0.05), `${round2(sumProfit)} مقابل ${range.profit_loss.net_profit}`);
ok("مجموع مبيعات الأشهر = مبيعات الفترة", near(sumRevenue, range.profit_loss.revenue, 0.05));
ok("الربح بالتقرير = الربح بالميزانية", near(range.profit_loss.net_profit, range.balance_sheet.current_earnings, 0.05), `${range.profit_loss.net_profit} مقابل ${range.balance_sheet.current_earnings}`);
const finalGood = await invariants("بالآخر");
log(`   ${finalGood ? "✅" : "❌"} بالآخر: كل الأرصدة متطابقة`);

const counts = {};
for (const t of ["purchase_invoices", "sales_invoices", "customer_payments", "supplier_payments", "sales_returns", "journal_entries"]) {
  counts[t] = (await admin.from(t).select("id", { count: "exact", head: true }).eq("company_id", company)).count;
}
log(`   انعمل: ${counts.purchase_invoices} فاتورة شراء، ${counts.sales_invoices} فاتورة بيع، ${counts.customer_payments} قبض، ${counts.supplier_payments} دفعة مورد، ${counts.sales_returns} مرتجع، ${counts.journal_entries} قيد`);
if (unexpected) log(`   ⚠️  ${unexpected} عملية انرفضت بشكل مش متوقع (فوق)`);

log(failures || unexpected ? `\n❌ ${failures} مشكلة، ${unexpected} رفض مش متوقع` : "\n✅ كل الفحوصات نجحت");
process.exit(failures || unexpected ? 1 : 0);
