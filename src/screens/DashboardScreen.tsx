import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Empty, ErrorView, Loading } from '../components/ui';
import { ApiError, dashboard } from '../lib/api';
import { money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { useOpenDestination } from '../navigation/useOpenDestination';
import { colors, radius, space } from '../theme';

type Tone = 'default' | 'amber' | 'red';

const TONE: Record<Tone, { value: string; chipBg: string }> = {
  default: { value: colors.text, chipBg: colors.border },
  amber: { value: colors.warnText, chipBg: colors.warnBg },
  red: { value: colors.danger, chipBg: '#ffebe9' },
};

function Tile({
  label,
  value,
  sub,
  tone = 'default',
  onPress,
}: {
  label: string;
  value: string;
  sub?: string;
  tone?: Tone;
  onPress?: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.tile, pressed ? { opacity: 0.7 } : null]}
    >
      <Text style={styles.tileLabel} numberOfLines={1}>
        {label}
      </Text>
      <Text style={[styles.tileValue, { color: TONE[tone].value }]} numberOfLines={1}>
        {value}
      </Text>
      {sub ? (
        <Text style={styles.tileSub} numberOfLines={1}>
          {sub}
        </Text>
      ) : null}
    </Pressable>
  );
}

export default function DashboardScreen() {
  const open = useOpenDestination();
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['dashboard-summary'],
    queryFn: dashboard.summary,
    refetchInterval: 60_000,
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const d = query.data!;
  const invoiceCount = (n: number) =>
    t(n === 1 ? 'dashboard.invoice' : 'dashboard.invoices', { n });

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      <View style={styles.grid}>
        <Tile
          label={t('dashboard.todaySales')}
          value={money(d.today.revenue)}
          sub={invoiceCount(d.today.saleCount)}
          onPress={() => open('sales')}
        />
        <Tile
          label={t('dashboard.mtd')}
          value={money(d.month.revenue)}
          sub={invoiceCount(d.month.saleCount)}
          onPress={() => open('accounting')}
        />
        <Tile
          label={t('dashboard.openAR')}
          value={money(d.openAR.total)}
          sub={t('dashboard.unpaid', { n: d.openAR.invoiceCount })}
          tone={d.openAR.total > 0 ? 'amber' : 'default'}
          onPress={() => open('money')}
        />
        <Tile
          label={t('dashboard.lowStock')}
          value={String(d.lowStockCount)}
          sub={t('dashboard.reorderSub')}
          tone={d.lowStockCount > 0 ? 'red' : 'default'}
          onPress={() => open('inventory')}
        />
        <Tile
          label={t('dashboard.openQuotes')}
          value={String(d.openQuotes)}
          sub={t('dashboard.awaitingConfirm')}
          onPress={() => open('sales')}
        />
        <Tile
          label={t('dashboard.paidInvoices')}
          value={String(d.paidInvoiceCount)}
          sub={t('dashboard.lifetime')}
          onPress={() => open('sales')}
        />
      </View>

      <Text style={styles.sectionTitle}>{t('dashboard.lowStockTitle')}</Text>
      <View style={styles.card}>
        {d.lowStock.length === 0 ? (
          <Empty message={t('dashboard.aboveReorder')} />
        ) : (
          d.lowStock.map((s, i) => (
            <Pressable
              key={s.id}
              onPress={() => open('inventory')}
              style={({ pressed }) => [
                styles.lowRow,
                i > 0 ? styles.lowRowBorder : null,
                pressed ? { opacity: 0.6 } : null,
              ]}
            >
              <View style={{ flex: 1, paddingRight: space.sm }}>
                <Text style={styles.lowTitle} numberOfLines={1}>
                  {s.brand} {s.model}
                </Text>
                <Text style={styles.lowSub} numberOfLines={1}>
                  {s.sku} · {s.size}
                </Text>
              </View>
              <View style={styles.lowBadge}>
                <Text style={styles.lowBadgeText}>
                  {s.onHand} / {s.reorderPoint}
                </Text>
              </View>
            </Pressable>
          ))
        )}
      </View>

      {d.topSkus.length > 0 ? (
        <>
          <Text style={styles.sectionTitle}>{t('dashboard.topSellers')}</Text>
          <View style={styles.card}>
            {d.topSkus.map((s, i) => (
              <View key={s.id} style={[styles.lowRow, i > 0 ? styles.lowRowBorder : null]}>
                <View style={{ flex: 1, paddingRight: space.sm }}>
                  <Text style={styles.lowTitle} numberOfLines={1}>
                    {s.brand} {s.model}
                  </Text>
                  <Text style={styles.lowSub} numberOfLines={1}>
                    {s.sku} · {s.size}
                  </Text>
                </View>
                <Text style={styles.qty}>{t('dashboard.sold', { n: s.qty })}</Text>
              </View>
            ))}
          </View>
        </>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.md },
  tile: {
    flexGrow: 1,
    flexBasis: '47%',
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.lg,
  },
  tileLabel: { fontSize: 13, color: colors.muted, fontWeight: '600' },
  tileValue: { fontSize: 24, fontWeight: '800', marginTop: 6 },
  tileSub: { fontSize: 12, color: colors.muted, marginTop: 2 },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginTop: space.xl,
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
  lowRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: space.md,
    paddingHorizontal: space.lg,
  },
  lowRowBorder: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
  lowTitle: { fontSize: 15, fontWeight: '600', color: colors.text },
  lowSub: { fontSize: 12, color: colors.muted, marginTop: 2 },
  lowBadge: {
    backgroundColor: '#ffebe9',
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 3,
  },
  lowBadgeText: { color: colors.danger, fontSize: 13, fontWeight: '700' },
  qty: { fontSize: 14, fontWeight: '700', color: colors.text },
});
