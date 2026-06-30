import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useEffect, useLayoutEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { Button, Field, KeyboardAwareScrollView } from '../components/ui';
import {
  ApiError,
  inventory,
  SkuInput,
  tireAttributes,
  TireCategory,
  TirePosition,
  TireSku,
} from '../lib/api';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

/** Single-select pill row, used for category / position / segment. */
function ChipGroup({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (v: string) => void;
  disabled?: boolean;
}) {
  return (
    <View style={{ marginBottom: space.md }}>
      <Text style={styles.chipLabel}>{label}</Text>
      <View style={styles.chipRow}>
        {options.map((o) => {
          const on = o.value === value;
          return (
            <Pressable
              key={o.value || '__none'}
              onPress={() => onChange(o.value)}
              disabled={disabled}
              style={[styles.chip, on ? styles.chipOn : null, disabled ? { opacity: 0.5 } : null]}
            >
              <Text style={[styles.chipText, on ? styles.chipTextOn : null]}>{o.label}</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export default function SkuFormScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const edit = useRoute<RouteProp<RootStackParamList, 'SkuForm'>>().params?.sku;
  const isEdit = !!edit;
  const qc = useQueryClient();
  const { t } = useI18n();

  const [sku, setSku] = useState(edit?.sku ?? '');
  const [size, setSize] = useState(edit?.size ?? '');
  const [brand, setBrand] = useState(edit?.brand ?? '');
  const [model, setModel] = useState(edit?.model ?? '');
  const [category, setCategory] = useState<TireCategory>(edit?.category ?? '');
  const [position, setPosition] = useState<TirePosition>(edit?.position ?? '');
  const [segment, setSegment] = useState(edit?.segment ?? '');
  const [loadIndex, setLoadIndex] = useState(edit?.loadIndex ?? '');
  const [pattern, setPattern] = useState(edit?.pattern ?? '');
  const [treadDepth32, setTreadDepth32] = useState(
    edit?.treadDepth32 != null ? String(edit.treadDepth32) : '',
  );
  const [maxLoadSingleLb, setMaxLoadSingleLb] = useState(
    edit?.maxLoadSingleLb != null ? String(edit.maxLoadSingleLb) : '',
  );
  const [weightLb, setWeightLb] = useState(edit?.weightLb != null ? String(edit.weightLb) : '');
  const [plyRating, setPlyRating] = useState(edit?.plyRating ?? '');
  const [reorderPoint, setReorderPoint] = useState(edit ? String(edit.reorderPoint) : '');
  const [priceCost, setPriceCost] = useState(edit ? String(edit.priceCost) : '');
  const [priceRetail, setPriceRetail] = useState(edit ? String(edit.priceRetail) : '');
  const [active, setActive] = useState(edit?.active ?? true);

  // Admin-managed category / position / segment options.
  const { data: attrs } = useQuery({
    queryKey: ['tire-attributes'],
    queryFn: () => tireAttributes.list(),
  });
  const activeOpts = (kind: 'CATEGORY' | 'POSITION' | 'SEGMENT') =>
    (attrs ?? [])
      .filter((a) => a.kind === kind && a.active)
      .map((a) => ({ value: a.value, label: a.label }));

  // Default category / position to the first configured option once loaded.
  useEffect(() => {
    if (!attrs) return;
    setCategory((c) => c || activeOpts('CATEGORY')[0]?.value || '');
    setPosition((p) => p || activeOpts('POSITION')[0]?.value || '');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [attrs]);

  useLayoutEffect(() => {
    nav.setOptions({ title: isEdit ? t('screen.editTire') : t('screen.newTire') });
  }, [nav, isEdit, t]);

  const valid =
    sku.trim() &&
    size.trim() &&
    brand.trim() &&
    model.trim() &&
    category &&
    position &&
    priceRetail.trim();

  const save = useMutation({
    mutationFn: async () => {
      const opt = (v: string) => (v.trim() ? v.trim() : undefined);
      const numOpt = (v: string) => (v.trim() ? Number(v) : undefined);
      const body: SkuInput = {
        sku: sku.trim(),
        brand: brand.trim(),
        model: model.trim(),
        size: size.trim(),
        category,
        position,
        segment: opt(segment),
        loadIndex: opt(loadIndex),
        pattern: opt(pattern),
        treadDepth32: numOpt(treadDepth32),
        maxLoadSingleLb: numOpt(maxLoadSingleLb),
        weightLb: numOpt(weightLb),
        plyRating: opt(plyRating),
        priceCost: priceCost.trim() ? Number(priceCost) : undefined,
        priceRetail: Number(priceRetail),
        reorderPoint: reorderPoint.trim() ? Number(reorderPoint) : undefined,
      };
      if (isEdit && edit) {
        const updated = await inventory.updateSku(edit.id, { ...body, active });
        // The API returns the SKU without its inventory rows; carry the ones we
        // already have so the detail/list stay complete.
        return { ...updated, inventory: edit.inventory } as TireSku;
      }
      const created = await inventory.createSku(body);
      return { ...created, inventory: [] } as TireSku;
    },
    onSuccess: (saved) => {
      qc.setQueryData(['sku', saved.id], saved);
      qc.invalidateQueries({ queryKey: ['skus'] });
      if (isEdit) {
        nav.goBack();
      } else {
        // Replace the modal with the new tire's detail.
        nav.goBack();
        nav.navigate('SkuDetail', { sku: saved });
      }
    },
    onError: (e) =>
      // A duplicate SKU code is the most common failure — surface the server message.
      Alert.alert(
        isEdit ? t('sku.saveFailedEdit') : t('sku.createFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  return (
    <KeyboardAwareScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg, paddingBottom: space.xl }}
    >
      <Field
        label={t('sku.fieldSku')}
        value={sku}
        onChangeText={setSku}
        autoCapitalize="characters"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.fieldSize')}
        value={size}
        onChangeText={setSize}
        placeholder="e.g. 11R22.5"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.fieldBrand')}
        value={brand}
        onChangeText={setBrand}
        autoCapitalize="words"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.fieldModel')}
        value={model}
        onChangeText={setModel}
        editable={!save.isPending}
      />

      <ChipGroup
        label={t('sku.category')}
        value={category}
        options={activeOpts('CATEGORY')}
        onChange={setCategory}
        disabled={save.isPending}
      />
      <ChipGroup
        label={t('sku.position')}
        value={position}
        options={activeOpts('POSITION')}
        onChange={setPosition}
        disabled={save.isPending}
      />
      <ChipGroup
        label={t('sku.segment')}
        value={segment}
        options={[{ value: '', label: t('sku.segmentNone') }, ...activeOpts('SEGMENT')]}
        onChange={setSegment}
        disabled={save.isPending}
      />

      <Field
        label={t('sku.loadIndex')}
        value={loadIndex}
        onChangeText={setLoadIndex}
        editable={!save.isPending}
      />
      <Field
        label={t('sku.pattern')}
        value={pattern}
        onChangeText={setPattern}
        editable={!save.isPending}
      />
      <Field
        label={t('sku.treadDepth')}
        value={treadDepth32}
        onChangeText={setTreadDepth32}
        keyboardType="decimal-pad"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.maxLoad')}
        value={maxLoadSingleLb}
        onChangeText={setMaxLoadSingleLb}
        keyboardType="number-pad"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.weight')}
        value={weightLb}
        onChangeText={setWeightLb}
        keyboardType="decimal-pad"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.plyRating')}
        value={plyRating}
        onChangeText={setPlyRating}
        editable={!save.isPending}
      />
      <Field
        label={t('sku.reorderPoint')}
        value={reorderPoint}
        onChangeText={setReorderPoint}
        keyboardType="number-pad"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.fieldCost')}
        value={priceCost}
        onChangeText={setPriceCost}
        keyboardType="decimal-pad"
        placeholder="0.00"
        editable={!save.isPending}
      />
      <Field
        label={t('sku.fieldRetail')}
        value={priceRetail}
        onChangeText={setPriceRetail}
        keyboardType="decimal-pad"
        placeholder="0.00"
        editable={!save.isPending}
      />

      {isEdit ? (
        <View style={styles.switchRow}>
          <View style={{ flex: 1, paddingRight: space.md }}>
            <Text style={styles.switchLabel}>{t('sku.active')}</Text>
            <Text style={styles.switchHint}>{t('sku.activeHint')}</Text>
          </View>
          <Switch value={active} onValueChange={setActive} disabled={save.isPending} />
        </View>
      ) : null}

      <View style={{ marginTop: space.lg }}>
        <Button
          title={isEdit ? t('sku.saveChanges') : t('sku.createTire')}
          onPress={() => save.mutate()}
          loading={save.isPending}
          disabled={!valid}
        />
      </View>
    </KeyboardAwareScrollView>
  );
}

const styles = StyleSheet.create({
  chipLabel: { fontSize: 13, color: colors.muted, marginBottom: space.xs, fontWeight: '600' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
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
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.md,
    marginTop: space.md,
  },
  switchLabel: { fontSize: 15, fontWeight: '600', color: colors.text },
  switchHint: { fontSize: 12, color: colors.muted, marginTop: 2 },
});
