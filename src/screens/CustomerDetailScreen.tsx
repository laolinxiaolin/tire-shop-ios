import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import * as Clipboard from 'expo-clipboard';
import * as DocumentPicker from 'expo-document-picker';
import React, { useLayoutEffect, useState } from 'react';
import { Alert, Linking, Pressable, SectionList, StyleSheet, Text, View } from 'react-native';
import { Badge, Button, Card, ErrorView, Loading } from '../components/ui';
import { ApiError, Customer, customers, CustomerDocument, CustomerSaleSummary } from '../lib/api';
import { money, shortDate } from '../lib/format';
import { useI18n, type Translate } from '../lib/i18n';
import { formatUsPhone } from '../lib/phone';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

/** Map an edit-button tap to the params NewCustomer expects. */
function editParams(c: Customer) {
  return {
    edit: {
      id: c.id,
      name: c.name,
      company: c.company,
      phone: c.phone,
      email: c.email,
      address: c.address,
      notes: c.notes,
      taxExempt: c.taxExempt,
      taxExemptNumber: c.taxExemptNumber,
    },
  };
}

/** "11R22.5 Roadlux ×2 +1 more" — a one-line summary of the sale's items. */
function previewText(sale: CustomerSaleSummary, t: Translate): string {
  if (!sale.lines || sale.lines.length === 0) return t('customerDetail.noItems');
  const first = sale.lines[0];
  const base = `${first.description}${first.qty > 1 ? ` ×${first.qty}` : ''}`;
  const more = sale.lines.length - 1;
  return more > 0 ? `${base}  ${t('customerDetail.moreItems', { n: more })}` : base;
}

/** " (7.00%)" — empty if the rate isn't a usable number. */
function taxPctLabel(taxRate: string | undefined): string {
  const n = Number(taxRate);
  return Number.isFinite(n) ? ` (${(n * 100).toFixed(2)}%)` : '';
}

export default function CustomerDetailScreen() {
  const { id } = useRoute<RouteProp<RootStackParamList, 'CustomerDetail'>>().params;
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const { t } = useI18n();
  const qc = useQueryClient();
  const query = useQuery({ queryKey: ['customer', id], queryFn: () => customers.get(id) });
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const canManage = has('customers.manage');
  const canDelete = has('customers.delete');
  const customer = query.data;

  // "Edit" in the header (when allowed and loaded).
  useLayoutEffect(() => {
    nav.setOptions({
      headerRight: () =>
        canManage && customer ? (
          <Pressable onPress={() => nav.navigate('NewCustomer', editParams(customer))} hitSlop={8}>
            <Text style={styles.headerAction}>{t('customerDetail.edit')}</Text>
          </Pressable>
        ) : null,
    });
  }, [nav, canManage, customer, t]);

  const upload = useMutation({
    mutationFn: async () => {
      const res = await DocumentPicker.getDocumentAsync({
        type: ['application/pdf', 'image/jpeg', 'image/png'],
        copyToCacheDirectory: true,
      });
      if (res.canceled) return null;
      const a = res.assets[0];
      return customers.uploadDocument(
        id,
        { uri: a.uri, name: a.name, mimeType: a.mimeType ?? 'application/octet-stream' },
        'ST5_EXEMPTION',
      );
    },
    onSuccess: (doc) => {
      if (!doc) return; // user cancelled the picker
      qc.invalidateQueries({ queryKey: ['customer', id] });
      Alert.alert(t('customerDetail.uploaded'), t('customerDetail.uploadedBody'));
    },
    onError: (e) =>
      Alert.alert(
        t('customerDetail.uploadFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  const remove = useMutation({
    mutationFn: () => customers.remove(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['customers'] });
      nav.goBack();
    },
    onError: (e) =>
      Alert.alert(
        t('customerDetail.deleteFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  const confirmDelete = () =>
    Alert.alert(t('customerDetail.deleteTitle'), t('customerDetail.deleteBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      { text: t('common.delete'), style: 'destructive', onPress: () => remove.mutate() },
    ]);

  const toggle = (saleId: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      next.has(saleId) ? next.delete(saleId) : next.add(saleId);
      return next;
    });

  const copy = async (label: string, value: string) => {
    await Clipboard.setStringAsync(value);
    Alert.alert(t('customerDetail.copied'), t('customerDetail.copiedBody', { label }));
  };

  const call = (phone: string) =>
    Linking.openURL(`tel:${phone}`).catch(() =>
      Alert.alert(t('customerDetail.cannotCall'), t('customerDetail.cannotCallBody')),
    );

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;
  const c = query.data!;
  const pastSales = c.sales ?? [];
  const documents = c.documents ?? [];

  return (
    <SectionList<CustomerSaleSummary>
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ paddingBottom: space.xl }}
      refreshing={query.isRefetching}
      onRefresh={query.refetch}
      sections={[{ data: pastSales }]}
      keyExtractor={(s) => s.id}
      ListHeaderComponent={
        <View style={{ padding: space.lg }}>
          <Text style={styles.name}>{c.name}</Text>
          {c.company ? <Text style={styles.company}>{c.company}</Text> : null}

          <Card style={{ marginTop: space.lg }}>
            {c.phone ? (
              <View style={styles.info}>
                <Text style={styles.infoLabel}>{t('customerDetail.phone')}</Text>
                <View style={styles.phoneRight}>
                  <Text style={styles.infoValue}>{formatUsPhone(c.phone)}</Text>
                  <Pressable onPress={() => call(c.phone!)} style={styles.callBtn} hitSlop={6}>
                    <Text style={styles.callBtnText}>{t('customerDetail.call')}</Text>
                  </Pressable>
                </View>
              </View>
            ) : null}
            {c.email ? (
              <Pressable
                style={styles.info}
                onPress={() => copy(t('customerDetail.email'), c.email!)}
              >
                <Text style={styles.infoLabel}>{t('customerDetail.email')}</Text>
                <Text style={[styles.infoValue, styles.copyable]} numberOfLines={1}>
                  {c.email}
                </Text>
              </Pressable>
            ) : null}
            {c.address ? (
              <Pressable
                style={styles.info}
                onPress={() => copy(t('customerDetail.address'), c.address!)}
              >
                <Text style={styles.infoLabel}>{t('customerDetail.address')}</Text>
                <Text style={[styles.infoValue, styles.copyable]} numberOfLines={2}>
                  {c.address}
                </Text>
              </Pressable>
            ) : null}
            <Info
              label={t('customerDetail.taxExempt')}
              value={c.taxExempt ? t('common.yes') : t('common.no')}
            />
            {c.creditLimit ? (
              <Info label={t('customerDetail.creditLimit')} value={money(c.creditLimit)} />
            ) : null}
            <Info
              label={t('customerDetail.accountBilling')}
              value={c.accountEnabled ? t('customerDetail.enabled') : t('customerDetail.disabled')}
            />
            {c.email || c.address ? (
              <Text style={styles.copyHint}>{t('customerDetail.copyHint')}</Text>
            ) : null}
          </Card>

          {/* Documents — shown for tax-exempt customers (ST5 on file) */}
          {c.taxExempt || documents.length > 0 ? (
            <Card style={{ marginTop: space.md }}>
              <Text style={styles.cardTitle}>{t('customerDetail.documents')}</Text>
              {documents.length === 0 ? (
                <Text style={styles.docsEmpty}>{t('customerDetail.noDocuments')}</Text>
              ) : (
                documents.map((d) => (
                  <View key={d.id} style={styles.docRow}>
                    <Text style={styles.docName} numberOfLines={1}>
                      {d.filename}
                    </Text>
                    <Text style={styles.docMeta}>
                      {t(`customerDetail.docKind.${d.kind}`)} · {(d.sizeBytes / 1024).toFixed(0)} KB
                      · {shortDate(d.createdAt)}
                    </Text>
                  </View>
                ))
              )}
              {canManage && c.taxExempt ? (
                <View style={{ marginTop: space.md }}>
                  <Button
                    title={
                      upload.isPending
                        ? t('customerDetail.uploading')
                        : t('customerDetail.uploadSt5')
                    }
                    variant="secondary"
                    onPress={() => upload.mutate()}
                    loading={upload.isPending}
                  />
                  <Text style={styles.docsEmpty}>{t('customerDetail.fileTypes')}</Text>
                </View>
              ) : null}
            </Card>
          ) : null}

          {canDelete ? (
            <View style={{ marginTop: space.lg }}>
              <Button
                title={remove.isPending ? t('common.deleting') : t('customerDetail.deleteCustomer')}
                variant="danger"
                onPress={confirmDelete}
                loading={remove.isPending}
              />
              <Text style={styles.docsEmpty}>{t('customerDetail.deleteHint')}</Text>
            </View>
          ) : null}
        </View>
      }
      renderSectionHeader={() => (
        <Text style={styles.sectionHeader}>
          {pastSales.length
            ? t('customerDetail.pastSalesCount', { n: pastSales.length })
            : t('customerDetail.pastSales')}
        </Text>
      )}
      renderItem={({ item }) => (
        <PastSaleRow
          sale={item}
          expanded={expanded.has(item.id)}
          onToggle={() => toggle(item.id)}
          t={t}
        />
      )}
      renderSectionFooter={({ section }) =>
        section.data.length === 0 ? (
          <Text style={styles.empty}>{t('customerDetail.noPastSales')}</Text>
        ) : null
      }
    />
  );
}

function PastSaleRow({
  sale,
  expanded,
  onToggle,
  t,
}: {
  sale: CustomerSaleSummary;
  expanded: boolean;
  onToggle: () => void;
  t: Translate;
}) {
  return (
    <View style={styles.saleCard}>
      <Pressable
        style={styles.saleHeader}
        onPress={onToggle}
        android_ripple={{ color: colors.border }}
      >
        <View style={{ flex: 1, paddingRight: space.sm }}>
          <View style={styles.saleHeadTop}>
            <Text style={styles.saleNum}>{sale.ref}</Text>
            <Text style={styles.saleDate}>{shortDate(sale.createdAt)}</Text>
          </View>
          <Text style={styles.preview} numberOfLines={1}>
            {previewText(sale, t)}
          </Text>
        </View>
        <View style={styles.saleRight}>
          <Text style={styles.total}>{money(sale.total)}</Text>
          <Badge label={sale.status} text={t(`status.${sale.status}`)} />
        </View>
        <Text style={[styles.chevron, expanded ? styles.chevronOpen : null]}>▾</Text>
      </Pressable>

      {expanded ? (
        <View style={styles.body}>
          {(sale.lines ?? []).length === 0 ? (
            <Text style={styles.bodyEmpty}>{t('customerDetail.noItemDetails')}</Text>
          ) : (
            (sale.lines ?? []).map((l) => (
              <View key={l.id} style={styles.bodyLine}>
                <View style={{ flex: 1, paddingRight: space.sm }}>
                  <Text style={styles.bodyDesc}>{l.description}</Text>
                  <Text style={styles.bodyMeta}>
                    {l.qty} × {money(l.unitPrice)}
                    {Number(l.discount) > 0 ? ` · −${money(l.discount)}` : ''}
                    {l.itemType === 'SERVICE' ? t('saleDetail.serviceSuffix') : ''}
                  </Text>
                </View>
                <Text style={styles.bodyLineTotal}>{money(l.lineTotal)}</Text>
              </View>
            ))
          )}
          <View style={styles.bodyDivider} />
          <PriceRow label={t('saleDetail.subtotal')} value={money(sale.subtotal)} />
          <PriceRow
            label={`${t('customerDetail.tax')}${taxPctLabel(sale.taxRate)}`}
            value={money(sale.taxAmount)}
          />
          <PriceRow label={t('saleDetail.total')} value={money(sale.total)} strong />
        </View>
      ) : null}
    </View>
  );
}

function PriceRow({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <View style={styles.priceRow}>
      <Text style={[styles.priceLabel, strong ? styles.priceStrong : null]}>{label}</Text>
      <Text style={[styles.priceValue, strong ? styles.priceStrong : null]}>{value}</Text>
    </View>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.info}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  name: { fontSize: 24, fontWeight: '800', color: colors.text },
  company: { fontSize: 15, color: colors.muted, marginTop: 2 },
  info: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: space.sm,
  },
  infoLabel: { fontSize: 14, color: colors.muted },
  infoValue: {
    fontSize: 15,
    color: colors.text,
    fontWeight: '600',
    flexShrink: 1,
    textAlign: 'right',
    marginLeft: space.md,
  },
  copyable: { color: colors.primary },
  copyHint: { fontSize: 11, color: colors.muted, marginTop: space.sm, textAlign: 'right' },
  phoneRight: { flexDirection: 'row', alignItems: 'center', flexShrink: 1, marginLeft: space.md },
  callBtn: {
    marginLeft: space.md,
    paddingHorizontal: space.md,
    paddingVertical: 6,
    borderRadius: radius.sm,
    backgroundColor: colors.primary,
  },
  callBtnText: { color: colors.primaryText, fontWeight: '700', fontSize: 13 },
  headerAction: { color: colors.primary, fontWeight: '600', fontSize: 15 },
  cardTitle: { fontSize: 16, fontWeight: '700', color: colors.text, marginBottom: space.sm },
  docsEmpty: { fontSize: 13, color: colors.muted, marginTop: space.xs },
  docRow: {
    paddingVertical: space.sm,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  docName: { fontSize: 15, fontWeight: '600', color: colors.text },
  docMeta: { fontSize: 12, color: colors.muted, marginTop: 2 },
  sectionHeader: {
    fontSize: 12,
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    paddingHorizontal: space.lg,
    paddingVertical: space.sm,
    backgroundColor: colors.bg,
  },
  empty: { color: colors.muted, padding: space.lg },

  saleCard: {
    backgroundColor: colors.card,
    marginHorizontal: space.md,
    marginBottom: space.sm,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  saleHeader: { flexDirection: 'row', alignItems: 'center', padding: space.md },
  saleHeadTop: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  saleNum: { fontSize: 16, fontWeight: '700', color: colors.text },
  saleDate: { fontSize: 13, color: colors.muted },
  preview: { fontSize: 13, color: colors.muted, marginTop: 3 },
  saleRight: { alignItems: 'flex-end', marginRight: space.sm },
  total: { fontSize: 16, fontWeight: '700', color: colors.text, marginBottom: 4 },
  chevron: { fontSize: 16, color: colors.muted, width: 18, textAlign: 'center' },
  chevronOpen: { transform: [{ rotate: '180deg' }] },

  body: {
    paddingHorizontal: space.md,
    paddingBottom: space.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  bodyEmpty: { fontSize: 14, color: colors.muted, paddingTop: space.md, fontStyle: 'italic' },
  bodyLine: { flexDirection: 'row', alignItems: 'center', paddingTop: space.md },
  bodyDesc: { fontSize: 15, fontWeight: '600', color: colors.text },
  bodyMeta: { fontSize: 13, color: colors.muted, marginTop: 2 },
  bodyLineTotal: { fontSize: 15, fontWeight: '700', color: colors.text },
  bodyDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginVertical: space.md,
  },
  priceRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 2 },
  priceLabel: { fontSize: 14, color: colors.muted },
  priceValue: { fontSize: 14, color: colors.text },
  priceStrong: { fontSize: 16, fontWeight: '800', color: colors.text },
});
