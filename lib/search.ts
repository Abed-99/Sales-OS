// البحث بالعربي متل ما بيكتب الناس: "احمد" بيلاقي "أحمد"، "مؤسسه" بيلاقي "مؤسسة"،
// و"سامسونغ براد" بيلاقي "براد سامسونغ" (كل كلمة لازم تكون موجودة، بأي ترتيب).
// نفس قواعد public.normalize_search بقاعدة البيانات، وعمود search_key مبني عليها
// للزبائن والأصناف والموردين.

const LETTERS: Record<string, string> = {
  "أ": "ا",
  "إ": "ا",
  "آ": "ا",
  "ٱ": "ا",
  "ة": "ه",
  "ى": "ي",
  "ؤ": "و",
  "ئ": "ي",
};

export function normalizeSearch(text: string | null | undefined) {
  return (text ?? "")
    .toLowerCase()
    .replace(/[أإآٱةىؤئ]/g, (letter) => LETTERS[letter])
    .replace(/[\u064B-\u0652\u0640]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** كلمات البحث بعد التوحيد، بلا الرموز يلي بتخرب فلاتر PostgREST. */
export function searchWords(term: string) {
  return normalizeSearch(term.replace(/[%_,()"'\\*]/g, " "))
    .split(" ")
    .filter(Boolean);
}

/**
 * شرط لـ `.or(...)` بيدوّر بعمود search_key: كل الكلمات لازم تكون موجودة.
 * مثال: `.or([searchKeyCondition(term), "phone.ilike.%0944%"].join(","))`.
 */
export function searchKeyCondition(term: string) {
  const words = searchWords(term);
  if (!words.length) return "";
  const parts = words.map((word) => `search_key.ilike.%${word}%`);
  return parts.length === 1 ? parts[0] : `and(${parts.join(",")})`;
}

/** بحث بالمتصفح: كل كلمات البحث موجودة بالنص. */
export function matchesSearch(text: string | null | undefined, term: string) {
  const haystack = normalizeSearch(text);
  return normalizeSearch(term)
    .split(" ")
    .filter(Boolean)
    .every((word) => haystack.includes(word));
}

/** أول قيمة من باراميتر الرابط (?q=...). */
export function firstParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

/** كلمة البحث من الرابط بلا الرموز يلي بتخرب فلاتر PostgREST، وبحد أقصى 100 حرف. */
export function cleanSearch(value: string) {
  return value
    .replace(/[%_(),"'\\]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
}
