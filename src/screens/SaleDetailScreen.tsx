import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Badge, Button, Card, Divider, ErrorView, Field, Loading } from '../components/ui';
import { PaymentSheet } from '../components/PaymentSheet';
import { ApiError, downloadAndShare, invoices, payments, sales } from '../lib/api';
import { money, dateTime } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

function TotalRow({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <View style={styles.totalRow}>
      <Text style={[styles.totalLabel, strong ? styles.strong : null]}>{label}</Text>
      <Text style={[styles.totalValue, strong ? styles.strong : null]}>{value}</Text>
    </View>
  );
}

export default function SaleDetailScreen() {
  const { id } = useRoute<RouteProp<RootStackParamList, 'SaleDetail'>>().params;
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { has } = useAuth();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const canPay = has('payments.collect');
  const canManage = has('sales.manage');
  const [showPay, setShowPay] = useState(false);
  const [showEmail, setShowEmail] = useState(false);
  const [emailTo, setEmailTo] = useState('');

  const query = useQuery({ queryKey: ['sale', id], queryFn: () => sales.get(id) });
  const gateway = useQuery({
    queryKey: ['gateway-status'],
    queryFn: () => payments.gatewayStatus(),
    staleTime: 5 * 60_000,
  });

  const invoiceId = query.data?.invoice?.id;
  const paymentsQ = useQuery({
    queryKey: ['invoice-payments', invoiceId],
    queryFn: () => payments.invoicePayments(invoiceId!),
    enabled: !!invoiceId,
  });

  const refreshAll = () => {
    qc.invalidateQueries({ queryKey: ['sale', id] });
    qc.invalidateQueries({ queryKey: ['sales'] });
    if (invoiceId) qc.invalidateQueries({ queryKey: ['invoice-payments', invoiceId] });
  };

  // One mutation drives every status transition; `run` picks the call + confirm copy.
  const action = useMutation({
    mutationFn: (fn: () => Promise<unknown>) => fn(),
    onSuccess: () => refreshAll(),
    onError: (e) =>
      Alert.alert(
        t('saleDetail.actionFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  // Download the invoice PDF and hand it to the OS share/print sheet.
  const sharePdf = useMutation({
    mutationFn: () => {
      const inv = query.data?.invoice;
      if (!inv) throw new ApiError(0, t('common.error'));
      const filename = `invoice-${inv.ref ?? inv.id}.pdf`;
      return downloadAndShare(invoices.pdfPath(inv.id), filename, 'application/pdf');
    },
    onError: (e) =>
      Alert.alert(t('saleDetail.pdfFailed'), e instanceof ApiError ? e.message : t('common.error')),
  });

  // Email the invoice PDF (server uses the customer's email when `to` is blank).
  const sendEmail = useMutation({
    mutationFn: () => {
      const inv = query.data?.invoice;
      if (!inv) throw new ApiError(0, t('common.error'));
      return invoices.email(inv.id, { to: emailTo.trim() || undefined });
    },
    onSuccess: (res) => {
      setShowEmail(false);
      setEmailTo('');
      Alert.alert(t('saleDetail.emailSentTitle'), t('saleDetail.emailSentBody', { to: res.to }));
    },
    onError: (e) =>
      Alert.alert(
        t('saleDetail.emailFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;
  const sale = query.data!;

  const balance = sale.invoice
    ? +(Number(sale.invoice.amountDue) - Number(sale.invoice.paidTotal)).toFixed(2)
    : 0;
  const canTapToPay = !!sale.invoice && balance > 0.005 && !!gateway.data?.enabled;
  const paymentList = paymentsQ.data ?? [];

  return (
    <ScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg, paddingBottom: space.lg + insets.bottom }}
      refreshControl={
        <RefreshControl
          refreshing={query.isRefetching}
          onRefresh={() => {
            query.refetch();
            paymentsQ.refetch();
          }}
        />
      }
    >
      <View style={styles.header}>
        <View>
          <Text style={styles.number}>{sale.ref}</Text>
          <Text style={styles.date}>{dateTime(sale.createdAt)}</Text>
        </View>
        <Badge label={sale.status} text={t(`status.${sale.status}`)} />
      </View>

      <Card style={{ marginTop: space.lg }}>
        <Text style={styles.sectionLabel}>{t('saleDetail.customer')}</Text>
        <Text style={styles.customerName}>{sale.customer?.name ?? t('sales.unknownCustomer')}</Text>
        {sale.customer?.company ? (
          <Text style={styles.company}>{sale.customer.company}</Text>
        ) : null}
      </Card>

      <Card style={{ marginTop: space.md, padding: 0 }}>
        {sale.lines.map((l, idx) => (
          <View key={l.id}>
            {idx > 0 ? <Divider /> : null}
            <View style={styles.line}>
              <View style={{ flex: 1, paddingRight: space.sm }}>
                <Text style={styles.lineDesc}>{l.description}</Text>
                <Text style={styles.lineMeta}>
                  {l.qty} × {money(l.unitPrice)}
                  {Number(l.discount) > 0 ? ` · −${money(l.discount)}` : ''}
                  {l.itemType === 'SERVICE' ? t('saleDetail.serviceSuffix') : ''}
                </Text>
              </View>
              <Text style={styles.lineTotal}>{money(l.lineTotal)}</Text>
            </View>
          </View>
        ))}
      </Card>

      <Card style={{ marginTop: space.md }}>
        <TotalRow label={t('saleDetail.subtotal')} value={money(sale.subtotal)} />
        <TotalRow
          label={t('saleDetail.tax', { rate: (Number(sale.taxRate) * 100).toFixed(2) })}
          value={money(sale.taxAmount)}
        />
        <TotalRow label={t('saleDetail.total')} value={money(sale.total)} strong />
        {sale.invoice ? (
          <>
            <View style={{ height: space.sm }} />
            <TotalRow label={t('saleDetail.paid')} value={money(sale.invoice.paidTotal)} />
            <TotalRow label={t('saleDetail.balance')} value={money(balance)} />
            {balance > 0.005 && canPay && (
              <>
                <View style={{ height: space.md }} />
                <Button
                  title={t('saleDetail.takePayment', { amount: money(balance) })}
                  onPress={() => setShowPay(true)}
                />
              </>
            )}
            {canTapToPay && canPay && (
              <>
                <View style={{ height: space.sm }} />
                <Button
                  title={t('saleDetail.tapToPay', { amount: money(balance) })}
                  variant="secondary"
                  onPress={() =>
                    navigation.navigate('TapToPay', {
                      invoiceId: sale.invoice!.id,
                      amount: balance,
                    })
                  }
                />
              </>
            )}
          </>
        ) : null}
      </Card>

      {sale.invoice && (
        <Card style={{ marginTop: space.md }}>
          <Text style={styles.sectionLabel}>{t('saleDetail.invoiceActions')}</Text>
          <View style={{ height: space.md }} />
          <Button
            title={t('saleDetail.sharePdf')}
            variant="secondary"
            onPress={() => sharePdf.mutate()}
            loading={sharePdf.isPending}
            disabled={sharePdf.isPending}
          />
          {canManage && (
            <>
              <View style={{ height: space.sm }} />
              <Button
                title={t('saleDetail.emailInvoice')}
                variant="secondary"
                onPress={() => {
                  setEmailTo('');
                  setShowEmail(true);
                }}
              />
            </>
          )}
        </Card>
      )}

      {sale.status === 'DRAFT' && (
        <Card style={{ marginTop: space.md }}>
          <Text style={styles.actionNote}>{t('saleDetail.draftNote')}</Text>
          {canManage && (
            <>
              <View style={{ height: space.md }} />
              <Button
                title={t('saleDetail.editDraft')}
                variant="secondary"
                onPress={() => navigation.navigate('EditSale', { id })}
                disabled={action.isPending}
              />
            </>
          )}
          <View style={{ height: space.md }} />
          <Button
            title={t('saleDetail.confirmInvoice')}
            onPress={() => action.mutate(() => sales.confirm(id))}
            loading={action.isPending}
            disabled={action.isPending}
          />
        </Card>
      )}

      {sale.status === 'QUOTE' && (
        <Card style={{ marginTop: space.md }}>
          <Text style={styles.actionNote}>{t('saleDetail.quoteNote')}</Text>
          <View style={{ height: space.md }} />
          <Button
            title={t('saleDetail.confirmInvoice')}
            onPress={() => action.mutate(() => sales.confirm(id))}
            loading={action.isPending}
            disabled={action.isPending}
          />
        </Card>
      )}

      {paymentList.length > 0 && (
        <Card style={{ marginTop: space.md, padding: 0 }}>
          <Text style={[styles.sectionLabel, { padding: space.lg, paddingBottom: space.sm }]}>
            {t('saleDetail.payments')}
          </Text>
          {paymentList.map((p, idx) => (
            <View key={p.id}>
              {idx > 0 ? <Divider /> : null}
              <View style={styles.payRow}>
                <View style={{ flex: 1, paddingRight: space.sm }}>
                  <Text style={styles.payAmount}>{money(p.amount)}</Text>
                  <Text style={styles.payMeta}>
                    {p.paymentMethod?.name ??
                      (p.processor ? t('saleDetail.card') : t('saleDetail.payment'))}
                    {p.createdAt ? ` · ${dateTime(p.createdAt)}` : ''}
                    {[p.reference, p.note].filter(Boolean).length
                      ? ` · ${[p.reference, p.note].filter(Boolean).join(' · ')}`
                      : ''}
                  </Text>
                </View>
              </View>
            </View>
          ))}
        </Card>
      )}

      {sale.invoice && (
        <PaymentSheet
          visible={showPay}
          invoiceId={sale.invoice.id}
          balance={balance}
          customerId={sale.customerId}
          onClose={() => setShowPay(false)}
          onPaid={() => {
            setShowPay(false);
            refreshAll();
          }}
        />
      )}

      {sale.invoice && (
        <Modal
          visible={showEmail}
          animationType="fade"
          transparent
          onRequestClose={() => setShowEmail(false)}
        >
          <KeyboardAvoidingView
            style={{ flex: 1 }}
            behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          >
            <Pressable style={styles.emailBackdrop} onPress={() => setShowEmail(false)}>
              <Pressable style={styles.emailCard} onPress={() => {}}>
                <Text style={styles.emailTitle}>{t('saleDetail.emailTitle')}</Text>
                <View style={{ height: space.md }} />
                <Field
                  label={t('saleDetail.emailToLabel')}
                  value={emailTo}
                  onChangeText={setEmailTo}
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoCorrect={false}
                  placeholder={t('saleDetail.emailToPlaceholder')}
                  editable={!sendEmail.isPending}
                  onSubmitEditing={() => sendEmail.mutate()}
                />
                <Text style={styles.emailHint}>{t('saleDetail.emailHint')}</Text>
                <View style={{ height: space.md }} />
                <Button
                  title={
                    sendEmail.isPending ? t('saleDetail.emailSending') : t('saleDetail.emailSend')
                  }
                  onPress={() => sendEmail.mutate()}
                  loading={sendEmail.isPending}
                  disabled={sendEmail.isPending}
                />
                <View style={{ height: space.sm }} />
                <Button
                  title={t('common.cancel')}
                  variant="secondary"
                  onPress={() => setShowEmail(false)}
                  disabled={sendEmail.isPending}
                />
              </Pressable>
            </Pressable>
          </KeyboardAvoidingView>
        </Modal>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  number: { fontSize: 24, fontWeight: '800', color: colors.text },
  date: { fontSize: 14, color: colors.muted, marginTop: 2 },
  sectionLabel: {
    fontSize: 12,
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
  },
  customerName: { fontSize: 18, fontWeight: '700', color: colors.text, marginTop: 4 },
  company: { fontSize: 14, color: colors.muted, marginTop: 2 },
  line: { flexDirection: 'row', alignItems: 'center', padding: space.lg },
  lineDesc: { fontSize: 15, fontWeight: '600', color: colors.text },
  lineMeta: { fontSize: 13, color: colors.muted, marginTop: 2 },
  lineTotal: { fontSize: 15, fontWeight: '700', color: colors.text },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3 },
  totalLabel: { fontSize: 15, color: colors.muted },
  totalValue: { fontSize: 15, color: colors.text },
  strong: { fontSize: 17, fontWeight: '800', color: colors.text },
  payRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: space.lg,
    paddingBottom: space.lg,
  },
  payAmount: { fontSize: 15, fontWeight: '700', color: colors.text },
  payMeta: { fontSize: 13, color: colors.muted, marginTop: 2 },
  reverseText: { fontSize: 14, color: colors.danger, fontWeight: '600' },
  pendingBadge: {
    paddingHorizontal: space.sm,
    paddingVertical: 4,
    borderRadius: radius.sm,
    backgroundColor: colors.warnBg,
  },
  pendingText: { fontSize: 11, color: colors.warnText, fontWeight: '700' },
  actionNote: { fontSize: 14, color: colors.muted, lineHeight: 20 },
  emailBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.4)',
    justifyContent: 'center',
    padding: space.xl,
  },
  emailCard: {
    backgroundColor: colors.card,
    borderRadius: radius.lg,
    padding: space.lg,
  },
  emailTitle: { fontSize: 18, fontWeight: '700', color: colors.text },
  emailHint: { fontSize: 12, color: colors.muted, marginTop: space.xs },
  voidPendingTitle: { fontSize: 15, fontWeight: '700', color: colors.warnText },
  voidPendingBody: { fontSize: 13, color: colors.muted, marginTop: 4 },
});
