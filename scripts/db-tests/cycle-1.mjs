// Full business cycle through the same RPCs the app uses, checking stock, journals and balances at each step.
import { admin, newUserClient } from "./local-supabase.mjs";

const u = newUserClient();
const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
const SYP_PER_USD = 13000;

let failures = 0;
const log = (s) => console.log(s);
function must(label, r) {
  if (r.error) {
    failures++;
    log(`   ❌ ${label}: ${r.error.message}`);
    return null;
  }
  return r.data;
}
function check(label, actual, expected) {
  const ok = Math.abs(Number(actual) - Number(expected)) < 0.005;
  if (!ok) failures++;
  log(`   ${ok ? "✅" : "❌"} ${label}: ${actual}${ok ? "" : `  (المتوقع ${expected})`}`);
}

let company, seenEntries = new Set();
async function journals(title) {
  const { data } = await admin
    .from("journal_entries")
    .select("id, source_type, description, journal_lines(debit, credit, finance_accounts(code, name))")
    .eq("company_id", company)
    .order("created_at");
  const fresh = (data ?? []).filter((e) => !seenEntries.has(e.id));
  fresh.forEach((e) => seenEntries.add(e.id));
  if (!fresh.length) { log(`   (ما انعمل قيد)`); return; }
  for (const e of fresh) {
    const d = e.journal_lines.reduce((s, l) => s + Number(l.debit), 0);
    const c = e.journal_lines.reduce((s, l) => s + Number(l.credit), 0);
    if (Math.abs(d - c) > 0.005) failures++;
    log(`   📒 قيد (${e.source_type}) ${Math.abs(d - c) < 0.005 ? "متوازن" : "❌ غير متوازن"}:`);
    for (const l of e.journal_lines) {
      const side = Number(l.debit) > 0 ? `مدين ${Number(l.debit)}` : `دائن ${Number(l.credit)}`;
      log(`        ${side.padEnd(12)} ${l.finance_accounts.code} ${l.finance_accounts.name}`);
    }
  }
}
async function accountBalance(code) {
  const { data } = await admin
    .from("journal_lines")
    .select("base_debit, base_credit, finance_accounts!inner(code, company_id), journal_entries!inner(status)")
    .eq("finance_accounts.code", code)
    .eq("finance_accounts.company_id", company)
    .eq("journal_entries.status", "posted");
  return Math.round((data ?? []).reduce((s, l) => s + Number(l.base_debit) - Number(l.base_credit), 0) * 100) / 100;
}
async function stock(productId) {
  const { data } = await admin.from("inventory_stock").select("on_hand, average_cost").eq("product_id", productId).maybeSingle();
  return data ?? { on_hand: 0, average_cost: 0 };
}

// ---------------------------------------------------------------- 0. setup
log("\n0️⃣  تجهيز الشركة");
const email = `cycle${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
await u.auth.signInWithPassword({ email, password: "Passw0rd!x" });
must("إنشاء الشركة", await u.from("companies").insert({ name: "شركة الدورة الكاملة", default_currency: "USD" }));
company = (await u.from("company_members").select("company_id").single()).data.company_id;
const usdBox = (await u.from("cashboxes").select("id, currency").eq("company_id", company).single()).data.id;
const warehouse = (await u.from("warehouses").select("id").eq("company_id", company).single()).data.id;
const sypBox = must("صندوق ليرة", await u.from("cashboxes").insert({ company_id: company, name: "صندوق الليرة", currency: "SYP" }).select("id").single())?.id;
must("سعر الصرف", await u.rpc("save_finance_exchange_rate", { target_company: company, target_currency: "SYP", target_date: today, target_rate: 1 / SYP_PER_USD, target_notes: null }));
log("   صندوق دولار + صندوق ليرة + مستودع + سعر صرف 13000");

log("\n1️⃣  المالك حط 1000$ رأس مال بالصندوق");
must("إيداع", await u.rpc("record_cash_movement", { target_company: company, target_cashbox: usdBox, movement_type: "adjustment_in", movement_amount: 1000, movement_notes: "رأس مال" }));
await journals();

// ---------------------------------------------------------------- purchases
const supplier = (await u.from("suppliers").insert({ company_id: company, name: "مصنع قوانغتشو" }).select("id").single()).data.id;
const cable = (await u.from("products").insert({ company_id: company, name: "كبل 2.5", sale_price: 10 }).select("id").single()).data.id;
const bulb = (await u.from("products").insert({ company_id: company, name: "لمبة LED", sale_price: 3 }).select("id").single()).data.id;

log("\n2️⃣  فاتورة شراء: 100 كبل × 4$ + 200 لمبة × 1$ = 600$");
const pinv = must("فاتورة الشراء", await u.rpc("create_purchase_invoice", { target_company: company, target_supplier: supplier, target_supplier_invoice_number: "GZ-001", target_invoice_date: today, target_due_date: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 100, unit_cost: 4 }, { product_id: bulb, quantity: 200, unit_cost: 1 }] }));
const pinvId = typeof pinv === "string" ? pinv : pinv?.invoice_id ?? pinv?.id;
await journals();
check("المخزون قبل الاستلام (كبل)", (await stock(cable)).on_hand, 0);

log("\n3️⃣  استلام البضاعة بالمستودع");
const pitems = (await admin.from("purchase_invoice_items").select("id, quantity").eq("invoice_id", pinvId)).data;
must("الاستلام", await u.rpc("receive_purchase_invoice", { target_company: company, target_invoice: pinvId, target_warehouse: warehouse, target_receipt_date: today, target_notes: null, items_payload: pitems.map((i) => ({ purchase_invoice_item_id: i.id, quantity: Number(i.quantity) })) }));
await journals();
check("كبل بالمستودع", (await stock(cable)).on_hand, 100);
check("كلفة الكبل", (await stock(cable)).average_cost, 4);
check("رصيد حساب المخزون", await accountBalance("1300"), 600);

log("\n4️⃣  دفعنا للمورد 600$");
must("دفعة المورد", await u.rpc("record_supplier_payment", { target_company: company, target_supplier: supplier, target_cashbox: usdBox, target_amount: 600, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: pinvId, amount: 600 }] }));
await journals();
check("ديون المورد (2100)", -(await accountBalance("2100")), 0);
check("الصندوق (1110)", await accountBalance("1110"), 400);

// ---------------------------------------------------------------- sales
const trader = (await u.from("traders").insert({ company_id: company, name: "محل النور - الحميدية" }).select("id").single()).data.id;
log("\n5️⃣  طلبية: 30 كبل × 10$ + 50 لمبة × 3$ = 450$");
const order = must("الطلبية", await u.rpc("create_sales_order_v2", { target_company: company, target_trader: trader, target_notes: null, items_payload: [{ product_id: cable, quantity: 30, sale_unit_price: 10 }, { product_id: bulb, quantity: 50, sale_unit_price: 3 }], target_source_quote: null }));
const orderId = order?.order_id;
const o1 = (await admin.from("sales_orders").select("status").eq("id", orderId).single()).data;
log(`   حالة الطلبية: ${o1.status}`);
await journals();

log("\n6️⃣  توصيل جزئي: 20 كبل + 50 لمبة");
const soItems = (await admin.from("sales_order_items").select("id, product_id").eq("order_id", orderId)).data;
const itemOf = (p) => soItems.find((i) => i.product_id === p).id;
must("خروج التوصيلة 1", await u.rpc("create_order_delivery", { target_company: company, target_order: orderId, items_payload: [{ sales_order_item_id: itemOf(cable), quantity: 20 }, { sales_order_item_id: itemOf(bulb), quantity: 50 }] }));
must("وصلت التوصيلة 1", await u.rpc("complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null }));
await journals();
check("كبل بالمستودع بعد التوصيلة", (await stock(cable)).on_hand, 80);

log("\n7️⃣  توصيل الباقي: 10 كبل");
must("خروج التوصيلة 2", await u.rpc("create_order_delivery", { target_company: company, target_order: orderId, items_payload: [{ sales_order_item_id: itemOf(cable), quantity: 10 }] }));
must("وصلت التوصيلة 2", await u.rpc("complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null }));
await journals();
const invoices = (await admin.from("sales_invoices").select("id, total, balance_due, status").eq("order_id", orderId).order("created_at")).data;
log(`   فواتير البيع: ${invoices.map((i) => `${i.total}$ (${i.status})`).join(" + ")}`);
check("مجموع الفواتير", invoices.reduce((s, i) => s + Number(i.total), 0), 450);
check("ديون الزبون (1200)", await accountBalance("1200"), 450);

log("\n8️⃣  الزبون دفع 200$ كاش");
must("قبض دولار", await u.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: usdBox, target_amount: 200, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: invoices[0].id, amount: 200 }] }));
await journals();

log(`\n9️⃣  الزبون دفع 150$ بالليرة = ${150 * SYP_PER_USD} ل.س بصندوق الليرة`);
must("قبض ليرة", await u.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: sypBox, target_amount: 150 * SYP_PER_USD, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: invoices[0].id, amount: 150 }] }));
await journals();
const inv1 = (await admin.from("sales_invoices").select("balance_due").eq("id", invoices[0].id).single()).data;
check("الباقي على الفاتورة الأولى", inv1.balance_due, invoices[0].total - 350);
check("ديون الزبون (1200)", await accountBalance("1200"), 100);

log("\n🔟  مرتجع: الزبون رجّع 5 كبل من الفاتورة التانية");
const siItems = (await admin.from("sales_invoice_items").select("id, product_id").eq("invoice_id", invoices[invoices.length - 1].id)).data;
must("المرتجع", await u.rpc("create_sales_return", { target_company: company, target_invoice: invoices[invoices.length - 1].id, target_warehouse: warehouse, target_date: today, target_notes: null, items_payload: [{ sales_invoice_item_id: siItems.find((i) => i.product_id === cable).id, quantity: 5 }] }));
await journals();
check("كبل بالمستودع بعد المرتجع", (await stock(cable)).on_hand, 75);

log("\n1️⃣1️⃣  مصروف: إيجار 30$");
must("المصروف", await u.rpc("record_expense", { target_company: company, target_cashbox: usdBox, expense_category: "rent", expense_amount: 30, expense_notes: "إيجار" }));
await journals();

// ---------------------------------------------------------------- final
log("\n📊 الفحص النهائي");
check("كبل بالمستودع", (await stock(cable)).on_hand, 75);
check("لمبات بالمستودع", (await stock(bulb)).on_hand, 150);
check("رصيد حساب المخزون = قيمة البضاعة (75×4 + 150×1)", await accountBalance("1300"), 450);
check("الصندوق دولار (1000 − 600 + 200 − 30)", await accountBalance("1110"), 570);
check("ديون الزبون (450 − 350 − 50 مرتجع)", await accountBalance("1200"), 50);
check("ديون المورد", -(await accountBalance("2100")), 0);
const { data: all } = await admin.from("journal_lines").select("debit: base_debit, credit: base_credit, journal_entries!inner(company_id, status)").eq("journal_entries.company_id", company).eq("journal_entries.status", "posted");
const td = all.reduce((s, l) => s + Number(l.debit), 0), tc = all.reduce((s, l) => s + Number(l.credit), 0);
check("ميزان المراجعة: مجموع المدين − الدائن", td - tc, 0);
const rep = await u.rpc("get_financial_report", { target_company: company, target_start: today, target_end: today });
if (rep.error) { failures++; log(`   ❌ تقرير الأرباح: ${rep.error.message}`); }
else {
  const pl = rep.data.profit_loss, bs = rep.data.balance_sheet;
  check("تقرير: صافي الربح (450 − 50 − 150 − 30)", pl.net_profit, 220);
  check("تقرير: كلفة البضاعة المباعة (130 + 40 − 20)", pl.cost_of_goods_sold, 150);
  check("تقرير: الأصول (570 + 150 ليرة + 50 + 450)", bs.assets, 1220);
  check("تقرير: الالتزامات", bs.liabilities, 0);
  check("تقرير: حقوق الملكية مع الربح", bs.equity_with_current_earnings, 1220);
}
log(failures ? `\n❌ ${failures} مشكلة` : "\n✅ كل الفحوصات نجحت");
