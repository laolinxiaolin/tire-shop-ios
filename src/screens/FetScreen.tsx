import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Card, Divider, Empty, ErrorView, Loading } from '../components/ui';
import { useI18n } from '../lib/i18n';
import { ApiError, fet } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { colors, radius, space } from '../theme';

export default function FetScreen() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['fet'],
    queryFn: () => fet.status(),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const d = query.data!;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      {/* Amount owed */}
      <View
        style={[
          styles.owedCard,
          Math.abs(d.payable) < 0.005
            ? styles.owedZero
            : d.payable > 0
              ? styles.owedAmber
              : styles.owedRed,
        ]}
      >
        <Text style={styles.owedLabel}>{t('fet.payable')}</Text>
        <Text style={styles.owedAmount}>{money(d.payable)}</Text>
        <Text style={styles.owedNote}>
          {Math.abs(d.payable) < 0.005 ? t('fet.allPaid') : t('fet.irsNote')}
        </Text>
      </View>

      {/* Quarterly breakdown */}
      <Text style={styles.sectionTitle}>{t('fet.quarterlyBreakdown')}</Text>
      {d.quarters.length === 0 ? (
        <Empty message={t('fet.noQuarterlyData')} />
      ) : (
        d.quarters.map((q, i) => {
          const paid = d.paidPerQuarter[q.key] ?? 0;
          const remaining = q.fetDue - paid;
          const overdue = new Date(q.formDueDate) < new Date() && remaining > 0.005;
          return (
            <Card
              key={q.key}
              style={{ marginBottom: i < d.quarters.length - 1 ? space.sm : space.md }}
            >
              <Text style={styles.qLabel}>{q.label}</Text>
              <Text style={styles.qPeriod}>
                {shortDate(q.periodStart)} – {shortDate(q.periodEnd)}
              </Text>
              <View style={styles.qRow}>
                <Text style={styles.qField}>{t('fet.fetOnTires')}</Text>
                <Text style={styles.qValue}>{money(q.fetDue)}</Text>
              </View>
              <Divider />
              <View style={styles.qRow}>
                <Text style={styles.qField}>{t('fet.paid')}</Text>
                <Text style={[styles.qValue, paid > 0 ? { color: colors.success } : null]}>
                  {money(paid)}
                </Text>
              </View>
              <Divider />
              <View style={styles.qRow}>
                <Text style={[styles.qField, remaining > 0.005 ? { fontWeight: '800' } : null]}>
                  {t('fet.remaining')}
                </Text>
                <Text style={[styles.qValue, remaining > 0.005 ? styles.neg : styles.pos]}>
                  {money(remaining)}
                </Text>
              </View>
              <Divider />
              <View style={styles.qRow}>
                <Text style={styles.qField}>{t('fet.form720Due')}</Text>
                <Text
                  style={[
                    styles.qValue,
                    overdue ? { color: colors.danger, fontWeight: '700' } : null,
                  ]}
                >
                  {shortDate(q.formDueDate)}
                  {overdue ? t('fet.overdue') : ''}
                </Text>
              </View>
              {q.depositRequired ? (
                <View style={styles.depositBadge}>
                  <Text style={styles.depositText}>{t('fet.depositsRequired')}</Text>
                </View>
              ) : null}
            </Card>
          );
        })
      )}

      {/* Payment history */}
      <Text style={styles.sectionTitle}>{t('fet.paymentHistory')}</Text>
      <Card style={{ marginBottom: space.xl }}>
        {d.payments.length === 0 ? (
          <Empty message={t('fet.noPayments')} />
        ) : (
          d.payments.map((p, i) => (
            <View key={p.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.pmtRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.pmtMemo} numberOfLines={1}>
                    {p.memo ?? t('fet.payment')}
                  </Text>
                  <Text style={styles.pmtDate}>{shortDate(p.date)}</Text>
                </View>
                <Text style={[styles.pmtAmount, { color: colors.text }]}>{money(p.amount)}</Text>
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
  owedCard: {
    alignItems: 'center',
    padding: space.xl,
    marginBottom: space.md,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  owedZero: { backgroundColor: '#dafbe1' },
  owedAmber: { backgroundColor: '#fff4e5' },
  owedRed: { backgroundColor: '#ffebe9' },
  owedLabel: { fontSize: 13, fontWeight: '700', color: colors.muted },
  owedAmount: { fontSize: 36, fontWeight: '800', color: colors.text, marginTop: space.xs },
  owedNote: { fontSize: 13, color: colors.muted, textAlign: 'center', marginTop: space.sm },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  qLabel: { fontSize: 16, fontWeight: '700', color: colors.text },
  qPeriod: { fontSize: 13, color: colors.muted, marginTop: 2 },
  qRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: space.sm },
  qField: { fontSize: 14, color: colors.text },
  qValue: { fontSize: 14, fontWeight: '600', color: colors.text },
  pos: { color: colors.success },
  neg: { color: colors.danger },
  depositBadge: {
    marginTop: space.sm,
    backgroundColor: '#fff4e5',
    borderRadius: radius.sm,
    padding: space.sm,
    alignItems: 'center',
  },
  depositText: { fontSize: 12, fontWeight: '600', color: colors.warnText },
  pmtRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  pmtMemo: { fontSize: 14, fontWeight: '600', color: colors.text },
  pmtDate: { fontSize: 12, color: colors.muted, marginTop: 2 },
  pmtAmount: { fontSize: 15, fontWeight: '700' },
});
