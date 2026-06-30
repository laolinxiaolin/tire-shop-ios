/**
 * Single API client for the mobile app — mirrors the hand-maintained types in
 * apps/web/lib/api.ts (the repo deliberately has no codegen). The JWT lives in
 * the device secure store and is sent as `Authorization: Bearer`, the same
 * bearer auth the NestJS JwtStrategy expects.
 */
import * as FileSystem from 'expo-file-system/legacy';
import * as SecureStore from 'expo-secure-store';
import * as Sharing from 'expo-sharing';
import { getServerUrl } from './server';

const TOKEN_KEY = 'ts_token';
let token: string | null = null;

export async function loadToken(): Promise<string | null> {
  token = await SecureStore.getItemAsync(TOKEN_KEY);
  return token;
}
export async function setToken(t: string): Promise<void> {
  token = t;
  await SecureStore.setItemAsync(TOKEN_KEY, t);
}
export async function clearToken(): Promise<void> {
  token = null;
  await SecureStore.deleteItemAsync(TOKEN_KEY);
}
export function getToken(): string | null {
  return token;
}

/** Auth context registers a handler so a 401 mid-session bounces to login. */
let onUnauthorized: (() => void) | null = null;
export function setUnauthorizedHandler(fn: (() => void) | null): void {
  onUnauthorized = fn;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

type RequestOpts = {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
  /** Skip the 401→logout side effect (used by the login call itself). */
  noAuthBounce?: boolean;
};

export async function api<T = unknown>(path: string, opts: RequestOpts = {}): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  let res: Response;
  try {
    // All backend routes live under the `/api` prefix (see main.ts).
    res = await fetch(`${getServerUrl()}/api${path}`, {
      method: opts.method ?? 'GET',
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    });
  } catch {
    throw new ApiError(
      0,
      `Can't reach the server at ${getServerUrl()}. Check the network and the server address in settings.`,
    );
  }

  if (res.status === 401 && !opts.noAuthBounce) {
    await clearToken();
    onUnauthorized?.();
    throw new ApiError(401, 'Session expired — please sign in again.');
  }

  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const data = await res.json();
      const m = (data as { message?: string | string[] }).message;
      if (Array.isArray(m)) message = m.join(', ');
      else if (typeof m === 'string') message = m;
    } catch {
      /* non-JSON error body */
    }
    throw new ApiError(res.status, message);
  }

  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/** Multipart upload (e.g. a customer document). Don't set Content-Type — fetch
 * adds the multipart boundary itself. */
export async function apiUpload<T = unknown>(path: string, form: FormData): Promise<T> {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let res: Response;
  try {
    res = await fetch(`${getServerUrl()}/api${path}`, { method: 'POST', headers, body: form });
  } catch {
    throw new ApiError(0, `Can't reach the server at ${getServerUrl()}.`);
  }
  if (res.status === 401) {
    await clearToken();
    onUnauthorized?.();
    throw new ApiError(401, 'Session expired — please sign in again.');
  }
  if (!res.ok) {
    let message = `Upload failed (${res.status})`;
    try {
      const m = ((await res.json()) as { message?: string | string[] }).message;
      if (Array.isArray(m)) message = m.join(', ');
      else if (typeof m === 'string') message = m;
    } catch {
      /* non-JSON */
    }
    throw new ApiError(res.status, message);
  }
  return (await res.json()) as T;
}

/** Download a server file (e.g. an xlsx export) with the bearer token, then open
 * the OS share sheet so the user can save/send it. The web uses a plain anchor
 * download; on a phone there's no filesystem to drop into, so we share instead. */
export async function downloadAndShare(
  path: string,
  filename: string,
  mimeType: string,
): Promise<void> {
  const dest = (FileSystem.cacheDirectory ?? '') + filename;
  let result: FileSystem.FileSystemDownloadResult;
  try {
    result = await FileSystem.downloadAsync(`${getServerUrl()}/api${path}`, dest, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    });
  } catch {
    throw new ApiError(0, `Can't reach the server at ${getServerUrl()}.`);
  }
  if (result.status === 401) {
    await clearToken();
    onUnauthorized?.();
    throw new ApiError(401, 'Session expired — please sign in again.');
  }
  if (result.status < 200 || result.status >= 300) {
    throw new ApiError(result.status, `Download failed (${result.status}).`);
  }
  if (!(await Sharing.isAvailableAsync())) {
    throw new ApiError(0, 'Sharing is not available on this device.');
  }
  await Sharing.shareAsync(result.uri, { mimeType, dialogTitle: filename });
}

// ---------------------------------------------------------------- types
export type Paged<T> = { items: T[]; total: number; page: number; pageSize: number };

export type MfaMethod = 'TOTP' | 'EMAIL';

export type SessionUser = {
  id: string;
  email: string;
  fullName: string;
  roleId: string;
  roleName: string;
  isAdmin: boolean;
  permissions: string[];
  approvalPermissions?: string[];
  mfaMethod: MfaMethod | null;
};

export type MfaChallenge = { mfaRequired: true; method: MfaMethod; challengeToken: string };

export type LoginSession = {
  mfaRequired?: undefined;
  accessToken: string;
  user: SessionUser;
  usedBackupCode?: boolean;
  backupCodesRemaining?: number;
};

export type LoginResult = LoginSession | MfaChallenge;

// category / position / segment are admin-managed strings (see TireAttribute),
// not fixed enums.
export type TireCategory = string;
export type TirePosition = string;

export type TireAttributeKind = 'CATEGORY' | 'POSITION' | 'SEGMENT';

export type TireAttribute = {
  id: string;
  kind: TireAttributeKind;
  value: string;
  label: string;
  sortOrder: number;
  active: boolean;
  usageCount: number;
};

export type TireSku = {
  id: string;
  sku: string;
  brand: string;
  model: string;
  size: string;
  category: TireCategory;
  position: TirePosition;
  segment: string | null;
  // "LI & SR" — combined load index & speed rating.
  loadIndex: string | null;
  pattern: string | null;
  treadDepth32: string | null;
  maxLoadSingleLb: number | null;
  weightLb: string | null;
  plyRating: string | null;
  priceRetail: string;
  priceCost: string;
  reorderPoint: number;
  active: boolean;
  inventory: { id: string; location: string; qtyOnHand: number; qtyReserved: number }[];
};

export type SaleStatus = 'DRAFT' | 'QUOTE' | 'CONFIRMED' | 'INVOICED' | 'PAID' | 'CANCELLED';

export type SaleLine = {
  id: string;
  itemType: 'SKU' | 'SERVICE';
  itemId: string;
  description: string;
  qty: number;
  unitPrice: string;
  discount: string;
  lineTotal: string;
};

export type Sale = {
  id: string;
  ref: string | null;
  status: SaleStatus;
  customer: { id: string; name: string; company: string | null };
  customerId: string;
  subtotal: string;
  taxRate: string;
  taxAmount: string;
  total: string;
  createdAt: string;
  lines: SaleLine[];
  invoice?: { id: string; ref: string | null; amountDue: string; paidTotal: string } | null;
};

export type SaleListItem = Sale & {
  tireQty: number;
  sampleDescription: string | null;
  extraLineCount: number;
  grossProfit: string;
};

export type CustomerSaleSummary = {
  id: string;
  ref: string | null;
  status: SaleStatus;
  subtotal: string;
  taxRate: string;
  taxAmount: string;
  total: string;
  createdAt: string;
  lines: SaleLine[];
};

export type CustomerDocumentKind = 'ST5_EXEMPTION' | 'RESALE_CERT' | 'OTHER';

export type CustomerDocument = {
  id: string;
  kind: CustomerDocumentKind;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  note: string | null;
  createdAt: string;
};

export type Customer = {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  notes: string | null;
  taxExempt: boolean;
  taxExemptNumber: string | null;
  accountEnabled: boolean;
  creditLimit: string | null;
  sales?: CustomerSaleSummary[];
  documents?: CustomerDocument[];
  createdAt: string;
};

export type Service = {
  id: string;
  code: string;
  name: string;
  price: string;
  defaultMinutes: number;
  active: boolean;
};

export type NewSaleLine = {
  itemType: 'SKU' | 'SERVICE';
  itemId: string;
  description: string;
  qty: number;
  unitPrice: number;
  discount?: number;
};

// ---------------------------------------------------------------- endpoints
export const auth = {
  login: (email: string, password: string) =>
    api<LoginResult>('/auth/login', {
      method: 'POST',
      body: { email, password },
      noAuthBounce: true,
    }),
  verifyMfa: (challengeToken: string, code: string) =>
    api<LoginSession>('/auth/mfa/verify', {
      method: 'POST',
      body: { challengeToken, code },
      noAuthBounce: true,
    }),
};

const qs = (params: Record<string, string | number | undefined>): string => {
  const parts = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== '')
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`);
  return parts.length ? `?${parts.join('&')}` : '';
};

export type DashboardSummary = {
  today: { revenue: number; saleCount: number };
  month: { revenue: number; saleCount: number };
  openAR: { total: number; invoiceCount: number };
  paidInvoiceCount: number;
  openQuotes: number;
  lowStockCount: number;
  lowStock: {
    id: string;
    sku: string;
    brand: string;
    model: string;
    size: string;
    reorderPoint: number;
    onHand: number;
  }[];
  topSkus: { id: string; sku: string; brand: string; model: string; size: string; qty: number }[];
};

export const dashboard = {
  summary: () => api<DashboardSummary>('/dashboard/summary'),
};

/** Fields shared by the create/edit SKU forms. */
export type SkuInput = {
  sku: string;
  brand: string;
  model: string;
  size: string;
  category: TireCategory;
  position: TirePosition;
  segment?: string;
  loadIndex?: string;
  pattern?: string;
  treadDepth32?: number;
  maxLoadSingleLb?: number;
  weightLb?: number;
  plyRating?: string;
  priceRetail: number;
  priceCost?: number;
  reorderPoint?: number;
  active?: boolean;
};

export type StockAdjustReason = 'PURCHASE' | 'ADJUSTMENT' | 'RETURN';

/** A single inventory location row (what `adjust` returns on the affected location). */
export type InventoryItem = {
  id: string;
  location: string;
  qtyOnHand: number;
  qtyReserved: number;
};

/** `adjust` either applies immediately (returns the updated location row) or,
 * when the caller only holds the permission in approval mode, captures a
 * pending approval request instead. */
export type AdjustResult = InventoryItem | { approvalRequest: { id: string } };

export function isApprovalResult<T extends object>(
  r: T,
): r is Extract<T, { approvalRequest: { id: string } }> {
  return 'approvalRequest' in r;
}

/** Per-row outcome of a spreadsheet import (mirrors the API's ImportSummary). */
export type ImportSummary = {
  total: number;
  created: number;
  updated: number;
  errorCount: number;
  errors: { row: number; message: string }[];
};

export const tireAttributes = {
  list: (kind?: TireAttributeKind) => api<TireAttribute[]>(`/tire-attributes${qs({ kind })}`),
};

export const inventory = {
  listSkus: (p: {
    q?: string;
    category?: TireCategory;
    position?: TirePosition;
    page?: number;
    pageSize?: number;
  }) => api<Paged<TireSku>>(`/inventory/skus${qs(p)}`),
  createSku: (body: SkuInput) => api<TireSku>('/inventory/skus', { method: 'POST', body }),
  updateSku: (id: string, body: Partial<SkuInput>) =>
    api<TireSku>(`/inventory/skus/${id}`, { method: 'PATCH', body }),
  adjust: (id: string, body: { delta: number; reason: StockAdjustReason; note?: string }) =>
    api<AdjustResult>(`/inventory/skus/${id}/adjust`, { method: 'POST', body }),
  importSkus: (file: { uri: string; name: string; mimeType: string }) => {
    const form = new FormData();
    // RN FormData file part shape: { uri, name, type }
    form.append('file', { uri: file.uri, name: file.name, type: file.mimeType } as unknown as Blob);
    return apiUpload<ImportSummary>('/inventory/skus/import', form);
  },
};

/** Void either applies immediately (returns the updated Sale) or, for
 * approval-mode holders, returns a pending request. */
export type VoidResult = Sale | { approvalRequest: { id: string } };

export const sales = {
  list: (p: { q?: string; status?: SaleStatus; page?: number; pageSize?: number }) =>
    api<Paged<SaleListItem>>(`/sales${qs(p)}`),
  get: (id: string) => api<Sale>(`/sales/${id}`),
  create: (body: { customerId: string; taxRate?: number; lines: NewSaleLine[] }) =>
    api<Sale>('/sales', { method: 'POST', body }),
  update: (id: string, body: { customerId: string; taxRate?: number; lines: NewSaleLine[] }) =>
    api<Sale>(`/sales/${id}`, { method: 'PATCH', body }),
  promoteToQuote: (id: string) => api<Sale>(`/sales/${id}/quote`, { method: 'POST' }),
  /** Confirm a draft/quote → decrements stock and issues the invoice. */
  confirm: (id: string) => api<Sale>(`/sales/${id}/confirm`, { method: 'POST' }),
  /** Pull a posted invoice back to an editable draft (restocks, reverses books). */
  reverseToDraft: (id: string) => api<Sale>(`/sales/${id}/reverse-to-draft`, { method: 'POST' }),
  /** Demote a quote back to a draft. */
  revertQuoteToDraft: (id: string) => api<Sale>(`/sales/${id}/revert-draft`, { method: 'POST' }),
  /** Cancel an open quote. */
  cancelQuote: (id: string, reason?: string) =>
    api<Sale>(`/sales/${id}/cancel`, { method: 'POST', body: { reason } }),
  /** Delete a draft sale outright. */
  deleteDraft: (id: string) => api<{ deleted: boolean }>(`/sales/${id}`, { method: 'DELETE' }),
  /** Void a posted sale. In approval mode returns { approvalRequest }. */
  voidSale: (id: string, reason?: string) =>
    api<VoidResult>(`/sales/${id}/void`, { method: 'POST', body: { reason } }),
};

export type NewCustomer = {
  name: string;
  company?: string;
  phone?: string;
  email?: string;
  address?: string;
  notes?: string;
  taxExempt?: boolean;
  taxExemptNumber?: string;
};

/** Editable profile fields (tax status is set separately via setTaxStatus).
 * Empty strings clear the field on the server. */
export type CustomerProfilePatch = {
  name: string;
  company: string;
  phone: string;
  email: string;
  address: string;
  notes: string;
};

export const customers = {
  list: (p: { q?: string; page?: number; pageSize?: number }) =>
    api<Paged<Customer>>(`/customers${qs(p)}`),
  get: (id: string) => api<Customer>(`/customers/${id}`),
  create: (body: NewCustomer) => api<Customer>('/customers', { method: 'POST', body }),
  update: (id: string, body: CustomerProfilePatch) =>
    api<Customer>(`/customers/${id}`, { method: 'PATCH', body }),
  setTaxStatus: (id: string, body: { taxExempt: boolean; taxExemptNumber?: string }) =>
    api<Customer>(`/customers/${id}/tax-status`, { method: 'PATCH', body }),
  remove: (id: string) => api<{ ok: boolean }>(`/customers/${id}`, { method: 'DELETE' }),
  uploadDocument: (
    id: string,
    file: { uri: string; name: string; mimeType: string },
    kind: CustomerDocumentKind = 'ST5_EXEMPTION',
  ) => {
    const form = new FormData();
    // RN FormData file part shape: { uri, name, type }
    form.append('file', { uri: file.uri, name: file.name, type: file.mimeType } as unknown as Blob);
    form.append('kind', kind);
    return apiUpload<CustomerDocument>(`/customers/${id}/documents`, form);
  },
  /** Available store-credit balance — caps the "store credit" tender at payment. */
  creditBalance: (id: string) => api<{ balance: number }>(`/customers/${id}/credit-balance`),
};

export const services = {
  list: () => api<Service[]>('/services'),
};

// --- Card payments (Stripe) ---

export type GatewayStatus = {
  enabled: boolean;
  provider: 'stripe';
  publishableKey: string | null;
};

export type TerminalIntent = {
  paymentIntentId: string;
  clientSecret: string | null;
  balance: number;
  surcharge: number;
  amount: number;
  readerId: string | null;
  readerStatus: string | null;
};

export type InvoicePayment = {
  id: string;
  externalId: string | null;
  amount: string;
  status: string;
  createdAt?: string;
  reference?: string | null;
  note?: string | null;
  processor?: string | null;
  paymentMethod?: { name: string } | null;
};

/** A reverse either applies immediately or (in approval mode) returns a request. */
export type ReverseResult = { approvalRequest?: { id: string } };

// --- Work orders ---

export type WorkOrderStatus = 'OPEN' | 'IN_PROGRESS' | 'DONE' | 'CANCELLED';

export type WorkOrderTask = {
  id: string;
  description: string;
  done: boolean;
  doneAt: string | null;
};

export type WorkOrder = {
  id: string;
  status: WorkOrderStatus;
  bay: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
  tasks: WorkOrderTask[];
  sale: {
    id: string;
    ref: string | null;
    total: string;
    customer: { id: string; name: string; company: string | null };
    lines: { id: string; description: string; qty: number; itemType: 'SKU' | 'SERVICE' }[];
  };
};

export const workOrders = {
  list: (p: { status?: WorkOrderStatus; page?: number; pageSize?: number }) =>
    api<Paged<WorkOrder>>(`/work-orders${qs(p)}`),
  get: (id: string) => api<WorkOrder>(`/work-orders/${id}`),
  update: (id: string, body: { status?: WorkOrderStatus; bay?: string; notes?: string }) =>
    api<WorkOrder>(`/work-orders/${id}`, { method: 'PATCH', body }),
  addTask: (id: string, description: string) =>
    api<WorkOrderTask>(`/work-orders/${id}/tasks`, { method: 'POST', body: { description } }),
  toggleTask: (woId: string, taskId: string, done: boolean) =>
    api<WorkOrderTask>(`/work-orders/${woId}/tasks/${taskId}`, { method: 'PATCH', body: { done } }),
  deleteTask: (woId: string, taskId: string) =>
    api<void>(`/work-orders/${woId}/tasks/${taskId}`, { method: 'DELETE' }),
};

// --- Returns ---

export type ReturnType = 'RETURN' | 'EXCHANGE' | 'WARRANTY';
export type ReturnStatus = 'DRAFT' | 'POSTED' | 'VOIDED';
export type RefundMethod = 'ORIGINAL' | 'CASH' | 'CHECK' | 'CARD' | 'STORE_CREDIT';
export type InventoryDisposition = 'RESTOCK' | 'SCRAP';
export type WarrantyDisposition = 'SUPPLIER_CLAIM' | 'WRITE_OFF';

/** What's still returnable on a sale — drives the return/exchange wizard. */
export type Returnable = {
  saleId: string;
  saleRef: string | null;
  saleStatus: string;
  taxRate: number;
  originalPaymentMethodId: string | null;
  originalPaymentMethodName: string | null;
  lines: {
    saleLineId: string;
    skuId: string;
    description: string;
    unitPrice: number;
    qtySold: number;
    qtyAlreadyReturned: number;
    qtyRemaining: number;
  }[];
};

export type ReturnLine = {
  id: string;
  saleLineId: string;
  skuId: string;
  qty: number;
  unitRefund: string;
  inventoryDisposition: 'RESTOCK' | 'SCRAP';
};

export type ReturnRecord = {
  id: string;
  ref: string | null;
  saleId: string;
  type: ReturnType;
  status: ReturnStatus;
  reason: string | null;
  notes: string | null;
  restockingFee: string;
  refundSubtotal: string;
  refundTax: string;
  refundTotal: string;
  refundMethod: RefundMethod;
  paymentMethod: { id: string; name: string } | null;
  postedAt: string | null;
  voidedAt: string | null;
  createdAt: string;
  sale?: {
    id: string;
    ref: string | null;
    customer?: { id: string; name: string; company: string | null } | null;
  };
  replacementSale?: { id: string; ref: string | null; total: string; status: string } | null;
  lines: ReturnLine[];
};

/** One returned line in a create-return request. */
export type ReturnLineInput = {
  saleLineId: string;
  qty: number;
  inventoryDisposition?: InventoryDisposition;
};

/** A replacement tire on an EXCHANGE or warranty-replace. */
export type ReplacementLineInput = {
  skuId: string;
  qty: number;
  unitPrice?: number;
};

export type CreateReturnInput = {
  type: ReturnType;
  reason?: string;
  restockingFee?: number;
  refundMethod: RefundMethod;
  paymentMethodId?: string;
  notes?: string;
  lines: ReturnLineInput[];
  replacementLines?: ReplacementLineInput[];
  warrantyDisposition?: WarrantyDisposition;
  supplierId?: string;
};

export type PostReturnInput = {
  /** EXCHANGE, replacement dearer: collect the net upcharge now. */
  netPayment?: { paymentMethodId: string; amount: number; reference?: string; note?: string };
  /** EXCHANGE, replacement cheaper: refund the leftover via a cash/check/card tender. */
  netRefund?: { paymentMethodId: string; reference?: string; note?: string };
};

export const returns = {
  list: (p: { status?: ReturnStatus; saleId?: string; page?: number; pageSize?: number }) =>
    api<Paged<ReturnRecord>>(`/returns${qs(p)}`),
  get: (id: string) => api<ReturnRecord>(`/returns/${id}`),
  /** What's left to return on a sale. */
  returnable: (saleId: string) => api<Returnable>(`/sales/${saleId}/returnable`),
  /** Create a DRAFT return/exchange/warranty against a sale. */
  create: (saleId: string, body: CreateReturnInput) =>
    api<ReturnRecord>(`/sales/${saleId}/returns`, { method: 'POST', body }),
  /** Post a draft return — applies refund/credit, inventory, and net upcharge. */
  post: (id: string, body?: PostReturnInput) =>
    api<ReturnRecord>(`/returns/${id}/post`, { method: 'POST', body: body ?? {} }),
};

// --- Suppliers ---

export type Supplier = { id: string; name: string };

export const suppliers = {
  list: () => api<Paged<Supplier>>(`/suppliers${qs({ pageSize: 1000 })}`),
};

// --- Money (AR / AP) ---

export type ReceivableCustomer = {
  customer: { id: string; name: string; company: string | null };
  openBalance: number;
  openCount: number;
  oldestAt: string;
  ageDays: number;
};

export type PayableVendor = {
  vendor: string | null;
  vendorKey: string;
  totalDue: number;
  count: number;
  oldestAt: string;
  ageDays: number;
};

export const receivables = {
  list: (p: { page?: number; pageSize?: number }) =>
    api<Paged<ReceivableCustomer>>(`/receivables${qs(p)}`),
};

export const payables = {
  list: (p: { page?: number; pageSize?: number }) => api<Paged<PayableVendor>>(`/payables${qs(p)}`),
};

// --- Inventory counts ---

export type InventoryCountStatus = 'OPEN' | 'POSTED' | 'VOIDED';

export type InventoryCountListItem = {
  id: string;
  ref: string | null;
  status: InventoryCountStatus;
  scopeCategory: TireCategory | null;
  scopePosition: TirePosition | null;
  location: string;
  notes: string | null;
  costVariance: string;
  postedAt: string | null;
  voidedAt: string | null;
  createdAt: string;
  _count: { lines: number };
};

export type InventoryCountLine = {
  id: string;
  countId: string;
  skuId: string;
  expectedQty: number;
  unitCost: string;
  countExpr: string | null;
  countedQty: number | null;
  sku: {
    id: string;
    sku: string;
    brand: string;
    model: string;
    size: string;
    category: TireCategory;
    position: TirePosition;
  };
};

export type InventoryCountDetail = InventoryCountListItem & {
  lines: InventoryCountLine[];
};

/** A post/reverse either applies immediately or, for approval-mode holders,
 * captures a pending request — same shape as {@link AdjustResult}. */
export type CountActionResult = InventoryCountDetail | { approvalRequest: { id: string } };

export const inventoryCounts = {
  list: (p: { status?: InventoryCountStatus; page?: number; pageSize?: number }) =>
    api<Paged<InventoryCountListItem>>(`/inventory-counts${qs(p)}`),
  get: (id: string) => api<InventoryCountDetail>(`/inventory-counts/${id}`),
  create: (body: {
    scopeCategory?: TireCategory;
    scopePosition?: TirePosition;
    location?: string;
    notes?: string;
  }) => api<{ id: string }>('/inventory-counts', { method: 'POST', body }),
  /** Enter (`countExpr`) or clear (both null) the counted quantity on one line. */
  updateLine: (
    id: string,
    lineId: string,
    body: { countExpr: string | null; countedQty: number | null },
  ) =>
    api<InventoryCountLine>(`/inventory-counts/${id}/lines/${lineId}`, { method: 'PATCH', body }),
  post: (id: string) => api<CountActionResult>(`/inventory-counts/${id}/post`, { method: 'POST' }),
  reverse: (id: string, reason?: string) =>
    api<CountActionResult>(`/inventory-counts/${id}/reverse`, { method: 'POST', body: { reason } }),
  remove: (id: string) => api<{ ok: true }>(`/inventory-counts/${id}`, { method: 'DELETE' }),
};

// --- Purchasing (containers) ---

export type ContainerStatus =
  | 'DRAFT'
  | 'ORDERED'
  | 'IN_TRANSIT'
  | 'ARRIVED'
  | 'RECEIVED'
  | 'CANCELLED';

export type ContainerLine = {
  id: string;
  skuId: string;
  qty: number;
  unitCost: string;
  fetPerUnit: string;
  landedUnitCost: string | null;
  landedTotal: string | null;
  prevPriceCost: string | null;
  sku: {
    id: string;
    sku: string;
    brand: string;
    model: string;
    size: string;
    category: string;
    position: string;
  };
};

export type ContainerCost = {
  id: string;
  containerId: string;
  category: string;
  status: 'DUE' | 'PAID';
  description: string | null;
  amount: string;
  amountPaid: string;
  vendor: string | null;
  reference: string | null;
  createdAt: string;
};

export type Container = {
  id: string;
  ref: string | null;
  reference: string | null;
  bolNumber: string | null;
  supplier: { id: string; name: string; country: string | null };
  status: ContainerStatus;
  isDDP: boolean;
  costSpread: string;
  etaAt: string | null;
  arrivedAt: string | null;
  receivedAt: string | null;
  notes: string | null;
  lines: ContainerLine[];
  costs: ContainerCost[];
  createdAt: string;
  _count?: { lines: number; costs: number };
};

export const containers = {
  list: (p: { status?: ContainerStatus; q?: string; page?: number; pageSize?: number }) =>
    api<Paged<Container>>(`/containers${qs(p)}`),
  get: (id: string) => api<Container>(`/containers/${id}`),
};

// --- Accounting ---

export type AccountType = 'ASSET' | 'LIABILITY' | 'EQUITY' | 'REVENUE' | 'EXPENSE';

export type Account = {
  id: string;
  code: string;
  name: string;
  type: AccountType;
  balance: number;
};

export type JournalLine = {
  id: string;
  debit: string;
  credit: string;
  account: { code: string; name: string };
};

export type JournalEntry = {
  id: string;
  date: string;
  memo: string | null;
  refType: string | null;
  refId: string | null;
  lines: JournalLine[];
};

export type Pnl = {
  from: string;
  to: string;
  revenue: { code: string; name: string; total: number }[];
  revenueTotal: number;
  expenses: { code: string; name: string; total: number }[];
  expensesTotal: number;
  netIncome: number;
};

export const accounting = {
  accounts: () => api<Account[]>('/accounting/accounts'),
  journal: (p: { page?: number; pageSize?: number }) =>
    api<Paged<JournalEntry>>(`/accounting/journal${qs(p)}`),
  pnl: (p: { from?: string; to?: string }) => api<Pnl>(`/accounting/reports/pnl${qs(p)}`),
};

// --- Cash accounts ---

export type CashAccount = {
  id: string;
  code: string;
  name: string;
  type: string;
  balance: number;
};

export type CashTransfer = {
  id: string;
  fromAccount: { code: string; name: string };
  toAccount: { code: string; name: string };
  amount: string;
  fee: string;
  note: string | null;
  createdAt: string;
};

export type PaymentMethod = {
  id: string;
  name: string;
  feeRate: string | null;
  isActive: boolean;
  processor: string | null;
  account: { code: string; name: string };
};

export const cashAccounts = {
  list: () => api<CashAccount[]>('/accounting/cash-accounts'),
  transfers: (limit?: number) =>
    api<CashTransfer[]>(`/accounting/transfers${limit ? `?limit=${limit}` : ''}`),
  methods: () => api<PaymentMethod[]>('/accounting/payment-methods'),
};

// --- FET (Federal Excise Tax) ---

export type FetQuarter = {
  key: string;
  label: string;
  year: number;
  quarter: number;
  periodStart: string;
  periodEnd: string;
  formDueDate: string;
  fetDue: number;
  depositRequired: boolean;
};

export type FetStatus = {
  payable: number;
  quarters: FetQuarter[];
  payments: { id: string; refId: string; date: string; memo: string | null; amount: number }[];
  paidPerQuarter: Record<string, number>;
};

export const fet = {
  status: () => api<FetStatus>('/accounting/fet'),
};

// --- End of Day ---

export type EodReport = {
  date: string;
  sales: {
    items: {
      saleRef: string | null;
      customer: string;
      soldBy: string;
      status: string;
      subtotal: number;
      tax: number;
      total: number;
      at: string;
    }[];
    summary: { count: number; subtotal: number; tax: number; total: number };
  };
  payments: {
    items: {
      method: string;
      amount: number;
      surcharge: number;
      reference: string | null;
      at: string;
    }[];
    byMethod: { method: string; count: number; amount: number }[];
    summary: { count: number; total: number };
  };
  expenses: { items: { memo: string | null; amount: number; at: string }[]; total: number };
  pnl: {
    revenue: { code: string; name: string; total: number }[];
    revenueTotal: number;
    expenses: { code: string; name: string; total: number }[];
    expensesTotal: number;
    netIncome: number;
  };
  cashMovement: { code: string; name: string; in: number; out: number; net: number }[];
};

export const eod = {
  report: (date: string) => api<EodReport>(`/accounting/reports/eod?date=${date}`),
};

// --- Activity (audit log) ---

export type AuditLog = {
  id: string;
  action: string;
  entity: string;
  entityId: string | null;
  data: Record<string, unknown> | null;
  createdAt: string;
  user: { id: string; fullName: string; email: string } | null;
};

export const activity = {
  list: (p: { page?: number; pageSize?: number }) => api<Paged<AuditLog>>(`/audit${qs(p)}`),
};

// --- Approvals ---

export type ApprovalStatus = 'PENDING' | 'EXECUTED' | 'DENIED' | 'CANCELLED' | 'FAILED';

/** A full display-ready sale inside an approval context. */
export type ApprovalSale = {
  ref: string | null;
  status: string;
  createdAt: string;
  customer: { name: string; company: string | null; phone: string | null } | null;
  lines: {
    description: string;
    itemType: string;
    qty: number;
    unitPrice: number;
    lineTotal: number;
  }[];
  subtotal: number;
  taxAmount: number;
  total: number;
  paid: number;
  payments: {
    amount: number;
    method: string | null;
    reference: string | null;
    createdAt: string;
  }[];
};

/** The underlying transaction an approval acts on (only on GET /approvals/:id). */
export type ApprovalContext =
  | { kind: 'sale'; sale: ApprovalSale }
  | {
      kind: 'payment';
      payment: {
        amount: number;
        method: string | null;
        reference: string | null;
        processor: string | null;
        createdAt: string;
      };
      sale: ApprovalSale | null;
    }
  | {
      kind: 'sku';
      sku: {
        sku: string;
        brand: string;
        model: string;
        size: string;
        category: string;
        position: string;
        priceRetail: number;
        priceCost: number;
      };
      onHand: number;
      delta: number;
      resulting: number;
    }
  | {
      kind: 'count';
      count: {
        ref: string | null;
        status: string;
        location: string;
        totalLines: number;
        countedLines: number;
        costVariance: number;
      };
    }
  | {
      kind: 'payable';
      vendor: string | null;
      bills: { description: string; vendor: string | null; amount: number }[];
      total: number;
      paidAt: string | null;
      reference: string | null;
    };

export type ApprovalRequest = {
  id: string;
  action: string;
  entityType: string | null;
  entityId: string | null;
  payload: any;
  status: ApprovalStatus;
  note: string | null;
  requestedById: string;
  requestedBy: { id: string; fullName: string; email: string };
  requestedAt: string;
  decidedById: string | null;
  decidedBy: { id: string; fullName: string; email: string } | null;
  decidedAt: string | null;
  decisionNote: string | null;
  executedAt: string | null;
  executionError: string | null;
  /** Resolved underlying transaction — present only on GET /approvals/:id. */
  context?: ApprovalContext | null;
};

export const approvals = {
  list: (p: { status?: ApprovalStatus; mine?: boolean; page?: number; pageSize?: number }) =>
    api<Paged<ApprovalRequest>>(`/approvals${qs({ ...p, mine: p.mine ? '1' : undefined })}`),
  pendingCount: () => api<{ count: number }>('/approvals/pending-count'),
  get: (id: string) => api<ApprovalRequest>(`/approvals/${id}`),
  approve: (id: string, note?: string) =>
    api<ApprovalRequest>(`/approvals/${id}/approve`, { method: 'POST', body: { note } }),
  deny: (id: string, note?: string) =>
    api<ApprovalRequest>(`/approvals/${id}/deny`, { method: 'POST', body: { note } }),
  cancel: (id: string) => api<ApprovalRequest>(`/approvals/${id}/cancel`, { method: 'POST' }),
};

// --- Users ---

export type User = {
  id: string;
  email: string;
  fullName: string;
  roleId: string;
  roleName: string;
  active: boolean;
  mfaMethod: MfaMethod | null;
  createdAt: string;
};

export const users = {
  list: () => api<User[]>('/users'),
  /** Update the signed-in user's own display name (no permission gate). */
  updateMe: (fullName: string) => api<User>('/users/me', { method: 'PATCH', body: { fullName } }),
  create: (body: { email: string; password: string; fullName: string; roleId: string }) =>
    api<User>('/users', { method: 'POST', body }),
  update: (id: string, body: { fullName?: string; roleId?: string; active?: boolean }) =>
    api<User>(`/users/${id}`, { method: 'PATCH', body }),
  resetPassword: (id: string, password: string) =>
    api<void>(`/users/${id}/reset-password`, { method: 'POST', body: { password } }),
  resetMfa: (id: string) => api<void>(`/users/${id}/reset-mfa`, { method: 'POST' }),
};

// --- Roles ---

export type Role = {
  id: string;
  name: string;
  description: string | null;
  permissions: string[];
  approvalPermissions: string[];
  isSystem: boolean;
  userCount: number;
  createdAt: string;
};

export type PermissionGroup = {
  group: string;
  permissions: { key: string; label: string; approvable?: boolean }[];
};

export const roles = {
  list: () => api<Role[]>('/roles'),
  catalog: () => api<PermissionGroup[]>('/permissions'),
  create: (body: {
    name: string;
    description?: string;
    permissions: string[];
    approvalPermissions?: string[];
  }) => api<Role>('/roles', { method: 'POST', body }),
  update: (
    id: string,
    body: {
      name?: string;
      description?: string;
      permissions?: string[];
      approvalPermissions?: string[];
    },
  ) => api<Role>(`/roles/${id}`, { method: 'PATCH', body }),
  remove: (id: string) => api<void>(`/roles/${id}`, { method: 'DELETE' }),
};

// --- API Keys ---

export type ApiKey = {
  id: string;
  name: string;
  scopes: string[];
  lastUsedAt: string | null;
  revokedAt: string | null;
  revoked: boolean;
  createdAt: string;
};

export type ApiKeyCreated = ApiKey & { plaintext: string };

export type AiScopeGroup = {
  group: string;
  scopes: { key: string; label: string }[];
};

export const apiKeys = {
  list: () => api<ApiKey[]>('/api-keys'),
  scopes: () => api<AiScopeGroup[]>('/api-keys/scopes'),
  create: (body: { name: string; scopes: string[] }) =>
    api<ApiKeyCreated>('/api-keys', { method: 'POST', body }),
  revoke: (id: string) => api<void>(`/api-keys/${id}`, { method: 'DELETE' }),
};

// --- Shop Settings ---

export type GeneralSettings = { timezone: string; defaultTaxRate: number };

export type BrandingSettings = {
  shopName: string | null;
  shopAddress: string | null;
  shopPhone: string | null;
  shopEmail: string | null;
  logoUrl: string | null;
};

export type MailConfig = {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  from: string;
  fromName: string;
  hasPassword: boolean;
};

export const settings = {
  general: () => api<GeneralSettings>('/settings/general'),
  updateGeneral: (body: { timezone: string }) =>
    api<GeneralSettings>('/settings/general', { method: 'PATCH', body }),
  branding: () => api<BrandingSettings>('/settings/branding'),
  updateBranding: (body: {
    shopName?: string;
    shopAddress?: string;
    shopPhone?: string;
    shopEmail?: string;
  }) => api<BrandingSettings>('/settings/branding', { method: 'PATCH', body }),
  mail: () => api<MailConfig>('/settings/mail'),
  updateMail: (body: {
    host?: string;
    port?: number;
    secure?: boolean;
    user?: string;
    password?: string;
    from?: string;
  }) => api<MailConfig>('/settings/mail', { method: 'PATCH', body }),
  testMail: (to: string) =>
    api<{ sent: boolean }>('/settings/mail/test', { method: 'POST', body: { to } }),
};

export const invoices = {
  /** Relative path to an invoice's PDF (rendered server-side). Hand to
   * {@link downloadAndShare} to open the OS share/print sheet. */
  pdfPath: (invoiceId: string) => `/invoices/${invoiceId}/pdf`,
  /** Email the invoice PDF. `to` omitted → the server uses the customer's email
   * on file (404s if there's none). Needs `sales.manage`. */
  email: (invoiceId: string, body: { to?: string } = {}) =>
    api<{ ok: true; to: string; messageId?: string }>(`/invoices/${invoiceId}/email`, {
      method: 'POST',
      body,
    }),
};

export const payments = {
  /** Whether card-charging is configured (gates the Tap to Pay UI). */
  gatewayStatus: () => api<GatewayStatus>('/payments/gateway/status'),
  /** Short-lived Terminal SDK token + the location to connect the reader to. */
  connectionToken: () =>
    api<{ secret: string; locationId: string | null }>('/payments/stripe/connection-token', {
      method: 'POST',
    }),
  /** Card-present PaymentIntent for an invoice (no readerId → on-device Tap to Pay). */
  terminalIntent: (invoiceId: string) =>
    api<TerminalIntent>('/payments/stripe/terminal/intent', {
      method: 'POST',
      body: { invoiceId },
    }),
  /** Poll an invoice's payments to detect the webhook-booked charge. */
  invoicePayments: (invoiceId: string) => api<InvoicePayment[]>(`/invoices/${invoiceId}/payments`),
  /** Record a manual (cash/check/card-on-file/store-credit) payment against an invoice. */
  record: (
    invoiceId: string,
    body: { paymentMethodId: string; amount: number; reference?: string; note?: string },
  ) => api<InvoicePayment>(`/invoices/${invoiceId}/payments`, { method: 'POST', body }),
  /** Reverse a manual payment. In approval mode returns { approvalRequest }. */
  reverse: (paymentId: string, reason?: string) =>
    api<ReverseResult>(`/payments/${paymentId}/reverse`, { method: 'POST', body: { reason } }),
  /** Refund a processor (Stripe) card payment: refunds the card and unwinds the books. */
  refundProcessor: (paymentId: string, reason?: string) =>
    api<ReverseResult>(`/payments/${paymentId}/refund`, { method: 'POST', body: { reason } }),
};
