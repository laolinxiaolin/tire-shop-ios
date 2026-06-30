import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Button, Empty, ErrorView, KeyboardAwareScrollView, Loading } from '../components/ui';
import { api, users, User, ApiError } from '../lib/api';
import { dateTime } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

type Role = { id: string; name: string; isSystem: boolean };

export default function UsersScreen() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  const listQuery = useQuery({
    queryKey: ['users'],
    queryFn: () => users.list(),
  });

  const rolesQuery = useQuery({
    queryKey: ['roles'],
    queryFn: () => api<Role[]>('/roles'),
  });

  if (listQuery.isLoading) return <Loading />;
  if (listQuery.isError)
    return (
      <ErrorView message={(listQuery.error as ApiError).message} onRetry={listQuery.refetch} />
    );

  const userList = listQuery.data ?? [];
  const roles = rolesQuery.data ?? [];

  return (
    <View style={styles.screen}>
      <FlatList
        data={userList}
        refreshing={listQuery.isRefetching}
        onRefresh={() => {
          listQuery.refetch();
          rolesQuery.refetch();
        }}
        keyExtractor={(u) => u.id}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
        ListEmptyComponent={<Empty message={t('users.empty')} />}
        ListHeaderComponent={
          <View style={styles.header}>
            <Text style={styles.headerTitle}>
              {t('users.title', { n: userList.length, plural: userList.length !== 1 ? 's' : '' })}
            </Text>
            <Button
              title={t('users.newUser')}
              variant="primary"
              onPress={() => setShowCreate(true)}
            />
          </View>
        }
        renderItem={({ item: u }) => (
          <UserRow
            user={u}
            roles={roles}
            expanded={editingId === u.id}
            onToggle={() => setEditingId(editingId === u.id ? null : u.id)}
            onUpdated={() => {
              queryClient.invalidateQueries({ queryKey: ['users'] });
              setEditingId(null);
            }}
          />
        )}
      />

      <CreateUserModal
        visible={showCreate}
        roles={roles}
        onClose={() => setShowCreate(false)}
        onCreated={() => {
          queryClient.invalidateQueries({ queryKey: ['users'] });
          setShowCreate(false);
        }}
      />
    </View>
  );
}

function UserRow({
  user: u,
  roles,
  expanded,
  onToggle,
  onUpdated,
}: {
  user: User;
  roles: Role[];
  expanded: boolean;
  onToggle: () => void;
  onUpdated: () => void;
}) {
  const { t } = useI18n();
  return (
    <View>
      <Pressable style={styles.row} onPress={onToggle}>
        <View style={{ flex: 1 }}>
          <Text style={styles.name}>{u.fullName}</Text>
          <Text style={styles.email}>{u.email}</Text>
          <View style={styles.badges}>
            <View style={[styles.badge, { backgroundColor: '#ddf4ff' }]}>
              <Text style={[styles.badgeText, { color: '#0969da' }]}>{u.roleName}</Text>
            </View>
            {!u.active && (
              <View style={[styles.badge, { backgroundColor: '#ffebe9' }]}>
                <Text style={[styles.badgeText, { color: '#cf222e' }]}>{t('users.inactive')}</Text>
              </View>
            )}
            {u.mfaMethod && (
              <View style={[styles.badge, { backgroundColor: '#dafbe1' }]}>
                <Text style={[styles.badgeText, { color: '#1a7f37' }]}>
                  {t('users.twoFA', { method: u.mfaMethod })}
                </Text>
              </View>
            )}
          </View>
        </View>
        <Text style={styles.expandIcon}>{expanded ? '▲' : '▼'}</Text>
      </Pressable>

      {expanded && <EditUserForm user={u} roles={roles} onUpdated={onUpdated} />}
    </View>
  );
}

function EditUserForm({
  user: u,
  roles,
  onUpdated,
}: {
  user: User;
  roles: Role[];
  onUpdated: () => void;
}) {
  const { t } = useI18n();
  const [fullName, setFullName] = useState(u.fullName);
  const [roleId, setRoleId] = useState(u.roleId);
  const [active, setActive] = useState(u.active);
  const [newPassword, setNewPassword] = useState('');
  const [busy, setBusy] = useState(false);

  const updateMut = useMutation({
    mutationFn: () =>
      users.update(u.id, {
        fullName: fullName !== u.fullName ? fullName : undefined,
        roleId: roleId !== u.roleId ? roleId : undefined,
        active: active !== u.active ? active : undefined,
      }),
    onSuccess: onUpdated,
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const resetPwMut = useMutation({
    mutationFn: () => users.resetPassword(u.id, newPassword),
    onSuccess: () => {
      Alert.alert(t('users.done'), t('users.passwordReset'));
      setNewPassword('');
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const resetMfaMut = useMutation({
    mutationFn: () => users.resetMfa(u.id),
    onSuccess: () => Alert.alert(t('users.done'), t('users.mfaReset')),
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const isSaving = updateMut.isPending || resetPwMut.isPending || resetMfaMut.isPending;

  return (
    <View style={styles.editForm}>
      <Text style={styles.fieldLabel}>{t('users.fullName')}</Text>
      <TextInput style={styles.input} value={fullName} onChangeText={setFullName} />

      <Text style={styles.fieldLabel}>{t('users.role')}</Text>
      <View style={styles.roleRow}>
        {roles.map((r) => (
          <Pressable
            key={r.id}
            onPress={() => setRoleId(r.id)}
            style={[styles.roleChip, roleId === r.id && styles.roleChipActive]}
          >
            <Text style={[styles.roleChipText, roleId === r.id && styles.roleChipTextActive]}>
              {r.name}
            </Text>
          </Pressable>
        ))}
      </View>

      <Pressable style={styles.toggleRow} onPress={() => setActive(!active)}>
        <Text style={styles.fieldLabel}>{t('users.active')}</Text>
        <View style={[styles.toggle, active && styles.toggleOn]}>
          <View style={[styles.toggleKnob, active && styles.toggleKnobOn]} />
        </View>
      </Pressable>

      <View style={styles.editActions}>
        <Button
          title={t('users.save')}
          variant="primary"
          onPress={() => updateMut.mutate()}
          disabled={isSaving}
        />
      </View>

      <View style={styles.dangerZone}>
        <Text style={styles.dangerTitle}>{t('users.resetPassword')}</Text>
        <View style={styles.resetRow}>
          <TextInput
            style={[styles.input, { flex: 1 }]}
            placeholder={t('users.newPasswordHint')}
            value={newPassword}
            onChangeText={setNewPassword}
            secureTextEntry
          />
          <Button
            title={t('users.reset')}
            variant="secondary"
            onPress={() => {
              if (newPassword.length < 8) {
                Alert.alert('Error', t('users.passwordTooShort'));
                return;
              }
              resetPwMut.mutate();
            }}
            disabled={isSaving}
          />
        </View>

        <View style={styles.mfaRow}>
          <View style={{ flex: 1 }}>
            <Text style={styles.dangerTitle}>{t('users.twoStepVerification')}</Text>
            <Text style={styles.mfaStatus}>
              {u.mfaMethod
                ? t('users.mfaEnabled', { method: u.mfaMethod })
                : t('users.mfaNotEnabled')}
            </Text>
          </View>
          {u.mfaMethod && (
            <Button
              title={t('users.resetMfa')}
              variant="danger"
              onPress={() => resetMfaMut.mutate()}
              disabled={isSaving}
            />
          )}
        </View>
      </View>
    </View>
  );
}

function CreateUserModal({
  visible,
  roles,
  onClose,
  onCreated,
}: {
  visible: boolean;
  roles: Role[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const { t } = useI18n();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [roleId, setRoleId] = useState(roles[0]?.id ?? '');

  const createMut = useMutation({
    mutationFn: () => users.create({ email, password, fullName, roleId }),
    onSuccess: () => {
      onCreated();
      setEmail('');
      setPassword('');
      setFullName('');
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  // Pick the first non-admin role as default when roles load
  React.useEffect(() => {
    const nonAdmin = roles.find((r) => !r.isSystem);
    if (nonAdmin) setRoleId(nonAdmin.id);
  }, [roles]);

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={styles.modal}>
        <View style={styles.modalHeader}>
          <Text style={styles.modalTitle}>{t('users.createTitle')}</Text>
          <Pressable onPress={onClose}>
            <Text style={styles.modalClose}>{t('approvals.cancel')}</Text>
          </Pressable>
        </View>

        <KeyboardAwareScrollView>
          <Text style={styles.fieldLabel}>{t('users.fullName')}</Text>
          <TextInput
            style={styles.input}
            value={fullName}
            onChangeText={setFullName}
            placeholder={t('users.namePlaceholder')}
          />

          <Text style={styles.fieldLabel}>{t('users.email')}</Text>
          <TextInput
            style={styles.input}
            value={email}
            onChangeText={setEmail}
            placeholder={t('users.emailPlaceholder')}
            autoCapitalize="none"
            keyboardType="email-address"
          />

          <Text style={styles.fieldLabel}>{t('users.password')}</Text>
          <TextInput
            style={styles.input}
            value={password}
            onChangeText={setPassword}
            placeholder={t('users.passwordPlaceholder')}
            secureTextEntry
          />

          <Text style={styles.fieldLabel}>{t('users.role')}</Text>
          <View style={styles.roleRow}>
            {roles.map((r) => (
              <Pressable
                key={r.id}
                onPress={() => setRoleId(r.id)}
                style={[styles.roleChip, roleId === r.id && styles.roleChipActive]}
              >
                <Text style={[styles.roleChipText, roleId === r.id && styles.roleChipTextActive]}>
                  {r.name}
                </Text>
              </Pressable>
            ))}
          </View>

          <View style={styles.createActions}>
            <Button
              title={createMut.isPending ? t('users.creating') : t('users.createUser')}
              variant="primary"
              onPress={() => {
                if (!email || !password || !fullName || !roleId) {
                  Alert.alert('Error', t('users.allFieldsRequired'));
                  return;
                }
                if (password.length < 8) {
                  Alert.alert('Error', t('users.passwordTooShort'));
                  return;
                }
                createMut.mutate();
              }}
              disabled={createMut.isPending}
            />
          </View>
        </KeyboardAwareScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: space.lg,
    backgroundColor: colors.card,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  headerTitle: { fontSize: 14, fontWeight: '600', color: colors.muted },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    padding: space.lg,
    backgroundColor: colors.card,
  },
  name: { fontSize: 16, fontWeight: '700', color: colors.text },
  email: { fontSize: 13, color: colors.muted, marginTop: 2 },
  badges: { flexDirection: 'row', gap: space.xs, marginTop: space.sm, flexWrap: 'wrap' },
  badge: {
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
  },
  badgeText: { fontSize: 11, fontWeight: '700' },
  expandIcon: { fontSize: 12, color: colors.muted, marginTop: 4 },
  editForm: {
    padding: space.lg,
    backgroundColor: colors.card,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
    gap: space.sm,
  },
  fieldLabel: { fontSize: 12, fontWeight: '700', color: colors.muted, textTransform: 'uppercase' },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    fontSize: 14,
    backgroundColor: colors.bg,
    color: colors.text,
  },
  roleRow: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
  roleChip: {
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderRadius: radius.md,
    backgroundColor: colors.bg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  roleChipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  roleChipText: { fontSize: 13, fontWeight: '600', color: colors.muted },
  roleChipTextActive: { color: colors.primaryText },
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
  editActions: { flexDirection: 'row', gap: space.sm, marginTop: space.sm },
  dangerZone: {
    marginTop: space.md,
    paddingTop: space.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
    gap: space.sm,
  },
  dangerTitle: { fontSize: 13, fontWeight: '700', color: colors.text },
  resetRow: { flexDirection: 'row', gap: space.sm, alignItems: 'center' },
  mfaRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  mfaStatus: { fontSize: 12, color: colors.muted, marginTop: 2 },
  modal: { flex: 1, backgroundColor: colors.bg, padding: space.lg },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: space.lg,
  },
  modalTitle: { fontSize: 20, fontWeight: '800', color: colors.text },
  modalClose: { fontSize: 15, color: colors.primary, fontWeight: '600' },
  createActions: { marginTop: space.lg },
});
