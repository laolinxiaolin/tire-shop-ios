import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Badge, Button, Card } from '../components/ui';
import { money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { useQuote } from '../state/quote';
import { colors, space } from '../theme';
import { onHand } from './InventoryListScreen';

function Spec({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.spec}>
      <Text style={styles.specLabel}>{label}</Text>
      <Text style={styles.specValue}>{value}</Text>
    </View>
  );
}

export default function SkuDetailScreen() {
  const { sku: routeSku } = useRoute<RouteProp<RootStackParamList, 'SkuDetail'>>().params;
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const quote = useQuote();
  const { t } = useI18n();

  // Hold the SKU in the query cache so the edit/adjust screens can push updates
  // back here (and to the list) without a round-trip — there's no get-by-id API.
  const { data: sku = routeSku } = useQuery({
    queryKey: ['sku', routeSku.id],
    queryFn: () => routeSku,
    initialData: routeSku,
    staleTime: Infinity,
  });

  const stock = onHand(sku);
  const low = stock <= sku.reorderPoint;
  const canQuote = has('sales.manage');

  const addToQuote = () => {
    quote.addLine({
      itemType: 'SKU',
      itemId: sku.id,
      description: `${sku.brand} ${sku.model} ${sku.size} (${sku.position.replace('_', '-')})`,
      qty: 1,
      unitPrice: Number(sku.priceRetail),
    });
    Alert.alert(
      t('sku.addedToQuoteTitle'),
      t('sku.addedToQuoteBody', { name: `${sku.brand} ${sku.model} ${sku.size}` }),
      [
        { text: t('sku.keepBrowsing'), style: 'cancel' },
        { text: t('sku.goToQuote'), onPress: () => nav.navigate('Main', { screen: 'newQuote' }) },
      ],
    );
  };

  return (
    <ScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg }}
    >
      <Text style={styles.title}>{`${sku.size} · ${sku.brand}`}</Text>
      <Text style={styles.subtitle}>
        {sku.model} · {sku.sku}
      </Text>

      <Card style={{ marginTop: space.lg }}>
        <View style={styles.stockRow}>
          <View>
            <Text style={[styles.stockNum, low ? { color: colors.danger } : null]}>{stock}</Text>
            <Text style={styles.stockLabel}>{t('sku.unitsOnHand')}</Text>
          </View>
          {low ? <Badge label="LOW STOCK" text={t('sku.lowStock')} /> : null}
        </View>
        {sku.inventory.length > 0 ? (
          <View style={{ marginTop: space.md }}>
            {sku.inventory.map((i) => (
              <View key={i.id} style={styles.locRow}>
                <Text style={styles.locName}>{i.location}</Text>
                <Text style={styles.locQty}>
                  {t('sku.locOnHand', { n: i.qtyOnHand })}
                  {i.qtyReserved ? t('sku.locReserved', { n: i.qtyReserved }) : ''}
                </Text>
              </View>
            ))}
          </View>
        ) : null}
      </Card>

      <Card style={{ marginTop: space.md }}>
        <View style={styles.priceRow}>
          <Spec label={t('sku.retail')} value={money(sku.priceRetail)} />
          {has('inventory.view') ? (
            <Spec label={t('sku.cost')} value={money(sku.priceCost)} />
          ) : null}
        </View>
      </Card>

      <Card style={{ marginTop: space.md }}>
        <Spec label={t('sku.category')} value={t(`tire.category.${sku.category}`)} />
        <Spec label={t('sku.position')} value={t(`tire.position.${sku.position}`)} />
        {sku.segment ? <Spec label={t('sku.segment')} value={sku.segment} /> : null}
        <Spec label={t('sku.reorderPoint')} value={String(sku.reorderPoint)} />
        {sku.loadIndex ? <Spec label={t('sku.loadIndex')} value={sku.loadIndex} /> : null}
        {sku.pattern ? <Spec label={t('sku.pattern')} value={sku.pattern} /> : null}
        {sku.treadDepth32 ? (
          <Spec label={t('sku.treadDepth')} value={String(sku.treadDepth32)} />
        ) : null}
        {sku.maxLoadSingleLb != null ? (
          <Spec label={t('sku.maxLoad')} value={String(sku.maxLoadSingleLb)} />
        ) : null}
        {sku.weightLb ? <Spec label={t('sku.weight')} value={String(sku.weightLb)} /> : null}
        {sku.plyRating ? <Spec label={t('sku.plyRating')} value={sku.plyRating} /> : null}
      </Card>

      {canQuote ? (
        <View style={{ marginTop: space.lg }}>
          <Button title={t('sku.addToQuote')} onPress={addToQuote} />
        </View>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  title: { fontSize: 24, fontWeight: '800', color: colors.text },
  subtitle: { fontSize: 15, color: colors.muted, marginTop: 2 },
  stockRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  stockNum: { fontSize: 40, fontWeight: '800', color: colors.text },
  stockLabel: { fontSize: 13, color: colors.muted },
  locRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: space.xs },
  locName: { fontSize: 15, color: colors.text, fontWeight: '600' },
  locQty: { fontSize: 14, color: colors.muted },
  priceRow: { flexDirection: 'row', justifyContent: 'space-between' },
  spec: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: space.xs },
  specLabel: { fontSize: 14, color: colors.muted },
  specValue: { fontSize: 15, color: colors.text, fontWeight: '600' },
});
