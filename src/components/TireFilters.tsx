import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text } from 'react-native';
import type { TireCategory, TirePosition } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

// `labelKey` resolves through `t()`; '' is the "All" option, common to both.
export const CATEGORY_FILTERS: { value: TireCategory | ''; labelKey: string }[] = [
  { value: '', labelKey: 'status.ALL' },
  { value: 'SEMI', labelKey: 'tire.category.SEMI' },
  { value: 'LT', labelKey: 'tire.category.LT' },
];

export const POSITION_FILTERS: { value: TirePosition | ''; labelKey: string }[] = [
  { value: '', labelKey: 'status.ALL' },
  { value: 'STEER', labelKey: 'tire.position.STEER' },
  { value: 'DRIVE', labelKey: 'tire.position.DRIVE' },
  { value: 'TRAILER', labelKey: 'tire.position.TRAILER' },
  { value: 'ALL_POSITION', labelKey: 'tire.position.ALL_POSITION' },
];

/** Horizontal, single-select pill row used for the category/position filters.
 * Option labels are translation keys, resolved here. */
export function FilterChips<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { value: T; labelKey: string }[];
  onChange: (v: T) => void;
}) {
  const { t } = useI18n();
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      // Without flexGrow:0 a horizontal ScrollView stretches to fill the column's
      // leftover vertical space (and grows further on re-render after a tap).
      style={styles.scroll}
      contentContainerStyle={styles.row}
    >
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable
            key={o.value || 'all'}
            onPress={() => onChange(o.value)}
            style={[styles.chip, on ? styles.chipOn : null]}
          >
            <Text style={[styles.chipText, on ? styles.chipTextOn : null]}>{t(o.labelKey)}</Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flexGrow: 0, flexShrink: 0 },
  row: { paddingHorizontal: space.lg, paddingVertical: space.xs, gap: space.sm },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: 6,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  chipOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { color: colors.text, fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: colors.primaryText },
});
