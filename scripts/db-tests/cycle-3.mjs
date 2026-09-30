// Part 3: product catalog links for traders — public view (no login), settings, and ordering from the catalog.
import { admin, newUserClient } from "./local-supabase.mjs";

const u = newUserClient();
const guest = newUserClient(); // زائر بدون تسجيل دخول

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
function ok(label, cond, detail = "") {
  if (!cond) failures++;
  log(`   ${cond ? "✅" : "❌"} ${label}${cond ? "" : `  ${detail}`}`);
}

log("0️⃣  تجهيز");
const email = `cycle3${Date.now()}@test.local`;
await admin.auth.admin.createUser({ email, password: "Passw0rd!x", email_confirm: true });
await u.auth.signInWithPassword({ email, password: "Passw0rd!x" });
must("الشركة", await u.from("companies").insert({ name: "شركة الكتالوج", default_currency: "USD", whatsapp: "+963944000000" }));
const company = (await u.from("company_members").select("company_id").single()).data.company_id;
const wh = (await u.from("warehouses").select("id").eq("company_id", company).single()).data.id;

const lamps = must("تصنيف لمبات", await u.from("categories").insert({ company_id: company, name: "لمبات" }).select("id").single())?.id;
const cables = must("تصنيف كبلات", await u.from("categories").insert({ company_id: company, name: "كبلات" }).select("id").single())?.id;
const product = async (name, category, price) =>
  must(name, await u.rpc("save_product_with_supplier_prices", {
    target_company: company, target_product: null, product_name: name, product_sku: null, product_brand: "ABC",
    target_category: category, product_unit: "قطعة", product_sale_price: price, product_minimum_sale_price: null,
    product_image_url: "https://example.com/x.jpg", product_active: true, supplier_prices_payload: [],
  }));
const lamp = await product("لمبة LED", lamps, 2);
const cable = await product("كبل 2 مم", cables, 10);
const empty = await product("لمبة نفدت", lamps, 3);
const level = must("مستوى جملة", await u.from("price_levels").insert({ company_id: company, name: "جملة" }).select("id").single())?.id;
must("شرح اللمبة وسعر الجملة", await u.rpc("save_product_packaging_and_prices", {
  target_company: company, target_product: lamp, product_pack_size: 50, product_pack_unit: "كرتونة",
  level_prices: [{ price_level_id: level, price: 1.5 }], product_description: "لمبة 12 واط، ضوء أبيض",
}));
// المخزون مباشرة (هاد الفحص عن الكتالوج مش عن الشراء).
must("مخزون", await admin.from("inventory_stock").insert([
  { company_id: company, warehouse_id: wh, product_id: lamp, on_hand: 120, average_cost: 1 },
  { company_id: company, warehouse_id: wh, product_id: cable, on_hand: 7, average_cost: 6 },
]));
const trader = must("تاجر", await u.from("traders").insert({ company_id: company, name: "محل النور", phone: "+963933111222", status: "customer", price_level_id: level }).select("id").single())?.id;
must("تاجر تاني", await u.from("traders").insert({ company_id: company, name: "محل تاني", phone: "+963933999888", status: "customer" }));

log("\n1️⃣  الزائر ما بيشوف شي بدون رابط");
const direct = await guest.from("products").select("id");
ok("الزائر ما بيقرا جدول الأصناف", direct.error || (direct.data ?? []).length === 0);
mustFail("الزائر ما بيعمل رابط", await guest.rpc("save_catalog_link", { target_company: company, target_link: null, settings: {} }));
const bad = await guest.rpc("get_public_catalog", { target_token: "x".repeat(64) });
ok("رمز غلط = ما في كتالوج", !bad.error && bad.data === null, JSON.stringify(bad));

log("\n2️⃣  رابط عام: مع أسعار عادية ومتوفر/غير متوفر");
const pub = must("رابط عام", await u.rpc("save_catalog_link", { target_company: company, target_link: null, settings: { title: "كتالوج الكل" } }));
const pubToken = (await u.from("catalog_links").select("token").eq("id", pub).single()).data.token;
let cat = must("الزائر فتح الرابط", await guest.rpc("get_public_catalog", { target_token: pubToken }));
const find = (c, id) => c.products.find((p) => p.id === id);
ok("3 أصناف", cat.products.length === 3);
ok("السعر العادي 2", find(cat, lamp).price === 2);
ok("متوفر بدون كمية", find(cat, lamp).in_stock === true && find(cat, lamp).quantity === null);
ok("اللمبة اللي نفدت: غير متوفر", find(cat, empty).in_stock === false);
ok("الشرح والكرتونة ظاهرين", find(cat, lamp).description === "لمبة 12 واط، ضوء أبيض" && Number(find(cat, lamp).pack_size) === 50);
ok("ما في كلفة", !JSON.stringify(cat).includes("average_cost") && !("cost" in find(cat, lamp)));
ok("التصنيفات", cat.categories.length === 2);
ok("اسم الشركة", cat.company.name === "شركة الكتالوج");
mustFail("الطلب مطفي بهاد الرابط", await guest.rpc("submit_catalog_order", { target_token: pubToken, target_phone: "0933111222", items_payload: [{ product_id: lamp, quantity: 5 }] }));

log("\n3️⃣  رابط خاص لتاجر: سعر جملة، مع الكمية، بلا صور ولا شرح، اللمبات بس، بدون اللي نفد");
const priv = must("رابط التاجر", await u.rpc("save_catalog_link", { target_company: company, target_link: null, settings: {
  trader_id: trader, price_level_id: level, stock_mode: "quantity", show_images: false, show_description: false,
  category_ids: [lamps], hide_out_of_stock: true, allow_orders: true,
} }));
const privRow = (await u.from("catalog_links").select("token, title").eq("id", priv).single()).data;
ok("العنوان تلقائي باسم التاجر", privRow.title === "كتالوج محل النور", privRow.title);
cat = must("التاجر فتح رابطو", await guest.rpc("get_public_catalog", { target_token: privRow.token }));
ok("صنف واحد (لمبة متوفرة)", cat.products.length === 1 && cat.products[0].id === lamp, JSON.stringify(cat.products.map((p) => p.name)));
ok("سعر الجملة 1.5", cat.products[0].price === 1.5);
ok("الكمية 120", Number(cat.products[0].quantity) === 120);
ok("بلا صورة ولا شرح", cat.products[0].image_url === null && cat.products[0].description === null);

log("\n4️⃣  بلا أسعار ومخزون مخفي");
must("تعديل الرابط العام", await u.rpc("save_catalog_link", { target_company: company, target_link: pub, settings: { title: "بلا أسعار", show_prices: false, stock_mode: "hidden" } }));
cat = must("فتح", await guest.rpc("get_public_catalog", { target_token: pubToken }));
ok("ما في أسعار", cat.products.every((p) => p.price === null));
ok("ما في مخزون", cat.products.every((p) => p.in_stock === null && p.quantity === null));

log("\n5️⃣  الطلب من الكتالوج");
let r = must("رقم مش مسجّل", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0999000000", items_payload: [{ product_id: lamp, quantity: 5 }] }));
ok("رجع: الرقم مش معروف", r && r.ok === false);
r = must("رقم تاجر تاني برابط خاص", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0933999888", items_payload: [{ product_id: lamp, quantity: 5 }] }));
ok("رجع: مش معروف (الرابط لتاجر تاني)", r && r.ok === false);
mustFail("صنف مش بالكتالوج (كبل)", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0933111222", items_payload: [{ product_id: cable, quantity: 1 }] }));
mustFail("كمية سالبة", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0933111222", items_payload: [{ product_id: lamp, quantity: -1 }] }));
r = must("طلب صحيح", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0933 111 222", items_payload: [{ product_id: lamp, quantity: 100 }], target_notes: "بدي ياهن بكرا" }));
ok("انعمل عرض سعر", r && r.ok === true && /\S/.test(r.quote_number ?? ""), JSON.stringify(r));
const { data: q } = await u.from("sales_quotes").select("id, trader_id, status, source, total, notes, sales_quote_items(quantity, sale_unit_price)").eq("quote_number", r?.quote_number).single();
ok("العرض للتاجر الصح، مسودة، من الكتالوج", q.trader_id === trader && q.status === "draft" && q.source === "catalog");
ok("بسعر الجملة: 100 × 1.5 = 150", Number(q.total) === 150 && Number(q.sales_quote_items[0].sale_unit_price) === 1.5);
ok("الملاحظة انحفظت", q.notes === "بدي ياهن بكرا");
const ov = must("لوحة المالك", await u.rpc("get_owner_overview", { target_company: company }));
ok("تنبيه: طلب جديد من الكتالوج", ov?.alerts?.catalog_orders === 1, JSON.stringify(ov?.alerts));
must("إرسال العرض", await u.rpc("set_sales_quote_status", { target_company: company, target_quote: q.id, target_status: "sent" }));
must("الموافقة على العرض", await u.rpc("set_sales_quote_status", { target_company: company, target_quote: q.id, target_status: "accepted" }));
must("العرض بيتحوّل لطلبية عادي", await u.rpc("convert_sales_quote_to_order", { target_company: company, target_quote: q.id }));

log("\n6️⃣  حماية");
for (let i = 0; i < 10; i++) await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: `09990000${String(i).padStart(2, "0")}`, items_payload: [{ product_id: lamp, quantity: 1 }] });
mustFail("بعد 10 أرقام غلط الرابط بيوقف الطلب ساعة", await guest.rpc("submit_catalog_order", { target_token: privRow.token, target_phone: "0933111222", items_payload: [{ product_id: lamp, quantity: 1 }] }));
must("إيقاف الرابط", await u.rpc("set_catalog_link_active", { target_company: company, target_link: priv, target_active: false }));
cat = await guest.rpc("get_public_catalog", { target_token: privRow.token });
ok("الرابط الموقوف ما بيفتح", !cat.error && cat.data === null);
mustFail("الزائر ما بيقرا جدول الروابط", { error: (await guest.from("catalog_links").select("token")).data?.length ? null : { message: "ما في وصول" } });
const views = (await u.from("catalog_links").select("view_count").eq("id", pub).single()).data.view_count;
ok("عدد المشاهدات انحسب", views >= 2, String(views));

log(failures ? `\n❌ ${failures} مشكلة` : "\n✅ كل الفحوصات نجحت");
process.exit(failures ? 1 : 0);
