import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Badge, Empty, ErrorView, Loading, Row } from '../components/ui';
import { ApiError, workOrders, WorkOrderStatus } from '../lib/api';
import { shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const STATUSES: (WorkOrderStatus | 'ALL')[] = ['ALL', 'OPEN', 'IN_PROGRESS', 'DONE', 'CANCELLED'];

const STATUS_COLOR: Record<WorkOrderStatus, { bg: string; fg: string }> = {
  OPEN: { bg: '#ddf4ff', fg: '#0969da' },
  IN_PROGRESS: { bg: '#fff8c5', fg: '#7d4e00' },
  DONE: { bg: '#dafbe1', fg: '#1a7f37' },
  CANCELLED: { bg: '#ffebe9', fg: '#cf222e' },
};

function StatusBadge({ status }: { status: WorkOrderStatus }) {
  const { t } = useI18n();
  const c = STATUS_COLOR[status];
  return (
    <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
      <Text style={[styles.statusText, { color: c.fg }]}>{t(`workOrder.status.${status}`)}</Text>
    </View>
  );
}

export default function WorkOrdersListScreen() {
  const { t } = useI18n();
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const [status, setStatus] = useState<WorkOrderStatus | 'ALL'>('ALL');

  const query = useQuery({
    queryKey: ['work-orders', status],
    queryFn: () =>
      workOrders.list({
        status: status === 'ALL' ? undefined : status,
        pageSize: 50,
      }),
  });

  return (
    <View style={styles.screen}>
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
                  {s === 'ALL' ? t('workOrder.all') : t(`workOrder.status.${s}`)}
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
          keyExtractor={(wo) => wo.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('workOrder.empty')} />}
          renderItem={({ item }) => {
            const customerName =
              item.sale.customer?.company ?? item.sale.customer?.name ?? t('workOrder.unknown');
            const bayText = item.bay ? t('workOrder.bay', { n: item.bay }) : '—';
            const done = item.tasks.filter((task) => task.done).length;
            return (
              <Row
                title={`${customerName} · ${bayText}`}
                subtitle={`${t('workOrder.title', { n: item.sale.ref ?? '' })} · ${shortDate(item.createdAt)}`}
                onPress={() => nav.navigate('WorkOrderDetail', { id: item.id })}
                right={
                  <View style={{ alignItems: 'flex-end' }}>
                    <Text style={styles.taskCount}>
                      {t('workOrder.doneCount', { done, total: item.tasks.length })}
                    </Text>
                    <StatusBadge status={item.status} />
                  </View>
                }
              />
            );
          }}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  taskCount: { fontSize: 12, color: colors.muted, marginBottom: 4 },
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
  statusBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  statusText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
});
