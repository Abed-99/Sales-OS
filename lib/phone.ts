export function normalizeSyrianMobile(value: string) {
  const clean = value.trim().replace(/[\s\-()]/g, "");
  if (!clean) return null;
  if (/^09\d{8}$/.test(clean)) return `+963${clean.slice(1)}`;
  if (/^\+9639\d{8}$/.test(clean)) return clean;
  if (/^009639\d{8}$/.test(clean)) return `+${clean.slice(2)}`;
  return null;
}

export function syrianPhoneState(value: string): "empty" | "valid" | "invalid" {
  if (!value.trim()) return "empty";
  return normalizeSyrianMobile(value) ? "valid" : "invalid";
}

/**
 * Syrian mobile or any international number (e.g. a factory in China: +86...).
 * International numbers must start with + or 00 and have 8–15 digits.
 */
export function normalizeAnyPhone(value: string) {
  const syrian = normalizeSyrianMobile(value);
  if (syrian) return syrian;

  const clean = value.trim().replace(/[\s\-()]/g, "");
  const international = clean.startsWith("00") ? `+${clean.slice(2)}` : clean;
  return /^\+[1-9]\d{7,14}$/.test(international) ? international : null;
}

export function anyPhoneState(value: string): "empty" | "valid" | "invalid" {
  if (!value.trim()) return "empty";
  return normalizeAnyPhone(value) ? "valid" : "invalid";
}
