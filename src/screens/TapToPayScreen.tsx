import { useNavigation, useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import { useStripeTerminal } from '@stripe/stripe-terminal-react-native';
import type { Reader } from '@stripe/stripe-terminal-react-native';
import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  PermissionsAndroid,
  Platform,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { Button } from '../components/ui';
import { payments } from '../lib/api';
import { money } from '../lib/format';
import type { RootStackParamList } from '../navigation/types';
import { useI18n } from '../lib/i18n';
import { colors, space } from '../theme';

type Phase = 'preparing' | 'ready' | 'charging' | 'done' | 'error';

/** Stripe Terminal won't discover readers until location permission is granted
 *  at runtime (Android). iOS handles this through the entitlement flow. */
async function requestLocationPermission(
  t: (key: string, params?: Record<string, string | number>) => string,
): Promise<void> {
  if (Platform.OS !== 'android') return;
  const granted = await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
    {
      title: t('tapToPay.locationTitle'),
      message: t('tapToPay.locationMessage'),
      buttonPositive: 'OK',
    },
  );
  if (granted !== PermissionsAndroid.RESULTS.GRANTED) {
    throw new Error(t('tapToPay.locationRequired'));
  }
}

/**
 * In-person Tap to Pay (Android). Flow: initialize → discover the on-device
 * Tap-to-Pay reader → connect → create a card-present PaymentIntent on the
 * backend → collect (customer taps) → confirm. The webhook books it; we poll
 * the invoice's payments to confirm capture. Requires a real NFC device + a
 * dev build (the SDK is a native module).
 */
export default function TapToPayScreen() {
  const { invoiceId, amount } = useRoute<RouteProp<RootStackParamList, 'TapToPay'>>().params;
  const navigation = useNavigation();
  const { t } = useI18n();

  const [phase, setPhase] = useState<Phase>('preparing');
  const [msg, setMsg] = useState(t('tapToPay.initializing'));
  const locationId = useRef<string | null>(null);
  const connecting = useRef(false);

  const {
    initialize,
    discoverReaders,
    connectReader,
    connectedReader,
    retrievePaymentIntent,
    collectPaymentMethod,
    confirmPaymentIntent,
  } = useStripeTerminal({
    onUpdateDiscoveredReaders: (readers: Reader.Type[]) => {
      if (readers.length > 0) void connectTo(readers[0]);
    },
  });

  // Set up the reader on mount: init → resolve location → discover.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // The reader stays connected at the app level across visits — reuse it
        // instead of re-discovering (the SDK rejects discovery while connected).
        if (connectedReader) {
          setPhase('ready');
          setMsg(t('tapToPay.ready'));
          return;
        }

        const init = await initialize();
        if (init.error) throw new Error(init.error.message);

        // Stripe Terminal requires location permission to be granted at runtime
        // before discovering readers (Android).
        setMsg(t('tapToPay.locationPermission'));
        await requestLocationPermission(t);

        const { locationId: loc } = await payments.connectionToken();
        if (!loc) throw new Error(t('tapToPay.errNoLocation'));
        if (cancelled) return;
        locationId.current = loc;
        setMsg(t('tapToPay.looking'));
        const disc = await discoverReaders({ discoveryMethod: 'tapToPay' });
        if (disc.error) throw new Error(disc.error.message);
      } catch (e) {
        if (!cancelled) fail(e);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function connectTo(reader: Reader.Type) {
    if (connecting.current || connectedReader || !locationId.current) return;
    connecting.current = true;
    try {
      setMsg(t('tapToPay.connecting'));
      const res = await connectReader({
        discoveryMethod: 'tapToPay',
        reader,
        locationId: locationId.current,
        merchantDisplayName: 'Tire Shop',
      });
      if (res.error) throw new Error(res.error.message);
      setPhase('ready');
      setMsg(t('tapToPay.ready'));
    } catch (e) {
      connecting.current = false;
      fail(e);
    }
  }

  async function charge() {
    setPhase('charging');
    try {
      setMsg(t('tapToPay.creating'));
      const intent = await payments.terminalIntent(invoiceId);
      if (!intent.clientSecret) throw new Error(t('tapToPay.errNoPayment'));

      const retrieved = await retrievePaymentIntent(intent.clientSecret);
      if (retrieved.error || !retrieved.paymentIntent) {
        throw new Error(retrieved.error?.message ?? t('tapToPay.errLoadFailed'));
      }

      setMsg(t('tapToPay.holdCard'));
      const collected = await collectPaymentMethod({ paymentIntent: retrieved.paymentIntent });
      if (collected.error || !collected.paymentIntent) {
        throw new Error(collected.error?.message ?? t('tapToPay.errCardNotRead'));
      }

      setMsg(t('tapToPay.processing'));
      const confirmed = await confirmPaymentIntent({ paymentIntent: collected.paymentIntent });
      if (confirmed.error) throw new Error(confirmed.error.message);

      setMsg(t('tapToPay.confirming'));
      const booked = await pollBooked(intent.paymentIntentId);
      setPhase('done');
      setMsg(booked ? t('tapToPay.captured') : t('tapToPay.charged'));
    } catch (e) {
      fail(e);
    }
  }

  /** Poll the invoice's payments until the webhook books this PaymentIntent. */
  async function pollBooked(paymentIntentId: string): Promise<boolean> {
    const deadline = Date.now() + 30_000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 2000));
      try {
        const ps = await payments.invoicePayments(invoiceId);
        if (ps.some((p) => p.externalId === paymentIntentId)) return true;
      } catch {
        /* keep polling */
      }
    }
    return false;
  }

  function fail(e: unknown) {
    setPhase('error');
    setMsg(e instanceof Error ? e.message : String(e));
  }

  const busy = phase === 'preparing' || phase === 'charging';

  return (
    <View style={styles.container}>
      <Text style={styles.amount}>{money(amount)}</Text>
      <Text style={styles.sub}>{t('tapToPay.cardFee')}</Text>

      <View style={styles.status}>
        {busy ? <ActivityIndicator color={colors.primary} /> : null}
        <Text
          style={[
            styles.msg,
            phase === 'error' ? { color: colors.danger } : null,
            phase === 'done' ? { color: colors.primary } : null,
          ]}
        >
          {msg}
        </Text>
      </View>

      <View style={styles.actions}>
        {phase === 'ready' && (
          <Button title={t('tapToPay.charge', { amount: money(amount) })} onPress={charge} />
        )}
        {phase === 'done' && (
          <Button
            title={t('tapToPay.done')}
            onPress={() => navigation.goBack()}
            variant="secondary"
          />
        )}
        {phase === 'error' && (
          <Button
            title={t('tapToPay.back')}
            onPress={() => navigation.goBack()}
            variant="secondary"
          />
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: space.lg, alignItems: 'center' },
  amount: { fontSize: 40, fontWeight: '800', color: colors.text, marginTop: space.lg },
  sub: { fontSize: 14, color: colors.muted, marginTop: 4 },
  status: { flexDirection: 'row', alignItems: 'center', gap: space.sm, marginTop: space.lg * 2 },
  msg: { fontSize: 16, color: colors.text, textAlign: 'center', flexShrink: 1 },
  actions: { marginTop: space.lg * 2, width: '100%', gap: space.md },
});
