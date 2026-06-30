import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { FlatList, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Card, Divider, Empty, ErrorView, Loading } from '../components/ui';
import { ApiError, cashAccounts } from '../lib/api';
import { dateTime, money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

export default function CashAccountsScreen() {
  const { t } = useI18n();
  const accts = useQuery({
    queryKey: ['cash-accounts'],
    queryFn: () => cashAccounts.list(),
  });
  const transfers = useQuery({
    queryKey: ['cash-transfers'],
    queryFn: () => cashAccounts.transfers(25),
  });
  const methods = useQuery({
    queryKey: ['payment-methods'],
    queryFn: () => cashAccounts.methods(),
  });

  if (accts.isLoading) return <Loading />;
  if (accts.isError)
    return <ErrorView message={(accts.error as ApiError).message} onRetry={accts.refetch} />;

  const accounts = accts.data!;
  const total = accounts.reduce((s, a) => s + a.balance, 0);

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={
        <RefreshControl
          refreshing={accts.isRefetching}
          onRefresh={() => {
            accts.refetch();
            transfers.refetch();
            methods.refetch();
          }}
        />
      }
    >
      {/* Balance cards */}
      <View style={styles.balanceGrid}>
        {accounts.map((a) => (
          <Card key={a.id} style={styles.balanceCard}>
            <Text style={styles.acctCode}>{a.code}</Text>
            <Text style={styles.acctName} numberOfLines={1}>
              {a.name}
            </Text>
            <Text style={[styles.acctBalance, a.balance >= 0 ? styles.pos : styles.neg]}>
              {money(a.balance)}
            </Text>
          </Card>
        ))}
      </View>

      {/* Total */}
      <View style={styles.totalBar}>
        <Text style={styles.totalLabel}>{t('cash.totalPosition')}</Text>
        <Text style={[styles.totalValue, total >= 0 ? styles.pos : styles.neg]}>
          {money(total)}
        </Text>
      </View>

      {/* Transfers */}
      <Text style={styles.sectionTitle}>{t('cash.recentTransfers')}</Text>
      <Card style={{ marginBottom: space.md }}>
        {transfers.isLoading ? (
          <Loading />
        ) : transfers.isError ? (
          <ErrorView message={(transfers.error as ApiError).message} />
        ) : transfers.data!.length === 0 ? (
          <Empty message={t('cash.noTransfers')} />
        ) : (
          transfers.data!.map((tr, i) => (
            <View key={tr.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.transferRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.transferLabel}>
                    {tr.fromAccount.name} → {tr.toAccount.name}
                  </Text>
                  <Text style={styles.transferDate}>{dateTime(tr.createdAt)}</Text>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.transferAmount}>{money(tr.amount)}</Text>
                  {Number(tr.fee) > 0 ? (
                    <Text style={styles.transferFee}>
                      {t('cash.fee', { amount: money(tr.fee) })}
                    </Text>
                  ) : null}
                </View>
              </View>
            </View>
          ))
        )}
      </Card>

      {/* Payment Methods */}
      <Text style={styles.sectionTitle}>{t('cash.paymentMethods')}</Text>
      <Card style={{ marginBottom: space.xl }}>
        {methods.isLoading ? (
          <Loading />
        ) : methods.isError ? (
          <ErrorView message={(methods.error as ApiError).message} />
        ) : methods.data!.length === 0 ? (
          <Empty message={t('cash.noMethods')} />
        ) : (
          methods.data!.map((m, i) => (
            <View key={m.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.methodRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.methodName}>{m.name}</Text>
                  <Text style={styles.methodAcct}>
                    {m.account.code} · {m.account.name}
                    {m.processor === 'stripe' ? ' · Stripe' : ''}
                  </Text>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  {m.feeRate && Number(m.feeRate) > 0 ? (
                    <Text style={styles.feeRate}>{(Number(m.feeRate) * 100).toFixed(1)}% fee</Text>
                  ) : null}
                  <View
                    style={[
                      styles.activeBadge,
                      m.isActive ? styles.activeBadgeOn : styles.activeBadgeOff,
                    ]}
                  >
                    <Text
                      style={[
                        styles.activeText,
                        m.isActive ? { color: colors.success } : { color: colors.muted },
                      ]}
                    >
                      {m.isActive ? t('cash.active') : t('cash.inactive')}
                    </Text>
                  </View>
                </View>
              </View>
            </View>
          ))
        )}
      </Card>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  balanceGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.md, marginBottom: space.md },
  balanceCard: { flexGrow: 1, flexBasis: '44%', padding: space.lg },
  acctCode: { fontSize: 12, fontWeight: '700', color: colors.muted },
  acctName: { fontSize: 14, fontWeight: '600', color: colors.text, marginTop: 2 },
  acctBalance: { fontSize: 20, fontWeight: '800', marginTop: space.xs },
  pos: { color: colors.success },
  neg: { color: colors.danger },
  totalBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#1a1d22',
    borderRadius: radius.md,
    padding: space.lg,
    marginBottom: space.md,
  },
  totalLabel: { fontSize: 14, fontWeight: '700', color: '#fff' },
  totalValue: { fontSize: 20, fontWeight: '800', color: '#dafbe1' },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  transferRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  transferLabel: { fontSize: 14, fontWeight: '600', color: colors.text },
  transferDate: { fontSize: 12, color: colors.muted, marginTop: 2 },
  transferAmount: { fontSize: 15, fontWeight: '700', color: colors.text },
  transferFee: { fontSize: 12, color: colors.muted, marginTop: 2 },
  methodRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  methodName: { fontSize: 14, fontWeight: '600', color: colors.text },
  methodAcct: { fontSize: 12, color: colors.muted, marginTop: 2 },
  feeRate: { fontSize: 12, color: colors.warnText, marginBottom: 4 },
  activeBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  activeBadgeOn: { backgroundColor: '#dafbe1' },
  activeBadgeOff: { backgroundColor: '#eceef1' },
  activeText: { fontSize: 11, fontWeight: '700' },
});
