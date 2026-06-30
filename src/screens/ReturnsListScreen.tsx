import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Badge, Empty, ErrorView, Loading, Row } from '../components/ui';
import { ApiError, returns, ReturnStatus, ReturnType } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const STATUSES: (ReturnStatus | 'ALL')[] = ['ALL', 'DRAFT', 'POSTED', 'VOIDED'];

const STATUS_COLOR: Record<ReturnStatus, { bg: string; fg: string }> = {
  DRAFT: { bg: '#eceef1', fg: '#57606a' },
  POSTED: { bg: '#dafbe1', fg: '#1a7f37' },
  VOIDED: { bg: '#ffebe9', fg: '#cf222e' },
};

function StatusBadge({ status }: { status: ReturnStatus }) {
  const { t } = useI18n();
  const c = STATUS_COLOR[status];
  return (
    <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
      <Text style={[styles.statusText, { color: c.fg }]}>{t(`return.status.${status}`)}</Text>
    </View>
  );
}

export default function ReturnsListScreen() {
  const { t } = useI18n();
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const [status, setStatus] = useState<ReturnStatus | 'ALL'>('ALL');

  const query = useQuery({
    queryKey: ['returns', status],
    queryFn: () =>
      returns.list({
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
                  {s === 'ALL' ? t('returns.all') : t(`return.status.${s}`)}
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
          keyExtractor={(r) => r.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('returns.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={`${item.ref} · ${item.sale?.customer?.company ?? item.sale?.customer?.name ?? t('returns.unknown')}`}
              subtitle={`${t(`return.type.${item.type}`)} · ${shortDate(item.createdAt)} · Sale ${item.sale?.ref ?? '—'}`}
              onPress={() => nav.navigate('SaleDetail', { id: item.saleId })}
              right={
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.total}>{money(item.refundTotal)}</Text>
                  <StatusBadge status={item.status} />
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
  statusBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  statusText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
});
