// بيعمل "شركة تجريبية" منفصلة بحسابك ويعبّيها ببيانات وهمية قليلة لتشوف كل الشاشات شغّالة.
// ما بيلمس أي شركة تانية. بيستعمل نفس الدوال اللي بتستعملها الشاشات، فالحسابات حقيقية.
//
// التشغيل (من مجلد المشروع):   node scripts/demo-data.mjs
// بيقرأ عنوان Supabase من .env.local وبيسألك عن إيميلك وكلمة سرك.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { createInterface } from "node:readline/promises";

const require = createRequire(import.meta.url);
const { createClient } = require("@supabase/supabase-js");

const DEMO_NAME = "شركة تجريبية";

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

let email = process.env.DEMO_EMAIL;
let password = process.env.DEMO_PASSWORD;
if (!email || !password) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  email = (await rl.question("الإيميل: ")).trim();
  password = (await rl.question("كلمة السر: ")).trim();
  rl.close();
}

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
  typeof data === "string" ? data : keys.map((k) => data?.[k]).find(Boolean) ?? data?.id;

const days = (n) => {
  const d = new Date(Date.now() - n * 86400000);
  return d.toLocaleDateString("en-CA", { timeZone: "Asia/Damascus" });
};
const today = days(0);

// ------------------------------------------------------------------ الشركة
const existing = await db
  .from("company_members")
  .select("companies!inner(id,name)")
  .eq("user_id", me)
  .eq("companies.name", DEMO_NAME);
if ((existing.data ?? []).length) {
  console.log(`في "${DEMO_NAME}" عندك من قبل؛ ما رح اعمل وحدة تانية.`);
  process.exit(0);
}

step("الشركة التجريبية", await db.from("companies").insert({ name: DEMO_NAME, default_currency: "USD", phone: "+963944000000", whatsapp: "+963944000000", address: "دمشق - الحريقة" }));
const company = (
  await db.from("companies").select("id").eq("owner_user_id", me).eq("name", DEMO_NAME).order("created_at", { ascending: false }).limit(1).single()
).data.id;
const box = (await db.from("cashboxes").select("id").eq("company_id", company).limit(1).single()).data.id;
const wh = (await db.from("warehouses").select("id").eq("company_id", company).limit(1).single()).data.id;

// ------------------------------------------------------------------ الشركاء ورأس المال
const p1 = idOf(step("شريك: أبو خالد 60%", await db.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "أبو خالد", target_phone: null, target_ownership_percent: 60, target_profit_share_percent: 60, target_notes: null, target_active: true })));
const p2 = idOf(step("شريك: أبو سامر 40%", await db.rpc("save_partner", { target_company: company, target_partner: null, target_number: null, target_name: "أبو سامر", target_phone: null, target_ownership_percent: 40, target_profit_share_percent: 40, target_notes: null, target_active: true })));
step("رأس مال 6000$", await db.rpc("record_partner_transaction", { target_company: company, target_partner: p1, target_type: "capital_contribution", target_amount: 6000, target_currency: "USD", target_cashbox: box, target_date: days(10), target_notes: "رأس مال تجريبي" }));
step("رأس مال 4000$", await db.rpc("record_partner_transaction", { target_company: company, target_partner: p2, target_type: "capital_contribution", target_amount: 4000, target_currency: "USD", target_cashbox: box, target_date: days(10), target_notes: "رأس مال تجريبي" }));

// ------------------------------------------------------------------ التصنيفات والأصناف
const cat = {};
for (const name of ["إنارة", "كبلات", "قواطع وبرايز", "أجهزة"]) {
  cat[name] = step(`تصنيف ${name}`, await db.from("categories").insert({ company_id: company, name }).select("id").single()).id;
}
const productRows = [
  ["لمبة LED 12 واط", "LED-12", "إنارة", 1.5, 1.2, 50, 0.6],
  ["لمبة LED 18 واط", "LED-18", "إنارة", 2.25, 1.8, 50, 0.9],
  ["كبل 2.5 مم (لفة 100م)", "CBL-25", "كبلات", 35, 30, null, 22],
  ["كبل 4 مم (لفة 100م)", "CBL-40", "كبلات", 55, 48, null, 36],
  ["قاطع 16 أمبير", "BRK-16", "قواطع وبرايز", 4, 3.2, 12, 2.2],
  ["بريز مزدوج", "SKT-2", "قواطع وبرايز", 2.5, 2, 20, 1.1],
  ["براد 16 قدم", "FR-16", "أجهزة", 320, 300, null, 210],
  ["مروحة سقف", "FAN-56", "أجهزة", 45, 38, null, 28],
];
const P = {};
for (const [name, sku, category, price, min, pack, cost] of productRows) {
  P[sku] = { cost };
  P[sku].id = step(
    `صنف ${name}`,
    await db.from("products").insert({ company_id: company, name, sku, category_id: cat[category], unit: "قطعة", sale_price: price, minimum_sale_price: min, reorder_level: pack ? pack : 3, pack_size: pack, pack_unit: pack ? "كرتونة" : null, warranty_months: category === "أجهزة" ? 12 : null }).select("id").single()
  ).id;
}

// ------------------------------------------------------------------ الموردين والمشتريات
const china = step("مورد: مصنع نينغبو للإنارة", await db.from("suppliers").insert({ company_id: company, name: "مصنع نينغبو للإنارة", phone: "+8613800001111", country: "الصين" }).select("id").single()).id;
const local = step("مورد: مؤسسة الشام للكهربائيات", await db.from("suppliers").insert({ company_id: company, name: "مؤسسة الشام للكهربائيات", phone: "+963933111222", country: "سوريا" }).select("id").single()).id;

async function purchase(label, supplier, ref, date, lines) {
  const inv = step(label, await db.rpc("create_purchase_invoice", { target_company: company, target_supplier: supplier, target_supplier_invoice_number: ref, target_invoice_date: date, target_due_date: null, target_notes: null, items_payload: lines.map(([sku, qty]) => ({ product_id: P[sku].id, quantity: qty, unit_cost: P[sku].cost })) }));
  const invId = idOf(inv, "invoice_id");
  const items = (await db.from("purchase_invoice_items").select("id").eq("invoice_id", invId)).data;
  step(`  استلام البضاعة (${ref})`, await db.rpc("receive_purchase_invoice", { target_company: company, target_invoice: invId, target_warehouse: wh, target_receipt_date: date, target_notes: null, items_payload: items.map((it, i) => ({ purchase_invoice_item_id: it.id, quantity: lines[i][1] })) }));
  return invId;
}
const pi1 = await purchase("فاتورة شراء من الصين", china, "NB-2026-01", days(8), [["LED-12", 500], ["LED-18", 300], ["FAN-56", 20]]);
const pi2 = await purchase("فاتورة شراء محلية", local, "SH-551", days(7), [["CBL-25", 30], ["CBL-40", 20], ["BRK-16", 120], ["SKT-2", 100], ["FR-16", 8]]);
step("دفعة للمورد الصيني 400$", await db.rpc("record_supplier_payment", { target_company: company, target_supplier: china, target_cashbox: box, target_amount: 400, target_payment_date: days(6), target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: pi1, amount: 400 }] }));
const pi2Row = (await db.from("purchase_invoices").select("total").eq("id", pi2).single()).data;
step(`دفعة كاملة للمورد المحلي ${pi2Row.total}$`, await db.rpc("record_supplier_payment", { target_company: company, target_supplier: local, target_cashbox: box, target_amount: Number(pi2Row.total), target_payment_date: days(5), target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ purchase_invoice_id: pi2, amount: Number(pi2Row.total) }] }));

// ------------------------------------------------------------------ الزبائن
const traders = {};
for (const [name, contact, area, phone, limit] of [
  ["محل أبو خالد للكهربائيات", "أبو خالد", "الميدان", "+963933123456", 2000],
  ["كهربائيات النور", "أبو أحمد", "المزة", "+963944222333", 1500],
  ["محل السلام", "أبو محمد", "جرمانا", "+963955333444", 1000],
  ["مؤسسة الفرات", "أبو علي", "دوما", "+963966444555", 3000],
]) {
  traders[area] = step(`زبون ${name}`, await db.from("traders").insert({ company_id: company, name, contact_name: contact, area, phone, whatsapp: phone, status: "customer", credit_limit: limit, payment_terms_days: 30 }).select("id").single()).id;
}

// ------------------------------------------------------------------ المبيعات: عرض سعر ← طلبية ← توصيل ← فاتورة
async function sale(label, trader, lines, { deliver = true, pay = 0 } = {}) {
  const q = step(`عرض سعر: ${label}`, await db.rpc("create_sales_quote", { target_company: company, target_trader: trader, target_valid_until: null, target_notes: null, items_payload: lines.map(([sku, qty, price]) => ({ product_id: P[sku].id, quantity: qty, sale_unit_price: price })) }));
  const qId = idOf(q, "quote_id");
  step("  إرسال", await db.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "sent" }));
  step("  قبول", await db.rpc("set_sales_quote_status", { target_company: company, target_quote: qId, target_status: "accepted" }));
  const conv = step("  تحويل لطلبية", await db.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: qId }));
  const orderId = conv?.order_id ?? conv;
  if (!deliver) return null;
  const items = (await db.from("sales_order_items").select("id, quantity").eq("order_id", orderId)).data;
  step("  تجهيز التسليمة", await db.rpc("create_order_delivery", { target_company: company, target_order: orderId, items_payload: items.map((it) => ({ sales_order_item_id: it.id, quantity: Number(it.quantity) })) }));
  step("  تم التسليم (انعملت الفاتورة)", await db.rpc("complete_order_delivery", { target_company: company, target_order: orderId, target_notes: null }));
  const inv = (await db.from("sales_invoices").select("id, total").eq("order_id", orderId).single()).data;
  if (pay > 0) {
    const amount = Math.min(pay, Number(inv.total));
    step(`  قبض ${amount}$`, await db.rpc("record_customer_payment", { target_company: company, target_trader: trader, target_cashbox: box, target_amount: amount, target_payment_date: today, target_method: "cash", target_reference: null, target_notes: null, allocations_payload: [{ sales_invoice_id: inv.id, amount }] }));
  }
  return inv;
}

const inv1 = await sale("أبو خالد (لمبات وقواطع)", traders["الميدان"], [["LED-12", 100, 1.5], ["BRK-16", 24, 4], ["SKT-2", 20, 2.5]], { pay: 9999 });
await sale("كهربائيات النور (كبلات)", traders["المزة"], [["CBL-25", 5, 35], ["CBL-40", 3, 55]], { pay: 200 });
await sale("محل السلام (براد ومروحة)", traders["جرمانا"], [["FR-16", 1, 320], ["FAN-56", 2, 45]]);
await sale("مؤسسة الفرات (طلبية جاهزة ما انشحنت)", traders["دوما"], [["LED-18", 100, 2.25], ["CBL-25", 4, 35]], { deliver: false });
step("عرض سعر مفتوح لمؤسسة الفرات", await db.rpc("create_sales_quote", { target_company: company, target_trader: traders["دوما"], target_valid_until: null, target_notes: "عرض تجريبي", items_payload: [{ product_id: P["FR-16"].id, quantity: 2, sale_unit_price: 315 }] }));

// ------------------------------------------------------------------ بيع سريع، مرتجع، مصاريف، كتالوج
step("بيع سريع لزبون نقدي (5 لمبات)", await db.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: P["LED-12"].id, quantity: 5, sale_unit_price: 1.5 }], target_cashbox: box, target_paid_amount: 7.5, target_cash_amount: 7.5 }));
step("بيع سريع لزبون نقدي (مروحة)", await db.rpc("quick_sale", { target_company: company, target_trader: null, items_payload: [{ product_id: P["FAN-56"].id, quantity: 1, sale_unit_price: 45 }], target_cashbox: box, target_paid_amount: 45, target_cash_amount: 45 }));
const retItem = (await db.from("sales_invoice_items").select("id").eq("invoice_id", inv1.id).eq("product_id", P["LED-12"].id).single()).data.id;
step("مرتجع: أبو خالد رجّع 10 لمبات", await db.rpc("create_sales_return", { target_company: company, target_invoice: inv1.id, target_warehouse: wh, target_date: today, target_notes: "لمبات معطلة (تجريبي)", items_payload: [{ sales_invoice_item_id: retItem, quantity: 10 }] }));
for (const [category, amount, note] of [["إيجار", 300, "إيجار المحل"], ["بنزين", 40, "سيارة التوصيل"], ["هاتف وإنترنت", 15, null]]) {
  step(`مصروف ${category} ${amount}$`, await db.rpc("record_expense", { target_company: company, target_cashbox: box, expense_category: category, expense_amount: amount, expense_notes: note }));
}
step("رابط كتالوج للتجار", await db.rpc("save_catalog_link", { target_company: company, target_link: null, settings: { title: "كتالوج تجريبي", show_prices: true, stock_mode: "available" } }));

console.log(`\n🎉 خلصنا. فوت عالبرنامج، ومن قائمة اسمك (تحت عاليمين) اختار "${DEMO_NAME}".`);
process.exit(0);
