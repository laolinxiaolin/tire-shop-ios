import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { Empty, ErrorView, Loading, Row } from '../components/ui';
import { activity, ApiError } from '../lib/api';
import { dateTime } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

export default function ActivityScreen() {
  const { t } = useI18n();
  const query = useQuery({
    queryKey: ['activity'],
    queryFn: () => activity.list({ pageSize: 100 }),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const items = query.data?.items ?? [];

  return (
    <FlatList
      style={styles.screen}
      data={items}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      keyExtractor={(a) => a.id}
      ItemSeparatorComponent={() => <View style={styles.sep} />}
      ListEmptyComponent={<Empty message={t('activity.empty')} />}
      renderItem={({ item: a }) => (
        <Row
          title={a.action}
          subtitle={`${a.entity}${a.entityId ? ` · ${a.entityId}` : ''}`}
          right={
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={styles.user}>{a.user?.fullName ?? t('activity.system')}</Text>
              <Text style={styles.date}>{dateTime(a.createdAt)}</Text>
            </View>
          }
        />
      )}
    />
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  user: { fontSize: 12, color: colors.muted, marginBottom: 2 },
  date: { fontSize: 11, color: colors.muted },
});
