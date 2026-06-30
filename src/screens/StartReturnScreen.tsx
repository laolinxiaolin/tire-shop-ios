import { useNavigation, useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  Button,
  Card,
  Divider,
  Empty,
  ErrorView,
  Field,
  Loading,
  SearchBar,
} from '../components/ui';
import { useI18n } from '../lib/i18n';
import {
  ApiError,
  cashAccounts,
  CreateReturnInput,
  InventoryDisposition,
  inventory,
  PaymentMethod,
  RefundMethod,
  Returnable,
  returns,
  ReturnType,
  Supplier,
  suppliers as suppliersApi,
  TireSku,
  WarrantyDisposition,
} from '../lib/api';
import { money } from '../lib/format';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

type ReturnLineRow = {
  saleLineId: string;
  description: string;
  unitPrice: number;
  qtyRemaining: number;
  qty: number;
  disposition: InventoryDisposition;
};

type ReplacementRow = { skuId: string; qty: number; unitPrice: number };

const REFUND_METHODS: RefundMethod[] = ['ORIGINAL', 'CASH', 'CHECK', 'CARD', 'STORE_CREDIT'];

const round2 = (n: number) => Math.round(n * 100) / 100;
const stockOf = (s: TireSku) => s.inventory.reduce((a, i) => a + i.qtyOnHand, 0);
const skuLabel = (s: TireSku) => `${s.brand} ${s.model} ${s.size} ${s.position}`;

export default function StartReturnScreen() {
  const { t } = useI18n();
  const { saleId, saleRef } = useRoute<RouteProp<RootStackParamList, 'StartReturn'>>().params;
  const saleLabel = saleRef ?? '';
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const insets = useSafeAreaInsets();

  const returnableQ = useQuery({
    queryKey: ['returnable', saleId],
    queryFn: () => returns.returnable(saleId),
  });
  const methodsQ = useQuery({
    queryKey: ['payment-methods'],
    queryFn: () => cashAccounts.methods(),
  });
  const skusQ = useQuery({
    queryKey: ['skus', 'all'],
    queryFn: () => inventory.listSkus({ pageSize: 1000 }),
  });
  const suppliersQ = useQuery({ queryKey: ['suppliers'], queryFn: () => suppliersApi.list() });

  const data = returnableQ.data ?? null;
  const methods = useMemo(() => (methodsQ.data ?? []).filter((m) => m.isActive), [methodsQ.data]);
  // Tenders we can hand cash back through: not store credit, not gateway.
  const payoutTenders = useMemo(
    () => methods.filter((m) => !m.processor && m.account.code !== '2400'),
    [methods],
  );
  const skus = useMemo(() => (skusQ.data?.items ?? []).filter((s) => s.active), [skusQ.data]);
  const suppliers = useMemo(() => suppliersQ.data?.items ?? [], [suppliersQ.data]);

  const [type, setType] = useState<ReturnType>('RETURN');
  const [lines, setLines] = useState<ReturnLineRow[]>([]);
  const [replacements, setReplacements] = useState<ReplacementRow[]>([]);
  const [refundMethod, setRefundMethod] = useState<RefundMethod>('ORIGINAL');
  const [paymentMethodId, setPaymentMethodId] = useState('');
  const [restockingFee, setRestockingFee] = useState('0');
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  const [warrantyDisposition, setWarrantyDisposition] = useState<WarrantyDisposition>('WRITE_OFF');
  const [supplierId, setSupplierId] = useState('');
  const [warrantyReplace, setWarrantyReplace] = useState(false);
  const [netMode, setNetMode] = useState<'collect' | 'invoice'>('collect');
  const [netPaymentMethodId, setNetPaymentMethodId] = useState('');
  const [refundMode, setRefundMode] = useState<'refund' | 'credit'>('refund');
  const [netRefundMethodId, setNetRefundMethodId] = useState('');
  const [skuPickerFor, setSkuPickerFor] = useState<number | null>(null);

  // Seed line rows once the returnable lines arrive.
  useEffect(() => {
    if (!data) return;
    setLines(
      data.lines
        .filter((l) => l.qtyRemaining > 0)
        .map((l) => ({
          saleLineId: l.saleLineId,
          description: l.description,
          unitPrice: l.unitPrice,
          qtyRemaining: l.qtyRemaining,
          qty: 0,
          disposition: 'RESTOCK' as InventoryDisposition,
        })),
    );
    if (!data.originalPaymentMethodId) setRefundMethod('CASH');
  }, [data]);

  useEffect(() => {
    if (methods.length && !netPaymentMethodId) setNetPaymentMethodId(methods[0].id);
  }, [methods, netPaymentMethodId]);
  useEffect(() => {
    if (payoutTenders.length && !netRefundMethodId) setNetRefundMethodId(payoutTenders[0].id);
  }, [payoutTenders, netRefundMethodId]);
  useEffect(() => {
    if (suppliers.length && !supplierId) setSupplierId(suppliers[0].id);
  }, [suppliers, supplierId]);

  // EXCHANGE issues store credit on the return half; warranty-replace likewise.
  useEffect(() => {
    if (type === 'EXCHANGE') setRefundMethod('STORE_CREDIT');
    if (type === 'WARRANTY' && warrantyReplace) setRefundMethod('STORE_CREDIT');
    if (type === 'WARRANTY') setRestockingFee('0');
  }, [type, warrantyReplace]);

  function updateLine(i: number, patch: Partial<ReturnLineRow>) {
    setLines((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));
  }
  function addReplacement() {
    const first = skus[0];
    setReplacements((prev) => [
      ...prev,
      first
        ? { skuId: first.id, qty: 1, unitPrice: Number(first.priceRetail) }
        : { skuId: '', qty: 1, unitPrice: 0 },
    ]);
  }
  function updateReplacement(i: number, patch: Partial<ReplacementRow>) {
    setReplacements((prev) =>
      prev.map((r, idx) => {
        if (idx !== i) return r;
        const merged = { ...r, ...patch };
        if (patch.skuId && patch.skuId !== r.skuId) {
          const sku = skus.find((s) => s.id === patch.skuId);
          if (sku) merged.unitPrice = Number(sku.priceRetail);
        }
        return merged;
      }),
    );
  }
  function removeReplacement(i: number) {
    setReplacements((prev) => prev.filter((_, idx) => idx !== i));
  }

  const selectedLines = useMemo(() => lines.filter((l) => l.qty > 0), [lines]);
  const refundSubtotal = useMemo(
    () => round2(selectedLines.reduce((a, l) => a + l.unitPrice * l.qty, 0)),
    [selectedLines],
  );
  const taxRate = data?.taxRate ?? 0;
  const refundTax = round2(refundSubtotal * taxRate);
  const fee = Math.max(0, Number(restockingFee) || 0);
  const refundTotal = round2(refundSubtotal + refundTax - fee);

  const replacementSubtotal = useMemo(
    () => round2(replacements.reduce((a, r) => a + r.unitPrice * r.qty, 0)),
    [replacements],
  );
  const replacementTax = round2(replacementSubtotal * taxRate);
  const replacementTotal = round2(replacementSubtotal + replacementTax);
  const net = round2(replacementTotal - refundTotal); // positive = customer owes

  const isWarrantyRefund = type === 'WARRANTY' && !warrantyReplace;
  const isWarrantyReplace = type === 'WARRANTY' && warrantyReplace;
  const needsPaymentMethod =
    (type === 'RETURN' || isWarrantyRefund) &&
    (refundMethod === 'CASH' || refundMethod === 'CHECK' || refundMethod === 'CARD');
  const customerOwes = type === 'EXCHANGE' && net > 0.005;
  const customerNeedsRefund = type === 'EXCHANGE' && net < -0.005;
  const sendReplacementLines = type === 'EXCHANGE' || isWarrantyReplace;

  const submit = useMutation({
    mutationFn: async () => {
      const body: CreateReturnInput = {
        type,
        reason: reason || undefined,
        restockingFee: type === 'WARRANTY' ? 0 : fee,
        refundMethod,
        paymentMethodId: needsPaymentMethod ? paymentMethodId : undefined,
        notes: notes || undefined,
        lines: selectedLines.map((l) => ({
          saleLineId: l.saleLineId,
          qty: l.qty,
          inventoryDisposition: l.disposition,
        })),
        replacementLines: sendReplacementLines
          ? replacements.map((r) => ({ skuId: r.skuId, qty: r.qty, unitPrice: r.unitPrice }))
          : undefined,
        warrantyDisposition: type === 'WARRANTY' ? warrantyDisposition : undefined,
        supplierId:
          type === 'WARRANTY' && warrantyDisposition === 'SUPPLIER_CLAIM' ? supplierId : undefined,
      };
      const draft = await returns.create(saleId, body);
      const postBody =
        customerOwes && netMode === 'collect'
          ? { netPayment: { paymentMethodId: netPaymentMethodId, amount: net } }
          : customerNeedsRefund && refundMode === 'refund'
            ? { netRefund: { paymentMethodId: netRefundMethodId } }
            : undefined;
      return returns.post(draft.id, postBody);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['returns'] });
      qc.invalidateQueries({ queryKey: ['sale', saleId] });
      qc.invalidateQueries({ queryKey: ['sales'] });
      qc.invalidateQueries({ queryKey: ['skus'] });
      Alert.alert(
        t('startReturn.done'),
        t('startReturn.postedFor', { type: t(`return.type.${type}`), n: saleLabel }),
        [{ text: t('common.ok'), onPress: () => nav.goBack() }],
      );
    },
    onError: (e) =>
      Alert.alert(
        t('startReturn.couldNotPost'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  function validateAndSubmit() {
    if (selectedLines.length === 0) return Alert.alert(t('startReturn.pickLine'));
    if (type === 'EXCHANGE' && replacements.length === 0)
      return Alert.alert(t('startReturn.addReplacement'));
    if (sendReplacementLines && replacements.some((r) => !r.skuId || r.qty <= 0))
      return Alert.alert(t('startReturn.incompleteReplacement'));
    if (fee > refundSubtotal + refundTax) return Alert.alert(t('startReturn.feeTooHigh'));
    if (needsPaymentMethod && !paymentMethodId)
      return Alert.alert(t('startReturn.pickRefundMethod'));
    if (customerOwes && netMode === 'collect' && !netPaymentMethodId)
      return Alert.alert(t('startReturn.pickCollectMethod'));
    if (customerNeedsRefund && refundMode === 'refund' && !netRefundMethodId)
      return Alert.alert(t('startReturn.pickCollectMethod'));
    if (type === 'WARRANTY' && warrantyDisposition === 'SUPPLIER_CLAIM' && !supplierId)
      return Alert.alert(t('startReturn.pickSupplier'));
    submit.mutate();
  }

  const loading =
    returnableQ.isLoading || methodsQ.isLoading || skusQ.isLoading || suppliersQ.isLoading;
  if (loading) return <Loading />;
  if (returnableQ.isError)
    return (
      <ErrorView message={(returnableQ.error as ApiError).message} onRetry={returnableQ.refetch} />
    );

  const submitLabel = submit.isPending
    ? t('startReturn.posting')
    : type === 'EXCHANGE'
      ? customerOwes && netMode === 'collect'
        ? t('startReturn.collectAndPost', { amount: money(net) })
        : customerNeedsRefund && refundMode === 'refund'
          ? t('startReturn.refundAndPost', { amount: money(Math.abs(net)) })
          : t('startReturn.postExchange')
      : isWarrantyReplace
        ? t('startReturn.postWarranty')
        : type === 'WARRANTY'
          ? t('startReturn.refundWarranty', { amount: money(refundTotal) })
          : t('startReturn.refundAmount', { amount: money(refundTotal) });

  const skuName = (id: string) => {
    const s = skus.find((x) => x.id === id);
    return s ? skuLabel(s) : t('startReturn.chooseTire');
  };

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <ScrollView
        style={{ backgroundColor: colors.bg }}
        contentContainerStyle={{ padding: space.lg, paddingBottom: 120 + insets.bottom }}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.title}>{t('startReturn.saleTitle', { n: saleLabel })}</Text>

        {/* Type */}
        <Segmented
          options={(['RETURN', 'EXCHANGE', 'WARRANTY'] as ReturnType[]).map((rt) => ({
            value: rt,
            label: t(`return.type.${rt}`),
          }))}
          value={type}
          onChange={setType}
        />

        {lines.length === 0 ? (
          <Empty message={t('startReturn.everythingReturned')} />
        ) : (
          <>
            {/* Lines coming back */}
            <Text style={styles.section}>{t('startReturn.comingBack')}</Text>
            <Card style={{ padding: 0 }}>
              {lines.map((l, i) => (
                <View key={l.saleLineId}>
                  {i > 0 ? <Divider /> : null}
                  <View style={styles.lineRow}>
                    <View style={{ flex: 1, paddingRight: space.sm }}>
                      <Text style={styles.lineDesc} numberOfLines={2}>
                        {l.description}
                      </Text>
                      <Text style={styles.lineMeta}>
                        {money(l.unitPrice)} · {l.qtyRemaining} {t('startReturn.left')}
                      </Text>
                      {l.qty > 0 ? (
                        <View style={styles.dispRow}>
                          {(['RESTOCK', 'SCRAP'] as InventoryDisposition[]).map((d) => (
                            <Pressable
                              key={d}
                              onPress={() => updateLine(i, { disposition: d })}
                              style={[
                                styles.miniChip,
                                l.disposition === d ? styles.miniChipOn : null,
                              ]}
                            >
                              <Text
                                style={[
                                  styles.miniChipText,
                                  l.disposition === d ? styles.miniChipTextOn : null,
                                ]}
                              >
                                {d === 'RESTOCK'
                                  ? t('startReturn.restock')
                                  : t('startReturn.scrap')}
                              </Text>
                            </Pressable>
                          ))}
                        </View>
                      ) : null}
                    </View>
                    <Stepper
                      value={l.qty}
                      min={0}
                      max={l.qtyRemaining}
                      onChange={(q) => updateLine(i, { qty: q })}
                    />
                  </View>
                </View>
              ))}
            </Card>

            {/* Warranty options */}
            {type === 'WARRANTY' ? (
              <>
                <Text style={styles.section}>{t('startReturn.warranty')}</Text>
                <Card>
                  <Text style={styles.label}>{t('startReturn.disposition')}</Text>
                  <Segmented
                    compact
                    options={[
                      { value: 'WRITE_OFF', label: t('startReturn.writeOff') },
                      { value: 'SUPPLIER_CLAIM', label: t('startReturn.supplierClaim') },
                    ]}
                    value={warrantyDisposition}
                    onChange={setWarrantyDisposition}
                  />
                  {warrantyDisposition === 'SUPPLIER_CLAIM' ? (
                    <>
                      <Text style={[styles.label, { marginTop: space.md }]}>
                        {t('startReturn.supplier')}
                      </Text>
                      <ChipPicker
                        options={suppliers.map((s: Supplier) => ({ value: s.id, label: s.name }))}
                        value={supplierId}
                        onChange={setSupplierId}
                        emptyText={t('startReturn.noSuppliers')}
                      />
                    </>
                  ) : null}
                  <Pressable
                    onPress={() => setWarrantyReplace((v) => !v)}
                    style={[styles.toggleRow, { marginTop: space.md }]}
                  >
                    <View style={[styles.checkbox, warrantyReplace ? styles.checkboxOn : null]}>
                      {warrantyReplace ? <Text style={styles.checkmark}>✓</Text> : null}
                    </View>
                    <Text style={styles.toggleLabel}>{t('startReturn.freeReplacement')}</Text>
                  </Pressable>
                  {!warrantyReplace ? (
                    <Text style={styles.hint}>{t('startReturn.refundOnly')}</Text>
                  ) : null}
                </Card>
              </>
            ) : null}

            {/* Replacements */}
            {sendReplacementLines ? (
              <>
                <View style={styles.sectionRow}>
                  <Text style={styles.section}>
                    {isWarrantyReplace
                      ? t('startReturn.replacementFree')
                      : t('startReturn.goingOut')}
                  </Text>
                  <Pressable onPress={addReplacement} hitSlop={8}>
                    <Text style={styles.addLink}>{t('startReturn.addTire')}</Text>
                  </Pressable>
                </View>
                {replacements.length === 0 ? (
                  <Text style={styles.hint}>{t('startReturn.addReplacementHint')}</Text>
                ) : (
                  <Card style={{ padding: 0 }}>
                    {replacements.map((r, i) => {
                      const stock = skus.find((s) => s.id === r.skuId);
                      return (
                        <View key={i}>
                          {i > 0 ? <Divider /> : null}
                          <View style={styles.replRow}>
                            <View style={styles.replTop}>
                              <Pressable style={{ flex: 1 }} onPress={() => setSkuPickerFor(i)}>
                                <Text style={styles.replSku} numberOfLines={1}>
                                  {skuName(r.skuId)}
                                </Text>
                                <Text style={styles.lineMeta}>
                                  {stock
                                    ? t('startReturn.inStock', { n: stockOf(stock) })
                                    : t('common.tapToChoose')}
                                </Text>
                              </Pressable>
                              <Pressable onPress={() => removeReplacement(i)} hitSlop={8}>
                                <Text style={styles.remove}>✕</Text>
                              </Pressable>
                            </View>
                            <View style={styles.replControls}>
                              <PriceInput
                                value={r.unitPrice}
                                onChange={(n) => updateReplacement(i, { unitPrice: n })}
                              />
                              <Stepper
                                value={r.qty}
                                min={1}
                                onChange={(q) => updateReplacement(i, { qty: q })}
                              />
                            </View>
                          </View>
                        </View>
                      );
                    })}
                  </Card>
                )}
              </>
            ) : null}

            {/* Refund details */}
            <Text style={styles.section}>{t('startReturn.details')}</Text>
            <Card>
              {type === 'RETURN' || isWarrantyRefund ? (
                <>
                  <Text style={styles.label}>{t('startReturn.refundMethod')}</Text>
                  <Segmented
                    compact
                    options={REFUND_METHODS.map((m) => ({
                      value: m,
                      label:
                        m === 'ORIGINAL' && data?.originalPaymentMethodName
                          ? t('startReturn.originalWithName', {
                              name: data.originalPaymentMethodName,
                            })
                          : {
                              CASH: t('startReturn.refundCash'),
                              CHECK: t('startReturn.refundCheck'),
                              CARD: t('startReturn.refundCard'),
                              STORE_CREDIT: t('startReturn.refundStoreCredit'),
                              ORIGINAL: t('startReturn.refundOriginal'),
                            }[m],
                      disabled: m === 'ORIGINAL' && !data?.originalPaymentMethodId,
                    }))}
                    value={refundMethod}
                    onChange={setRefundMethod}
                  />
                </>
              ) : null}

              {needsPaymentMethod ? (
                <>
                  <Text style={[styles.label, { marginTop: space.md }]}>
                    {t('startReturn.paidOutVia')}
                  </Text>
                  <ChipPicker
                    options={methods.map((m: PaymentMethod) => ({ value: m.id, label: m.name }))}
                    value={paymentMethodId}
                    onChange={setPaymentMethodId}
                    emptyText={t('startReturn.noPaymentMethods')}
                  />
                </>
              ) : null}

              {type !== 'WARRANTY' ? (
                <View style={{ marginTop: space.md }}>
                  <Field
                    label={t('startReturn.restockingFee')}
                    value={restockingFee}
                    onChangeText={setRestockingFee}
                    keyboardType="decimal-pad"
                    placeholder="0"
                  />
                </View>
              ) : null}

              <View style={{ marginTop: type !== 'WARRANTY' ? 0 : space.md }}>
                <Field
                  label={t('startReturn.reason')}
                  value={reason}
                  onChangeText={setReason}
                  placeholder={t('startReturn.optional')}
                />
              </View>
              <Field
                label={t('startReturn.notes')}
                value={notes}
                onChangeText={setNotes}
                placeholder={t('startReturn.optional')}
              />
            </Card>

            {/* Summary */}
            <Card style={{ marginTop: space.md }}>
              <SummaryRow label={t('startReturn.subtotal')} value={money(refundSubtotal)} />
              <SummaryRow
                label={t('startReturn.taxRate', { rate: (taxRate * 100).toFixed(2) })}
                value={money(refundTax)}
              />
              {fee > 0 ? (
                <SummaryRow label={t('startReturn.restockingFee')} value={`−${money(fee)}`} />
              ) : null}
              <View style={styles.summaryDivider} />
              <SummaryRow
                label={
                  type === 'EXCHANGE'
                    ? t('startReturn.storeCreditIssued')
                    : isWarrantyReplace
                      ? t('startReturn.refundWarrantyFree')
                      : t('startReturn.refund')
                }
                value={money(refundTotal)}
                strong
              />
              {type === 'EXCHANGE' ? (
                <>
                  <SummaryRow
                    label={t('startReturn.replacementTotal')}
                    value={money(replacementTotal)}
                  />
                  <SummaryRow
                    label={
                      net > 0
                        ? t('startReturn.customerOwes')
                        : net < 0
                          ? t('startReturn.creditRemaining')
                          : t('startReturn.even')
                    }
                    value={money(Math.abs(net))}
                    tint={net > 0 ? colors.warnText : net < 0 ? colors.success : undefined}
                    strong
                  />
                </>
              ) : null}
            </Card>

            {/* Net upcharge */}
            {customerOwes ? (
              <Card style={{ marginTop: space.md }}>
                <Text style={styles.label}>
                  {t('startReturn.customerOwes')} {money(net)}
                </Text>
                <Segmented
                  compact
                  options={[
                    { value: 'collect', label: t('startReturn.collectNow') },
                    { value: 'invoice', label: t('startReturn.invoice') },
                  ]}
                  value={netMode}
                  onChange={setNetMode}
                />
                {netMode === 'collect' ? (
                  <>
                    <Text style={[styles.label, { marginTop: space.md }]}>
                      {t('startReturn.collectedVia')}
                    </Text>
                    <ChipPicker
                      options={methods.map((m: PaymentMethod) => ({ value: m.id, label: m.name }))}
                      value={netPaymentMethodId}
                      onChange={setNetPaymentMethodId}
                      emptyText={t('startReturn.noPaymentMethods')}
                    />
                  </>
                ) : null}
              </Card>
            ) : null}

            {customerNeedsRefund ? (
              <Card style={{ marginTop: space.md }}>
                <Text style={styles.label}>
                  {t('startReturn.netToRefund', { amount: money(Math.abs(net)) })}
                </Text>
                <Segmented
                  compact
                  options={[
                    { value: 'refund', label: t('startReturn.refundNow') },
                    { value: 'credit', label: t('startReturn.keepAsCredit') },
                  ]}
                  value={refundMode}
                  onChange={setRefundMode}
                />
                {refundMode === 'refund' ? (
                  <>
                    <Text style={[styles.label, { marginTop: space.md }]}>
                      {t('startReturn.paidOutVia')}
                    </Text>
                    <ChipPicker
                      options={payoutTenders.map((m: PaymentMethod) => ({
                        value: m.id,
                        label: m.name,
                      }))}
                      value={netRefundMethodId}
                      onChange={setNetRefundMethodId}
                      emptyText={t('startReturn.noPaymentMethods')}
                    />
                  </>
                ) : (
                  <Text style={[styles.hint, { marginTop: space.sm }]}>
                    {t('startReturn.creditRemains', { amount: money(Math.abs(net)) })}
                  </Text>
                )}
              </Card>
            ) : null}
          </>
        )}
      </ScrollView>

      {lines.length > 0 ? (
        <View style={[styles.footer, { paddingBottom: space.lg + insets.bottom }]}>
          <Button
            title={submitLabel}
            onPress={validateAndSubmit}
            loading={submit.isPending}
            disabled={selectedLines.length === 0}
          />
        </View>
      ) : null}

      <SkuPickerModal
        visible={skuPickerFor !== null}
        skus={skus}
        onClose={() => setSkuPickerFor(null)}
        onPick={(skuId) => {
          if (skuPickerFor !== null) updateReplacement(skuPickerFor, { skuId });
          setSkuPickerFor(null);
        }}
      />
    </KeyboardAvoidingView>
  );
}

function Segmented<T extends string>({
  options,
  value,
  onChange,
  compact,
}: {
  options: { value: T; label: string; disabled?: boolean }[];
  value: T;
  onChange: (v: T) => void;
  compact?: boolean;
}) {
  return (
    <View style={[styles.segRow, compact ? null : { marginVertical: space.md }]}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable
            key={o.value}
            disabled={o.disabled}
            onPress={() => onChange(o.value)}
            style={[styles.seg, on ? styles.segOn : null, o.disabled ? { opacity: 0.4 } : null]}
          >
            <Text style={[styles.segText, on ? styles.segTextOn : null]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function ChipPicker({
  options,
  value,
  onChange,
  emptyText,
}: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
  emptyText: string;
}) {
  if (options.length === 0) return <Text style={styles.hint}>{emptyText}</Text>;
  return (
    <View style={styles.chipWrap}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable
            key={o.value}
            onPress={() => onChange(o.value)}
            style={[styles.chip, on ? styles.chipOn : null]}
          >
            <Text style={[styles.chipText, on ? styles.chipTextOn : null]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function Stepper({
  value,
  min = 0,
  max,
  onChange,
}: {
  value: number;
  min?: number;
  max?: number;
  onChange: (n: number) => void;
}) {
  const dec = () => onChange(Math.max(min, value - 1));
  const inc = () => onChange(max != null ? Math.min(max, value + 1) : value + 1);
  return (
    <View style={styles.stepper}>
      <Pressable onPress={dec} style={styles.stepBtn} hitSlop={6}>
        <Text style={styles.stepBtnText}>−</Text>
      </Pressable>
      <Text style={styles.stepQty}>{value}</Text>
      <Pressable onPress={inc} style={styles.stepBtn} hitSlop={6}>
        <Text style={styles.stepBtnText}>+</Text>
      </Pressable>
    </View>
  );
}

/** Editable price; keeps its own text so "12." is allowed mid-edit. */
function PriceInput({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const [text, setText] = useState(value.toFixed(2));
  useEffect(() => {
    setText(value.toFixed(2));
  }, [value]);
  return (
    <View style={styles.priceBox}>
      <Text style={styles.priceCurrency}>$</Text>
      <TextInput
        style={styles.priceField}
        value={text}
        keyboardType="decimal-pad"
        selectTextOnFocus
        returnKeyType="done"
        onChangeText={(t) => {
          let cleaned = t.replace(/[^0-9.]/g, '');
          const parts = cleaned.split('.');
          if (parts.length > 2) cleaned = `${parts[0]}.${parts.slice(1).join('')}`;
          setText(cleaned);
          const n = Number(cleaned);
          if (Number.isFinite(n)) onChange(n);
        }}
        onBlur={() => setText((Number(text) || 0).toFixed(2))}
      />
    </View>
  );
}

function SummaryRow({
  label,
  value,
  strong,
  tint,
}: {
  label: string;
  value: string;
  strong?: boolean;
  tint?: string;
}) {
  return (
    <View style={styles.sumRow}>
      <Text style={[styles.sumLabel, strong ? styles.sumStrong : null]}>{label}</Text>
      <Text
        style={[styles.sumValue, strong ? styles.sumStrong : null, tint ? { color: tint } : null]}
      >
        {value}
      </Text>
    </View>
  );
}

function SkuPickerModal({
  visible,
  skus,
  onClose,
  onPick,
}: {
  visible: boolean;
  skus: TireSku[];
  onClose: () => void;
  onPick: (skuId: string) => void;
}) {
  const { t } = useI18n();
  const [q, setQ] = useState('');
  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return skus;
    return skus.filter((s) => `${skuLabel(s)} ${s.sku}`.toLowerCase().includes(needle));
  }, [q, skus]);
  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View style={styles.modal}>
        <View style={styles.modalHeader}>
          <Text style={styles.modalTitle}>{t('startReturn.chooseTire')}</Text>
          <Pressable onPress={onClose} hitSlop={8}>
            <Text style={styles.modalClose}>{t('common.cancel')}</Text>
          </Pressable>
        </View>
        <View style={{ padding: space.md }}>
          <SearchBar value={q} onChangeText={setQ} placeholder={t('startReturn.searchTires')} />
        </View>
        <FlatList
          data={filtered}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={() => <Divider />}
          keyboardShouldPersistTaps="handled"
          ListEmptyComponent={<Empty message={t('startReturn.noTiresMatch')} />}
          renderItem={({ item }) => (
            <Pressable style={styles.skuRow} onPress={() => onPick(item.id)}>
              <View style={{ flex: 1, paddingRight: space.sm }}>
                <Text style={styles.replSku}>{skuLabel(item)}</Text>
                <Text style={styles.lineMeta}>
                  {item.sku} · {t('startReturn.inStock', { n: stockOf(item) })}
                </Text>
              </View>
              <Text style={styles.lineTotal}>{money(item.priceRetail)}</Text>
            </Pressable>
          )}
        />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  title: { fontSize: 20, fontWeight: '800', color: colors.text },
  section: {
    fontSize: 12,
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginTop: space.lg,
    marginBottom: space.sm,
  },
  sectionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: space.lg,
    marginBottom: space.sm,
  },
  addLink: { color: colors.primary, fontWeight: '700', fontSize: 14 },
  label: { fontSize: 13, color: colors.muted, marginBottom: space.xs, fontWeight: '600' },
  hint: { fontSize: 13, color: colors.muted, fontStyle: 'italic' },
  lineRow: { flexDirection: 'row', alignItems: 'center', padding: space.md },
  lineDesc: { fontSize: 15, fontWeight: '600', color: colors.text },
  lineMeta: { fontSize: 13, color: colors.muted, marginTop: 2 },
  lineTotal: { fontSize: 15, fontWeight: '700', color: colors.text },
  dispRow: { flexDirection: 'row', gap: space.sm, marginTop: space.sm },
  miniChip: {
    paddingHorizontal: space.sm,
    paddingVertical: 4,
    borderRadius: radius.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  miniChipOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  miniChipText: { fontSize: 12, color: colors.text, fontWeight: '600' },
  miniChipTextOn: { color: colors.primaryText },
  replRow: { padding: space.md },
  replTop: { flexDirection: 'row', alignItems: 'flex-start' },
  replSku: { fontSize: 15, fontWeight: '600', color: colors.text },
  replControls: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: space.sm,
  },
  remove: { fontSize: 16, color: colors.danger, paddingLeft: space.sm },
  segRow: { flexDirection: 'row', gap: space.sm },
  seg: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: space.sm,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  segOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  segText: { fontSize: 14, fontWeight: '600', color: colors.text },
  segTextOn: { color: colors.primaryText },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  chipOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { fontSize: 14, color: colors.text, fontWeight: '600' },
  chipTextOn: { color: colors.primaryText },
  toggleRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: radius.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  checkmark: { color: colors.primaryText, fontSize: 14, fontWeight: '800' },
  toggleLabel: { fontSize: 15, color: colors.text, flex: 1 },
  stepper: { flexDirection: 'row', alignItems: 'center' },
  stepBtn: {
    width: 32,
    height: 32,
    borderRadius: radius.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bg,
  },
  stepBtnText: { fontSize: 20, color: colors.text, lineHeight: 22 },
  stepQty: {
    minWidth: 32,
    textAlign: 'center',
    fontSize: 16,
    fontWeight: '700',
    color: colors.text,
  },
  priceBox: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    backgroundColor: colors.bg,
    paddingHorizontal: space.sm,
    minWidth: 100,
  },
  priceCurrency: { fontSize: 15, color: colors.muted },
  priceField: { flex: 1, paddingVertical: 6, paddingLeft: 2, fontSize: 16, color: colors.text },
  sumRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3 },
  sumLabel: { fontSize: 15, color: colors.muted },
  sumValue: { fontSize: 15, color: colors.text },
  sumStrong: { fontSize: 17, fontWeight: '800', color: colors.text },
  summaryDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginVertical: space.sm,
  },
  footer: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    padding: space.lg,
    backgroundColor: colors.card,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  modal: { flex: 1, backgroundColor: colors.bg },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: space.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
    backgroundColor: colors.card,
  },
  modalTitle: { fontSize: 18, fontWeight: '700', color: colors.text },
  modalClose: { fontSize: 16, color: colors.primary, fontWeight: '600' },
  skuRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: space.lg,
    backgroundColor: colors.card,
  },
});
