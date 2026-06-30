import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React, { useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AddRow, Empty, ErrorView, Loading, Row, SearchBar } from '../components/ui';
import { ApiError, customers } from '../lib/api';
import { useDebounced } from '../lib/hooks';
import { useI18n } from '../lib/i18n';
import { formatUsPhone } from '../lib/phone';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { useQuote } from '../state/quote';
import { colors, space } from '../theme';

export default function CustomerPickerScreen() {
  const { t } = useI18n();
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const quote = useQuote();
  const insets = useSafeAreaInsets();
  const [q, setQ] = useState('');
  const debounced = useDebounced(q);

  const query = useQuery({
    queryKey: ['customers', 'picker', debounced],
    queryFn: () => customers.list({ q: debounced || undefined, pageSize: 50 }),
  });

  return (
    <View style={styles.screen}>
      <SearchBar value={q} onChangeText={setQ} placeholder={t('customerPicker.search')} autoFocus />
      {has('customers.manage') ? (
        <AddRow
          label={t('customerPicker.newCustomer')}
          onPress={() => nav.navigate('NewCustomer', { forQuote: true })}
        />
      ) : null}
      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ paddingBottom: insets.bottom }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('customerPicker.empty')} />}
          renderItem={({ item }) => (
            <Row
              title={item.name}
              subtitle={
                [item.company, formatUsPhone(item.phone) || null].filter(Boolean).join(' · ') ||
                undefined
              }
              onPress={() => {
                quote.setCustomer({
                  id: item.id,
                  name: item.name,
                  company: item.company,
                  taxExempt: item.taxExempt,
                });
                nav.goBack();
              }}
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
