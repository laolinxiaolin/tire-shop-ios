import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { Divider, Empty, ErrorView, Loading } from '../components/ui';
import { accounting, Account, ApiError } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

type Tab = 'pnl' | 'trialBalance' | 'journal';

const TYPE_COLOR: Record<string, string> = {
  ASSET: '#0969da',
  LIABILITY: '#9a6700',
  EQUITY: '#8250df',
  REVENUE: '#1a7f37',
  EXPENSE: '#cf222e',
};

export default function AccountingScreen() {
  const { t } = useI18n();
  const [tab, setTab] = useState<Tab>('pnl');

  return (
    <View style={styles.screen}>
      <View style={styles.tabs}>
        {(['pnl', 'trialBalance', 'journal'] as Tab[]).map((tabKey) => (
          <Pressable
            key={tabKey}
            onPress={() => setTab(tabKey)}
            style={[styles.tab, tab === tabKey ? styles.tabActive : null]}
          >
            <Text style={[styles.tabText, tab === tabKey ? styles.tabTextActive : null]}>
              {t(
                tabKey === 'pnl'
                  ? 'accounting.pnl'
                  : tabKey === 'trialBalance'
                    ? 'accounting.trialBalance'
                    : 'accounting.journal',
              )}
            </Text>
          </Pressable>
        ))}
      </View>
      {tab === 'pnl' ? <PnlTab /> : tab === 'trialBalance' ? <TrialBalanceTab /> : <JournalTab />}
    </View>
  );
}

/* ---- P&L ---- */

function PnlTab() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['accounting-pnl'],
    queryFn: () => accounting.pnl({}),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const p = query.data!;
  return (
    <FlatList
      data={[]}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      renderItem={() => null}
      ListEmptyComponent={null}
      ListHeaderComponent={
        <View style={{ padding: space.md }}>
          <Text style={styles.header}>
            {shortDate(p.from)} → {shortDate(p.to)}
          </Text>

          <Text style={styles.sectionTitle}>{t('accounting.revenue')}</Text>
          <View style={styles.card}>
            {p.revenue.map((r, i) => (
              <View key={r.code}>
                {i > 0 ? <Divider /> : null}
                <View style={styles.pnlRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.acctCode}>{r.code}</Text>
                    <Text style={styles.acctName}>{r.name}</Text>
                  </View>
                  <Text style={styles.acctAmount}>{money(r.total)}</Text>
                </View>
              </View>
            ))}
            <Divider />
            <View style={styles.pnlRow}>
              <Text style={styles.totalLabel}>{t('accounting.totalRevenue')}</Text>
              <Text style={[styles.totalValue, p.revenueTotal >= 0 ? styles.pos : styles.neg]}>
                {money(p.revenueTotal)}
              </Text>
            </View>
          </View>

          <Text style={styles.sectionTitle}>{t('accounting.expenses')}</Text>
          <View style={styles.card}>
            {p.expenses.map((e, i) => (
              <View key={e.code}>
                {i > 0 ? <Divider /> : null}
                <View style={styles.pnlRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.acctCode}>{e.code}</Text>
                    <Text style={styles.acctName}>{e.name}</Text>
                  </View>
                  <Text style={styles.acctAmount}>{money(e.total)}</Text>
                </View>
              </View>
            ))}
            <Divider />
            <View style={styles.pnlRow}>
              <Text style={styles.totalLabel}>{t('accounting.totalExpenses')}</Text>
              <Text style={styles.acctAmount}>{money(p.expensesTotal)}</Text>
            </View>
          </View>

          <View style={[styles.netIncome, p.netIncome >= 0 ? styles.netPos : styles.netNeg]}>
            <Text style={styles.netLabel}>{t('accounting.netIncome')}</Text>
            <Text style={styles.netValue}>{money(p.netIncome)}</Text>
          </View>

          <View style={{ height: space.xl }} />
        </View>
      }
    />
  );
}

/* ---- Trial Balance ---- */

function TrialBalanceTab() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['accounting-accounts'],
    queryFn: () => accounting.accounts(),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const accounts = query.data!;
  return (
    <FlatList
      data={accounts}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      keyExtractor={(a) => a.id}
      ItemSeparatorComponent={() => <View style={styles.sep} />}
      ListEmptyComponent={<Empty message={t('accounting.noAccounts')} />}
      renderItem={({ item: a }) => (
        <View style={styles.tbRow}>
          <View style={{ flex: 1 }}>
            <Text style={styles.acctCode}>{a.code}</Text>
            <Text style={styles.acctName} numberOfLines={1}>
              {a.name}
            </Text>
          </View>
          <View style={{ alignItems: 'flex-end' }}>
            <Text style={[styles.balance, a.balance >= 0 ? styles.pos : styles.neg]}>
              {money(a.balance)}
            </Text>
            <View style={[styles.typeBadge, { backgroundColor: TYPE_COLOR[a.type] + '18' }]}>
              <Text style={[styles.typeText, { color: TYPE_COLOR[a.type] }]}>{a.type}</Text>
            </View>
          </View>
        </View>
      )}
    />
  );
}

/* ---- Journal ---- */

function JournalTab() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['accounting-journal'],
    queryFn: () => accounting.journal({ pageSize: 50 }),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const entries = query.data?.items ?? [];
  return (
    <FlatList
      data={entries}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      keyExtractor={(je) => je.id}
      ItemSeparatorComponent={() => <View style={styles.jeSep} />}
      ListEmptyComponent={<Empty message={t('accounting.noJournalEntries')} />}
      renderItem={({ item: je }) => (
        <View style={styles.jeCard}>
          <View style={styles.jeHeader}>
            <Text style={styles.jeDate}>{shortDate(je.date)}</Text>
            <Text style={styles.jeMemo} numberOfLines={2}>
              {je.memo ?? '—'}
            </Text>
            {je.refType ? (
              <View style={styles.refBadge}>
                <Text style={styles.refText}>{je.refType}</Text>
              </View>
            ) : null}
          </View>
          {je.lines.map((l, i) => (
            <View key={l.id} style={[styles.jeLine, i > 0 ? styles.jeLineBorder : null]}>
              <Text style={styles.jeAcct} numberOfLines={1}>
                {l.account.code} · {l.account.name}
              </Text>
              <View style={styles.jeAmounts}>
                <Text style={styles.debit}>{(Number(l.debit) || 0) > 0 ? money(l.debit) : ''}</Text>
                <Text style={styles.credit}>
                  {(Number(l.credit) || 0) > 0 ? money(l.credit) : ''}
                </Text>
              </View>
            </View>
          ))}
        </View>
      )}
    />
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
  tabText: { fontSize: 13, fontWeight: '600', color: colors.muted },
  tabTextActive: { color: colors.primaryText },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },

  // P&L
  header: { fontSize: 14, color: colors.muted, marginBottom: space.md, textAlign: 'center' },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginTop: space.md,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  pnlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: space.sm,
    paddingHorizontal: space.lg,
  },
  acctCode: { fontSize: 13, fontWeight: '700', color: colors.text },
  acctName: { fontSize: 12, color: colors.muted, marginTop: 1 },
  acctAmount: { fontSize: 15, fontWeight: '700', color: colors.text },
  totalLabel: { flex: 1, fontSize: 15, fontWeight: '800', color: colors.text },
  totalValue: { fontSize: 16, fontWeight: '800' },
  pos: { color: colors.success },
  neg: { color: colors.danger },
  netIncome: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: space.md,
    borderRadius: radius.md,
    padding: space.lg,
  },
  netPos: { backgroundColor: '#dafbe1' },
  netNeg: { backgroundColor: '#ffebe9' },
  netLabel: { fontSize: 16, fontWeight: '800', color: colors.text },
  netValue: { fontSize: 20, fontWeight: '800', color: colors.text },

  // Trial Balance
  tbRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: space.md,
    paddingHorizontal: space.lg,
    backgroundColor: colors.card,
  },
  balance: { fontSize: 16, fontWeight: '700', marginBottom: 4 },
  typeBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  typeText: { fontSize: 10, fontWeight: '700', letterSpacing: 0.3 },

  // Journal
  jeSep: { height: space.md },
  jeCard: {
    marginHorizontal: space.md,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  jeHeader: {
    padding: space.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  jeDate: { fontSize: 12, color: colors.muted, fontWeight: '600' },
  jeMemo: { fontSize: 15, fontWeight: '600', color: colors.text, marginTop: 2 },
  refBadge: {
    marginTop: space.sm,
    alignSelf: 'flex-start',
    backgroundColor: '#fff4e5',
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
  },
  refText: { fontSize: 11, fontWeight: '700', color: '#9a6700' },
  jeLine: { paddingVertical: space.sm, paddingHorizontal: space.lg },
  jeLineBorder: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
  jeAcct: { fontSize: 13, color: colors.text },
  jeAmounts: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 4 },
  debit: { fontSize: 14, fontWeight: '600', color: colors.danger },
  credit: { fontSize: 14, fontWeight: '600', color: colors.success },
});
