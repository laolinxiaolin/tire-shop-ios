import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, Field, KeyboardAwareScrollView } from '../components/ui';
import { ApiError, inventory, isApprovalResult, StockAdjustReason, TireSku } from '../lib/api';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { onHand } from './InventoryListScreen';
import { colors, radius, space } from '../theme';

const REASONS: { value: StockAdjustReason; labelKey: string }[] = [
  { value: 'PURCHASE', labelKey: 'adjust.reason.PURCHASE' },
  { value: 'ADJUSTMENT', labelKey: 'adjust.reason.ADJUSTMENT' },
  { value: 'RETURN', labelKey: 'adjust.reason.RETURN' },
];

export default function AdjustStockScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { sku } = useRoute<RouteProp<RootStackParamList, 'AdjustStock'>>().params;
  const qc = useQueryClient();
  const { t } = useI18n();

  const [sign, setSign] = useState<1 | -1>(1);
  const [magnitude, setMagnitude] = useState('');
  const [reason, setReason] = useState<StockAdjustReason>('PURCHASE');
  const [note, setNote] = useState('');

  const current = onHand(sku);
  const n = Number(magnitude);
  const delta = magnitude.trim() && Number.isFinite(n) ? sign * Math.abs(Math.trunc(n)) : 0;
  const resulting = current + delta;
  const valid = delta !== 0 && resulting >= 0;

  const apply = useMutation({
    mutationFn: () => inventory.adjust(sku.id, { delta, reason, note: note.trim() || undefined }),
    onSuccess: (res) => {
      if (isApprovalResult(res)) {
        qc.invalidateQueries({ queryKey: ['approvals'] });
        Alert.alert(t('adjust.submittedForApproval'), t('adjust.approvalBody'), [
          { text: t('common.ok'), onPress: () => nav.goBack() },
        ]);
        return;
      }
      // Merge the returned location row back into the SKU we hold so the detail
      // (keyed ['sku', id]) and list both reflect the new quantity.
      const others = sku.inventory.filter((i) => i.location !== res.location);
      const merged: TireSku = {
        ...sku,
        inventory: [
          ...others,
          {
            id: res.id,
            location: res.location,
            qtyOnHand: res.qtyOnHand,
            qtyReserved: res.qtyReserved,
          },
        ],
      };
      qc.setQueryData(['sku', sku.id], merged);
      qc.invalidateQueries({ queryKey: ['skus'] });
      nav.goBack();
    },
    onError: (e) =>
      Alert.alert(
        t('adjust.couldNotAdjust'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  return (
    <KeyboardAwareScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg }}
    >
      <Text style={styles.title}>{`${sku.size} · ${sku.brand}`}</Text>
      <Text style={styles.subtitle}>{sku.sku}</Text>

      <View style={styles.summary}>
        <Summary label={t('adjust.onHand')} value={String(current)} />
        <Summary
          label={t('adjust.change')}
          value={delta > 0 ? `+${delta}` : String(delta)}
          tint={delta < 0 ? colors.danger : colors.success}
        />
        <Summary
          label={t('adjust.resulting')}
          value={String(resulting)}
          tint={resulting < 0 ? colors.danger : colors.text}
        />
      </View>

      <View style={styles.signRow}>
        {(
          [
            [1, t('adjust.add')],
            [-1, t('adjust.remove')],
          ] as const
        ).map(([s, label]) => {
          const on = sign === s;
          return (
            <Pressable
              key={s}
              onPress={() => setSign(s)}
              disabled={apply.isPending}
              style={[styles.signBtn, on ? styles.signBtnOn : null]}
            >
              <Text style={[styles.signText, on ? styles.signTextOn : null]}>{label}</Text>
            </Pressable>
          );
        })}
      </View>

      <Field
        label={t('adjust.quantity')}
        value={magnitude}
        onChangeText={setMagnitude}
        keyboardType="number-pad"
        placeholder="0"
        editable={!apply.isPending}
      />

      <Text style={styles.chipLabel}>{t('adjust.reasonLabel')}</Text>
      <View style={styles.chipRow}>
        {REASONS.map((r) => {
          const on = r.value === reason;
          return (
            <Pressable
              key={r.value}
              onPress={() => setReason(r.value)}
              disabled={apply.isPending}
              style={[styles.chip, on ? styles.chipOn : null]}
            >
              <Text style={[styles.chipText, on ? styles.chipTextOn : null]}>{t(r.labelKey)}</Text>
            </Pressable>
          );
        })}
      </View>

      <Field
        label={t('adjust.note')}
        value={note}
        onChangeText={setNote}
        placeholder={t('adjust.notePlaceholder')}
        editable={!apply.isPending}
      />

      <View style={{ marginTop: space.lg }}>
        <Button
          title={t('adjust.apply')}
          onPress={() => apply.mutate()}
          loading={apply.isPending}
          disabled={!valid}
        />
        {resulting < 0 ? <Text style={styles.warn}>{t('adjust.warnTooMuch')}</Text> : null}
      </View>
    </KeyboardAwareScrollView>
  );
}

function Summary({ label, value, tint }: { label: string; value: string; tint?: string }) {
  return (
    <View style={styles.summaryCell}>
      <Text style={[styles.summaryValue, tint ? { color: tint } : null]}>{value}</Text>
      <Text style={styles.summaryLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  title: { fontSize: 20, fontWeight: '800', color: colors.text },
  subtitle: { fontSize: 14, color: colors.muted, marginTop: 2 },
  summary: {
    flexDirection: 'row',
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.md,
    marginTop: space.lg,
    marginBottom: space.lg,
  },
  summaryCell: { flex: 1, alignItems: 'center' },
  summaryValue: { fontSize: 22, fontWeight: '800', color: colors.text },
  summaryLabel: { fontSize: 12, color: colors.muted, marginTop: 2 },
  signRow: { flexDirection: 'row', gap: space.sm, marginBottom: space.md },
  signBtn: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: space.md,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  signBtnOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  signText: { fontSize: 15, fontWeight: '700', color: colors.text },
  signTextOn: { color: colors.primaryText },
  chipLabel: { fontSize: 13, color: colors.muted, marginBottom: space.xs, fontWeight: '600' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm, marginBottom: space.md },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  chipOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { color: colors.text, fontSize: 14, fontWeight: '600' },
  chipTextOn: { color: colors.primaryText },
  warn: { color: colors.danger, fontSize: 13, marginTop: space.sm, textAlign: 'center' },
});
