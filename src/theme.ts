export const colors = {
  bg: '#f4f5f7',
  card: '#ffffff',
  border: '#e2e5ea',
  text: '#1a1d22',
  muted: '#6b7280',
  primary: '#1f6feb',
  primaryText: '#ffffff',
  danger: '#d1242f',
  success: '#1a7f37',
  warnBg: '#fff4e5',
  warnText: '#9a6700',
};

export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 };
export const radius = { sm: 6, md: 10, lg: 14 };

/** Status → badge color. */
export const statusColor: Record<string, { bg: string; fg: string }> = {
  DRAFT: { bg: '#eceef1', fg: '#57606a' },
  QUOTE: { bg: '#ddf4ff', fg: '#0969da' },
  CONFIRMED: { bg: '#fff8c5', fg: '#7d4e00' },
  INVOICED: { bg: '#dafbe1', fg: '#1a7f37' },
  PAID: { bg: '#1a7f37', fg: '#ffffff' },
  CANCELLED: { bg: '#ffebe9', fg: '#cf222e' },
};
