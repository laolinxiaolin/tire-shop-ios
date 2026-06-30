/**
 * US telephone helpers — mirror of apps/web/lib/phone.ts and
 * apps/api/src/common/phone.ts. The API stores customer phones as 10 canonical
 * digits; we pre-check input here so the user sees the error before submitting.
 * Keep the three in sync.
 */

/** Reduce US phone input to 10 digits, `null` if blank, throws if invalid. */
export function normalizeUsPhone(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const trimmed = String(raw).trim();
  if (trimmed === '') return null;
  let digits = trimmed.replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('1')) digits = digits.slice(1);
  if (digits.length !== 10) throw new Error('Phone must be a 10-digit US number');
  return digits;
}

/** Render stored digits as `(XXX) XXX-XXXX`; pass anything else through. */
export function formatUsPhone(phone: string | null | undefined): string {
  if (!phone) return '';
  const d = phone.replace(/\D/g, '');
  if (d.length !== 10) return phone;
  return `(${d.slice(0, 3)}) ${d.slice(3, 6)}-${d.slice(6)}`;
}
