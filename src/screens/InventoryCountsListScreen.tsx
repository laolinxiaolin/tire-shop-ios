import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { AddRow, Empty, ErrorView, Loading, Row } from '../components/ui';
import { ApiError, inventoryCounts, InventoryCountStatus } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

const STATUSES: (InventoryCountStatus | 'ALL')[] = ['ALL', 'OPEN', 'POSTED', 'VOIDED'];

const STATUS_COLOR: Record<InventoryCountStatus, { bg: string; fg: string }> = {
  OPEN: { bg: '#fff8c5', fg: '#7d4e00' },
  POSTED: { bg: '#dafbe1', fg: '#1a7f37' },
  VOIDED: { bg: '#ffebe9', fg: '#cf222e' },
};

function StatusBadge({ label, status }: { label: string; status: InventoryCountStatus }) {
  const c = STATUS_COLOR[status];
  return (
    <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
      <Text style={[styles.statusText, { color: c.fg }]}>{label}</Text>
    </View>
  );
}

export default function InventoryCountsListScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const { t } = useI18n();
  const [status, setStatus] = useState<InventoryCountStatus | 'ALL'>('ALL');

  const query = useQuery({
    queryKey: ['inventory-counts', status],
    queryFn: () =>
      inventoryCounts.list({
        status: status === 'ALL' ? undefined : status,
        pageSize: 50,
      }),
  });

  function statusChipLabel(s: (typeof STATUSES)[number]) {
    return s === 'ALL' ? t('inventoryCount.all') : t(`inventoryCount.status.${s}`);
  }

  function scopeLabel(key: string): string {
    const map: Record<string, string> = {
      LT: t('tire.category.LT'),
      SEMI: t('tire.category.SEMI'),
      STEER: t('tire.position.STEER'),
      DRIVE: t('tire.position.DRIVE'),
      TRAILER: t('tire.position.TRAILER'),
      ALL_POSITION: t('tire.position.ALL_POSITION'),
    };
    return map[key] ?? key;
  }

  function scope(c: { scopeCategory: string | null; scopePosition: string | null }) {
    const parts = [c.scopeCategory, c.scopePosition].filter(Boolean) as string[];
    return parts.length
      ? parts.map((p) => scopeLabel(p)).join(' · ')
      : t('inventoryCount.allTires');
  }

  return (
    <View style={styles.screen}>
      <View style={styles.chipsWrap}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chips}
        >
          {STATUSES.map((s) => {
            const active = s === status;
            return (
              <Pressable
                key={s}
                onPress={() => setStatus(s)}
                style={[styles.chip, active ? styles.chipActive : null]}
              >
                <Text style={[styles.chipText, active ? styles.chipTextActive : null]}>
                  {statusChipLabel(s)}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>
      </View>
      {has('inventory.count.manage') ? (
        <AddRow
          label={t('inventoryCount.newCount')}
          onPress={() => nav.navigate('NewInventoryCount')}
        />
      ) : null}
      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          refreshing={query.isRefetching}
          onRefresh={query.refetch}
          keyExtractor={(c) => c.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('inventoryCount.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.ref} · ${scope(item)}`}
              subtitle={`${t('inventoryCount.linesCount', { n: item._count.lines })} · ${shortDate(item.createdAt)}${item.location ? ` · ${item.location}` : ''}`}
              onPress={() => nav.navigate('InventoryCountDetail', { id: item.id })}
              right={
                <View style={{ alignItems: 'flex-end' }}>
                  <Text
                    style={[
                      styles.variance,
                      Number(item.costVariance) < 0 ? styles.varianceNeg : null,
                    ]}
                  >
                    {money(item.costVariance)}
                  </Text>
                  <StatusBadge
                    label={t(`inventoryCount.status.${item.status}`)}
                    status={item.status}
                  />
                </View>
              }
            />
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  variance: { fontSize: 16, fontWeight: '700', color: colors.text, marginBottom: 4 },
  varianceNeg: { color: colors.danger },
  chipsWrap: { backgroundColor: colors.bg },
  chips: {
    paddingHorizontal: space.md,
    paddingTop: space.sm,
    paddingBottom: space.sm,
    gap: space.sm,
  },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: 6,
    borderRadius: radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  chipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { fontSize: 13, color: colors.muted, fontWeight: '600' },
  chipTextActive: { color: colors.primaryText },
  statusBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  statusText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
});
