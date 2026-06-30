import React, { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, Card, Field, KeyboardAwareScrollView } from '../components/ui';
import { ApiError, users } from '../lib/api';
import { LANGUAGES, useI18n } from '../lib/i18n';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

export default function ProfileScreen() {
  const { user, signOut, updateUser } = useAuth();
  const { t, lang, setLang } = useI18n();
  const [fullName, setFullName] = useState(user?.fullName ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  if (!user) return null;

  const trimmed = fullName.trim();
  const dirty = trimmed !== '' && trimmed !== user.fullName;
  const initials = user.fullName.slice(0, 1).toUpperCase();
  const mfaLabel =
    user.mfaMethod === 'TOTP'
      ? t('profile.mfaOnTotp')
      : user.mfaMethod === 'EMAIL'
        ? t('profile.mfaOnEmail')
        : t('profile.mfaOff');

  const save = async () => {
    setSaving(true);
    setSaved(false);
    setErr(null);
    try {
      await users.updateMe(trimmed);
      await updateUser({ fullName: trimmed });
      setFullName(trimmed);
      setSaved(true);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : t('profile.saveFailed'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <KeyboardAwareScrollView contentContainerStyle={styles.container}>
      <View style={styles.identity}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>{initials}</Text>
        </View>
        <Text style={styles.name}>{user.fullName}</Text>
        <Text style={styles.role}>{user.roleName}</Text>
      </View>

      <Text style={styles.section}>{t('profile.account')}</Text>
      <Card>
        <Field
          label={t('profile.displayName')}
          value={fullName}
          onChangeText={(v) => {
            setFullName(v);
            setSaved(false);
          }}
          maxLength={120}
          autoCapitalize="words"
        />
        <Field
          label={t('profile.email')}
          value={user.email}
          editable={false}
          style={styles.readonly}
        />
        <Field
          label={t('profile.role')}
          value={user.roleName}
          editable={false}
          style={styles.readonly}
        />
        <Text style={styles.note}>{t('profile.managedNote')}</Text>
        {err ? <Text style={styles.error}>{err}</Text> : null}
        {saved ? <Text style={styles.success}>{t('profile.saved')}</Text> : null}
        <View style={{ height: space.sm }} />
        <Button title={t('common.save')} onPress={save} loading={saving} disabled={!dirty} />
      </Card>

      <Text style={styles.section}>{t('profile.language')}</Text>
      <Card>
        <View style={styles.langRow}>
          {LANGUAGES.map((l) => {
            const active = l.code === lang;
            return (
              <Pressable
                key={l.code}
                onPress={() => setLang(l.code)}
                style={[styles.langChip, active ? styles.langChipActive : null]}
              >
                <Text style={[styles.langChipText, active ? styles.langChipTextActive : null]}>
                  {l.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
        <View style={{ height: space.sm }} />
        <Text style={styles.note}>{t('profile.languageNote')}</Text>
      </Card>

      <Text style={styles.section}>{t('profile.mfaTitle')}</Text>
      <Card>
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>{t('profile.mfaStatus')}</Text>
          <Text style={styles.statusValue}>{mfaLabel}</Text>
        </View>
        <Text style={styles.note}>{t('profile.mfaNote')}</Text>
      </Card>

      <View style={{ height: space.lg }} />
      <Button title={t('profile.signOut')} variant="danger" onPress={signOut} />
    </KeyboardAwareScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: space.lg, backgroundColor: colors.bg, flexGrow: 1 },
  identity: { alignItems: 'center', marginBottom: space.xl },
  avatar: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: space.sm,
  },
  avatarText: { color: colors.primaryText, fontSize: 26, fontWeight: '700' },
  name: { fontSize: 18, fontWeight: '700', color: colors.text },
  role: { fontSize: 14, color: colors.muted, marginTop: 2 },
  section: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    marginBottom: space.sm,
    letterSpacing: 0.3,
  },
  readonly: { color: colors.muted, backgroundColor: colors.bg },
  note: { color: colors.muted, fontSize: 13, lineHeight: 18 },
  error: { color: colors.danger, fontSize: 14, marginTop: space.sm },
  success: { color: colors.success, fontSize: 14, marginTop: space.sm },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: space.sm,
  },
  statusLabel: { fontSize: 15, color: colors.text, fontWeight: '600' },
  statusValue: { fontSize: 15, color: colors.muted },
  langRow: { flexDirection: 'row', gap: space.sm },
  langChip: {
    flex: 1,
    paddingVertical: space.md,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    backgroundColor: colors.bg,
    alignItems: 'center',
  },
  langChipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  langChipText: { fontSize: 15, color: colors.text, fontWeight: '600' },
  langChipTextActive: { color: colors.primaryText },
});
