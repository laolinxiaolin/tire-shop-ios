import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, Field, KeyboardAwareScrollView } from '../components/ui';
import { ApiError, inventoryCounts, TireCategory, TirePosition } from '../lib/api';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const CATEGORY_OPTIONS: { value: TireCategory | ''; labelKey: string }[] = [
  { value: '', labelKey: 'inventoryCount.all' },
  { value: 'LT', labelKey: 'tire.category.LT' },
  { value: 'SEMI', labelKey: 'tire.category.SEMI' },
];

const POSITION_OPTIONS: { value: TirePosition | ''; labelKey: string }[] = [
  { value: '', labelKey: 'inventoryCount.all' },
  { value: 'STEER', labelKey: 'tire.position.STEER' },
  { value: 'DRIVE', labelKey: 'tire.position.DRIVE' },
  { value: 'TRAILER', labelKey: 'tire.position.TRAILER' },
  { value: 'ALL_POSITION', labelKey: 'tire.position.ALL_POSITION' },
];

export default function NewInventoryCountScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { t } = useI18n();

  const [category, setCategory] = useState<TireCategory | ''>('');
  const [position, setPosition] = useState<TirePosition | ''>('');
  const [location, setLocation] = useState('MAIN');
  const [notes, setNotes] = useState('');

  const categories = CATEGORY_OPTIONS.map((o) => ({ value: o.value, label: t(o.labelKey) }));
  const positions = POSITION_OPTIONS.map((o) => ({ value: o.value, label: t(o.labelKey) }));

  const create = useMutation({
    mutationFn: () =>
      inventoryCounts.create({
        scopeCategory: category || undefined,
        scopePosition: position || undefined,
        location: location.trim() || undefined,
        notes: notes.trim() || undefined,
      }),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['inventory-counts'] });
      // Replace this modal with the new count's detail so Back returns to the list.
      nav.replace('InventoryCountDetail', { id: res.id });
    },
    onError: (e) =>
      Alert.alert(
        t('inventoryCount.couldNotStart'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  return (
    <KeyboardAwareScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg }}
    >
      <Text style={styles.help}>{t('inventoryCount.help')}</Text>

      <Text style={styles.label}>{t('inventoryCount.category')}</Text>
      <Chips
        options={categories}
        value={category}
        onChange={setCategory}
        disabled={create.isPending}
      />

      <Text style={styles.label}>{t('inventoryCount.position')}</Text>
      <Chips
        options={positions}
        value={position}
        onChange={setPosition}
        disabled={create.isPending}
      />

      <Field
        label={t('inventoryCount.location')}
        value={location}
        onChangeText={setLocation}
        placeholder="MAIN"
        autoCapitalize="characters"
        editable={!create.isPending}
      />

      <Field
        label="Notes"
        value={notes}
        onChangeText={setNotes}
        placeholder="Optional"
        multiline
        editable={!create.isPending}
      />

      <View style={{ marginTop: space.md }}>
        <Button
          title={t('inventoryCount.startCount')}
          onPress={() => create.mutate()}
          loading={create.isPending}
        />
      </View>
    </KeyboardAwareScrollView>
  );
}

function Chips<T extends string>({
  options,
  value,
  onChange,
  disabled,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  disabled?: boolean;
}) {
  return (
    <View style={styles.chipRow}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable
            key={o.value || 'all'}
            onPress={() => onChange(o.value)}
            disabled={disabled}
            style={[styles.chip, on ? styles.chipOn : null]}
          >
            <Text style={[styles.chipText, on ? styles.chipTextOn : null]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  help: { fontSize: 13, color: colors.muted, marginBottom: space.lg, lineHeight: 18 },
  label: { fontSize: 13, color: colors.muted, marginBottom: space.xs, fontWeight: '600' },
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
});
