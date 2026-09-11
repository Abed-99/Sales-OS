export function normalizeSyrianMobile(value: string) {
  const clean = value.trim().replace(/[\s\-()]/g, "");
  if (!clean) return null;
  if (/^09\d{8}$/.test(clean)) return `+963${clean.slice(1)}`;
  if (/^\+9639\d{8}$/.test(clean)) return clean;
  if (/^009639\d{8}$/.test(clean)) return `+${clean.slice(2)}`;
  return null;
}
export function syrianPhoneState(value: string): "empty"|"valid"|"invalid" {
  if (!value.trim()) return "empty";
  return normalizeSyrianMobile(value) ? "valid" : "invalid";
}
