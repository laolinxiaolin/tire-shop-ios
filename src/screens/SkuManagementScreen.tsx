import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import * as DocumentPicker from 'expo-document-picker';
import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { CATEGORY_FILTERS, FilterChips, POSITION_FILTERS } from '../components/TireFilters';
import { AddRow, Badge, Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import {
  ApiError,
  downloadAndShare,
  ImportSummary,
  inventory,
  TireCategory,
  TirePosition,
} from '../lib/api';
import { money } from '../lib/format';
import { useDebounced } from '../lib/hooks';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, space } from '../theme';

const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/** Catalog management: view / add / edit / import SKU definitions. Deliberately
 * shows no stock quantities — that's the Inventory screen's job. */
export default function SkuManagementScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { t } = useI18n();

  const [q, setQ] = useState('');
  const [category, setCategory] = useState<TireCategory | ''>('');
  const [position, setPosition] = useState<TirePosition | ''>('');
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

  const template = useMutation({
    mutationFn: () =>
      downloadAndShare(
        '/inventory/skus/import/template',
        'inventory-import-template.xlsx',
        XLSX_MIME,
      ),
    onError: (e) =>
      Alert.alert(
        t('skuManagement.templateFailed'),
        e instanceof ApiError ? e.message : 'Something went wrong.',
      ),
  });

  const importer = useMutation({
    mutationFn: async () => {
      const res = await DocumentPicker.getDocumentAsync({
        type: [XLSX_MIME, 'application/vnd.ms-excel', '*/*'],
        copyToCacheDirectory: true,
      });
      if (res.canceled) return null;
      const a = res.assets[0];
      return inventory.importSkus({
        uri: a.uri,
        name: a.name,
        mimeType: a.mimeType ?? XLSX_MIME,
      });
    },
    onSuccess: (summary) => {
      if (!summary) return; // picker cancelled
      qc.invalidateQueries({ queryKey: ['skus'] });
      Alert.alert(t('skuManagement.importComplete'), summarize(summary, t));
    },
    onError: (e) =>
      Alert.alert(
        t('skuManagement.importFailed'),
        e instanceof ApiError ? e.message : 'Something went wrong.',
      ),
  });

  const busy = template.isPending || importer.isPending;

  return (
    <View style={styles.screen}>
      <SearchBar value={q} onChangeText={setQ} placeholder={t('skuManagement.search')} />
      <FilterChips value={category} options={CATEGORY_FILTERS} onChange={setCategory} />
      <FilterChips value={position} options={POSITION_FILTERS} onChange={setPosition} />

      <View style={styles.toolbar}>
        <Pressable
          onPress={() => template.mutate()}
          disabled={busy}
          hitSlop={8}
          style={styles.toolBtn}
        >
          {template.isPending ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : (
            <Text style={styles.toolText}>{t('skuManagement.template')}</Text>
          )}
        </Pressable>
        <Pressable
          onPress={() => importer.mutate()}
          disabled={busy}
          hitSlop={8}
          style={styles.toolBtn}
        >
          {importer.isPending ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : (
            <Text style={styles.toolText}>{t('skuManagement.import')}</Text>
          )}
        </Pressable>
      </View>

      <AddRow label={t('skuManagement.newSku')} onPress={() => nav.navigate('SkuForm')} />

      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          style={{ flex: 1 }}
          refreshing={query.isRefetching}
          onRefresh={query.refetch}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={Sep}
          ListEmptyComponent={<Empty message={t('skuManagement.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.size} · ${item.brand} ${item.model}`}
              subtitle={`${item.sku} · ${item.position} · ${item.category}`}
              onPress={() => nav.navigate('SkuForm', { sku: item })}
              right={
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.price}>{money(item.priceRetail)}</Text>
                  {!item.active ? <Badge label={t('skuManagement.inactive')} /> : null}
                </View>
              }
            />
          )}
        />
      )}
    </View>
  );
}

function summarize(
  s: ImportSummary,
  t: (key: string, params?: Record<string, string | number>) => string,
): string {
  const lines = [
    t('skuManagement.summary', {
      created: s.created,
      updated: s.updated,
      errors: s.errorCount,
      errorPlural: s.errorCount !== 1 ? 's' : '',
      total: s.total,
    }),
  ];
  if (s.errors.length) {
    lines.push('');
    for (const e of s.errors.slice(0, 5)) lines.push(`Row ${e.row}: ${e.message}`);
    if (s.errors.length > 5) lines.push(`…and ${s.errors.length - 5} more.`);
  }
  return lines.join('\n');
}

function Sep() {
  return <View style={styles.sep} />;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  price: { fontSize: 15, fontWeight: '700', color: colors.text },
  toolbar: {
    flexDirection: 'row',
    gap: space.lg,
    paddingHorizontal: space.lg,
    paddingBottom: space.sm,
  },
  toolBtn: { paddingVertical: 4, minWidth: 90 },
  toolText: { fontSize: 14, color: colors.primary, fontWeight: '600' },
});
