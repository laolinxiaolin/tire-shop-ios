import React, { useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { Button, Field } from '../components/ui';
import { ApiError } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { useAuth } from '../state/auth';
import { colors, space } from '../theme';

export default function LoginScreen() {
  const { signIn, completeMfa } = useAuth();
  const { t } = useI18n();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);

  // MFA second step
  const [challenge, setChallenge] = useState<{ method: string; token: string } | null>(null);
  const [code, setCode] = useState('');

  const fail = (e: unknown) =>
    Alert.alert(t('login.failedTitle'), e instanceof ApiError ? e.message : t('login.failedBody'));

  const submitCredentials = async () => {
    if (!email.trim() || !password) return;
    setBusy(true);
    try {
      const res = await signIn(email.trim(), password);
      if (res.kind === 'mfa') {
        setChallenge({ method: res.method, token: res.challengeToken });
        setCode('');
      }
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };

  const submitCode = async () => {
    if (!challenge || code.trim().length < 6) return;
    setBusy(true);
    try {
      const res = await completeMfa(challenge.token, code.trim());
      if (res.usedBackupCode) {
        Alert.alert(
          t('login.backupUsedTitle'),
          t('login.backupUsedBody', { count: res.backupCodesRemaining ?? 0 }),
        );
      }
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
        <Text style={styles.brand}>{t('app.name')}</Text>
        <Text style={styles.sub}>{t('login.subtitle')}</Text>

        {!challenge ? (
          <View style={styles.form}>
            <Field
              label={t('login.email')}
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              autoComplete="email"
              placeholder="you@tireshop.local"
              editable={!busy}
            />
            <Field
              label={t('login.password')}
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              placeholder="••••••••"
              editable={!busy}
              onSubmitEditing={submitCredentials}
            />
            <Button
              title={t('login.signIn')}
              onPress={submitCredentials}
              loading={busy}
              disabled={!email.trim() || !password}
            />
          </View>
        ) : (
          <View style={styles.form}>
            <Text style={styles.hint}>
              {challenge.method === 'EMAIL' ? t('login.mfaEmailHint') : t('login.mfaTotpHint')}{' '}
              {t('login.mfaBackupHint')}
            </Text>
            <Field
              label={t('login.code')}
              value={code}
              onChangeText={setCode}
              keyboardType="number-pad"
              placeholder="123456"
              autoFocus
              editable={!busy}
              onSubmitEditing={submitCode}
            />
            <Button
              title={t('login.verify')}
              onPress={submitCode}
              loading={busy}
              disabled={code.trim().length < 6}
            />
            <View style={{ height: space.sm }} />
            <Button
              title={t('common.back')}
              variant="secondary"
              onPress={() => setChallenge(null)}
              disabled={busy}
            />
          </View>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: space.xl,
    backgroundColor: colors.bg,
  },
  brand: { fontSize: 32, fontWeight: '800', color: colors.text, textAlign: 'center' },
  sub: { fontSize: 15, color: colors.muted, textAlign: 'center', marginBottom: space.xl },
  form: { marginTop: space.lg },
  hint: { color: colors.muted, marginBottom: space.md, lineHeight: 20 },
});
