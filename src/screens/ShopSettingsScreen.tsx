import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Button, Empty, ErrorView, KeyboardAwareScrollView, Loading } from '../components/ui';
import { settings, ApiError } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

type Tab = 'branding' | 'general' | 'mail';

export default function ShopSettingsScreen() {
  const { t } = useI18n();
  const [tab, setTab] = useState<Tab>('branding');

  return (
    <View style={styles.screen}>
      <View style={styles.tabs}>
        {(['branding', 'general', 'mail'] as Tab[]).map((tabKey) => (
          <Pressable
            key={tabKey}
            onPress={() => setTab(tabKey)}
            style={[styles.tab, tab === tabKey && styles.tabActive]}
          >
            <Text style={[styles.tabText, tab === tabKey && styles.tabTextActive]}>
              {tabKey === 'branding'
                ? t('shop.branding')
                : tabKey === 'general'
                  ? t('shop.general')
                  : t('shop.mail')}
            </Text>
          </Pressable>
        ))}
      </View>

      {tab === 'branding' && <BrandingTab />}
      {tab === 'general' && <GeneralTab />}
      {tab === 'mail' && <MailTab />}
    </View>
  );
}

function BrandingTab() {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['settings', 'branding'],
    queryFn: () => settings.branding(),
  });

  const [shopName, setShopName] = useState('');
  const [shopAddress, setShopAddress] = useState('');
  const [shopPhone, setShopPhone] = useState('');
  const [shopEmail, setShopEmail] = useState('');
  const [initialized, setInitialized] = useState(false);

  // NB: every hook must run before the loading/error early-returns below, or
  // the hook count changes when the query resolves and React crashes.
  const updateMut = useMutation({
    mutationFn: () => settings.updateBranding({ shopName, shopAddress, shopPhone, shopEmail }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'branding'] });
      Alert.alert(t('shop.saved'), t('shop.brandingUpdated'));
    },
    onError: (e: ApiError) => Alert.alert(t('common.error'), e.message),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const d = query.data!;
  if (!initialized) {
    setShopName(d.shopName ?? '');
    setShopAddress(d.shopAddress ?? '');
    setShopPhone(d.shopPhone ?? '');
    setShopEmail(d.shopEmail ?? '');
    setInitialized(true);
  }

  const dirty =
    shopName !== (d.shopName ?? '') ||
    shopAddress !== (d.shopAddress ?? '') ||
    shopPhone !== (d.shopPhone ?? '') ||
    shopEmail !== (d.shopEmail ?? '');

  return (
    <KeyboardAwareScrollView contentContainerStyle={styles.form}>
      {d.logoUrl && <Text style={styles.logoNote}>{t('shop.logoNote')}</Text>}
      <Field label={t('shop.shopName')} value={shopName} onChange={setShopName} />
      <Field label={t('shop.address')} value={shopAddress} onChange={setShopAddress} />
      <Field
        label={t('shop.phone')}
        value={shopPhone}
        onChange={setShopPhone}
        keyboardType="phone-pad"
      />
      <Field
        label={t('shop.email')}
        value={shopEmail}
        onChange={setShopEmail}
        keyboardType="email-address"
        autoCapitalize="none"
      />
      <Button
        title={updateMut.isPending ? t('shop.saving') : t('shop.saveBranding')}
        variant="primary"
        onPress={() => updateMut.mutate()}
        disabled={!dirty || updateMut.isPending}
      />
    </KeyboardAwareScrollView>
  );
}

function GeneralTab() {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['settings', 'general'],
    queryFn: () => settings.general(),
  });

  const [timezone, setTimezone] = useState('');
  const [initialized, setInitialized] = useState(false);

  const updateMut = useMutation({
    mutationFn: () => settings.updateGeneral({ timezone }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'general'] });
      Alert.alert(t('shop.saved'), t('shop.timezoneUpdated'));
    },
    onError: (e: ApiError) => Alert.alert(t('common.error'), e.message),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  if (!initialized) {
    setTimezone(query.data!.timezone);
    setInitialized(true);
  }

  const dirty = timezone !== query.data!.timezone;

  return (
    <KeyboardAwareScrollView contentContainerStyle={styles.form}>
      <Text style={styles.hint}>{t('shop.timezoneHint')}</Text>
      <Field
        label={t('shop.timezone')}
        value={timezone}
        onChange={setTimezone}
        autoCapitalize="none"
      />
      <Button
        title={updateMut.isPending ? t('shop.saving') : t('shop.saveTimezone')}
        variant="primary"
        onPress={() => updateMut.mutate()}
        disabled={!dirty || updateMut.isPending}
      />
    </KeyboardAwareScrollView>
  );
}

function MailTab() {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['settings', 'mail'],
    queryFn: () => settings.mail(),
  });

  const [host, setHost] = useState('');
  const [port, setPort] = useState('');
  const [secure, setSecure] = useState(false);
  const [user, setUser] = useState('');
  const [password, setPassword] = useState('');
  const [from, setFrom] = useState('');
  const [testEmail, setTestEmail] = useState('');
  const [initialized, setInitialized] = useState(false);

  // Hooks must run before the early-returns below (see BrandingTab note).
  const updateMut = useMutation({
    mutationFn: () =>
      settings.updateMail({
        host,
        port: Number(port),
        secure,
        user,
        password: password || undefined,
        from,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'mail'] });
      setPassword('');
      Alert.alert(t('shop.saved'), t('shop.mailUpdated'));
    },
    onError: (e: ApiError) => Alert.alert(t('common.error'), e.message),
  });

  const testMut = useMutation({
    mutationFn: () => settings.testMail(testEmail),
    onSuccess: () => Alert.alert(t('shop.saved'), t('shop.testSent', { email: testEmail })),
    onError: (e: ApiError) => Alert.alert(t('common.error'), e.message),
  });

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const d = query.data!;
  if (!initialized) {
    setHost(d.host);
    setPort(String(d.port));
    setSecure(d.secure);
    setUser(d.user);
    setFrom(d.from);
    setInitialized(true);
  }

  const dirty =
    host !== d.host ||
    port !== String(d.port) ||
    secure !== d.secure ||
    user !== d.user ||
    password !== '' ||
    from !== d.from;

  return (
    <KeyboardAwareScrollView contentContainerStyle={styles.form}>
      <Field label={t('shop.smtpHost')} value={host} onChange={setHost} autoCapitalize="none" />
      <Field label={t('shop.port')} value={port} onChange={setPort} keyboardType="numeric" />
      <Field label={t('shop.username')} value={user} onChange={setUser} autoCapitalize="none" />
      <Field
        label={t('shop.password')}
        value={password}
        onChange={setPassword}
        placeholder={d.hasPassword ? t('shop.passwordStored') : ''}
        secureTextEntry
      />
      <Field
        label={t('shop.fromAddress')}
        value={from}
        onChange={setFrom}
        autoCapitalize="none"
        keyboardType="email-address"
      />

      <Pressable style={styles.toggleRow} onPress={() => setSecure(!secure)}>
        <Text style={styles.fieldLabel}>{t('shop.useTls')}</Text>
        <View style={[styles.toggle, secure && styles.toggleOn]}>
          <View style={[styles.toggleKnob, secure && styles.toggleKnobOn]} />
        </View>
      </Pressable>

      <Button
        title={updateMut.isPending ? t('shop.saving') : t('shop.saveMail')}
        variant="primary"
        onPress={() => updateMut.mutate()}
        disabled={!dirty || updateMut.isPending}
      />

      <View style={styles.divider} />

      <Text style={styles.sectionTitle}>{t('shop.testEmail')}</Text>
      <Field
        label={t('shop.sendTestTo')}
        value={testEmail}
        onChange={setTestEmail}
        keyboardType="email-address"
        autoCapitalize="none"
      />
      <Button
        title={testMut.isPending ? t('shop.sending') : t('shop.sendTest')}
        variant="secondary"
        onPress={() => {
          if (!testEmail) {
            Alert.alert(t('common.error'), t('shop.enterEmail'));
            return;
          }
          testMut.mutate();
        }}
        disabled={testMut.isPending}
      />
    </KeyboardAwareScrollView>
  );
}

function Field({
  label,
  value,
  onChange,
  ...rest
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  [key: string]: unknown;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChange}
        placeholderTextColor={colors.muted}
        {...(rest as Record<string, unknown>)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  tabs: {
    flexDirection: 'row',
    margin: space.md,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  tab: {
    flex: 1,
    paddingVertical: space.sm + 2,
    alignItems: 'center',
    borderRadius: radius.md - 2,
  },
  tabActive: { backgroundColor: colors.primary },
  tabText: { fontSize: 14, fontWeight: '600', color: colors.muted },
  tabTextActive: { color: colors.primaryText },
  form: { padding: space.lg, gap: space.md, paddingBottom: space.xl },
  field: { gap: 4 },
  fieldLabel: { fontSize: 12, fontWeight: '700', color: colors.muted, textTransform: 'uppercase' },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    fontSize: 14,
    backgroundColor: colors.card,
    color: colors.text,
  },
  toggleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  toggle: {
    width: 44,
    height: 24,
    borderRadius: 12,
    backgroundColor: colors.border,
    justifyContent: 'center',
    paddingHorizontal: 2,
  },
  toggleOn: { backgroundColor: colors.primary },
  toggleKnob: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: '#fff',
    alignSelf: 'flex-start',
  },
  toggleKnobOn: { alignSelf: 'flex-end' },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginVertical: space.sm,
  },
  sectionTitle: { fontSize: 15, fontWeight: '700', color: colors.text },
  hint: { fontSize: 12, color: colors.muted, marginBottom: 4 },
  logoNote: { fontSize: 13, color: colors.muted, fontStyle: 'italic' },
});
