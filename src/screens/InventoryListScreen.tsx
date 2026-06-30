import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useMemo, useState } from 'react';
import { FlatList, StyleSheet, Switch, Text, View } from 'react-native';
import { CATEGORY_FILTERS, FilterChips, POSITION_FILTERS } from '../components/TireFilters';
import { Badge, Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import { ApiError, inventory, TireCategory, TirePosition, TireSku } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { useDebounced } from '../lib/hooks';
import type { RootStackParamList } from '../navigation/types';
import { colors, space } from '../theme';

export function onHand(sku: TireSku): number {
  return sku.inventory.reduce((s, i) => s + i.qtyOnHand, 0);
}

export default function InventoryListScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { t } = useI18n();

  const [q, setQ] = useState('');
  const [category, setCategory] = useState<TireCategory | ''>('');
  const [position, setPosition] = useState<TirePosition | ''>('');
  const [hideZero, setHideZero] = useState(false);
  const debounced = useDebounced(q);

  const query = useQuery({
    queryKey: ['skus', debounced, category, position],
    queryFn: () =>
      inventory.listSkus({
        q: debounced || undefined,
        category: category || undefined,
        position: position || undefined,
        pageSize: 50,
      }),
  });

  const items = useMemo(() => {
    const list = query.data?.items ?? [];
    return hideZero ? list.filter((s) => onHand(s) > 0) : list;
  }, [query.data, hideZero]);

  const openSku = (item: TireSku) => {
    // Seed the detail's cache with this fresh row so it shows current data even
    // if a stale entry lingered from a previous visit.
    qc.setQueryData(['sku', item.id], item);
    nav.navigate('SkuDetail', { sku: item });
  };

  return (
    <View style={styles.screen}>
      <SearchBar value={q} onChangeText={setQ} placeholder={t('inventory.search')} />
      <FilterChips value={category} options={CATEGORY_FILTERS} onChange={setCategory} />
      <FilterChips value={position} options={POSITION_FILTERS} onChange={setPosition} />
      <View style={styles.toolbar}>
        <View style={styles.hideZeroRight}>
          <Text style={styles.hideZeroLabel}>{t('inventory.hideOutOfStock')}</Text>
          <Switch value={hideZero} onValueChange={setHideZero} />
        </View>
      </View>

      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={items}
          style={{ flex: 1 }}
          refreshing={query.isRefetching}
          onRefresh={query.refetch}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={Sep}
          ListEmptyComponent={<Empty message={t('inventory.empty')} />}
          renderItem={({ item }) => {
            const stock = onHand(item);
            const low = stock <= item.reorderPoint && item.reorderPoint > 0;
            return (
              <Row
                title={`${item.size} · ${item.brand}`}
                subtitle={`${item.sku} · ${item.position} · ${item.category}`}
                onPress={() => openSku(item)}
                right={
                  <View style={{ alignItems: 'flex-end' }}>
                    <Text style={[styles.qty, low ? { color: colors.danger } : null]}>{stock}</Text>
                    <Text style={styles.qtyLabel}>{t('inventory.onHand')}</Text>
                    {low ? <Badge label="LOW" text={t('inventory.low')} /> : null}
                  </View>
                }
              />
            );
          }}
        />
      )}
    </View>
  );
}

function Sep() {
  return <View style={styles.sep} />;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  qty: { fontSize: 18, fontWeight: '700', color: colors.text },
  qtyLabel: { fontSize: 11, color: colors.muted },
  toolbar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    paddingHorizontal: space.lg,
    paddingBottom: space.sm,
  },
  hideZeroRight: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  hideZeroLabel: { fontSize: 14, color: colors.muted },
});
