// Part 6: delivery fee (on the customer or on us) and one-step sales invoice correction
// (payments move to the new invoice, stock and journals stay balanced).
import { admin, newUserClient } from "./local-supabase.mjs";

const u = newUserClient();
const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });

let failures = 0;
const log = (s) => console.log(s);
function must(label, r) {
  if (r.error) { failures++; log(`   ❌ ${label}: ${r.error.message}`); return null; }
  log(`   ✅ ${label}`);
  return r.data ?? true;
}
function mustFail(label, r, expected) {
  if (!r.error) { failures++; log(`   ❌ ${label}: كان لازم ينرفض بس انقبل`); return; }
  if (expected && !r.error.message.includes(expected)) {
    failures++;
    log(`   ❌ ${label}: انرفض بس بسبب غلط (${r.error.message})`);
    return;
  }
  log(`   ✅ ${label}: انرفض (${r.error.message})`);
}
function check(label, actual, expected) {
  const ok = Math.abs(Number(actual) - Number(expected)) < 0.02;
  if (!ok) failures++;
  log(`   ${ok ? "✅" : "❌"} ${label}: ${Number(actual).toFixed(2)}${ok ? "" : `  (المتوقع ${Number(expected).toFixed(2)})`}`);
}

let company;
async function gl(filter) {
  let q = admin.from("journal_lines")
    .select("base_debit, base_credit, finance_accounts!inner(code, system_key, company_id)")
    .eq("finance_accounts.company_id", company);
  q = filter(q);
  const { data, error } = await q;
  if (error) throw error;
  return Math.round(data.reduce((s, l) => s + Number(l.base_debit) - Number(l.base_credit), 0) * 100) / 100;
}
const byCode = (code) => gl((q) => q.eq("finance_accounts.code", code));
const byKey = (key) => gl((q) => q.eq("finance_accounts.system_key", key));
async function stockOf(product) {
  const { data } = await admin.from("inventory_stock").select("on_hand").eq("product_id", product);
  return (data ?? []).reduce((s, r) => s + Number(r.on_hand), 0);
}
const invoiceOf = async (id) =>
  (await admin.from("sales_invoices").select("*").eq("id", id).single()).data;

// يعمل طلبية ويسلّمها كلها، وبيرجّع رقم الفاتورة.
async function sell(trader, items, extra = {}) {
  const order = (await u.rpc("create_sales_order_v2", {
    target_company: company, target_trader: trader, target_notes: null, items_payload: items, target_source_quote: null,
  })).data?.order_id;
  const lines = (await admin.from("sales_order_items").select("id, quantity").eq("order_id", order)).data;
  await u.rpc("create_order_delivery", {
    target_company: company, target_order: order,
    items_payload: lines.map((l) => ({ sales_order_item_id: l.id, quantity: Number(l.quantity) })),
  });
  return u.rpc("complete_order_delivery", { target_company: company, target_order: order, target_notes: null, ...extra });
}

// ---------------------------------------------------------------- setup
log("0️⃣  تجهيز");
const email = `cycle6${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
await u.auth.signInWithPassword({ email, password: "Passw0rd!x" });
must("الشركة", await u.from("companies").insert({ name: "شركة الدورة 6", default_currency: "USD" }));
company = (await u.from("company_members").select("company_id").single()).data.company_id;
const usdBox = (await u.from("cashboxes").select("id").eq("company_id", company).single()).data.id;
const wh = (await u.from("warehouses").select("id").eq("company_id", company).single()).data.id;
const supplier = (await u.from("suppliers").insert({ company_id: company, name: "مورد" }).select("id").single()).data.id;
const cable = (await u.from("products").insert({ company_id: company, name: "كبل", sale_price: 10 }).select("id").single()).data.id;
const pinv = (await u.rpc("create_purchase_invoice", {
  target_company: company, target_supplier: supplier, target_supplier_invoice_number: "P-1", target_invoice_date: today,
  target_due_date: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 100, unit_cost: 4 }],
})).data;
const pinvId = typeof pinv === "string" ? pinv : pinv?.invoice_id ?? pinv?.id;
const pItem = (await admin.from("purchase_invoice_items").select("id").eq("invoice_id", pinvId).single()).data.id;
must("استلام 100 كبل", await u.rpc("receive_purchase_invoice", {
  target_company: company, target_invoice: pinvId, target_warehouse: wh, target_receipt_date: today, target_notes: null,
  items_payload: [{ purchase_invoice_item_id: pItem, quantity: 100 }],
}));
const cashStart = await byCode("1110");
const trader = (await u.from("traders").insert({ company_id: company, name: "محل النور" }).select("id").single()).data.id;
const accounts = (await admin.from("finance_accounts").select("code").eq("company_id", company).in("code", ["4500", "6700"])).data;
check("الحسابين الجداد موجودين (4500، 6700)", accounts.length, 2);

// ---------------------------------------------------------------- A. fee on the customer
log("\nA️⃣  أجرة توصيل على الزبون");
const invA = must("تسليم 10×10$ مع أجرة 5$", await sell(trader, [{ product_id: cable, quantity: 10, sale_unit_price: 10 }], { target_delivery_fee: 5 }));
const a = await invoiceOf(invA);
check("مجموع الفاتورة 105", a.total, 105);
check("أجرة التوصيل بالفاتورة", a.delivery_fee, 5);
check("المبيعات 100 بس", -(await byKey("sales_revenue")), 100);
check("إيراد التوصيل 5", -(await byKey("delivery_revenue")), 5);
check("ديون الزبون 105", await byKey("accounts_receivable"), 105);

// ---------------------------------------------------------------- B. fee on us
log("\nB️⃣  أجرة توصيل علينا");
const invB = must("تسليم 5×10$ وأجرة 3$ علينا", await sell(trader, [{ product_id: cable, quantity: 5, sale_unit_price: 10 }], {
  target_delivery_cost: 3, target_cost_cashbox: usdBox,
}));
const b = await invoiceOf(invB);
check("مجموع الفاتورة 50 (الأجرة ما بتبين للزبون)", b.total, 50);
check("المصروف مربوط بالفاتورة", b.delivery_expense_id ? 1 : 0, 1);
check("مصاريف التوصيل 3", await byKey("delivery_expense"), 3);
check("الصندوق نقص 3", await byCode("1110"), cashStart - 3);
mustFail("أجرة علينا بدون صندوق", await sell(trader, [{ product_id: cable, quantity: 1, sale_unit_price: 10 }], { target_delivery_cost: 3 }), "Cashbox required");
mustFail("أجرة بالسالب", await sell(trader, [{ product_id: cable, quantity: 1, sale_unit_price: 10 }], { target_delivery_fee: -1 }), "Invalid delivery fee");

// ---------------------------------------------------------------- C. quick sale with fee
log("\nC️⃣  بيع سريع مع أجرة توصيل");
const qs = must("بيع سريع 1×10$ + أجرة 2$، دفع كامل", await u.rpc("quick_sale", {
  target_company: company, target_trader: null, items_payload: [{ product_id: cable, quantity: 1, sale_unit_price: 10 }],
  target_cashbox: usdBox, target_paid_amount: null, target_cash_amount: null, target_delivery_fee: 2,
}));
check("مجموع البيع السريع 12", qs?.total, 12);
check("انقبض كامل 12", qs?.paid, 12);
check("إيراد التوصيل صار 7", -(await byKey("delivery_revenue")), 7);
check("كبل بالمخزون (100-10-5-1)", await stockOf(cable), 84);

// ---------------------------------------------------------------- D. correction with a partial payment
log("\nD️⃣  تصحيح فاتورة عليها دفعة");
must("قبض 60$ على الفاتورة A", await u.rpc("record_customer_payment", {
  target_company: company, target_trader: trader, target_cashbox: usdBox, target_amount: 60, target_payment_date: today,
  target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: invA, amount: 60 }],
}));
mustFail("تصحيح بدون سبب", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: invA, target_reason: " ", items_payload: [{ product_id: cable, quantity: 8, sale_unit_price: 10 }],
}), "reason");
const corr = must("تصحيح A: 8 بدل 10، والأجرة 5", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: invA, target_reason: "الكمية غلط",
  items_payload: [{ product_id: cable, quantity: 8, sale_unit_price: 10 }], target_delivery_fee: 5,
}));
const oldA = await invoiceOf(invA);
const newA = await invoiceOf(corr?.invoice_id);
check("الفاتورة القديمة ملغاة", oldA.status === "cancelled" ? 1 : 0, 1);
check("طلبيتها القديمة ملغاة", (await admin.from("sales_orders").select("status").eq("id", oldA.order_id).single()).data.status === "cancelled" ? 1 : 0, 1);
check("الجديدة مربوطة بالقديمة", newA.corrected_from_id === invA ? 1 : 0, 1);
check("مجموع الجديدة 85", newA.total, 85);
check("الدفعة انتقلت (المدفوع 60)", newA.paid_total, 60);
check("الباقي 25", newA.balance_due, 25);
check("كبل بالمخزون (رجع 10 وطلع 8)", await stockOf(cable), 86);
check("إيراد التوصيل ما تكرّر (5+2)", -(await byKey("delivery_revenue")), 7);
check("المبيعات: 80 + 50 + 10", -(await byKey("sales_revenue")), 140);
check("ما في رصيد معلّق للزبون", await byKey("customer_advances"), 0);
mustFail("تصحيح فاتورة ملغاة", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: invA, target_reason: "تاني مرة", items_payload: [{ product_id: cable, quantity: 1, sale_unit_price: 10 }],
}), "Only posted");

// ---------------------------------------------------------------- E. correction below what was paid
log("\nE️⃣  تصحيح لمبلغ أقل من المدفوع");
must("قبض الباقي 25$", await u.rpc("record_customer_payment", {
  target_company: company, target_trader: trader, target_cashbox: usdBox, target_amount: 25, target_payment_date: today,
  target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: newA.id, amount: 25 }],
}));
const corr2 = must("تصحيح لـ 5×10$ بدون أجرة", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: newA.id, target_reason: "رجّعلنا 3",
  items_payload: [{ product_id: cable, quantity: 5, sale_unit_price: 10 }], target_delivery_fee: 0,
}));
const e = await invoiceOf(corr2?.invoice_id);
check("الجديدة 50 ومدفوعة كلها", e.paid_total, 50);
check("حالتها مدفوعة", e.payment_status === "paid" ? 1 : 0, 1);
check("الزيادة 35 صارت رصيد للزبون", -(await byKey("customer_advances")), 35);
check("كبل بالمخزون (رجع 8 وطلع 5)", await stockOf(cable), 89);

// ---------------------------------------------------------------- F. refusals
log("\nF️⃣  حالات لازم تنرفض");
const order = (await u.rpc("create_sales_order_v2", {
  target_company: company, target_trader: trader, target_notes: null,
  items_payload: [{ product_id: cable, quantity: 10, sale_unit_price: 10 }], target_source_quote: null,
})).data?.order_id;
const line = (await admin.from("sales_order_items").select("id").eq("order_id", order).single()).data.id;
await u.rpc("create_order_delivery", { target_company: company, target_order: order, items_payload: [{ sales_order_item_id: line, quantity: 4 }] });
const partial = (await u.rpc("complete_order_delivery", { target_company: company, target_order: order, target_notes: null })).data;
mustFail("تصحيح فاتورة طلبية ما خلص تسليمها", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: partial, target_reason: "غلط", items_payload: [{ product_id: cable, quantity: 4, sale_unit_price: 10 }],
}), "Order has other invoices");
mustFail("تصحيح لكمية مش موجودة", await u.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: invB, target_reason: "غلط", items_payload: [{ product_id: cable, quantity: 9999, sale_unit_price: 10 }],
}), "Not enough stock");
check("الفاتورة B ضلّت متل ما هي بعد الرفض", (await invoiceOf(invB)).status === "posted" ? 1 : 0, 1);

const repEmail = `rep6${Date.now()}@test.local`;
const { data: repUser } = await admin.auth.admin.createUser({ email: repEmail, password: "Passw0rd!x", email_confirm: true });
const salesRole = (await u.from("company_roles").select("id").eq("company_id", company).eq("name", "مبيعات").single()).data.id;
await u.rpc("assign_company_member_role", { target_company: company, target_user: repUser.user.id, target_role: salesRole });
const rep = newUserClient();
await rep.auth.signInWithPassword({ email: repEmail, password: "Passw0rd!x" });
mustFail("موظف مبيعات بدون صلاحية الإلغاء", await rep.rpc("correct_sales_invoice", {
  target_company: company, target_invoice: invB, target_reason: "غلط", items_payload: [{ product_id: cable, quantity: 5, sale_unit_price: 10 }],
}), "Not allowed");
mustFail("موظف مبيعات بيحط أجرة علينا بدون صلاحية المصاريف", await rep.rpc("quick_sale", {
  target_company: company, target_trader: null, items_payload: [{ product_id: cable, quantity: 1, sale_unit_price: 10 }],
  target_cashbox: usdBox, target_paid_amount: null, target_cash_amount: null, target_delivery_cost: 2, target_cost_cashbox: usdBox,
}));

// ---------------------------------------------------------------- G. invariants
log("\nG️⃣  التوازن");
const posted = (await admin.from("sales_invoices").select("balance_due").eq("company_id", company).eq("status", "posted")).data;
check("ديون الزبائن بالحسابات = باقي الفواتير", await byKey("accounts_receivable"), posted.reduce((s, r) => s + Number(r.balance_due), 0));
const stock = (await admin.from("inventory_stock").select("on_hand, average_cost").eq("product_id", cable)).data;
check("المخزون بالحسابات = قيمة البضاعة", await byCode("1300"), stock.reduce((s, r) => s + Number(r.on_hand) * Number(r.average_cost), 0));
check("القيود موزونة", await gl((q) => q), 0);

log(failures ? `\n❌ ${failures} فحص فشل` : "\n✅ كل الفحوصات نجحت");
process.exit(failures ? 1 : 0);
