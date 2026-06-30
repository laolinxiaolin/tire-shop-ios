import { useMutation, useQuery } from '@tanstack/react-query';
import React, { useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ApiError, cashAccounts, customers, payments, PaymentMethod } from '../lib/api';
import { money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';
import { Button, KeyboardAvoider } from './ui';

const STORE_CREDIT_CODE = '2400';

type Row = { paymentMethodId: string; amount: string; reference: string };

/**
 * Record one or more manual payments against an invoice — the mobile twin of
 * the web `PaymentModal`. Supports split tender, per-method card surcharges,
 * and capping a store-credit tender at the customer's available balance.
 * Processor-backed methods (Stripe) are hidden: those charge through Tap to
 * Pay, and the API rejects manual records for them.
 */
export function PaymentSheet({
  visible,
  invoiceId,
  balance,
  customerId,
  onClose,
  onPaid,
}: {
  visible: boolean;
  invoiceId: string;
  balance: number;
  customerId?: string;
  onClose: () => void;
  onPaid: () => void;
}) {
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const methodsQ = useQuery({
    queryKey: ['payment-methods'],
    queryFn: () => cashAccounts.methods(),
    enabled: visible,
  });
  const methods = useMemo(
    () => (methodsQ.data ?? []).filter((m) => m.isActive && !m.processor),
    [methodsQ.data],
  );

  const creditQ = useQuery({
    queryKey: ['credit-balance', customerId],
    queryFn: () => customers.creditBalance(customerId!),
    enabled: visible && !!customerId,
  });
  const creditBalance = customerId ? (creditQ.data?.balance ?? null) : null;

  // Seed a single row defaulting to the full balance on the first real method.
  useEffect(() => {
    if (!visible) {
      setRows([]);
      setErr(null);
      return;
    }
    if (rows.length === 0 && methods.length > 0) {
      const dflt = methods.find((m) => m.account.code !== STORE_CREDIT_CODE) ?? methods[0];
      setRows([{ paymentMethodId: dflt.id, amount: balance.toFixed(2), reference: '' }]);
    }
  }, [visible, methods, balance, rows.length]);

  function updateRow(i: number, patch: Partial<Row>) {
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));
  }
  function removeRow(i: number) {
    setRows((prev) => prev.filter((_, idx) => idx !== i));
  }
  function addRow() {
    const applied = rows.reduce((a, r) => a + (Number(r.amount) || 0), 0);
    const remaining = +(balance - applied).toFixed(2);
    setRows((prev) => [
      ...prev,
      {
        paymentMethodId: methods[0]?.id ?? '',
        amount: remaining > 0 ? remaining.toFixed(2) : '',
        reference: '',
      },
    ]);
  }

  const methodById = (id: string) => methods.find((m) => m.id === id);
  const feeRate = (r: Row) => {
    const m = methodById(r.paymentMethodId);
    return m && m.account.code !== STORE_CREDIT_CODE && m.feeRate ? Number(m.feeRate) : 0;
  };
  const rowSurcharge = (r: Row) => {
    const rate = feeRate(r);
    return rate > 0 ? +((Number(r.amount) || 0) * rate).toFixed(2) : 0;
  };

  const totalApplied = +rows.reduce((a, r) => a + (Number(r.amount) || 0), 0).toFixed(2);
  const totalSurcharge = +rows.reduce((a, r) => a + rowSurcharge(r), 0).toFixed(2);
  const totalCustomerPays = +(totalApplied + totalSurcharge).toFixed(2);
  const remaining = +(balance - totalApplied).toFixed(2);
  const overpay = totalApplied - balance > 0.01;
  const storeCreditApplied = +rows
    .filter((r) => methodById(r.paymentMethodId)?.account.code === STORE_CREDIT_CODE)
    .reduce((a, r) => a + (Number(r.amount) || 0), 0)
    .toFixed(2);
  const overCredit = creditBalance != null && storeCreditApplied > creditBalance + 0.005;

  const record = useMutation({
    mutationFn: async () => {
      const valid = rows.filter((r) => Number(r.amount) > 0 && r.paymentMethodId);
      if (valid.length === 0) throw new ApiError(0, t('payment.addOne'));
      if (overpay) throw new ApiError(0, t('payment.exceedsBalance'));
      for (const r of valid) {
        const applied = Number(r.amount);
        const rate = feeRate(r);
        const gross = rate > 0 ? +(applied * (1 + rate)).toFixed(2) : applied;
        await payments.record(invoiceId, {
          paymentMethodId: r.paymentMethodId,
          amount: gross,
          reference: r.reference || undefined,
        });
      }
    },
    onSuccess: () => onPaid(),
    onError: (e) => setErr(e instanceof ApiError ? e.message : t('common.error')),
  });

  const validCount = rows.filter((r) => Number(r.amount) > 0).length;

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <KeyboardAvoider style={styles.screen}>
        <View style={styles.header}>
          <Text style={styles.title}>{t('payment.recordPayment')}</Text>
          <Pressable onPress={onClose} hitSlop={8}>
            <Text style={styles.close}>{t('common.cancel')}</Text>
          </Pressable>
        </View>

        <ScrollView contentContainerStyle={{ padding: space.lg, paddingBottom: 40 }}>
          <Text style={styles.balanceLabel}>
            {t('payment.balanceOwed')} <Text style={styles.balanceValue}>{money(balance)}</Text>
          </Text>

          {methodsQ.isLoading ? (
            <Text style={styles.muted}>{t('common.loading')}</Text>
          ) : methods.length === 0 ? (
            <Text style={styles.errText}>{t('payment.noMethods')}</Text>
          ) : (
            <>
              {rows.map((r, i) => (
                <RowEditor
                  key={i}
                  row={r}
                  methods={methods}
                  creditBalance={creditBalance}
                  hasCustomer={!!customerId}
                  surcharge={rowSurcharge(r)}
                  feeRate={feeRate(r)}
                  onChange={(patch) => updateRow(i, patch)}
                  onRemove={rows.length > 1 ? () => removeRow(i) : undefined}
                />
              ))}

              <Pressable onPress={addRow} hitSlop={6} style={{ paddingVertical: space.sm }}>
                <Text style={styles.addMethod}>{t('payment.addMethod')}</Text>
              </Pressable>

              <View style={styles.totals}>
                <Total label={t('payment.appliedToInvoice')} value={money(totalApplied)} />
                {totalSurcharge > 0 && (
                  <Total label={t('payment.fee')} value={money(totalSurcharge)} />
                )}
                {totalSurcharge > 0 && (
                  <Total
                    label={t('payment.customerPaysTotal')}
                    value={money(totalCustomerPays)}
                    strong
                  />
                )}
                <Total
                  label={remaining >= 0 ? t('payment.remainingBalance') : t('payment.overpayment')}
                  value={money(Math.abs(remaining))}
                  tone={Math.abs(remaining) < 0.01 ? 'good' : remaining > 0 ? 'warn' : 'bad'}
                />
              </View>

              {overCredit && (
                <Text style={styles.errText}>
                  {t('payment.overCredit', { amount: money(creditBalance ?? 0) })}
                </Text>
              )}
              {err && <Text style={styles.errText}>{err}</Text>}
            </>
          )}
        </ScrollView>

        {methods.length > 0 && (
          <View style={[styles.footer, { paddingBottom: space.lg + insets.bottom }]}>
            <Button
              title={
                record.isPending
                  ? t('payment.recording')
                  : validCount <= 1
                    ? t('payment.recordOne')
                    : t('payment.recordN', { n: validCount })
              }
              onPress={() => {
                setErr(null);
                record.mutate();
              }}
              loading={record.isPending}
              disabled={totalApplied <= 0 || overpay || overCredit}
            />
          </View>
        )}
      </KeyboardAvoider>
    </Modal>
  );
}

function RowEditor({
  row,
  methods,
  creditBalance,
  hasCustomer,
  surcharge,
  feeRate,
  onChange,
  onRemove,
}: {
  row: Row;
  methods: PaymentMethod[];
  creditBalance: number | null;
  hasCustomer: boolean;
  surcharge: number;
  feeRate: number;
  onChange: (patch: Partial<Row>) => void;
  onRemove?: () => void;
}) {
  const { t } = useI18n();
  const applied = Number(row.amount) || 0;
  const gross = +(applied + surcharge).toFixed(2);

  return (
    <View style={styles.row}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chips}
      >
        {methods.map((m) => {
          const sc = m.account.code === STORE_CREDIT_CODE;
          const disabled = sc && (!hasCustomer || (creditBalance ?? 0) < 0.005);
          const active = m.id === row.paymentMethodId;
          return (
            <Pressable
              key={m.id}
              disabled={disabled}
              onPress={() => onChange({ paymentMethodId: m.id })}
              style={[
                styles.chip,
                active ? styles.chipActive : null,
                disabled ? styles.chipDisabled : null,
              ]}
            >
              <Text style={[styles.chipText, active ? styles.chipTextActive : null]}>
                {m.name}
                {sc && hasCustomer ? ` (${money(creditBalance ?? 0)})` : ''}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>

      <View style={styles.rowControls}>
        <View style={styles.amountBox}>
          <Text style={styles.currency}>$</Text>
          <TextInput
            style={styles.amountField}
            value={row.amount}
            keyboardType="decimal-pad"
            selectTextOnFocus
            placeholder="0.00"
            placeholderTextColor={colors.muted}
            onChangeText={(text) => {
              let cleaned = text.replace(/[^0-9.]/g, '');
              const parts = cleaned.split('.');
              if (parts.length > 2) cleaned = `${parts[0]}.${parts.slice(1).join('')}`;
              onChange({ amount: cleaned });
            }}
          />
        </View>
        {onRemove && (
          <Pressable onPress={onRemove} hitSlop={8} style={{ paddingLeft: space.sm }}>
            <Text style={styles.remove}>✕</Text>
          </Pressable>
        )}
      </View>

      {feeRate > 0 && applied > 0 && (
        <Text style={styles.feeNote}>
          {t('payment.feeRateNote', {
            rate: (feeRate * 100).toFixed(1),
            surcharge: money(surcharge),
          })}{' '}
          · {t('payment.customerPaysGross', { gross: money(gross) })}
        </Text>
      )}

      <TextInput
        style={styles.refField}
        value={row.reference}
        placeholder={t('payment.referenceOptional')}
        placeholderTextColor={colors.muted}
        onChangeText={(v) => onChange({ reference: v })}
      />
    </View>
  );
}

function Total({
  label,
  value,
  strong,
  tone,
}: {
  label: string;
  value: string;
  strong?: boolean;
  tone?: 'good' | 'warn' | 'bad';
}) {
  const color =
    tone === 'good'
      ? colors.success
      : tone === 'warn'
        ? colors.warnText
        : tone === 'bad'
          ? colors.danger
          : colors.text;
  return (
    <View style={styles.totalRow}>
      <Text style={[styles.totalLabel, strong || tone ? { fontWeight: '700', color } : null]}>
        {label}
      </Text>
      <Text style={[styles.totalValue, strong || tone ? { fontWeight: '800', color } : null]}>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: space.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
    backgroundColor: colors.card,
  },
  title: { fontSize: 18, fontWeight: '700', color: colors.text },
  close: { fontSize: 16, color: colors.primary, fontWeight: '600' },
  balanceLabel: { fontSize: 14, color: colors.muted, marginBottom: space.md },
  balanceValue: { fontSize: 15, fontWeight: '800', color: colors.text },
  muted: { color: colors.muted },
  row: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.md,
    marginBottom: space.sm,
  },
  chips: { gap: space.sm, paddingBottom: space.sm },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: 6,
    borderRadius: radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.bg,
  },
  chipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipDisabled: { opacity: 0.4 },
  chipText: { fontSize: 13, color: colors.text, fontWeight: '600' },
  chipTextActive: { color: colors.primaryText },
  rowControls: { flexDirection: 'row', alignItems: 'center', marginTop: space.xs },
  amountBox: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    backgroundColor: colors.bg,
    paddingHorizontal: space.sm,
  },
  currency: { fontSize: 16, color: colors.muted },
  amountField: {
    flex: 1,
    paddingVertical: 8,
    paddingLeft: 4,
    fontSize: 16,
    color: colors.text,
    textAlign: 'right',
  },
  remove: { fontSize: 16, color: colors.danger },
  feeNote: { fontSize: 12, color: colors.warnText, marginTop: space.sm },
  refField: {
    marginTop: space.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    backgroundColor: colors.bg,
    paddingHorizontal: space.sm,
    paddingVertical: 8,
    fontSize: 14,
    color: colors.text,
  },
  addMethod: { fontSize: 15, color: colors.primary, fontWeight: '600' },
  totals: {
    marginTop: space.md,
    paddingTop: space.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3 },
  totalLabel: { fontSize: 15, color: colors.muted },
  totalValue: { fontSize: 15, color: colors.text },
  errText: { fontSize: 14, color: colors.danger, marginTop: space.sm },
  footer: {
    padding: space.lg,
    backgroundColor: colors.card,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});
