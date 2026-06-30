import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  Alert,
  FlatList,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Button, Card, Divider, Empty, KeyboardAvoider } from '../components/ui';
import { ApiError, sales, services as servicesApi } from '../lib/api';
import { money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { useQuote } from '../state/quote';
import { colors, radius, space } from '../theme';

/** `embeddedInStack` is set when the builder is reused by EditSaleScreen as a
 * full-height stack screen (no bottom tab bar beneath it), so the action footer
 * must clear the Android navigation bar itself. As a pinned tab the tab bar
 * already occupies the safe area, so no extra inset is added there. */
export default function NewQuoteScreen({
  embeddedInStack = false,
}: {
  embeddedInStack?: boolean;
} = {}) {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { has } = useAuth();
  const quote = useQuote();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const [serviceModal, setServiceModal] = useState(false);

  const canQuote = has('sales.manage');
  // When set, the builder is editing an existing draft (PATCH + stay a draft)
  // rather than creating and confirming a new sale.
  const editingId = quote.editingSaleId;

  const submit = useMutation({
    mutationFn: async () => {
      if (!quote.customer) throw new ApiError(0, t('newQuote.pickCustomerFirst'));
      const body = {
        customerId: quote.customer.id,
        // API expects a fraction (0.07); a tax-exempt customer is always 0.
        taxRate: quote.customer.taxExempt ? 0 : quote.taxRate / 100,
        lines: quote.lines.map((l) => ({
          itemType: l.itemType,
          itemId: l.itemId,
          description: l.description,
          qty: l.qty,
          unitPrice: l.unitPrice,
          discount: l.discount,
        })),
      };
      if (editingId) {
        await sales.update(editingId, body);
        return { id: editingId, edited: true };
      }
      const sale = await sales.create(body);
      await sales.confirm(sale.id);
      return { id: sale.id, edited: false };
    },
    onSuccess: ({ id, edited }) => {
      qc.invalidateQueries({ queryKey: ['sales'] });
      qc.invalidateQueries({ queryKey: ['sale', id] });
      if (edited) {
        // EditSaleScreen clears the shared cart on unmount; just return to the
        // sale, which refetches with the saved changes.
        nav.goBack();
      } else {
        quote.clear();
        nav.navigate('SaleDetail', { id });
      }
    },
    onError: (e) =>
      Alert.alert(
        editingId ? t('newQuote.couldNotSave') : t('newQuote.couldNotCreate'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  if (!canQuote) {
    return <Empty message={t('newQuote.noPermission')} />;
  }

  const canSubmit = !!quote.customer && quote.lines.length > 0 && !submit.isPending;

  return (
    <KeyboardAvoider style={{ flex: 1, backgroundColor: colors.bg }}>
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{
          padding: space.lg,
          paddingBottom: 120 + (embeddedInStack ? insets.bottom : 0),
        }}
      >
        {/* Customer */}
        <Text style={styles.sectionLabel}>{t('newQuote.customer')}</Text>
        <Pressable onPress={() => nav.navigate('CustomerPicker')}>
          <Card style={{ marginTop: space.sm }}>
            {quote.customer ? (
              <View style={styles.rowBetween}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.customerName}>{quote.customer.name}</Text>
                  {quote.customer.company ? (
                    <Text style={styles.muted}>{quote.customer.company}</Text>
                  ) : null}
                  {quote.customer.taxExempt ? (
                    <Text style={styles.exempt}>{t('newQuote.taxExempt')}</Text>
                  ) : null}
                </View>
                <Text style={styles.change}>{t('newQuote.change')}</Text>
              </View>
            ) : (
              <Text style={styles.placeholder}>{t('newQuote.selectCustomer')}</Text>
            )}
          </Card>
        </Pressable>

        {/* Lines */}
        <Text style={[styles.sectionLabel, { marginTop: space.lg }]}>{t('newQuote.items')}</Text>
        <Card style={{ marginTop: space.sm, padding: 0 }}>
          {quote.lines.length === 0 ? (
            <Text style={styles.placeholder}>{t('newQuote.noItems')}</Text>
          ) : (
            quote.lines.map((l, idx) => {
              const lineTotal = l.unitPrice * l.qty - (l.discount ?? 0);
              const customized = l.unitPrice !== l.listPrice;
              return (
                <View key={l.key}>
                  {idx > 0 ? <Divider /> : null}
                  <View style={styles.line}>
                    <View style={styles.lineTop}>
                      <Text style={styles.lineDesc} numberOfLines={2}>
                        {l.description}
                        {l.itemType === 'SERVICE' ? t('newQuote.serviceSuffix') : ''}
                      </Text>
                      <Pressable onPress={() => quote.removeLine(l.key)} hitSlop={8}>
                        <Text style={styles.remove}>✕</Text>
                      </Pressable>
                    </View>
                    <View style={styles.lineControls}>
                      <View>
                        <PriceInput
                          value={l.unitPrice}
                          onChange={(n) => quote.updatePrice(l.key, n)}
                        />
                        {customized ? (
                          <Pressable
                            onPress={() => quote.updatePrice(l.key, l.listPrice)}
                            hitSlop={6}
                          >
                            <Text style={styles.listHint}>
                              {t('newQuote.listReset', { price: money(l.listPrice) })}
                            </Text>
                          </Pressable>
                        ) : (
                          <Text style={styles.eaHint}>{t('newQuote.each')}</Text>
                        )}
                      </View>
                      <View style={styles.stepper}>
                        <Stepper label="−" onPress={() => quote.updateQty(l.key, l.qty - 1)} />
                        <Text style={styles.qty}>{l.qty}</Text>
                        <Stepper label="+" onPress={() => quote.updateQty(l.key, l.qty + 1)} />
                      </View>
                      <Text style={styles.lineTotal}>{money(lineTotal)}</Text>
                    </View>
                  </View>
                </View>
              );
            })
          )}
        </Card>

        <View style={styles.addRow}>
          <View style={{ flex: 1 }}>
            <Button
              title={t('newQuote.addTire')}
              variant="secondary"
              onPress={() => nav.navigate('SkuPicker')}
            />
          </View>
          <View style={{ width: space.md }} />
          <View style={{ flex: 1 }}>
            <Button
              title={t('newQuote.addService')}
              variant="secondary"
              onPress={() => setServiceModal(true)}
            />
          </View>
        </View>

        {/* Totals */}
        <Card style={{ marginTop: space.lg }}>
          <Total label={t('newQuote.subtotal')} value={money(quote.subtotal)} />
          {quote.customer?.taxExempt ? (
            <Total label={t('newQuote.taxExemptParen')} value={money(quote.taxAmount)} />
          ) : (
            <TaxRateRow
              pct={quote.taxRate}
              onChange={quote.setTaxRate}
              amount={money(quote.taxAmount)}
            />
          )}
          <Total label={t('newQuote.total')} value={money(quote.total)} strong />
          {quote.lines.length > 0 && (
            <RoundTotalRow current={quote.total} onApply={quote.roundTotal} />
          )}
        </Card>
      </ScrollView>

      <View
        style={[styles.footer, { paddingBottom: space.lg + (embeddedInStack ? insets.bottom : 0) }]}
      >
        <Button
          title={
            submit.isPending
              ? editingId
                ? t('common.saving')
                : t('newQuote.confirming')
              : editingId
                ? t('newQuote.saveChanges')
                : t('newQuote.confirmInvoice')
          }
          onPress={() => submit.mutate()}
          loading={submit.isPending}
          disabled={!canSubmit}
        />
      </View>

      <ServicePickerModal visible={serviceModal} onClose={() => setServiceModal(false)} />
    </KeyboardAvoider>
  );
}

function Stepper({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={styles.stepBtn} hitSlop={6}>
      <Text style={styles.stepBtnText}>{label}</Text>
    </Pressable>
  );
}

/** Editable unit price. Keeps its own text state so intermediate input like
 * "12." is allowed; commits the parsed number on every change and tidies the
 * display to 2dp on blur. */
function PriceInput({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const [text, setText] = useState(value.toFixed(2));
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

function Total({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <View style={styles.totalRow}>
      <Text style={[styles.totalLabel, strong ? styles.strong : null]}>{label}</Text>
      <Text style={[styles.totalValue, strong ? styles.strong : null]}>{value}</Text>
    </View>
  );
}

/** Round the order to a whole amount the customer pays (up or down). Entering a
 * target total and tapping Apply back-solves the unit prices via the cart's
 * `roundTotal`, so the difference rides along as a discount. */
function RoundTotalRow({
  current,
  onApply,
}: {
  current: number;
  onApply: (target: number) => void;
}) {
  const { t } = useI18n();
  const [text, setText] = useState('');
  const apply = () => {
    const n = Number(text);
    if (Number.isFinite(n) && n > 0) {
      onApply(n);
      setText('');
    }
  };
  return (
    <>
      <View
        style={[
          styles.totalRow,
          {
            borderTopWidth: StyleSheet.hairlineWidth,
            borderTopColor: colors.border,
            paddingTop: 8,
            marginTop: 4,
          },
        ]}
      >
        <View style={styles.taxLabelWrap}>
          <Text style={styles.totalLabel}>{t('newQuote.roundTotal')}</Text>
          <TextInput
            style={styles.taxInput}
            value={text}
            placeholder={current.toFixed(2)}
            placeholderTextColor={colors.muted}
            onChangeText={(v) => setText(v.replace(/[^0-9.]/g, ''))}
            keyboardType="decimal-pad"
            returnKeyType="done"
            selectTextOnFocus
            onSubmitEditing={apply}
            accessibilityLabel={t('newQuote.roundTotal')}
          />
        </View>
        <Pressable onPress={apply} disabled={!text} style={styles.roundBtn} hitSlop={6}>
          <Text style={[styles.roundBtnText, !text ? styles.roundBtnDisabled : null]}>
            {t('newQuote.roundApply')}
          </Text>
        </Pressable>
      </View>
      <Text style={styles.roundHint}>{t('newQuote.roundHint')}</Text>
    </>
  );
}

/** Editable sales-tax-rate row. Keeps its own text state so partial input like
 * "8." is allowed, committing the parsed percent (clamped to 0–100) on change. */
function TaxRateRow({
  pct,
  onChange,
  amount,
}: {
  pct: number;
  onChange: (pct: number) => void;
  amount: string;
}) {
  const { t } = useI18n();
  const [text, setText] = useState(String(pct));

  // Reflect external changes (seeding a draft, store default loading) unless the
  // field already holds the same numeric value the user is mid-typing.
  React.useEffect(() => {
    if (Number(text) !== pct) setText(String(pct));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pct]);

  return (
    <View style={styles.totalRow}>
      <View style={styles.taxLabelWrap}>
        <Text style={styles.totalLabel}>{t('newQuote.taxRateLabel')}</Text>
        <TextInput
          style={styles.taxInput}
          value={text}
          onChangeText={(v) => {
            setText(v);
            const n = Number(v);
            if (Number.isFinite(n) && n >= 0 && n <= 100) onChange(n);
          }}
          keyboardType="decimal-pad"
          returnKeyType="done"
          selectTextOnFocus
          accessibilityLabel={t('newQuote.taxRateLabel')}
        />
        <Text style={styles.totalLabel}>%</Text>
      </View>
      <Text style={styles.totalValue}>{amount}</Text>
    </View>
  );
}

function ServicePickerModal({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const quote = useQuote();
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['services'],
    queryFn: () => servicesApi.list(),
    enabled: visible,
  });

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View style={styles.modal}>
        <View style={styles.modalHeader}>
          <Text style={styles.modalTitle}>{t('newQuote.addServiceTitle')}</Text>
          <Pressable onPress={onClose} hitSlop={8}>
            <Text style={styles.modalClose}>{t('common.done')}</Text>
          </Pressable>
        </View>
        <FlatList
          data={query.data ?? []}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={() => <Divider />}
          ListEmptyComponent={
            <Empty message={query.isLoading ? t('common.loading') : t('newQuote.noServices')} />
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.serviceRow}
              onPress={() => {
                quote.addLine({
                  itemType: 'SERVICE',
                  itemId: item.id,
                  description: item.name,
                  qty: 1,
                  unitPrice: Number(item.price),
                });
                onClose();
              }}
            >
              <Text style={styles.lineDesc}>{item.name}</Text>
              <Text style={styles.muted}>{money(item.price)}</Text>
            </Pressable>
          )}
        />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  sectionLabel: {
    fontSize: 12,
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
  },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  customerName: { fontSize: 17, fontWeight: '700', color: colors.text },
  muted: { fontSize: 13, color: colors.muted, marginTop: 2 },
  exempt: { fontSize: 12, color: colors.warnText, marginTop: 2, fontWeight: '600' },
  change: { color: colors.primary, fontWeight: '600' },
  placeholder: { color: colors.muted, padding: space.md },
  line: { padding: space.md },
  lineTop: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' },
  lineDesc: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
    flex: 1,
    paddingRight: space.sm,
  },
  lineControls: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: space.sm,
  },
  lineTotal: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.text,
    minWidth: 72,
    textAlign: 'right',
  },
  listHint: { fontSize: 11, color: colors.primary, marginTop: 2 },
  eaHint: { fontSize: 11, color: colors.muted, marginTop: 2 },
  priceBox: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    backgroundColor: colors.bg,
    paddingHorizontal: space.sm,
    minWidth: 90,
  },
  priceCurrency: { fontSize: 15, color: colors.muted },
  priceField: { flex: 1, paddingVertical: 6, paddingLeft: 2, fontSize: 16, color: colors.text },
  stepper: { flexDirection: 'row', alignItems: 'center', marginHorizontal: space.sm },
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
  qty: { minWidth: 28, textAlign: 'center', fontSize: 16, fontWeight: '700', color: colors.text },
  remove: { fontSize: 16, color: colors.danger, paddingLeft: space.sm },
  addRow: { flexDirection: 'row', marginTop: space.md },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3 },
  totalLabel: { fontSize: 15, color: colors.muted },
  totalValue: { fontSize: 15, color: colors.text },
  taxLabelWrap: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  taxInput: {
    minWidth: 56,
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    fontSize: 15,
    color: colors.text,
    textAlign: 'right',
    backgroundColor: colors.bg,
  },
  strong: { fontSize: 18, fontWeight: '800', color: colors.text },
  roundBtn: {
    paddingVertical: 4,
    paddingHorizontal: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    backgroundColor: colors.bg,
  },
  roundBtnText: { fontSize: 15, fontWeight: '600', color: colors.text },
  roundBtnDisabled: { color: colors.muted },
  roundHint: { fontSize: 12, color: colors.muted, marginTop: 4 },
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
  footerRow: { flexDirection: 'row', marginTop: space.sm },
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
  serviceRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: space.lg,
    backgroundColor: colors.card,
  },
});
