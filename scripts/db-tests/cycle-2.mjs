// Part 2: partners, purchase returns, SYP supplier payments, transfers/counts, quotes & below-cost approval,
// reversals/cancellations, payroll & loans, fixed assets, month close — then global invariants.
import { admin, newUserClient } from "./local-supabase.mjs";

const u = newUserClient();
const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
const [Y, M] = today.split("-").map(Number);
const SYP = 13000;

let failures = 0;
const log = (s) => console.log(s);
function must(label, r) {
  if (r.error) { failures++; log(`   ❌ ${label}: ${r.error.message}`); return null; }
  return r.data ?? true;
}
function mustFail(label, r) {
  if (!r.error) { failures++; log(`   ❌ ${label}: كان لازم ينرفض بس انقبل`); return; }
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
    .select("base_debit, base_credit, finance_accounts!inner(code, system_key, account_group, company_id)")
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

// ---------------------------------------------------------------- setup
log("0️⃣  تجهيز");
const email = `cycle2${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
await u.auth.signInWithPassword({ email, password: "Passw0rd!x" });
must("الشركة", await u.from("companies").insert({ name: "شركة الدورة 2", default_currency: "USD" }));
company = (await u.from("company_members").select("company_id").single()).data.company_id;
const usdBox = (await u.from("cashboxes").select("id").eq("company_id", company).single()).data.id;
const wh1 = (await u.from("warehouses").select("id").eq("company_id", company).single()).data.id;
const sypBox = must("صندوق ليرة", await u.from("cashboxes").insert({ company_id: company, name: "صندوق الليرة", currency: "SYP" }).select("id").single())?.id;
must("سعر الصرف", await u.rpc("save_finance_exchange_rate", { target_company: company, target_currency: "SYP", target_date: today, target_rate: 1 / SYP, target_notes: null }));
const { data: sypAcc } = await admin.from("cashbox_gl_accounts").select("finance_accounts(code, name)").eq("cashbox_id", sypBox).single();
log(`   حساب صندوق الليرة: ${sypAcc.finance_accounts.code} ${sypAcc.finance_accounts.name}`);
if (!/^11\d\d$/.test(sypAcc.finance_accounts.code)) { failures++; log("   ❌ رقم حساب الصندوق مش مرتب"); }

// ---------------------------------------------------------------- A. partners
log("\nA️⃣  الشركاء");
const p1 = must("شريك 1", await u.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "عبد", target_phone: null, target_ownership_percent: 60, target_profit_share_percent: 60, target_notes: null, target_active: true }));
const p2 = must("شريك 2", await u.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "شريك تاني", target_phone: null, target_ownership_percent: 40, target_profit_share_percent: 40, target_notes: null, target_active: true }));
must("رأس مال 2000$", await u.rpc("record_partner_transaction", { target_company: company, target_partner: p1, target_type: "capital_contribution", target_amount: 2000, target_currency: "USD", target_cashbox: usdBox, target_date: today, target_notes: null }));
must("رأس مال بالليرة (200$)", await u.rpc("record_partner_transaction", { target_company: company, target_partner: p2, target_type: "capital_contribution", target_amount: 200 * SYP, target_currency: "SYP", target_cashbox: sypBox, target_date: today, target_notes: null }));
must("سحب شريك 100$", await u.rpc("record_partner_transaction", { target_company: company, target_partner: p1, target_type: "drawing", target_amount: 100, target_currency: "USD", target_cashbox: usdBox, target_date: today, target_notes: null }));
check("رأس المال (3100)", -(await byKey("capital")), 2200);
check("مسحوبات الشركاء", await byKey("partner_drawings"), 100);
check("الصندوق دولار", await byCode("1110"), 1900);
mustFail("شريك تالت بيخلّي الملكية فوق 100%", await u.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "زيادة", target_phone: null, target_ownership_percent: 10, target_profit_share_percent: 0, target_notes: null, target_active: true }));
const ps = await u.from("partner_summary").select("capital_contributions, drawings").eq("company_id", company);
if (ps.error) { failures++; log("   ❌ ملخص الشركاء: " + ps.error.message); }
else {
  check("ملخص الشركاء: رأس المال = الحسابات", ps.data.reduce((t, r) => t + Number(r.capital_contributions), 0), -(await byKey("capital")) + ps.data.reduce((t, r) => t + 0, 0));
  check("ملخص الشركاء: المسحوبات = الحسابات", ps.data.reduce((t, r) => t + Number(r.drawings), 0), await byKey("partner_drawings"));
}

// ---------------------------------------------------------------- B. purchases
log("\nB️⃣  مشتريات + مرتجع للمورد + دفع بالليرة");
const supplier = (await u.from("suppliers").insert({ company_id: company, name: "مصنع نينغبو" }).select("id").single()).data.id;
const cable = (await u.from("products").insert({ company_id: company, name: "كبل", sale_price: 10 }).select("id").single()).data.id;
const bulb = (await u.from("products").insert({ company_id: company, name: "لمبة", sale_price: 3 }).select("id").single()).data.id;
const pinv = must("فاتورة شراء 100×4", await u.rpc("create_purchase_invoice", { target_company: company, target_supplier: supplier, target_supplier_invoice_number: "NB-1", target_invoice_date: today, target_due_date: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 100, unit_cost: 4 }] }));
const pinvId = typeof pinv === "string" ? pinv : pinv?.invoice_id ?? pinv?.id;
const pItem = (await admin.from("purchase_invoice_items").select("id").eq("invoice_id", pinvId).single()).data.id;
must("استلام", await u.rpc("receive_purchase_invoice", { target_company: company, target_invoice: pinvId, target_warehouse: wh1, target_receipt_date: today, target_notes: null, items_payload: [{ purchase_invoice_item_id: pItem, quantity: 100 }] }));
must("مرتجع 10 للمورد", await u.rpc("create_purchase_return", { target_company: company, target_invoice: pinvId, target_warehouse: wh1, target_date: today, target_notes: null, items_payload: [{ purchase_invoice_item_id: pItem, quantity: 10 }] }));
check("كبل بالمخزون", await stockOf(cable), 90);
check("ديون المورد بعد المرتجع", -(await byKey("accounts_payable")), 360);
must("دفع 200$ بالليرة", await u.rpc("record_supplier_payment", { target_company: company, target_supplier: supplier, target_cashbox: sypBox, target_amount: 200 * SYP, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: pinvId, amount: 200 }] }));
check("ديون المورد بعد دفعة الليرة", -(await byKey("accounts_payable")), 160);
must("دفع الباقي 160$", await u.rpc("record_supplier_payment", { target_company: company, target_supplier: supplier, target_cashbox: usdBox, target_amount: 160, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: pinvId, amount: 160 }] }));
check("ديون المورد", -(await byKey("accounts_payable")), 0);
check("صندوق الليرة (بالدولار)", await byCode(sypAcc.finance_accounts.code), 0);

// ---------------------------------------------------------------- C. warehouses
log("\nC️⃣  مستودع تاني + تحويل + جرد");
const wh2 = must("مستودع 2", await u.rpc("create_warehouse", { target_company: company, target_name: "مستودع المزة", target_code: "MZ", target_address: null, target_is_default: false }));
const wh2Id = typeof wh2 === "string" ? wh2 : wh2?.id;
must("تحويل 20 كبل", await u.rpc("post_inventory_transfer", { target_company: company, target_source_warehouse: wh1, target_destination_warehouse: wh2Id, target_transfer_date: today, target_notes: null, items_payload: [{ product_id: cable, quantity: 20 }] }));
check("المخزون (1300) ما تغيّر بالتحويل", await byCode("1300"), 360);
must("جرد: لقينا 18 بدل 20", await u.rpc("post_inventory_count", { target_company: company, target_warehouse: wh2Id, target_count_date: today, target_notes: null, items_payload: [{ product_id: cable, counted_quantity: 18, unit_cost: null }] }));
check("كبل بالمخزون", await stockOf(cable), 88);
check("مصروف فروقات الجرد (2×4)", await byKey("inventory_adjustment_expense"), 8);

// ---------------------------------------------------------------- D. quotes
log("\nD️⃣  عرض سعر ← طلبية ← توصيل");
const trader = (await u.from("traders").insert({ company_id: company, name: "محل السلام" }).select("id").single()).data.id;
const q1 = must("عرض سعر 10×10$", await u.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 10, sale_unit_price: 10 }] }));
const q1Id = typeof q1 === "string" ? q1 : q1?.quote_id ?? q1?.id;
must("إرسال", await u.rpc("set_sales_quote_status", { target_company: company, target_quote: q1Id, target_status: "sent" }));
must("قبول", await u.rpc("set_sales_quote_status", { target_company: company, target_quote: q1Id, target_status: "accepted" }));
const conv = must("تحويل لطلبية", await u.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: q1Id }));
const orderId = conv?.order_id ?? conv;
log(`   نتيجة التحويل: ${JSON.stringify(conv)}`);
const soi = (await admin.from("sales_order_items").select("id").eq("order_id", orderId).single()).data?.id;
must("توصيل", await u.rpc("create_order_delivery", { target_company: company, target_order: orderId, items_payload: [{ sales_order_item_id: soi, quantity: 10 }] }));
must("تسليم", await u.rpc("complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null }));
check("ديون الزبون", await byKey("accounts_receivable"), 100);
check("الزبون صار «عميل» بعد أول فاتورة", (await admin.from("traders").select("status").eq("id", trader).single()).data.status === "customer" ? 1 : 0, 1);

log("\n   عرض سعر تحت الكلفة (5×3$، الكلفة 4$) من موظف مبيعات");
const repEmail = `rep${Date.now()}@test.local`;
const { data: repUser } = await admin.auth.admin.createUser({ email: repEmail, password: "Passw0rd!x", email_confirm: true });
const salesRole = (await u.from("company_roles").select("id").eq("company_id", company).eq("name", "مبيعات").single()).data.id;
must("إضافة الموظف بصفة مبيعات", await u.rpc("assign_company_member_role", { target_company: company, target_user: repUser.user.id, target_role: salesRole }));
const salesRep = newUserClient();
await salesRep.auth.signInWithPassword({ email: repEmail, password: "Passw0rd!x" });
const q2 = must("الموظف عمل عرض تحت الكلفة", await salesRep.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 5, sale_unit_price: 3 }] }));
const q2Id = typeof q2 === "string" ? q2 : q2?.quote_id ?? q2?.id;
must("إرسال", await salesRep.rpc("set_sales_quote_status", { target_company: company, target_quote: q2Id, target_status: "sent" }));
must("قبول", await salesRep.rpc("set_sales_quote_status", { target_company: company, target_quote: q2Id, target_status: "accepted" }));
const conv2 = await salesRep.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: q2Id });
log(`   نتيجة تحويل الموظف: ${conv2.error ? "خطأ: " + conv2.error.message : JSON.stringify(conv2.data)}`);
const approval = conv2.data?.approval_id;
if (!approval) { failures++; log("   ❌ البيع تحت الكلفة مشي بدون موافقة"); }
else {
  log("   ✅ انطلب موافقة المالك");
  must("المالك وافق", await u.rpc("resolve_approval_request", { target_company: company, target_request: approval, target_decision: "approved", target_notes: null }));
  const { data: made } = await admin.from("sales_orders").select("id, total").eq("trader_id", trader).order("created_at", { ascending: false }).limit(1).single();
  check("انعملت الطلبية بعد الموافقة (15$)", made.total, 15);
  const quoteAfter = (await admin.from("sales_quotes").select("status, converted_order_id").eq("id", q2Id).single()).data;
  if (quoteAfter.status !== "converted" || quoteAfter.converted_order_id !== made.id) { failures++; log(`   ❌ العرض ما تعلّم إنه تحوّل: ${JSON.stringify(quoteAfter)}`); }
  else log("   ✅ العرض صار «تحوّل لطلبية» ومربوط بالطلبية");
  const again = await salesRep.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: q2Id });
  const orderCount = (await admin.from("sales_orders").select("id", { count: "exact", head: true }).eq("trader_id", trader).eq("total", 15)).count;
  check("تحويل العرض مرة تانية ما بيعمل طلبية مكررة", orderCount, 1);
  must("إلغاء الطلبية", await u.rpc("cancel_sales_order", { target_company: company, target_order: made.id, target_reason: "تجربة" }));
}

// ---------------------------------------------------------------- E. reversals
log("\nE️⃣  عكس وإلغاء");
const inv = (await admin.from("sales_invoices").select("id").eq("order_id", orderId).single()).data.id;
const pay = must("قبض 100$", await u.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: usdBox, target_amount: 100, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv, amount: 100 }] }));
const payId = typeof pay === "string" ? pay : pay?.payment_id ?? pay?.id;
check("ديون الزبون بعد القبض", await byKey("accounts_receivable"), 0);
must("عكس القبض", await u.rpc("reverse_customer_payment", { target_company: company, target_payment: payId, target_reason: "غلط" }));
check("ديون الزبون رجعت", await byKey("accounts_receivable"), 100);
check("الصندوق رجع", await byCode("1110"), 1900 - 160);
const iItem = (await admin.from("sales_invoice_items").select("id").eq("invoice_id", inv).single()).data.id;
const ret = must("مرتجع 2 كبل", await u.rpc("create_sales_return", { target_company: company, target_invoice: inv, target_warehouse: wh1, target_date: today, target_notes: null, items_payload: [{ sales_invoice_item_id: iItem, quantity: 2 }] }));
const retId = typeof ret === "string" ? ret : ret?.return_id ?? ret?.id;
check("كبل بعد المرتجع", await stockOf(cable), 80);
must("عكس المرتجع", await u.rpc("reverse_sales_return", { target_company: company, target_return: retId, target_reason: "غلط" }));
check("كبل بعد عكس المرتجع", await stockOf(cable), 78);
check("ديون الزبون", await byKey("accounts_receivable"), 100);
const cancelled = await u.rpc("cancel_sales_invoice", { target_company: company, target_invoice: inv, target_reason: "تجربة" });
log(`   إلغاء الفاتورة (مرتجعها معكوس، فمسموح): ${cancelled.error ? "خطأ: " + cancelled.error.message : "تم"}`);
check("ديون الزبون بعد إلغاء الفاتورة", await byKey("accounts_receivable"), 0);
check("كبل رجع للمستودع بعد إلغاء الفاتورة", await stockOf(cable), 88);

const pinv2 = must("فاتورة شراء لمبات 50×1", await u.rpc("create_purchase_invoice", { target_company: company, target_supplier: supplier, target_supplier_invoice_number: "NB-2", target_invoice_date: today, target_due_date: null, target_notes: null, items_payload: [{ product_id: bulb, quantity: 50, unit_cost: 1 }] }));
const pinv2Id = typeof pinv2 === "string" ? pinv2 : pinv2?.invoice_id ?? pinv2?.id;
const p2Item = (await admin.from("purchase_invoice_items").select("id").eq("invoice_id", pinv2Id).single()).data.id;
const rec = must("استلام", await u.rpc("receive_purchase_invoice", { target_company: company, target_invoice: pinv2Id, target_warehouse: wh1, target_receipt_date: today, target_notes: null, items_payload: [{ purchase_invoice_item_id: p2Item, quantity: 50 }] }));
const recId = (await admin.from("goods_receipts").select("id").eq("purchase_invoice_id", pinv2Id).single()).data.id;
must("عكس الاستلام", await u.rpc("reverse_goods_receipt", { target_company: company, target_receipt: recId, target_reason: "غلط" }));
check("لمبات بعد عكس الاستلام", await stockOf(bulb), 0);
must("إلغاء فاتورة الشراء", await u.rpc("cancel_purchase_invoice", { target_company: company, target_invoice: pinv2Id, target_reason: "غلط" }));
check("ديون المورد", -(await byKey("accounts_payable")), 0);
check("حساب بضاعة بالطريق رجع صفر", await byKey("inventory_clearing"), 0);

// ---------------------------------------------------------------- F. return after payment
log("\nF️⃣  مرتجع من فاتورة مدفوعة ← رصيد للزبون ← ينخصم من الفاتورة الجاية");
async function sellCable(qty) {
  const q = must(`عرض ${qty} كبل`, await u.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: [{ product_id: cable, quantity: qty, sale_unit_price: 10 }] }));
  const qId = typeof q === "string" ? q : q?.quote_id ?? q?.id;
  await u.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "sent" });
  await u.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "accepted" });
  const c = must("تحويل", await u.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: qId }));
  const oId = c?.order_id ?? c;
  const oi = (await admin.from("sales_order_items").select("id").eq("order_id", oId).single()).data.id;
  must("توصيل", await u.rpc("create_order_delivery", { target_company: company, target_order: oId, items_payload: [{ sales_order_item_id: oi, quantity: qty }] }));
  must("تسليم", await u.rpc("complete_order_delivery", { target_company: company, target_order: oId, target_notes: null }));
  return (await admin.from("sales_invoices").select("id, balance_due").eq("order_id", oId).single()).data;
}
const advances = async () => -(await byKey("customer_advances"));
const inv3 = await sellCable(10);
const pay3 = must("قبض 100$ كامل", await u.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: usdBox, target_amount: 100, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv3.id, amount: 100 }] }));
const pay3Id = typeof pay3 === "string" ? pay3 : pay3?.payment_id ?? pay3?.id;
const i3Item = (await admin.from("sales_invoice_items").select("id").eq("invoice_id", inv3.id).single()).data.id;
must("مرتجع 3 كبل (30$)", await u.rpc("create_sales_return", { target_company: company, target_invoice: inv3.id, target_warehouse: wh1, target_date: today, target_notes: null, items_payload: [{ sales_invoice_item_id: i3Item, quantity: 3 }] }));
check("الفاتورة ما عليها شي", (await admin.from("sales_invoices").select("balance_due").eq("id", inv3.id).single()).data.balance_due, 0);
check("الدفعة: 30$ صارت رصيد للزبون", (await admin.from("customer_payments").select("unallocated_total").eq("id", pay3Id).single()).data.unallocated_total, 30);
check("رصيد الزبون الدائن بالحسابات", await advances(), 30);
const inv4 = await sellCable(2);
check("الفاتورة الجديدة (20$) انخصمت من الرصيد", (await admin.from("sales_invoices").select("balance_due").eq("id", inv4.id).single()).data.balance_due, 0);
check("ضل للزبون رصيد 10$", await advances(), 10);
must("عكس الدفعة", await u.rpc("reverse_customer_payment", { target_company: company, target_payment: pay3Id, target_reason: "تجربة" }));
check("بعد عكس الدفعة: الفاتورة الأولى عليها 70$", (await admin.from("sales_invoices").select("balance_due").eq("id", inv3.id).single()).data.balance_due, 70);
check("بعد عكس الدفعة: رصيد الزبون الدائن صفر", await advances(), 0);
check("ديون الزبون = 70 + 20", await byKey("accounts_receivable"), 90);
const byProduct = await u.rpc("get_sales_return_candidates", { target_company: company, target_search: "كبل", target_limit: 50, target_offset: 0 });
if (byProduct.error) { failures++; log("   ❌ بحث المرتجعات: " + byProduct.error.message); }
else check("بحث المرتجعات باسم الصنف لقى الفواتير", byProduct.data.total_count > 0 ? 1 : 0, 1);
const history = await u.rpc("get_returns_history", { target_company: company, target_search: "كبل", target_kind: null, target_status: null, target_limit: 50, target_offset: 0 });
if (history.error) { failures++; log("   ❌ سجل المرتجعات: " + history.error.message); }
else check("سجل المرتجعات باسم الصنف", history.data.total_count > 0 ? 1 : 0, 1);

// ---------------------------------------------------------------- K. price levels + cartons
log("\nK️⃣  مستويات الأسعار والكرتونة");
const lvl = must("مستوى جملة", await u.from("price_levels").insert({ company_id: company, name: "جملة" }).select("id").single())?.id;
must("كرتونة الكبل 24 + سعر جملة 8$", await u.rpc("save_product_packaging_and_prices", { target_company: company, target_product: cable, product_pack_size: 24, product_pack_unit: "كرتونة", level_prices: [{ price_level_id: lvl, price: 8 }] }));
const tp0 = await u.rpc("get_trader_product_prices", { target_company: company, target_trader: trader, target_products: [cable] });
check("زبون بدون مستوى: السعر العادي", tp0.data?.[0]?.price, 10);
must("الزبون صار جملة", await u.from("traders").update({ price_level_id: lvl }).eq("id", trader));
const tp1 = await u.rpc("get_trader_product_prices", { target_company: company, target_trader: trader, target_products: [cable] });
check("زبون جملة: سعر الجملة", tp1.data?.[0]?.price, 8);
mustFail("موظف المبيعات ما بيغيّر مستوى سعر زبون", await salesRep.from("traders").update({ price_level_id: null }).eq("id", trader).select("id").single());
// كرتونة (24) بـ 100$ = القطعة 4.1667 → مجموع السطر لازم يطلع 100 بالضبط
const cq = must("عرض كرتونة بـ100$", await u.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: [{ product_id: cable, quantity: 24, sale_unit_price: 4.1667 }] }));
const cqId = typeof cq === "string" ? cq : cq?.quote_id ?? cq?.id;
check("مجموع كرتونة بـ100$ = 100", (await admin.from("sales_quotes").select("total").eq("id", cqId).single()).data.total, 100);

// ---------------------------------------------------------------- L. rate per transaction
log("\nL️⃣  سعر الصرف مع كل عملية");
must("المندوب كتب سعر الليرة 15000", await salesRep.rpc("set_transaction_rate", { target_company: company, target_currency: "SYP", target_date: today, target_units_per_base: 15000 }));
check("آخر سعر = 15000", (await u.rpc("get_units_per_base", { target_company: company, target_currency: "SYP", target_date: today })).data, 15000);
const sypCash = await byCode(sypAcc.finance_accounts.code);
must("مصروف 150000 ليرة من صندوق الليرة", await u.rpc("record_cash_movement", { target_company: company, target_cashbox: sypBox, movement_type: "adjustment_in", movement_amount: 150000, movement_notes: null }));
check("صندوق الليرة زاد 10$ بسعر 15000", (await byCode(sypAcc.finance_accounts.code)) - sypCash, 10);
must("طلّعناهن بنفس السعر", await u.rpc("record_cash_movement", { target_company: company, target_cashbox: sypBox, movement_type: "adjustment_out", movement_amount: 150000, movement_notes: null }));
must("رجّعنا السعر 13000", await u.rpc("set_transaction_rate", { target_company: company, target_currency: "SYP", target_date: today, target_units_per_base: 13000 }));

// ---------------------------------------------------------------- M. owner approval code
log("\nM️⃣  رمز موافقة المالك");
mustFail("الموظف ما بيقدر يحط رمز المالك", await salesRep.rpc("set_owner_pin", { target_company: company, target_pin: "1234" }));
must("المالك حط الرمز", await u.rpc("set_owner_pin", { target_company: company, target_pin: "4821" }));
const mq = must("الموظف عمل عرض تحت الكلفة", await salesRep.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: [{ product_id: bulb, quantity: 2, sale_unit_price: 0.1 }] }));
const mqId = typeof mq === "string" ? mq : mq?.quote_id ?? mq?.id;
await salesRep.rpc("set_sales_quote_status", { target_company: company, target_quote: mqId, target_status: "sent" });
await salesRep.rpc("set_sales_quote_status", { target_company: company, target_quote: mqId, target_status: "accepted" });
const mconv = (await salesRep.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: mqId })).data;
check("انطلبت موافقة", mconv?.status === "pending_approval" ? 1 : 0, 1);
mustFail("بدون رمز: الموظف ما بيوافق لحالو", await salesRep.rpc("resolve_approval_request", { target_company: company, target_request: mconv.approval_id, target_decision: "approved", target_notes: null }));
check("رمز غلط", (await salesRep.rpc("unlock_owner_override", { target_company: company, target_action: "approve", target_pin: "0000" })).data ? 1 : 0, 0);
check("رمز صح", (await salesRep.rpc("unlock_owner_override", { target_company: company, target_action: "approve", target_pin: "4821" })).data ? 1 : 0, 1);
must("انوافق بالرمز", await salesRep.rpc("resolve_approval_request", { target_company: company, target_request: mconv.approval_id, target_decision: "approved", target_notes: "بكلمة سر المالك" }));
check("العرض صار طلبية", (await admin.from("sales_quotes").select("status").eq("id", mqId).single()).data.status === "converted" ? 1 : 0, 1);
mustFail("نفس الرمز ما بيشتغل مرتين", await salesRep.rpc("resolve_approval_request", { target_company: company, target_request: mconv.approval_id, target_decision: "approved", target_notes: null }));
const mOrder = (await admin.from("sales_quotes").select("converted_order_id").eq("id", mqId).single()).data.converted_order_id;
must("إلغاء الطلبية التجريبية", await u.rpc("cancel_sales_order", { target_company: company, target_order: mOrder, target_reason: "تجربة" }));

// ---------------------------------------------------------------- N. quick sale
log("\nN️⃣  البيع السريع");
const stockBefore = await stockOf(cable);
const arBefore = await byKey("accounts_receivable");
const cashBefore = await byCode("1110");
const qs = must("بيع سريع 3 كبل × 10$ لزبون نقدي، دفع كامل", await salesRep.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: cable, quantity: 3, sale_unit_price: 10 }], target_cashbox: usdBox, target_paid_amount: 30, target_cash_amount: 30 }));
check("الكبل نقص 3", stockBefore - (await stockOf(cable)), 3);
check("الصندوق زاد 30", (await byCode("1110")) - cashBefore, 30);
check("ديون الزبائن ما تغيّرت", (await byKey("accounts_receivable")) - arBefore, 0);
check("الفاتورة مدفوعة", (await admin.from("sales_invoices").select("balance_due").eq("id", qs?.invoice_id).single()).data?.balance_due, 0);
mustFail("بيع سريع تحت الكلفة بدون رمز", await salesRep.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: cable, quantity: 1, sale_unit_price: 1 }], target_cashbox: usdBox, target_paid_amount: 1, target_cash_amount: 1 }));
mustFail("بيع سريع لكمية مش موجودة", await salesRep.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: cable, quantity: 99999, sale_unit_price: 10 }], target_cashbox: usdBox, target_paid_amount: 0, target_cash_amount: 0 }));
check("الرفض ما ترك طلبيات معلّقة", (await admin.from("sales_orders").select("id", { count: "exact", head: true }).eq("company_id", company).eq("status", "to_purchase")).count, 0);

// ---------------------------------------------------------------- G. payroll
log("\nG️⃣  الرواتب والسلف");
const emp = must("موظف راتبه 300$", await u.rpc("save_employee", { target_company: company, target_employee: null, target_employee_number: null, target_name: "أحمد", target_phone: null, target_job_title: "سائق", target_department: null, target_hire_date: today, target_salary_currency: "USD", target_base_salary: 300, target_fixed_allowances: 0, target_overtime_rate: 0, target_employee_social_rate: 0, target_employer_social_rate: 0, target_income_tax_rate: 0, target_cashbox: usdBox, target_notes: null, target_status: "active" }));
const empId = typeof emp === "string" ? emp : emp?.employee_id ?? emp?.id;
const loan = must("سلفة 100$ قسط 50", await u.rpc("create_employee_loan", { target_company: company, target_employee: empId, target_type: "advance", target_amount: 100, target_installment: 50, target_start_date: today, target_notes: null }));
const loanId = typeof loan === "string" ? loan : loan?.loan_id ?? loan?.id;
const { data: loanRow } = await admin.from("employee_loans").select("status").eq("id", loanId).single();
log(`   حالة السلفة بعد الإنشاء: ${loanRow?.status}`);
must("صرف السلفة", await u.rpc("disburse_employee_loan", { target_company: company, target_loan: loanId, target_cashbox: usdBox, target_date: today }));
check("سلف الموظفين", await byKey("employee_advances"), 100);
const loan2 = must("سلفة تانية 80$ ما انصرفت", await u.rpc("create_employee_loan", { target_company: company, target_employee: empId, target_type: "advance", target_amount: 80, target_installment: 40, target_start_date: today, target_notes: null }));
const loan2Id = typeof loan2 === "string" ? loan2 : loan2?.loan_id ?? loan2?.id;
const start = `${Y}-${String(M).padStart(2, "0")}-01`;
const run = must("مسير الشهر", await u.rpc("create_payroll_run", { target_company: company, target_period_start: start, target_period_end: today, target_pay_date: today, target_currency: "USD", target_notes: null }));
const runId = typeof run === "string" ? run : run?.run_id ?? run?.id;
must("ترحيل المسير", await u.rpc("post_payroll_run", { target_company: company, target_run: runId }));
const { data: item } = await admin.from("payroll_items").select("id, net_pay, loan_deduction").eq("payroll_run_id", runId).single();
check("خصم السلفة من الراتب (بس المصروفة، مش اللي ما انصرفت)", item.loan_deduction, 50);
check("صافي الراتب", item.net_pay, 250);
must("دفع الراتب", await u.rpc("record_payroll_payment", { target_company: company, target_payroll_item: item.id, target_cashbox: usdBox, target_amount: item.net_pay, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null }));
check("مصروف الرواتب", await byKey("salary_expense"), 300);
check("سلف الموظفين بعد القسط", await byKey("employee_advances"), 50);
must("إلغاء السلفة اللي ما انصرفت", await u.rpc("cancel_employee_loan", { target_company: company, target_loan: loan2Id }));
mustFail("إلغاء سلفة مصروفة", await u.rpc("cancel_employee_loan", { target_company: company, target_loan: loanId }));
check("رواتب مستحقة", -(await byKey("payroll_payable")), 0);

// ---------------------------------------------------------------- H. assets
log("\nH️⃣  أصل ثابت + إهلاك");
must("سيارة 1200$ عمرها 12 شهر", await u.rpc("create_fixed_asset", { target_company: company, target_name: "سيارة توصيل", target_category: "vehicles", target_description: null, target_purchase_date: start, target_in_service_date: start, target_currency: "USD", target_purchase_cost: 1200, target_salvage_value: 0, target_useful_life_months: 12, target_notes: null, target_cashbox: usdBox }));
check("الأصول الثابتة", await byKey("fixed_assets"), 1200);
check("الصندوق دفع حق السيارة (1740 + 30 بيع سريع − 100 سلفة − 250 راتب − 1200)", await byCode("1110"), 1740 + 30 - 100 - 250 - 1200);
must("إهلاك الشهر", await u.rpc("post_asset_depreciation_month", { target_company: company, target_year: Y, target_month: M }));
check("مصروف الإهلاك", await byKey("depreciation_expense"), 100);
await u.rpc("post_asset_depreciation_month", { target_company: company, target_year: Y, target_month: M });
check("إهلاك نفس الشهر مرتين ما بيتكرر", await byKey("depreciation_expense"), 100);
const carId = (await admin.from("fixed_assets").select("id").eq("company_id", company).single()).data.id;
must("بيع السيارة بـ 1000$ (قيمتها الدفترية 1100)", await u.rpc("dispose_fixed_asset", { target_company: company, target_asset: carId, target_date: today, target_amount: 1000, target_cashbox: usdBox, target_notes: "بعناها" }));
check("الأصول الثابتة بعد البيع", await byKey("fixed_assets"), 0);
check("مجمع الإهلاك بعد البيع", await byKey("accumulated_depreciation"), 0);
check("خسارة بيع الأصل", await byKey("asset_disposal_loss"), 100);
mustFail("بيعها مرة تانية", await u.rpc("dispose_fixed_asset", { target_company: company, target_asset: carId, target_date: today, target_amount: 5, target_cashbox: usdBox, target_notes: null }));

// ---------------------------------------------------------------- I. month close
log("\nI️⃣  إقفال الشهر");
must("إقفال", await u.rpc("close_finance_month", { target_company: company, target_year: Y, target_month: M }));
mustFail("مصروف بشهر مقفل", await u.rpc("record_expense", { target_company: company, target_cashbox: usdBox, expense_category: "rent", expense_amount: 10, expense_notes: null }));
must("إعادة فتح", await u.rpc("reopen_finance_month", { target_company: company, target_year: Y, target_month: M }));
must("مصروف بعد إعادة الفتح", await u.rpc("record_expense", { target_company: company, target_cashbox: usdBox, expense_category: "rent", expense_amount: 10, expense_notes: null }));

// ---------------------------------------------------------------- invariants
log("\n📐 قواعد لازم تكون صح دايمًا");
const { data: st } = await admin.from("inventory_stock").select("on_hand, average_cost").eq("company_id", company);
check("حساب المخزون = قيمة البضاعة الفعلية", await byKey("inventory"), st.reduce((s, r) => s + Number(r.on_hand) * Number(r.average_cost), 0));
const invStats = await u.rpc("get_inventory_stats", { target_company: company });
if (invStats.error) { failures++; log("   ❌ أرقام صفحة المخزون: " + invStats.error.message); }
else check("قيمة المخزون بصفحة المخزون = حساب المخزون", invStats.data[0].stock_value, await byKey("inventory"));
const { data: sis } = await admin.from("sales_invoices").select("balance_due").eq("company_id", company).eq("status", "posted");
check("ديون الزبائن بالحسابات = مجموع الفواتير المفتوحة", await byKey("accounts_receivable"), sis.reduce((s, r) => s + Number(r.balance_due), 0));
const ra = await u.rpc("get_receivables_aging", { target_company: company, target_as_of: today });
if (ra.error) { failures++; log("   ❌ تقرير أعمار ديون الزبائن: " + ra.error.message); }
else check("= تقرير أعمار ديون الزبائن", await byKey("accounts_receivable"), ra.data.reduce((s, r) => s + Number(r.total_due), 0));
const { data: pis } = await admin.from("purchase_invoices").select("balance_due").eq("company_id", company).eq("status", "posted");
check("ديون الموردين بالحسابات = مجموع الفواتير المفتوحة", -(await byKey("accounts_payable")), pis.reduce((s, r) => s + Number(r.balance_due), 0));
const pa = await u.rpc("get_payables_aging", { target_company: company, target_as_of: today });
if (pa.error) { failures++; log("   ❌ تقرير أعمار ديون الموردين: " + pa.error.message); }
else check("= تقرير أعمار ديون الموردين", -(await byKey("accounts_payable")), pa.data.reduce((s, r) => s + Number(r.total_due), 0));
const sm = await u.rpc("get_sales_monthly_report", { target_company: company, target_start: start, target_end: today });
const pm = await u.rpc("get_purchase_monthly_report", { target_company: company, target_start: start, target_end: today });
if (sm.error || pm.error) { failures++; log("   ❌ تقارير المبيعات/المشتريات الشهرية: " + (sm.error ?? pm.error).message); }
else {
  const { data: allSi } = await admin.from("sales_invoices").select("total").eq("company_id", company).eq("status", "posted");
  const { data: allSr } = await admin.from("sales_returns").select("total").eq("company_id", company).eq("status", "posted");
  check("تقرير المبيعات الشهري = الفواتير − المرتجعات", sm.data.reduce((t, r) => t + Number(r.net_sales), 0), allSi.reduce((t, r) => t + Number(r.total), 0) - allSr.reduce((t, r) => t + Number(r.total), 0));
}
const stmt = await u.rpc("get_trader_statement", { target_company: company, target_trader: trader, target_from: null, target_to: today });
if (stmt.error) { failures++; log("   ❌ كشف حساب الزبون: " + stmt.error.message); }
else {
  const { data: trInv } = await admin.from("sales_invoices").select("balance_due").eq("trader_id", trader).eq("status", "posted");
  const { data: trPay } = await admin.from("customer_payments").select("unallocated_total").eq("trader_id", trader).eq("status", "posted");
  check("كشف حساب الزبون: آخر رصيد = ديونو − رصيدو الدائن", stmt.data[stmt.data.length - 1].balance, trInv.reduce((t, r) => t + Number(r.balance_due), 0) - trPay.reduce((t, r) => t + Number(r.unallocated_total), 0));
}
const ov = await u.rpc("get_owner_overview", { target_company: company });
if (ov.error) { failures++; log("   ❌ لوحة المالك: " + ov.error.message); }
else {
  check("لوحة المالك: ديون الزبائن = الحسابات", ov.data.receivables, await byKey("accounts_receivable"));
  check("لوحة المالك: ديون الموردين = الحسابات", ov.data.payables, -(await byKey("accounts_payable")));
  check("لوحة المالك: صندوق الدولار", ov.data.cash.find((c) => c.currency === "USD")?.balance ?? 0, await byCode("1110"));
}
const cs = await u.rpc("get_cashbox_summary", { target_company: company, target_date: today });
if (cs.error) { failures++; log("   ❌ ملخص الصناديق: " + cs.error.message); }
else {
  const usd = cs.data.find((r) => r.currency === "USD"), syp = cs.data.find((r) => r.currency === "SYP");
  check("صندوق الدولار: الحسابات = شاشة الصندوق", await byCode("1110"), usd?.balance ?? 0);
  check("صندوق الليرة: شاشة الصندوق (ليرة)", syp?.balance ?? 0, 0);
}
const ledger = await u.rpc("get_supplier_ledger", { target_company: company, target_supplier: supplier, target_limit: 1 });
const summary = await u.rpc("get_supplier_financial_summary", { target_company: company, target_supplier: supplier });
if (ledger.error || summary.error) { failures++; log("   ❌ كشف/ملخص المورد: " + (ledger.error ?? summary.error).message); }
else check("كشف حساب المورد (مع المرتجع) = ملخص المورد", ledger.data[0]?.balance ?? 0, summary.data[0].net_balance);
const { data: all } = await admin.from("journal_lines").select("base_debit, base_credit, journal_entries!inner(company_id)").eq("journal_entries.company_id", company);
check("ميزان المراجعة", all.reduce((s, l) => s + Number(l.base_debit) - Number(l.base_credit), 0), 0);
const rep = await u.rpc("get_financial_report", { target_company: company, target_start: start, target_end: today });
if (rep.error) { failures++; log("   ❌ التقرير المالي: " + rep.error.message); }
else {
  const bs = rep.data.balance_sheet, pl = rep.data.profit_loss;
  check("الميزانية: الأصول = الالتزامات + حقوق الملكية", bs.assets, bs.liabilities + bs.equity_with_current_earnings);
  check("الربح بالتقرير = الربح بالميزانية", pl.net_profit, bs.current_earnings);
  log(`   الربح: ${pl.net_profit} | الأصول: ${bs.assets} | الالتزامات: ${bs.liabilities} | حقوق الملكية: ${bs.equity_with_current_earnings}`);
}
log(failures ? `\n❌ ${failures} مشكلة` : "\n✅ كل الفحوصات نجحت");
