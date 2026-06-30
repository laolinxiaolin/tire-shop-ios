import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { AddRow, Badge, Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import { ApiError, sales, SaleStatus } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { useDebounced } from '../lib/hooks';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

const STATUSES: (SaleStatus | 'ALL')[] = ['ALL', 'QUOTE', 'INVOICED', 'PAID', 'DRAFT', 'CANCELLED'];

export default function SalesListScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { t } = useI18n();
  const { has } = useAuth();
  const [q, setQ] = useState('');
  const [status, setStatus] = useState<SaleStatus | 'ALL'>('ALL');
  const debounced = useDebounced(q);

  const query = useQuery({
    queryKey: ['sales', debounced, status],
    queryFn: () =>
      sales.list({
        q: debounced || undefined,
        status: status === 'ALL' ? undefined : status,
        pageSize: 50,
      }),
  });

  return (
    <View style={styles.screen}>
      <SearchBar value={q} onChangeText={setQ} placeholder={t('sales.search')} />
      {has('sales.manage') ? (
        <AddRow
          label={t('sales.newSale')}
          onPress={() => nav.navigate('Main', { screen: 'newQuote' })}
        />
      ) : null}
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
                  {t(`status.${s}`)}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>
      </View>
      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          refreshing={query.isRefetching}
          onRefresh={query.refetch}
          keyExtractor={(s) => s.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('sales.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.ref} · ${item.customer?.name ?? t('sales.unknownCustomer')}`}
              subtitle={`${shortDate(item.createdAt)}${item.sampleDescription ? ` · ${item.sampleDescription}` : ''}`}
              onPress={() => nav.navigate('SaleDetail', { id: item.id })}
              right={
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.total}>{money(item.total)}</Text>
                  <Badge label={item.status} text={t(`status.${item.status}`)} />
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
  total: { fontSize: 16, fontWeight: '700', color: colors.text, marginBottom: 4 },
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
});
