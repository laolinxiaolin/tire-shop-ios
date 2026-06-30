import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { AddRow, Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import { ApiError, customers } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { useDebounced } from '../lib/hooks';
import { formatUsPhone } from '../lib/phone';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, space } from '../theme';

export default function CustomersListScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const { t } = useI18n();
  const [q, setQ] = useState('');
  const debounced = useDebounced(q);

  const query = useQuery({
    queryKey: ['customers', debounced],
    queryFn: () => customers.list({ q: debounced || undefined, pageSize: 50 }),
  });

  return (
    <View style={styles.screen}>
      {has('customers.manage') ? (
        <AddRow label={t('customers.new')} onPress={() => nav.navigate('NewCustomer')} />
      ) : null}
      <SearchBar value={q} onChangeText={setQ} placeholder={t('customers.search')} />
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
          ListEmptyComponent={<Empty message={t('customers.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={item.name}
              subtitle={
                [item.company, formatUsPhone(item.phone) || null].filter(Boolean).join(' · ') ||
                undefined
              }
              onPress={() => nav.navigate('CustomerDetail', { id: item.id, name: item.name })}
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
});
