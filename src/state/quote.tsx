import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useQuery } from '@tanstack/react-query';
import { NewSaleLine, Sale, settings } from '../lib/api';

/** Fallback default sales tax rate (percent) until the store setting loads. */
const FALLBACK_TAX_PCT = 7;

/** A draft quote being assembled on the floor. Pickers (SKU / customer) write
 * into this shared cart so we don't have to pass callbacks through navigation
 * params (which must stay serializable). */
export type QuoteCustomer = {
  id: string;
  name: string;
  company: string | null;
  taxExempt: boolean;
};
/** `listPrice` is the catalog price captured when the line was added, so the UI
 * can show when the unit price has been customized away from it. */
export type QuoteLine = NewSaleLine & { key: string; listPrice: number };

type QuoteState = {
  customer: QuoteCustomer | null;
  lines: QuoteLine[];
  taxRate: number; // percent, e.g. 7 for 7%
  /** When set, the builder is editing this existing draft sale (PATCH on submit)
   * rather than creating a new one. */
  editingSaleId: string | null;
  setCustomer: (c: QuoteCustomer | null) => void;
  setTaxRate: (pct: number) => void;
  addLine: (line: NewSaleLine) => void;
  updateQty: (key: string, qty: number) => void;
  updatePrice: (key: string, unitPrice: number) => void;
  removeLine: (key: string) => void;
  /** Round the order to a target total the customer actually pays (up or down),
   * back-solving every line's unit price so the difference rides along as a
   * discount. The target is the post-tax total. */
  roundTotal: (target: number) => void;
  /** Load an existing sale into the cart for editing (customer must be resolved
   * separately so its tax-exempt flag is known). */
  seedFrom: (sale: Sale, customer: QuoteCustomer) => void;
  clear: () => void;
  subtotal: number;
  taxAmount: number;
  total: number;
};

const QuoteContext = createContext<QuoteState | null>(null);

let seq = 0;
const nextKey = () => `l${Date.now()}_${seq++}`;

export function QuoteProvider({ children }: { children: React.ReactNode }) {
  const [customer, setCustomer] = useState<QuoteCustomer | null>(null);
  const [lines, setLines] = useState<QuoteLine[]>([]);
  const [taxRate, setTaxRate] = useState(FALLBACK_TAX_PCT);
  const [editingSaleId, setEditingSaleId] = useState<string | null>(null);

  // The store-wide default tax rate (percent), used for a fresh quote and as
  // the reset target after clearing. Kept in a ref so `clear()` reads the
  // latest without being re-created on every change.
  const defaultPctRef = useRef(FALLBACK_TAX_PCT);
  const { data: general } = useQuery({
    queryKey: ['settings', 'general'],
    queryFn: settings.general,
    staleTime: 5 * 60 * 1000,
  });
  useEffect(() => {
    if (general?.defaultTaxRate == null) return;
    const pct = +(general.defaultTaxRate * 100).toFixed(4);
    defaultPctRef.current = pct;
    // Apply to a pristine builder (not editing an existing sale, no lines yet)
    // so a freshly opened quote shows the configured default.
    if (!editingSaleId && lines.length === 0) setTaxRate(pct);
  }, [general, editingSaleId, lines.length]);

  const addLine = useCallback((line: NewSaleLine) => {
    setLines((prev) => {
      // Same SKU/service already in the cart → bump quantity instead of duplicating.
      const existing = prev.find((l) => l.itemType === line.itemType && l.itemId === line.itemId);
      if (existing) {
        return prev.map((l) => (l === existing ? { ...l, qty: l.qty + line.qty } : l));
      }
      return [...prev, { ...line, key: nextKey(), listPrice: line.unitPrice }];
    });
  }, []);

  const updateQty = useCallback((key: string, qty: number) => {
    setLines((prev) => prev.map((l) => (l.key === key ? { ...l, qty: Math.max(1, qty) } : l)));
  }, []);

  const updatePrice = useCallback((key: string, unitPrice: number) => {
    const safe = Number.isFinite(unitPrice) && unitPrice >= 0 ? unitPrice : 0;
    setLines((prev) => prev.map((l) => (l.key === key ? { ...l, unitPrice: safe } : l)));
  }, []);

  const removeLine = useCallback((key: string) => {
    setLines((prev) => prev.filter((l) => l.key !== key));
  }, []);

  const roundTotal = useCallback(
    (target: number) => {
      if (!Number.isFinite(target) || target <= 0) return;
      const effRate = customer?.taxExempt ? 0 : taxRate / 100;
      const targetSubtotal = effRate ? target / (1 + effRate) : target;
      setLines((prev) => {
        const sub = prev.reduce((s, l) => s + (l.unitPrice * l.qty - (l.discount ?? 0)), 0);
        if (sub <= 0) return prev;
        const factor = targetSubtotal / sub;
        return prev.map((l) => ({ ...l, unitPrice: +(l.unitPrice * factor).toFixed(2) }));
      });
    },
    [customer, taxRate],
  );

  const seedFrom = useCallback((sale: Sale, c: QuoteCustomer) => {
    setCustomer(c);
    setLines(
      sale.lines.map((l) => ({
        itemType: l.itemType,
        itemId: l.itemId,
        description: l.description,
        qty: l.qty,
        unitPrice: Number(l.unitPrice),
        discount: Number(l.discount) || undefined,
        key: nextKey(),
        listPrice: Number(l.unitPrice),
      })),
    );
    setTaxRate(+(Number(sale.taxRate) * 100).toFixed(4));
    setEditingSaleId(sale.id);
  }, []);

  const clear = useCallback(() => {
    setCustomer(null);
    setLines([]);
    setTaxRate(defaultPctRef.current);
    setEditingSaleId(null);
  }, []);

  const subtotal = useMemo(
    () => lines.reduce((s, l) => s + (l.unitPrice * l.qty - (l.discount ?? 0)), 0),
    [lines],
  );
  const taxAmount = useMemo(
    () => (customer?.taxExempt ? 0 : +(subtotal * (taxRate / 100)).toFixed(2)),
    [customer, subtotal, taxRate],
  );
  const total = useMemo(() => +(subtotal + taxAmount).toFixed(2), [subtotal, taxAmount]);

  const value = useMemo<QuoteState>(
    () => ({
      customer,
      lines,
      taxRate,
      editingSaleId,
      setCustomer,
      setTaxRate,
      addLine,
      updateQty,
      updatePrice,
      removeLine,
      roundTotal,
      seedFrom,
      clear,
      subtotal,
      taxAmount,
      total,
    }),
    [
      customer,
      lines,
      taxRate,
      editingSaleId,
      addLine,
      updateQty,
      updatePrice,
      removeLine,
      roundTotal,
      seedFrom,
      clear,
      subtotal,
      taxAmount,
      total,
    ],
  );

  return <QuoteContext.Provider value={value}>{children}</QuoteContext.Provider>;
}

export function useQuote(): QuoteState {
  const ctx = useContext(QuoteContext);
  if (!ctx) throw new Error('useQuote must be used within QuoteProvider');
  return ctx;
}
