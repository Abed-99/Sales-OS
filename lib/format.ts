// تنسيق الأرقام بكل النظام: دايمًا بفواصل الآلاف (26000 → 26,000) وأرقام إنكليزية.

// ---------------------------------------------------------------- التواريخ (دايمًا بتوقيت دمشق)
// منبني النص من أجزاء التاريخ بإيدنا، مشان السيرفر (Vercel) والمتصفح يطلّعوا نفس الحروف بالضبط.

const DAMASCUS = "Asia/Damascus";
const dateParts = new Intl.DateTimeFormat("en-US", {
  timeZone: DAMASCUS,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h12",
});

function partsOf(date: Date) {
  const values: Record<string, string> = {};
  for (const part of dateParts.formatToParts(date)) values[part.type] = part.value;
  return values;
}

/** "2026-10-05" لحالها = منتصف ليل دمشق؛ غير هيك وقت كامل. */
function toDate(value: string | Date) {
  if (value instanceof Date) return value;
  return /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T12:00:00+03:00`) : new Date(value);
}

/** تاريخ اليوم بدمشق بصيغة خانة التاريخ: "2026-10-05" (بعد كم يوم إذا بدك). */
export function todayDamascus(days = 0) {
  const p = partsOf(new Date(Date.now() + days * 24 * 60 * 60 * 1000));
  return `${p.year}-${p.month}-${p.day}`;
}

/** "05/10/2026". */
export function formatDate(value: string | Date | null | undefined) {
  if (!value) return "—";
  const date = toDate(value);
  if (Number.isNaN(date.getTime())) return String(value);
  const p = partsOf(date);
  return `${p.day}/${p.month}/${p.year}`;
}

/** "05/10/2026 02:11 م". */
export function formatDateTime(value: string | Date | null | undefined) {
  if (!value) return "—";
  const date = toDate(value);
  if (Number.isNaN(date.getTime())) return String(value);
  const p = partsOf(date);
  const hour = p.hour === "00" ? "12" : p.hour;
  return `${p.day}/${p.month}/${p.year} ${hour}:${p.minute} ${p.dayPeriod === "PM" ? "م" : "ص"}`;
}

// ---------------------------------------------------------------- الأرقام

const formatters = new Map<string, Intl.NumberFormat>();

function formatter(minDigits: number, maxDigits: number) {
  const key = `${minDigits}:${maxDigits}`;
  let value = formatters.get(key);
  if (!value) {
    value = new Intl.NumberFormat("en-US", {
      minimumFractionDigits: minDigits,
      maximumFractionDigits: maxDigits,
    });
    formatters.set(key, value);
  }
  return value;
}

function toNumber(value: unknown) {
  const number = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

/** رقم بعدد ثابت من الخانات بعد الفاصلة: formatNumber(26000) → "26,000.00". */
export function formatNumber(value: unknown, digits = 2) {
  return formatter(digits, digits).format(toNumber(value));
}

/** مبلغ مع العملة: formatMoney(26000, "USD") → "26,000.00 USD". */
export function formatMoney(value: unknown, currency: string) {
  return `${formatNumber(value, 2)} ${currency}`;
}

/** كمية بدون أصفار زايدة: formatQty(1500) → "1,500"، formatQty(2.5) → "2.5". */
export function formatQty(value: unknown, maxDigits = 3) {
  return formatter(0, maxDigits).format(toNumber(value));
}

/** نص فيه فواصل أو أرقام عربية → نص رقم نظيف: "٢٦،٠٠٠" أو "26,000" → "26000". */
export function cleanNumberText(text: string, allowNegative = true) {
  let value = text
    .replace(/[٠-٩]/g, (digit) => String(digit.charCodeAt(0) - 0x660))
    .replace(/[۰-۹]/g, (digit) => String(digit.charCodeAt(0) - 0x6f0))
    .replace(/٫/g, ".")
    .replace(/[^0-9.\-]/g, "");
  const negative = allowNegative && value.startsWith("-");
  value = value.replace(/-/g, "");
  const dot = value.indexOf(".");
  if (dot >= 0) value = value.slice(0, dot + 1) + value.slice(dot + 1).replace(/\./g, "");
  return (negative ? "-" : "") + value;
}

/** "26,000.5" → 26000.5 (فاضي أو غلط → NaN). */
export function parseNumber(text: string | number | null | undefined) {
  if (typeof text === "number") return text;
  const clean = cleanNumberText(String(text ?? ""));
  return clean === "" || clean === "-" || clean === "." ? Number.NaN : Number(clean);
}

/** نص رقم نظيف → نفسه بفواصل الآلاف، وبيخلّي الكسور متل ما انكتبت: "26000.5" → "26,000.5". */
export function groupDigits(clean: string) {
  const negative = clean.startsWith("-");
  const body = negative ? clean.slice(1) : clean;
  const [whole, ...rest] = body.split(".");
  const grouped = whole.replace(/^0+(?=\d)/, "").replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return (negative ? "-" : "") + grouped + (rest.length ? "." + rest.join("") : "");
}

// ---------------------------------------------------------------- الأرقام والأسماء بالعرض

/** رقم الهاتف بالعرض: بيضل "+963..." من اليسار لليمين حتى جوّا نص عربي (وإلا بيطلع "963...+"). */
export function phoneText(phone: string | null | undefined) {
  return phone ? `\u2066${phone}\u2069` : "";
}

/**
 * اسم ملف (PDF / Excel) بأحرف إنكليزية بس: واتساب وبعض الأجهزة بيخربطوا الأحرف العربية
 * بأسماء الملفات ("ÙØ§ØªÙˆØ±Ø©"). محتوى الملف بيضل عربي عادي.
 */
export function safeFileName(name: string, fallback = "document") {
  const clean = name
    .replace(/[^\x20-\x7E]/g, " ")
    .replace(/[\\/:*?"<>|]/g, " ")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return clean || fallback;
}

/** الحرف بالدائرة جنب الاسم: "العمرين" → "ع" (منتجاوز "ال"). */
export function nameInitial(name: string | null | undefined) {
  const text = (name ?? "").trim();
  const word = text.startsWith("ال") && text.length > 3 ? text.slice(2) : text;
  return word.charAt(0) || "؟";
}
