// بيعبّي شركتك ببيانات تجريبية قليلة لتشوف كل الشاشات شغّالة: شركاء ورأس مال، أصناف، موردين ومشتريات،
// كونتينر استيراد بمصاريفو، زبائن عالخريطة، عروض أسعار وطلبيات وتوصيل مع سائق، فواتير وقبض، بيع سريع،
// مرتجع، تالف، مصاريف، موظفين ورواتب وسلفة، سيارة كأصل، أمر شراء، ورابط كتالوج.
// بيستعمل نفس الدوال اللي بتستعملها الشاشات، فالحسابات كلها حقيقية ومتطابقة.
//
// التشغيل (من مجلد المشروع):   node scripts/demo-data.mjs
// بيقرأ عنوان Supabase من .env.local، وبيسألك عن إيميلك وكلمة سرك، وعن الشركة إذا عندك أكتر من وحدة.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { createInterface } from "node:readline/promises";

const require = createRequire(import.meta.url);
const { createClient } = require("@supabase/supabase-js");

const MARKER_SUPPLIER = "مصنع نينغبو للإنارة"; // إذا موجود بالشركة، البيانات التجريبية منزّلة من قبل

function envFromFile() {
  try {
    const out = {};
    for (const line of readFileSync(".env.local", "utf8").split(/\r?\n/)) {
      const m = line.match(/^([A-Z_]+)=(.*)$/);
      if (m) out[m[1]] = m[2].trim().replace(/^"|"$/g, "");
    }
    return out;
  } catch {
    return {};
  }
}

const fileEnv = envFromFile();
const url = process.env.DEMO_SUPABASE_URL || fileEnv.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.DEMO_SUPABASE_KEY || fileEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
if (!url || !key) {
  console.error("ما لقيت عنوان Supabase. شغّل الأمر من مجلد المشروع (جنب ملف .env.local).");
  process.exit(1);
}

const rl = createInterface({ input: process.stdin, output: process.stdout });
const ask = async (q) => (await rl.question(q)).trim();
const email = process.env.DEMO_EMAIL || (await ask("الإيميل: "));
const password = process.env.DEMO_PASSWORD || (await ask("كلمة السر: "));

const db = createClient(url, key, { auth: { persistSession: false } });
const login = await db.auth.signInWithPassword({ email, password });
if (login.error) {
  console.error("ما قدرت فوت: الإيميل أو كلمة السر غلط.");
  process.exit(1);
}
const me = login.data.user.id;

function step(label, result) {
  if (result.error) {
    console.error(`❌ ${label}: ${result.error.message}`);
    process.exit(1);
  }
  console.log(`✅ ${label}`);
  return result.data;
}
const idOf = (data, ...keys) =>
  typeof data === "string" ? data : (keys.map((k) => data?.[k]).find(Boolean) ?? data?.id);
const days = (n) =>
  new Date(Date.now() - n * 86400000).toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
const today = days(0);
const monthStart = `${today.slice(0, 8)}01`;

// ------------------------------------------------------------------ أي شركة؟
const owned = (await db.from("companies").select("id,name").eq("owner_user_id", me).order("created_at")).data ?? [];
let company;
if (process.env.DEMO_COMPANY) {
  company = owned.find((c) => c.name === process.env.DEMO_COMPANY)?.id;
} else if (owned.length === 1) {
  const ok = await ask(`رح عبّي شركة "${owned[0].name}" ببيانات تجريبية. متأكد؟ اكتب y: `);
  if (ok.toLowerCase() !== "y") process.exit(0);
  company = owned[0].id;
} else if (owned.length > 1) {
  owned.forEach((c, i) => console.log(`${i + 1}) ${c.name}`));
  company = owned[Number(await ask("رقم الشركة: ")) - 1]?.id;
}
rl.close();
if (!company) {
  if (owned.length) {
    console.error("ما اخترت شركة.");
    process.exit(1);
  }
  step("الشركة", await db.from("companies").insert({ name: "شركتي", default_currency: "USD" }));
  company = (await db.from("companies").select("id").eq("owner_user_id", me).single()).data.id;
}

const already = await db.from("suppliers").select("id").eq("company_id", company).eq("name", MARKER_SUPPLIER);
if ((already.data ?? []).length) {
  console.log("البيانات التجريبية منزّلة بهالشركة من قبل؛ ما رح كررها.");
  process.exit(0);
}

const box = (await db.from("cashboxes").select("id").eq("company_id", company).eq("currency", "USD").eq("active", true).limit(1).single()).data?.id;
const wh = (await db.from("warehouses").select("id").eq("company_id", company).eq("active", true).order("is_default", { ascending: false }).limit(1).single()).data?.id;
if (!box || !wh) {
  console.error("ما لقيت صندوق دولار أو مستودع فعّال بالشركة.");
  process.exit(1);
}

// ------------------------------------------------------------------ رأس المال
const partner1 = await db.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "أبو خالد (تجريبي)", target_phone: null, target_ownership_percent: 60, target_profit_share_percent: 60, target_notes: null, target_active: true });
const partner2 = partner1.error ? partner1 : await db.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "أبو سامر (تجريبي)", target_phone: null, target_ownership_percent: 40, target_profit_share_percent: 40, target_notes: null, target_active: true });
if (!partner1.error && !partner2.error) {
  console.log("✅ شريكين: أبو خالد 60% وأبو سامر 40%");
  step("رأس مال 12000$", await db.rpc("record_partner_transaction", { target_company: company, target_partner: idOf(partner1.data), target_type: "capital_contribution", target_amount: 12000, target_currency: "USD", target_cashbox: box, target_date: days(20), target_notes: "رأس مال تجريبي" }));
  step("رأس مال 8000$", await db.rpc("record_partner_transaction", { target_company: company, target_partner: idOf(partner2.data), target_type: "capital_contribution", target_amount: 8000, target_currency: "USD", target_cashbox: box, target_date: days(20), target_notes: "رأس مال تجريبي" }));
} else {
  // في شركاء من قبل (الملكية مكتملة): منحط رصيد افتتاحي بالصندوق بدالهن.
  step("رصيد افتتاحي بالصندوق 20000$", await db.rpc("record_cash_movement", { target_company: company, target_cashbox: box, movement_type: "adjustment_in", movement_amount: 20000, movement_notes: "رصيد تجريبي" }));
}

// ------------------------------------------------------------------ التصنيفات والأصناف
const cat = {};
for (const name of ["إنارة", "كبلات", "قواطع وبرايز", "أجهزة"]) {
  const found = (await db.from("categories").select("id").eq("company_id", company).eq("name", name).maybeSingle()).data;
  cat[name] = found?.id ?? step(`تصنيف ${name}`, await db.from("categories").insert({ company_id: company, name }).select("id").single()).id;
}
const P = {};
for (const [name, sku, category, price, min, pack, cost] of [
  ["لمبة LED 12 واط", "LED-12", "إنارة", 1.5, 1.2, 50, 0.6],
  ["لمبة LED 18 واط", "LED-18", "إنارة", 2.25, 1.8, 50, 0.9],
  ["كبل 2.5 مم (لفة 100م)", "CBL-25", "كبلات", 35, 30, null, 22],
  ["كبل 4 مم (لفة 100م)", "CBL-40", "كبلات", 55, 48, null, 36],
  ["قاطع 16 أمبير", "BRK-16", "قواطع وبرايز", 4, 3.2, 12, 2.2],
  ["بريز مزدوج", "SKT-2", "قواطع وبرايز", 2.5, 2, 20, 1.1],
  ["براد 16 قدم", "FR-16", "أجهزة", 320, 300, null, 210],
  ["مروحة سقف", "FAN-56", "أجهزة", 45, 38, null, 28],
  ["مكيف 18000 BTU", "AC-18", "أجهزة", 450, 420, null, 300],
]) {
  P[sku] = { cost };
  P[sku].id = step(
    `صنف ${name}`,
    await db.from("products").insert({ company_id: company, name, sku, category_id: cat[category], unit: "قطعة", sale_price: price, minimum_sale_price: min, reorder_level: pack ?? 3, pack_size: pack, pack_unit: pack ? "كرتونة" : null, warranty_months: category === "أجهزة" ? 12 : null }).select("id").single()
  ).id;
}

// ------------------------------------------------------------------ الموردين والمشتريات المحلية
const china = step(`مورد: ${MARKER_SUPPLIER}`, await db.from("suppliers").insert({ company_id: company, name: MARKER_SUPPLIER, phone: "+8613800001111", country: "الصين" }).select("id").single()).id;
const local = step("مورد: مؤسسة الشام للكهربائيات", await db.from("suppliers").insert({ company_id: company, name: "مؤسسة الشام للكهربائيات", phone: "+963933111222", country: "سوريا" }).select("id").single()).id;

async function purchaseInvoice(label, supplier, ref, date, lines) {
  const inv = step(label, await db.rpc("create_purchase_invoice", { target_company: company, target_supplier: supplier, target_supplier_invoice_number: ref, target_invoice_date: date, target_due_date: null, target_notes: null, items_payload: lines.map(([sku, qty, cost]) => ({ product_id: P[sku].id, quantity: qty, unit_cost: cost ?? P[sku].cost })) }));
  return idOf(inv, "invoice_id");
}
async function receive(invId, date, label) {
  const items = (await db.from("purchase_invoice_items").select("id, quantity").eq("invoice_id", invId)).data;
  step(label, await db.rpc("receive_purchase_invoice", { target_company: company, target_invoice: invId, target_warehouse: wh, target_receipt_date: date, target_notes: null, items_payload: items.map((it) => ({ purchase_invoice_item_id: it.id, quantity: Number(it.quantity) })) }));
}
const totalOf = async (invId) => Number((await db.from("purchase_invoices").select("total").eq("id", invId).single()).data.total);

const piLocal = await purchaseInvoice("فاتورة شراء محلية", local, "SH-551", days(15), [["CBL-25", 30], ["CBL-40", 20], ["BRK-16", 120], ["SKT-2", 100], ["FR-16", 8], ["LED-12", 400]]);
await receive(piLocal, days(15), "  استلام البضاعة بالمستودع");
const localTotal = await totalOf(piLocal);
step(`  دفعة كاملة للمورد المحلي ${localTotal}$`, await db.rpc("record_supplier_payment", { target_company: company, target_supplier: local, target_cashbox: box, target_amount: localTotal, target_payment_date: days(14), target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: piLocal, amount: localTotal }] }));

// ------------------------------------------------------------------ الاستيراد: كونتينر وصل وانقفل، وكونتينر بالطريق
const ship1 = step("كونتينر من الصين (وصل)", await db.rpc("save_import_shipment", { target_company: company, target_shipment: null, target_container: "MSKU7712345", target_origin: "الصين - نينغبو", target_shipped_on: days(40), target_expected_on: days(12), target_arrived_on: days(12), target_status: "arrived", target_notes: "كونتينر تجريبي" }));
const piChina = await purchaseInvoice("  فاتورة المصنع: 20 مكيف + 1000 لمبة 18 واط + 30 مروحة", china, "NB-2026-07", days(40), [["AC-18", 20, 300], ["LED-18", 1000, 0.85], ["FAN-56", 30, 26]]);
step("  ربط الفاتورة بالكونتينر", await db.rpc("link_invoice_to_shipment", { target_company: company, target_invoice: piChina, target_shipment: ship1 }));
for (const [type, amount, label] of [["freight", 1200, "شحن بحري 1200$ (حسب الحجم)"], ["customs", 800, "جمرك 800$ (حسب الوزن)"], ["transport", 150, "نقل من المرفأ 150$ (حسب الوزن)"]]) {
  step(`  ${label}`, await db.rpc("add_shipment_cost", { target_company: company, target_shipment: ship1, target_type: type, target_amount: amount, target_cashbox: box, target_date: days(12), target_notes: null }));
}
await receive(piChina, days(11), "  استلام الكونتينر بالمستودع");
step("  الوزن والحجم من البيان الجمركي", await db.rpc("save_shipment_measures", { target_company: company, target_shipment: ship1, items_payload: [{ product_id: P["AC-18"].id, weight_kg: 900, volume_cbm: 12 }, { product_id: P["LED-18"].id, weight_kg: 250, volume_cbm: 3 }, { product_id: P["FAN-56"].id, weight_kg: 300, volume_cbm: 4 }] }));
step("  توزيع المصاريف وإقفال الكونتينر (الكلفة الواصلة)", await db.rpc("close_import_shipment", { target_company: company, target_shipment: ship1 }));
step("  دفعة للمصنع 5000$", await db.rpc("record_supplier_payment", { target_company: company, target_supplier: china, target_cashbox: box, target_amount: 5000, target_payment_date: days(10), target_method: "cash", target_reference: "حوالة", target_notes: null, allocations_payload: [{ purchase_invoice_id: piChina, amount: 5000 }] }));

const ship2 = step("كونتينر تاني (لسا بالبحر)", await db.rpc("save_import_shipment", { target_company: company, target_shipment: null, target_container: "MSKU9988776", target_origin: "الصين - نينغبو", target_shipped_on: days(9), target_expected_on: days(-20), target_arrived_on: null, target_status: "shipped", target_notes: "كونتينر تجريبي" }));
const piChina2 = await purchaseInvoice("  فاتورة المصنع: 15 مكيف", china, "NB-2026-09", days(9), [["AC-18", 15, 295]]);
step("  ربط الفاتورة بالكونتينر", await db.rpc("link_invoice_to_shipment", { target_company: company, target_invoice: piChina2, target_shipment: ship2 }));

step("أمر شراء مبعوت للمورد المحلي (لسا ما وصل)", await db.rpc("create_purchase_order", { target_company: company, target_supplier: local, target_expected_date: days(-5), target_notes: "تجريبي", items_payload: [{ product_id: P["CBL-25"].id, quantity: 20, unit_cost: 22 }, { product_id: P["SKT-2"].id, quantity: 100, unit_cost: 1.1 }] }));

// ------------------------------------------------------------------ الموظفين
async function employee(name, job, salary, phone) {
  return idOf(step(`موظف: ${name} (${job}) راتبو ${salary}$`, await db.rpc("save_employee", { target_company: company, target_employee: null, target_employee_number: null, target_name: name, target_phone: phone, target_job_title: job, target_department: null, target_hire_date: days(60), target_salary_currency: "USD", target_base_salary: salary, target_fixed_allowances: 0, target_overtime_rate: 0, target_employee_social_rate: 0, target_employer_social_rate: 0, target_income_tax_rate: 0, target_cashbox: box, target_notes: "موظف تجريبي", target_status: "active" })), "employee_id");
}
const driver = await employee("سامر الحلبي", "سائق", 250, "+963988111222");
const rep = await employee("رامي الشامي", "مندوب مبيعات", 300, "+963988333444");
await employee("ليلى الخطيب", "محاسبة", 350, "+963988555666");
step("  سامر سائق", await db.rpc("set_employee_roles", { target_company: company, target_employee: driver, target_is_driver: true, target_is_sales_rep: false, target_commission_rate: 0 }));
step("  رامي مندوب بعمولة 3%", await db.rpc("set_employee_roles", { target_company: company, target_employee: rep, target_is_driver: false, target_is_sales_rep: true, target_commission_rate: 3 }));
const loan = step("  سلفة لسامر 100$ (قسط 50$)", await db.rpc("create_employee_loan", { target_company: company, target_employee: driver, target_type: "advance", target_amount: 100, target_installment: 50, target_start_date: days(5), target_notes: null }));
step("  صرف السلفة", await db.rpc("disburse_employee_loan", { target_company: company, target_loan: idOf(loan, "loan_id"), target_cashbox: box, target_date: days(5) }));

// ------------------------------------------------------------------ الزبائن (مع مواقعهن عالخريطة)
const T = {};
for (const [k, name, contact, area, phone, limit, lat, lng, withRep] of [
  ["khaled", "محل أبو خالد للكهربائيات", "أبو خالد", "الميدان", "+963933123456", 2000, 33.4951, 36.2993, true],
  ["noor", "كهربائيات النور", "أبو أحمد", "المزة", "+963944222333", 1500, 33.5036, 36.2519, true],
  ["salam", "محل السلام", "أبو محمد", "جرمانا", "+963955333444", 1000, 33.4877, 36.3481, false],
  ["furat", "مؤسسة الفرات", "أبو علي", "دوما", "+963966444555", 3000, 33.5711, 36.4033, true],
  ["amal", "كهربائيات الأمل", "أبو يوسف", "باب توما", "+963977555666", 1200, 33.5133, 36.3164, false],
  ["rabee", "محل الربيع", "أبو حسن", "ركن الدين", "+963999666777", 800, 33.5364, 36.2956, true],
]) {
  T[k] = step(`زبون ${name} (${area})`, await db.from("traders").insert({ company_id: company, name, contact_name: contact, area, phone, whatsapp: phone, status: "customer", credit_limit: limit, payment_terms_days: 30, latitude: lat, longitude: lng, ...(withRep ? { sales_rep_id: rep } : {}) }).select("id").single()).id;
}

// ------------------------------------------------------------------ المبيعات: عرض ← طلبية ← توصيل (مع السائق) ← فاتورة ← قبض
async function sale(label, trader, lines, { deliver = "done", pay = 0 } = {}) {
  const q = step(`عرض سعر: ${label}`, await db.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: lines.map(([sku, qty, price]) => ({ product_id: P[sku].id, quantity: qty, sale_unit_price: price })) }));
  const qId = idOf(q, "quote_id");
  await db.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "sent" });
  await db.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "accepted" });
  const conv = step("  تحويل لطلبية", await db.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: qId }));
  const orderId = conv?.order_id ?? conv;
  if (deliver === "none") return null;
  const items = (await db.from("sales_order_items").select("id, quantity").eq("order_id", orderId)).data;
  const delivery = step("  طلعت مع السائق سامر", await db.rpc("create_order_delivery", { target_company: company, target_order: orderId, items_payload: items.map((it) => ({ sales_order_item_id: it.id, quantity: Number(it.quantity) })) }));
  await db.rpc("set_delivery_driver", { target_company: company, target_delivery: idOf(delivery, "delivery_id"), target_driver: driver });
  if (deliver === "out") return null;
  step("  تم التسليم (انعملت الفاتورة)", await db.rpc("complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null }));
  const inv = (await db.from("sales_invoices").select("id, total").eq("order_id", orderId).single()).data;
  if (pay > 0) {
    const amount = Math.min(pay, Number(inv.total));
    step(`  قبض ${amount}$`, await db.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: box, target_amount: amount, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv.id, amount }] }));
  }
  return inv;
}

const invKhaled = await sale("أبو خالد: لمبات وقواطع وبرايز", T.khaled, [["LED-12", 100, 1.5], ["BRK-16", 24, 4], ["SKT-2", 20, 2.5]], { pay: 9999 });
await sale("كهربائيات النور: كبلات", T.noor, [["CBL-25", 5, 35], ["CBL-40", 3, 55]], { pay: 200 });
await sale("محل السلام: براد ومروحتين", T.salam, [["FR-16", 1, 320], ["FAN-56", 2, 45]]);
await sale("كهربائيات الأمل: 3 مكيفات", T.amal, [["AC-18", 3, 450]], { pay: 1000 });
await sale("محل الربيع: لمبات 18 واط", T.rabee, [["LED-18", 150, 2.25]], { deliver: "out" });
await sale("مؤسسة الفرات: طلبية جاهزة بالمستودع", T.furat, [["LED-18", 100, 2.25], ["CBL-25", 4, 35]], { deliver: "none" });
step("عرض سعر مفتوح لمؤسسة الفرات (مكيفين)", await db.rpc("create_sales_quote", { target_company: company, target_trader: T.furat, target_valid_until: days(-7), target_notes: "عرض تجريبي", items_payload: [{ product_id: P["AC-18"].id, quantity: 2, sale_unit_price: 440 }] }));

// ------------------------------------------------------------------ بيع سريع، مرتجع، تالف، مصاريف، رواتب، أصل، كتالوج
step("بيع سريع لزبون نقدي (5 لمبات)", await db.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: P["LED-12"].id, quantity: 5, sale_unit_price: 1.5 }], target_cashbox: box, target_paid_amount: 7.5, target_cash_amount: 7.5 }));
step("بيع سريع لزبون نقدي (مروحة)", await db.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: P["FAN-56"].id, quantity: 1, sale_unit_price: 45 }], target_cashbox: box, target_paid_amount: 45, target_cash_amount: 45 }));
const retItem = (await db.from("sales_invoice_items").select("id").eq("invoice_id", invKhaled.id).eq("product_id", P["LED-12"].id).single()).data.id;
step("مرتجع: أبو خالد رجّع 10 لمبات (صار إلو رصيد عنا)", await db.rpc("create_sales_return", { target_company: company, target_invoice: invKhaled.id, target_warehouse: wh, target_date: today, target_notes: "لمبات معطلة (تجريبي)", items_payload: [{ sales_invoice_item_id: retItem, quantity: 10 }] }));
step("بضاعة تالفة: 3 لمبات انكسرت", await db.rpc("record_damaged_goods", { target_company: company, target_warehouse: wh, target_product: P["LED-18"].id, target_quantity: 3, target_reason: "انكسرت بالتنزيل (تجريبي)" }));
for (const [category, amount, note] of [["إيجار", 300, "إيجار المحل"], ["بنزين", 40, "سيارة التوصيل"], ["هاتف وإنترنت", 15, null], ["طعام شغل", 25, null]]) {
  step(`مصروف ${category} ${amount}$`, await db.rpc("record_expense", { target_company: company, target_cashbox: box, expense_category: category, expense_amount: amount, expense_notes: note }));
}
const run = await db.rpc("create_payroll_run", { target_company: company, target_period_start: monthStart, target_period_end: today, target_pay_date: today, target_currency: "USD", target_notes: "رواتب تجريبية" });
if (run.error) {
  console.log(`⚠️ رواتب الشهر ما انعملت (${run.error.message}) — فيك تعملها من صفحة الرواتب.`);
} else {
  console.log("✅ مسير رواتب الشهر");
  const runId = idOf(run.data, "run_id", "payroll_run_id");
  step("  ترحيل المسير", await db.rpc("post_payroll_run", { target_company: company, target_run: runId }));
  const item = (await db.from("payroll_items").select("id, net_pay").eq("payroll_run_id", runId).eq("employee_id", driver).single()).data;
  if (item) step(`  دفع راتب سامر ${item.net_pay}$ (بعد قسط السلفة)`, await db.rpc("record_payroll_payment", { target_company: company, target_payroll_item: item.id, target_cashbox: box, target_amount: item.net_pay, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null }));
}
step("سيارة توصيل 6000$ (أصل ثابت، عمرها 5 سنين)", await db.rpc("create_fixed_asset", { target_company: company, target_name: "سيارة توصيل (تجريبي)", target_category: "vehicles", target_description: null, target_purchase_date: days(30), target_in_service_date: days(30), target_currency: "USD", target_purchase_cost: 6000, target_salvage_value: 1000, target_useful_life_months: 60, target_notes: null, target_cashbox: box }));
step("رابط كتالوج للتجار", await db.rpc("save_catalog_link", { target_company: company, target_link: null, settings: { title: "كتالوج تجريبي", show_prices: true, stock_mode: "available" } }));

console.log("\n🎉 خلصنا. فوت عالبرنامج وشوف: الرئيسية، المبيعات، التوصيل، الخريطة، الاستيراد، الرواتب، التقارير.");
process.exit(0);
