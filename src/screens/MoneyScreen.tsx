import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { Empty, ErrorView, Loading, Row } from '../components/ui';
import { ApiError, receivables, payables } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

type Tab = 'receivables' | 'payables';

function ageBadge(days: number) {
  let bg = '#dafbe1';
  let fg = '#1a7f37';
  if (days > 90) {
    bg = '#ffebe9';
    fg = '#cf222e';
  } else if (days > 60) {
    bg = '#fff4e5';
    fg = '#9a6700';
  } else if (days > 30) {
    bg = '#fff8c5';
    fg = '#7d4e00';
  }
  return (
    <View style={[styles.ageBadge, { backgroundColor: bg }]}>
      <Text style={[styles.ageText, { color: fg }]}>{days}d</Text>
    </View>
  );
}

export default function MoneyScreen() {
  const [tab, setTab] = useState<Tab>('receivables');
  const { t } = useI18n();

  return (
    <View style={styles.screen}>
      {/* Tab toggle */}
      <View style={styles.tabs}>
        <Pressable
          onPress={() => setTab('receivables')}
          style={[styles.tab, tab === 'receivables' ? styles.tabActive : null]}
        >
          <Text style={[styles.tabText, tab === 'receivables' ? styles.tabTextActive : null]}>
            {t('money.receivables')}
          </Text>
        </Pressable>
        <Pressable
          onPress={() => setTab('payables')}
          style={[styles.tab, tab === 'payables' ? styles.tabActive : null]}
        >
          <Text style={[styles.tabText, tab === 'payables' ? styles.tabTextActive : null]}>
            {t('money.payables')}
          </Text>
        </Pressable>
      </View>

      {tab === 'receivables' ? <ReceivablesList /> : <PayablesList />}
    </View>
  );
}

function ReceivablesList() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['receivables'],
    queryFn: () => receivables.list({ pageSize: 100 }),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const items = query.data?.items ?? [];

  return (
    <FlatList
      data={items}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      keyExtractor={(r) => r.customer.id}
      ItemSeparatorComponent={() => <View style={styles.sep} />}
      ListEmptyComponent={<Empty message={t('money.noOpenReceivables')} />}
      ListHeaderComponent={
        items.length > 0 ? (
          <View style={styles.summary}>
            <Text style={styles.summaryTitle}>
              {money(items.reduce((s, r) => s + r.openBalance, 0))}{' '}
              {t('money.acrossCustomers', {
                n: items.length,
                plural: items.length !== 1 ? 's' : '',
              })}
            </Text>
            <AgingStrip items={items} />
          </View>
        ) : null
      }
      renderItem={({ item: r }) => (
        <Row
          title={r.customer.company ?? r.customer.name}
          subtitle={`${r.openCount} ${t('money.invoices', { n: r.openCount, plural: r.openCount !== 1 ? 's' : '' })} · ${t('money.since', { date: shortDate(r.oldestAt) })}`}
          right={
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={styles.amount}>{money(r.openBalance)}</Text>
              {ageBadge(r.ageDays)}
            </View>
          }
        />
      )}
    />
  );
}

function PayablesList() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['payables'],
    queryFn: () => payables.list({ pageSize: 100 }),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const items = query.data?.items ?? [];

  return (
    <FlatList
      data={items}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      keyExtractor={(p) => p.vendorKey}
      ItemSeparatorComponent={() => <View style={styles.sep} />}
      ListEmptyComponent={<Empty message={t('money.noOpenPayables')} />}
      ListHeaderComponent={
        items.length > 0 ? (
          <View style={styles.summary}>
            <Text style={styles.summaryTitle}>
              {money(items.reduce((s, p) => s + p.totalDue, 0))}{' '}
              {t('money.acrossVendors', { n: items.length, plural: items.length !== 1 ? 's' : '' })}
            </Text>
            <AgingStrip items={items} />
          </View>
        ) : null
      }
      renderItem={({ item: p }) => (
        <Row
          title={p.vendor ?? t('money.noVendor')}
          subtitle={`${p.count} ${t('money.items', { n: p.count, plural: p.count !== 1 ? 's' : '' })} · ${t('money.since', { date: shortDate(p.oldestAt) })}`}
          right={
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={styles.amount}>{money(p.totalDue)}</Text>
              {ageBadge(p.ageDays)}
            </View>
          }
        />
      )}
    />
  );
}

function AgingStrip({
  items,
}: {
  items: { ageDays: number; openBalance?: number; totalDue?: number }[];
}) {
  const { t } = useI18n();
  const buckets = [0, 0, 0, 0]; // current, 31-60, 61-90, 90+
  for (const item of items) {
    const bal =
      (item as { openBalance: number }).openBalance ?? (item as { totalDue: number }).totalDue;
    const d = item.ageDays;
    if (d <= 30) buckets[0] += bal;
    else if (d <= 60) buckets[1] += bal;
    else if (d <= 90) buckets[2] += bal;
    else buckets[3] += bal;
  }

  const labels = [
    t('money.current'),
    t('money.days31to60'),
    t('money.days61to90'),
    t('money.days90plus'),
  ];
  return (
    <View style={styles.agingRow}>
      {buckets.map((amt, i) => (
        <View key={i} style={styles.agingItem}>
          <Text style={styles.agingLabel}>{labels[i]}</Text>
          <Text style={styles.agingValue}>{money(amt)}</Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  tabs: {
    flexDirection: 'row',
    margin: space.md,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  tab: {
    flex: 1,
    paddingVertical: space.sm + 2,
    alignItems: 'center',
    borderRadius: radius.md - 2,
  },
  tabActive: { backgroundColor: colors.primary },
  tabText: { fontSize: 14, fontWeight: '600', color: colors.muted },
  tabTextActive: { color: colors.primaryText },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  summary: {
    padding: space.lg,
    backgroundColor: colors.card,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  summaryTitle: { fontSize: 18, fontWeight: '800', color: colors.text },
  amount: { fontSize: 16, fontWeight: '700', color: colors.text, marginBottom: 4 },
  ageBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  ageText: { fontSize: 11, fontWeight: '700' },
  agingRow: { flexDirection: 'row', marginTop: space.md, gap: space.sm },
  agingItem: { flex: 1 },
  agingLabel: { fontSize: 10, color: colors.muted, fontWeight: '600', textTransform: 'uppercase' },
  agingValue: { fontSize: 13, fontWeight: '700', color: colors.text, marginTop: 2 },
});
