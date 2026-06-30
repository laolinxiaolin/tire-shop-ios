import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import { ApiError, inventory } from '../lib/api';
import { money } from '../lib/format';
import { useDebounced } from '../lib/hooks';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useQuote } from '../state/quote';
import { colors, space } from '../theme';
import { onHand } from './InventoryListScreen';

export default function SkuPickerScreen() {
  const { t } = useI18n();
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const quote = useQuote();
  const [q, setQ] = useState('');
  const debounced = useDebounced(q);

  const query = useQuery({
    queryKey: ['skus', 'picker', debounced],
    queryFn: () => inventory.listSkus({ q: debounced || undefined, pageSize: 50 }),
  });

  return (
    <View style={styles.screen}>
      <SearchBar value={q} onChangeText={setQ} placeholder={t('skuPicker.search')} autoFocus />
      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('skuPicker.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.size} · ${item.brand} ${item.model}`}
              subtitle={`${item.sku} · ${t('skuPicker.onHand', { n: onHand(item) })}`}
              onPress={() => {
                quote.addLine({
                  itemType: 'SKU',
                  itemId: item.id,
                  description: `${item.brand} ${item.model} ${item.size} (${item.position.replace('_', '-')})`,
                  qty: 1,
                  unitPrice: Number(item.priceRetail),
                });
                nav.goBack();
              }}
              right={<Text style={styles.price}>{money(item.priceRetail)}</Text>}
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
  price: { fontSize: 15, fontWeight: '700', color: colors.text },
});
