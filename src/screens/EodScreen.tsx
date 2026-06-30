import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Card, Divider, Empty, ErrorView, Loading } from '../components/ui';
import { ApiError, eod } from '../lib/api';
import { money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export default function EodScreen() {
  const { t } = useI18n();
  const [date, setDate] = useState(todayStr);
  const query = useQuery({
    queryKey: ['eod', date],
    queryFn: () => eod.report(date),
  });

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      {/* Date picker */}
      <View style={styles.dateRow}>
        <TextInput
          value={date}
          onChangeText={setDate}
          placeholder={t('eod.datePlaceholder')}
          placeholderTextColor={colors.muted}
          style={styles.dateInput}
          autoCapitalize="none"
          autoCorrect={false}
          maxLength={10}
        />
        <Pressable
          onPress={() => setDate(todayStr())}
          style={({ pressed }) => [styles.todayBtn, pressed ? { opacity: 0.6 } : null]}
        >
          <Text style={styles.todayBtnText}>{t('eod.today')}</Text>
        </Pressable>
      </View>

      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        (() => {
          const r = query.data!;

          return (
            <>
              {/* Summary stats */}
              <View style={styles.statGrid}>
                <Card style={styles.stat}>
                  <Text style={styles.statLabel}>{t('eod.sales')}</Text>
                  <Text style={styles.statValue}>{money(r.sales.summary.total)}</Text>
                  <Text style={styles.statSub}>
                    {t('eod.invoicesCount', { n: r.sales.summary.count })}
                  </Text>
                </Card>
                <Card style={styles.stat}>
                  <Text style={styles.statLabel}>{t('eod.payments')}</Text>
                  <Text style={styles.statValue}>{money(r.payments.summary.total)}</Text>
                  <Text style={styles.statSub}>
                    {t('eod.paymentsCount', { n: r.payments.summary.count })}
                  </Text>
                </Card>
                <Card style={styles.stat}>
                  <Text style={styles.statLabel}>{t('eod.expenses')}</Text>
                  <Text style={[styles.statValue, { color: colors.danger }]}>
                    {money(r.expenses.total)}
                  </Text>
                </Card>
                <Card style={styles.stat}>
                  <Text style={styles.statLabel}>{t('eod.netIncome')}</Text>
                  <Text
                    style={[
                      styles.statValue,
                      r.pnl.netIncome >= 0 ? { color: colors.success } : { color: colors.danger },
                    ]}
                  >
                    {money(r.pnl.netIncome)}
                  </Text>
                </Card>
              </View>

              {/* Sales */}
              <Text style={styles.sectionTitle}>
                {t('eod.salesSection', { n: r.sales.items.length })}
              </Text>
              {r.sales.items.length === 0 ? (
                <Empty message={t('eod.noSales')} />
              ) : (
                <Card style={{ marginBottom: space.md }}>
                  {r.sales.items.map((s, i) => (
                    <View key={i}>
                      {i > 0 ? <Divider /> : null}
                      <View style={styles.row}>
                        <View style={{ flex: 1 }}>
                          <Text style={styles.rowTitle} numberOfLines={1}>
                            {s.saleRef} · {s.customer}
                          </Text>
                          <Text style={styles.rowSub}>
                            {s.soldBy} · {s.status}
                          </Text>
                        </View>
                        <Text style={styles.rowAmount}>{money(s.total)}</Text>
                      </View>
                    </View>
                  ))}
                </Card>
              )}

              {/* Payments */}
              <Text style={styles.sectionTitle}>
                {t('eod.paymentsSection', { n: r.payments.items.length })}
              </Text>
              {r.payments.items.length === 0 ? (
                <Empty message={t('eod.noPayments')} />
              ) : (
                <>
                  {r.payments.byMethod.length > 0 ? (
                    <ScrollView
                      horizontal
                      showsHorizontalScrollIndicator={false}
                      style={{ marginBottom: space.sm }}
                    >
                      <View style={{ flexDirection: 'row', gap: space.sm, paddingHorizontal: 0 }}>
                        {r.payments.byMethod.map((m) => (
                          <View key={m.method} style={styles.methodPill}>
                            <Text style={styles.methodName}>{m.method}</Text>
                            <Text style={styles.methodAmount}>{money(m.amount)}</Text>
                            <Text style={styles.methodCount}>{m.count}x</Text>
                          </View>
                        ))}
                      </View>
                    </ScrollView>
                  ) : null}
                  <Card style={{ marginBottom: space.md }}>
                    {r.payments.items.map((p, i) => (
                      <View key={i}>
                        {i > 0 ? <Divider /> : null}
                        <View style={styles.row}>
                          <View style={{ flex: 1 }}>
                            <Text style={styles.rowTitle} numberOfLines={1}>
                              {p.method}
                            </Text>
                            <Text style={styles.rowSub}>
                              {p.reference ?? '—'}
                              {p.surcharge > 0
                                ? ` · ${t('eod.surcharge', { amount: money(p.surcharge) })}`
                                : ''}
                            </Text>
                          </View>
                          <Text style={styles.rowAmount}>{money(p.amount)}</Text>
                        </View>
                      </View>
                    ))}
                  </Card>
                </>
              )}

              {/* P&L */}
              <Text style={styles.sectionTitle}>{t('eod.pnl')}</Text>
              <Card style={{ marginBottom: space.md }}>
                <Text style={styles.pnlHdr}>{t('accounting.revenue')}</Text>
                {r.pnl.revenue.map((a, i) => (
                  <View key={i} style={styles.pnlRow}>
                    <Text style={styles.pnlName}>
                      {a.code} · {a.name}
                    </Text>
                    <Text style={styles.pnlAmt}>{money(a.total)}</Text>
                  </View>
                ))}
                <Divider />
                <View style={styles.pnlRow}>
                  <Text style={styles.pnlTotal}>{t('accounting.totalRevenue')}</Text>
                  <Text style={styles.pnlTotalAmt}>{money(r.pnl.revenueTotal)}</Text>
                </View>

                <Text style={[styles.pnlHdr, { marginTop: space.md }]}>
                  {t('accounting.expenses')}
                </Text>
                {r.pnl.expenses.map((a, i) => (
                  <View key={i} style={styles.pnlRow}>
                    <Text style={styles.pnlName}>
                      {a.code} · {a.name}
                    </Text>
                    <Text style={styles.pnlAmt}>{money(a.total)}</Text>
                  </View>
                ))}
                <Divider />
                <View style={styles.pnlRow}>
                  <Text style={styles.pnlTotal}>{t('accounting.totalExpenses')}</Text>
                  <Text style={styles.pnlTotalAmt}>{money(r.pnl.expensesTotal)}</Text>
                </View>

                <View
                  style={[
                    styles.gpBar,
                    r.pnl.netIncome >= 0
                      ? { backgroundColor: '#dafbe1' }
                      : { backgroundColor: '#ffebe9' },
                  ]}
                >
                  <Text style={styles.gpLabel}>{t('eod.netIncome')}</Text>
                  <Text
                    style={[
                      styles.gpValue,
                      r.pnl.netIncome >= 0 ? { color: colors.success } : { color: colors.danger },
                    ]}
                  >
                    {money(r.pnl.netIncome)}
                  </Text>
                </View>
              </Card>

              {/* Cash Movement */}
              {r.cashMovement.length > 0 ? (
                <>
                  <Text style={styles.sectionTitle}>{t('eod.cashMovement')}</Text>
                  <Card style={{ marginBottom: space.xl }}>
                    {r.cashMovement.map((c, i) => (
                      <View key={c.code}>
                        {i > 0 ? <Divider /> : null}
                        <View style={styles.cashRow}>
                          <View style={{ flex: 1 }}>
                            <Text style={styles.rowTitle}>
                              {c.code} · {c.name}
                            </Text>
                          </View>
                          <View style={{ alignItems: 'flex-end' }}>
                            <View style={styles.cashAmts}>
                              {c.in > 0 ? <Text style={styles.cashIn}>+{money(c.in)}</Text> : null}
                              {c.out > 0 ? (
                                <Text style={styles.cashOut}>-{money(c.out)}</Text>
                              ) : null}
                            </View>
                            <Text
                              style={[
                                styles.cashNet,
                                c.net >= 0 ? { color: colors.success } : { color: colors.danger },
                              ]}
                            >
                              {t('eod.net', { amount: money(c.net) })}
                            </Text>
                          </View>
                        </View>
                      </View>
                    ))}
                  </Card>
                </>
              ) : null}

              <View style={{ height: space.xl }} />
            </>
          );
        })()
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  dateRow: {
    flexDirection: 'row',
    gap: space.sm,
    marginBottom: space.md,
  },
  dateInput: {
    flex: 1,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    paddingHorizontal: space.md,
    paddingVertical: space.md,
    fontSize: 16,
    color: colors.text,
  },
  todayBtn: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    justifyContent: 'center',
    paddingHorizontal: space.lg,
  },
  todayBtnText: { color: colors.primaryText, fontWeight: '700', fontSize: 14 },
  statGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.md, marginBottom: space.md },
  stat: { flexGrow: 1, flexBasis: '44%', alignItems: 'center', padding: space.md },
  statLabel: { fontSize: 12, fontWeight: '600', color: colors.muted },
  statValue: { fontSize: 20, fontWeight: '800', color: colors.text, marginTop: 4 },
  statSub: { fontSize: 12, color: colors.muted, marginTop: 2 },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  rowTitle: { fontSize: 14, fontWeight: '600', color: colors.text },
  rowSub: { fontSize: 12, color: colors.muted, marginTop: 2 },
  rowAmount: { fontSize: 15, fontWeight: '700', color: colors.text },
  methodPill: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.sm,
    alignItems: 'center',
    minWidth: 80,
  },
  methodName: { fontSize: 11, fontWeight: '600', color: colors.muted },
  methodAmount: { fontSize: 14, fontWeight: '700', color: colors.text, marginTop: 2 },
  methodCount: { fontSize: 10, color: colors.muted, marginTop: 1 },
  pnlHdr: { fontSize: 13, fontWeight: '700', color: colors.muted, marginBottom: space.xs },
  pnlRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 3,
  },
  pnlName: { fontSize: 13, color: colors.text, flex: 1 },
  pnlAmt: { fontSize: 13, fontWeight: '600', color: colors.text },
  pnlTotal: { fontSize: 14, fontWeight: '800', color: colors.text },
  pnlTotalAmt: { fontSize: 14, fontWeight: '800', color: colors.text },
  gpBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: space.md,
    borderRadius: radius.sm,
    padding: space.md,
  },
  gpLabel: { fontSize: 15, fontWeight: '800', color: colors.text },
  gpValue: { fontSize: 16, fontWeight: '800' },
  cashRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  cashAmts: { flexDirection: 'row', gap: space.sm },
  cashIn: { fontSize: 13, fontWeight: '600', color: colors.success },
  cashOut: { fontSize: 13, fontWeight: '600', color: colors.danger },
  cashNet: { fontSize: 14, fontWeight: '700', marginTop: 2 },
});
