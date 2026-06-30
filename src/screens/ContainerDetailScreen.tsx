import { useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Card, Divider, Empty, ErrorView, Loading } from '../components/ui';
import { ApiError, containers, ContainerStatus } from '../lib/api';
import { dateTime, money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const STATUS_COLOR: Record<ContainerStatus, { bg: string; fg: string }> = {
  DRAFT: { bg: '#eceef1', fg: '#57606a' },
  ORDERED: { bg: '#ddf4ff', fg: '#0969da' },
  IN_TRANSIT: { bg: '#fff8c5', fg: '#7d4e00' },
  ARRIVED: { bg: '#fff4e5', fg: '#9a6700' },
  RECEIVED: { bg: '#dafbe1', fg: '#1a7f37' },
  CANCELLED: { bg: '#ffebe9', fg: '#cf222e' },
};

const CATEGORY_LABEL_KEYS: Record<string, string> = {
  DOWN_PAYMENT: 'container.cost.DOWN_PAYMENT',
  BALANCE_PAYMENT: 'container.cost.BALANCE_PAYMENT',
  SUPPLIER_OTHER: 'container.cost.SUPPLIER_OTHER',
  FREIGHT: 'container.cost.FREIGHT',
  DUTY: 'container.cost.DUTY',
  TRUCKING: 'container.cost.TRUCKING',
  LABOR: 'container.cost.LABOR',
  OTHER: 'container.cost.OTHER',
};

export default function ContainerDetailScreen() {
  const { id } = useRoute<RouteProp<RootStackParamList, 'ContainerDetail'>>().params;
  const { t } = useI18n();

  const query = useQuery({
    queryKey: ['container', id],
    queryFn: () => containers.get(id),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const c = query.data!;
  const sc = STATUS_COLOR[c.status];
  const supplierCosts = c.costs.filter((x) =>
    ['DOWN_PAYMENT', 'BALANCE_PAYMENT', 'SUPPLIER_OTHER'].includes(x.category),
  );
  const otherCosts = c.costs.filter((x) =>
    ['FREIGHT', 'DUTY', 'TRUCKING', 'LABOR', 'OTHER'].includes(x.category),
  );
  const totalLines = c.lines.reduce((s, l) => s + l.qty, 0);

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      {/* Header */}
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>{c.ref}</Text>
          <Text style={styles.sub}>
            {c.supplier.name}
            {c.supplier.country ? ` · ${c.supplier.country}` : ''}
          </Text>
        </View>
        <View style={[styles.statusBadge, { backgroundColor: sc.bg }]}>
          <Text style={[styles.statusText, { color: sc.fg }]}>
            {t(`container.status.${c.status}`)}
          </Text>
        </View>
      </View>

      {/* Info */}
      <Card style={{ marginBottom: space.md }}>
        {c.reference ? (
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{t('container.reference')}</Text>
            <Text style={styles.infoValue}>{c.reference}</Text>
          </View>
        ) : null}
        {c.bolNumber ? (
          <>
            {c.reference ? <Divider /> : null}
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('container.bol')}</Text>
              <Text style={styles.infoValue}>{c.bolNumber}</Text>
            </View>
          </>
        ) : null}
        {c.etaAt ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('container.eta')}</Text>
              <Text style={styles.infoValue}>{shortDate(c.etaAt)}</Text>
            </View>
          </>
        ) : null}
        {c.arrivedAt ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('container.arrived')}</Text>
              <Text style={styles.infoValue}>{dateTime(c.arrivedAt)}</Text>
            </View>
          </>
        ) : null}
        {c.receivedAt ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('container.received')}</Text>
              <Text style={styles.infoValue}>{dateTime(c.receivedAt)}</Text>
            </View>
          </>
        ) : null}
        <Divider />
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('container.spread')}</Text>
          <Text style={styles.infoValue}>
            {c.costSpread}
            {c.isDDP ? ' · DDP' : ''}
          </Text>
        </View>
        <Divider />
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('inventoryCount.lines')}</Text>
          <Text style={styles.infoValue}>
            {t('container.skusTires', { skus: c.lines.length, tires: totalLines })}
          </Text>
        </View>
        {c.notes ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('workOrder.notes')}</Text>
              <Text style={styles.infoValue}>{c.notes}</Text>
            </View>
          </>
        ) : null}
      </Card>

      {/* Costs */}
      {supplierCosts.length > 0 ? (
        <>
          <Text style={styles.sectionTitle}>{t('container.supplierPayments')}</Text>
          <Card style={{ marginBottom: space.md }}>
            {supplierCosts.map((cost, i) => (
              <View key={cost.id}>
                {i > 0 ? <Divider /> : null}
                <View style={styles.costRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.costLabel}>
                      {t(CATEGORY_LABEL_KEYS[cost.category] ?? cost.category)}
                    </Text>
                    {cost.description ? (
                      <Text style={styles.costDesc} numberOfLines={1}>
                        {cost.description}
                      </Text>
                    ) : null}
                  </View>
                  <View style={{ alignItems: 'flex-end' }}>
                    <Text style={styles.costAmount}>{money(cost.amount)}</Text>
                    <View
                      style={[styles.costStatus, cost.status === 'PAID' ? styles.costPaid : null]}
                    >
                      <Text
                        style={[
                          styles.costStatusText,
                          cost.status === 'PAID' ? { color: colors.success } : null,
                        ]}
                      >
                        {cost.status === 'PAID'
                          ? t('container.paid', { amount: money(cost.amountPaid) })
                          : t('container.due')}
                      </Text>
                    </View>
                  </View>
                </View>
              </View>
            ))}
          </Card>
        </>
      ) : null}

      {otherCosts.length > 0 ? (
        <>
          <Text style={styles.sectionTitle}>{t('container.containerCosts')}</Text>
          <Card style={{ marginBottom: space.md }}>
            {otherCosts.map((cost, i) => (
              <View key={cost.id}>
                {i > 0 ? <Divider /> : null}
                <View style={styles.costRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.costLabel}>
                      {t(CATEGORY_LABEL_KEYS[cost.category] ?? cost.category)}
                    </Text>
                    {cost.vendor ? (
                      <Text style={styles.costDesc} numberOfLines={1}>
                        {cost.vendor}
                      </Text>
                    ) : null}
                  </View>
                  <View style={{ alignItems: 'flex-end' }}>
                    <Text style={styles.costAmount}>{money(cost.amount)}</Text>
                    <View
                      style={[styles.costStatus, cost.status === 'PAID' ? styles.costPaid : null]}
                    >
                      <Text
                        style={[
                          styles.costStatusText,
                          cost.status === 'PAID' ? { color: colors.success } : null,
                        ]}
                      >
                        {cost.status === 'PAID'
                          ? t('container.paid', { amount: money(cost.amountPaid) })
                          : t('container.due')}
                      </Text>
                    </View>
                  </View>
                </View>
              </View>
            ))}
          </Card>
        </>
      ) : null}

      {/* Lines */}
      <Text style={styles.sectionTitle}>{t('workOrder.lines')}</Text>
      <Card style={{ marginBottom: space.xl }}>
        {c.lines.length === 0 ? (
          <Empty message={t('container.noLines')} />
        ) : (
          c.lines.map((l, i) => (
            <View key={l.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.lineRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.lineSku} numberOfLines={1}>
                    {l.sku.sku}
                  </Text>
                  <Text style={styles.lineTire} numberOfLines={1}>
                    {l.sku.brand} {l.sku.model} · {l.sku.size}
                  </Text>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.lineQty}>
                    {l.qty} {t('container.tires')}
                  </Text>
                  <Text style={styles.lineCost}>
                    {money(l.unitCost)}
                    {t('container.ea')}
                    {l.landedUnitCost
                      ? ` → ${money(l.landedUnitCost)}${t('container.landed')}`
                      : ''}
                  </Text>
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
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: space.md },
  title: { fontSize: 20, fontWeight: '800', color: colors.text },
  sub: { fontSize: 14, color: colors.muted, marginTop: 2 },
  statusBadge: {
    borderRadius: radius.sm,
    paddingHorizontal: space.md,
    paddingVertical: 6,
  },
  statusText: { fontSize: 13, fontWeight: '700' },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  infoRow: { flexDirection: 'row', paddingVertical: space.sm },
  infoLabel: { fontSize: 14, color: colors.muted, width: 80 },
  infoValue: { fontSize: 14, fontWeight: '600', color: colors.text, flex: 1 },
  costRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  costLabel: { fontSize: 14, fontWeight: '600', color: colors.text },
  costDesc: { fontSize: 12, color: colors.muted, marginTop: 2 },
  costAmount: { fontSize: 15, fontWeight: '700', color: colors.text },
  costStatus: { marginTop: 2 },
  costPaid: {},
  costStatusText: { fontSize: 12, color: colors.warnText },
  lineRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  lineSku: { fontSize: 14, fontWeight: '700', color: colors.text },
  lineTire: { fontSize: 13, color: colors.muted, marginTop: 2 },
  lineQty: { fontSize: 14, fontWeight: '600', color: colors.text },
  lineCost: { fontSize: 12, color: colors.muted, marginTop: 2 },
});
