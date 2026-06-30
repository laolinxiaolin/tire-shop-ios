import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Empty, ErrorView, Loading, Row } from '../components/ui';
import { ApiError, containers, ContainerStatus } from '../lib/api';
import { shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const STATUSES: (ContainerStatus | 'ALL')[] = [
  'ALL',
  'DRAFT',
  'ORDERED',
  'IN_TRANSIT',
  'ARRIVED',
  'RECEIVED',
  'CANCELLED',
];

const STATUS_COLOR: Record<ContainerStatus, { bg: string; fg: string }> = {
  DRAFT: { bg: '#eceef1', fg: '#57606a' },
  ORDERED: { bg: '#ddf4ff', fg: '#0969da' },
  IN_TRANSIT: { bg: '#fff8c5', fg: '#7d4e00' },
  ARRIVED: { bg: '#fff4e5', fg: '#9a6700' },
  RECEIVED: { bg: '#dafbe1', fg: '#1a7f37' },
  CANCELLED: { bg: '#ffebe9', fg: '#cf222e' },
};

function StatusBadge({ status, t }: { status: ContainerStatus; t: (key: string) => string }) {
  const c = STATUS_COLOR[status];
  return (
    <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
      <Text style={[styles.statusText, { color: c.fg }]}>{t(`container.status.${status}`)}</Text>
    </View>
  );
}

export default function PurchasingScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { t } = useI18n();
  const [status, setStatus] = useState<ContainerStatus | 'ALL'>('ALL');

  const query = useQuery({
    queryKey: ['containers', status],
    queryFn: () =>
      containers.list({
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
                  {s === 'ALL' ? t('container.all') : t(`container.status.${s}`)}
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
          keyExtractor={(c) => c.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('container.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.ref} · ${item.supplier.name}`}
              subtitle={`${item.reference ?? t('container.noRef')}${item.bolNumber ? ` · BOL ${item.bolNumber}` : ''} · ${shortDate(item.createdAt)}`}
              onPress={() => nav.navigate('ContainerDetail', { id: item.id })}
              right={
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.lineCount}>
                    {t('container.lines', { n: item._count?.lines ?? item.lines?.length ?? 0 })}
                    {item.isDDP ? ' · DDP' : ''}
                  </Text>
                  <StatusBadge status={item.status} t={t} />
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
  lineCount: { fontSize: 12, color: colors.muted, marginBottom: 4 },
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
