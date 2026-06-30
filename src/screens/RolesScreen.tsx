import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import {
  Alert,
  FlatList,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  Button,
  Empty,
  ErrorView,
  KeyboardAwareScrollView,
  Loading,
} from '../components/ui';
import { roles, Role, PermissionGroup, ApiError } from '../lib/api';
import { dateTime } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

export default function RolesScreen() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  const listQuery = useQuery({
    queryKey: ['roles'],
    queryFn: () => roles.list(),
  });

  const catalogQuery = useQuery({
    queryKey: ['permissions'],
    queryFn: () => roles.catalog(),
  });

  if (listQuery.isLoading) return <Loading />;
  if (listQuery.isError)
    return (
      <ErrorView message={(listQuery.error as ApiError).message} onRetry={listQuery.refetch} />
    );

  const roleList = listQuery.data ?? [];
  const catalog = catalogQuery.data ?? [];

  return (
    <View style={styles.screen}>
      <FlatList
        data={roleList}
        refreshing={listQuery.isRefetching}
        onRefresh={() => {
          listQuery.refetch();
          catalogQuery.refetch();
        }}
        keyExtractor={(r) => r.id}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
        ListEmptyComponent={<Empty message={t('roles.empty')} />}
        ListHeaderComponent={
          <View style={styles.header}>
            <Text style={styles.headerTitle}>
              {t('roles.title', { n: roleList.length, plural: roleList.length !== 1 ? 's' : '' })}
            </Text>
            <Button
              title={t('roles.newRole')}
              variant="primary"
              onPress={() => setShowCreate(true)}
            />
          </View>
        }
        renderItem={({ item: r }) => (
          <RoleRow
            role={r}
            catalog={catalog}
            expanded={editingId === r.id}
            onToggle={() => setEditingId(editingId === r.id ? null : r.id)}
            onUpdated={() => {
              queryClient.invalidateQueries({ queryKey: ['roles'] });
              setEditingId(null);
            }}
          />
        )}
      />

      <CreateRoleModal
        visible={showCreate}
        catalog={catalog}
        onClose={() => setShowCreate(false)}
        onCreated={() => {
          queryClient.invalidateQueries({ queryKey: ['roles'] });
          setShowCreate(false);
        }}
      />
    </View>
  );
}

function RoleRow({
  role: r,
  catalog,
  expanded,
  onToggle,
  onUpdated,
}: {
  role: Role;
  catalog: PermissionGroup[];
  expanded: boolean;
  onToggle: () => void;
  onUpdated: () => void;
}) {
  const { t } = useI18n();
  const deleteMut = useMutation({
    mutationFn: () => roles.remove(r.id),
    onSuccess: onUpdated,
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  return (
    <View>
      <Pressable style={styles.row} onPress={onToggle}>
        <View style={{ flex: 1 }}>
          <View style={styles.nameRow}>
            <Text style={styles.name}>{r.name}</Text>
            {r.isSystem && (
              <View style={styles.systemBadge}>
                <Text style={styles.systemBadgeText}>{t('roles.system')}</Text>
              </View>
            )}
          </View>
          {r.description && <Text style={styles.desc}>{r.description}</Text>}
          <Text style={styles.meta}>
            {t('roles.permsCount', { n: r.permissions.length })}
            {r.approvalPermissions.length > 0
              ? t('roles.approvalCount', { n: r.approvalPermissions.length })
              : ''}
            {r.userCount > 0 ? t('roles.usersCount', { n: r.userCount }) : ''}
          </Text>
        </View>
        <Text style={styles.expandIcon}>{expanded ? '▲' : '▼'}</Text>
      </Pressable>

      {expanded && (
        <RoleEditForm
          role={r}
          catalog={catalog}
          onUpdated={onUpdated}
          onDelete={
            r.isSystem
              ? undefined
              : () => {
                  Alert.alert(
                    t('roles.deleteConfirmTitle'),
                    t('roles.deleteConfirmBody', { name: r.name }),
                    [
                      { text: t('approvals.cancel'), style: 'cancel' },
                      {
                        text: t('approvals.deny'),
                        style: 'destructive',
                        onPress: () => deleteMut.mutate(),
                      },
                    ],
                  );
                }
          }
        />
      )}
    </View>
  );
}

function RoleEditForm({
  role: r,
  catalog,
  onUpdated,
  onDelete,
}: {
  role: Role;
  catalog: PermissionGroup[];
  onUpdated: () => void;
  onDelete?: () => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState(r.name);
  const [description, setDescription] = useState(r.description ?? '');
  const [perms, setPerms] = useState<Set<string>>(new Set(r.permissions));
  const [approvalPerms, setApprovalPerms] = useState<Set<string>>(new Set(r.approvalPermissions));

  const updateMut = useMutation({
    mutationFn: () =>
      roles.update(r.id, {
        name: name !== r.name ? name : undefined,
        description: description !== (r.description ?? '') ? description || undefined : undefined,
        permissions:
          perms.size !== r.permissions.length || !r.permissions.every((p) => perms.has(p))
            ? [...perms]
            : undefined,
        approvalPermissions:
          approvalPerms.size !== r.approvalPermissions.length ||
          !r.approvalPermissions.every((p) => approvalPerms.has(p))
            ? [...approvalPerms]
            : undefined,
      }),
    onSuccess: onUpdated,
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  return (
    <View style={styles.editForm}>
      <Text style={styles.fieldLabel}>{t('roles.name')}</Text>
      <TextInput style={styles.input} value={name} onChangeText={setName} />

      <Text style={styles.fieldLabel}>{t('roles.description')}</Text>
      <TextInput style={styles.input} value={description} onChangeText={setDescription} />

      <Text style={styles.fieldLabel}>{t('roles.permissions')}</Text>
      {catalog.map((group) => (
        <View key={group.group} style={styles.permGroup}>
          <Text style={styles.permGroupName}>{group.group}</Text>
          {group.permissions.map((p) => {
            const checked = perms.has(p.key);
            const approval = approvalPerms.has(p.key);
            return (
              <View key={p.key} style={styles.permRow}>
                <Pressable
                  onPress={() => {
                    const next = new Set(perms);
                    if (checked) {
                      next.delete(p.key);
                      approvalPerms.delete(p.key);
                    } else next.add(p.key);
                    setPerms(next);
                  }}
                  style={[styles.checkbox, checked && styles.checkboxChecked]}
                >
                  {checked && <Text style={styles.checkmark}>✓</Text>}
                </Pressable>
                <Text style={[styles.permLabel, checked && styles.permLabelOn]}>{p.label}</Text>
                {checked && p.approvable && (
                  <Pressable
                    onPress={() => {
                      const next = new Set(approvalPerms);
                      approval ? next.delete(p.key) : next.add(p.key);
                      setApprovalPerms(next);
                    }}
                    style={[styles.approvalToggle, approval && styles.approvalToggleOn]}
                  >
                    <Text
                      style={[styles.approvalToggleText, approval && styles.approvalToggleTextOn]}
                    >
                      {approval ? t('roles.approvalToggleOn') : t('roles.approvalToggle')}
                    </Text>
                  </Pressable>
                )}
              </View>
            );
          })}
        </View>
      ))}

      <View style={styles.editActions}>
        <Button
          title={t('roles.save')}
          variant="primary"
          onPress={() => updateMut.mutate()}
          disabled={updateMut.isPending}
        />
        {onDelete && (
          <Button
            title={t('roles.deleteRole')}
            variant="danger"
            onPress={onDelete}
            disabled={updateMut.isPending}
          />
        )}
      </View>
    </View>
  );
}

function CreateRoleModal({
  visible,
  catalog,
  onClose,
  onCreated,
}: {
  visible: boolean;
  catalog: PermissionGroup[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [perms, setPerms] = useState<Set<string>>(new Set());
  const [approvalPerms, setApprovalPerms] = useState<Set<string>>(new Set());

  const createMut = useMutation({
    mutationFn: () =>
      roles.create({
        name,
        description: description || undefined,
        permissions: [...perms],
        approvalPermissions: [...approvalPerms],
      }),
    onSuccess: () => {
      onCreated();
      setName('');
      setDescription('');
      setPerms(new Set());
      setApprovalPerms(new Set());
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={styles.modal}>
        <View style={styles.modalHeader}>
          <Text style={styles.modalTitle}>{t('roles.createTitle')}</Text>
          <Pressable onPress={onClose}>
            <Text style={styles.modalClose}>{t('approvals.cancel')}</Text>
          </Pressable>
        </View>

        <KeyboardAwareScrollView contentContainerStyle={{ gap: space.sm }}>
          <Text style={styles.fieldLabel}>{t('roles.name')}</Text>
          <TextInput
            style={styles.input}
            value={name}
            onChangeText={setName}
            placeholder={t('roles.namePlaceholder')}
          />

          <Text style={styles.fieldLabel}>{t('roles.description')}</Text>
          <TextInput
            style={styles.input}
            value={description}
            onChangeText={setDescription}
            placeholder={t('roles.descPlaceholder')}
          />

          <Text style={styles.fieldLabel}>{t('roles.permissions')}</Text>
          {catalog.map((group) => (
            <View key={group.group} style={styles.permGroup}>
              <Text style={styles.permGroupName}>{group.group}</Text>
              {group.permissions.map((p) => {
                const checked = perms.has(p.key);
                const approval = approvalPerms.has(p.key);
                return (
                  <View key={p.key} style={styles.permRow}>
                    <Pressable
                      onPress={() => {
                        const next = new Set(perms);
                        if (checked) {
                          next.delete(p.key);
                          approvalPerms.delete(p.key);
                        } else next.add(p.key);
                        setPerms(next);
                      }}
                      style={[styles.checkbox, checked && styles.checkboxChecked]}
                    >
                      {checked && <Text style={styles.checkmark}>✓</Text>}
                    </Pressable>
                    <Text style={[styles.permLabel, checked && styles.permLabelOn]}>{p.label}</Text>
                    {checked && p.approvable && (
                      <Pressable
                        onPress={() => {
                          const next = new Set(approvalPerms);
                          approval ? next.delete(p.key) : next.add(p.key);
                          setApprovalPerms(next);
                        }}
                        style={[styles.approvalToggle, approval && styles.approvalToggleOn]}
                      >
                        <Text
                          style={[
                            styles.approvalToggleText,
                            approval && styles.approvalToggleTextOn,
                          ]}
                        >
                          {approval ? t('roles.approvalToggleOn') : t('roles.approvalToggle')}
                        </Text>
                      </Pressable>
                    )}
                  </View>
                );
              })}
            </View>
          ))}

          <View style={styles.createActions}>
            <Button
              title={createMut.isPending ? t('roles.creating') : t('roles.createRole')}
              variant="primary"
              onPress={() => {
                if (!name.trim()) {
                  Alert.alert('Error', t('roles.nameRequired'));
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
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  name: { fontSize: 16, fontWeight: '700', color: colors.text },
  systemBadge: {
    backgroundColor: '#eceef1',
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
  },
  systemBadgeText: { fontSize: 10, fontWeight: '700', color: '#57606a' },
  desc: { fontSize: 13, color: colors.muted, marginTop: 2 },
  meta: { fontSize: 11, color: colors.muted, marginTop: 4 },
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
  permGroup: { marginTop: space.xs },
  permGroupName: { fontSize: 12, fontWeight: '700', color: colors.muted, marginBottom: space.xs },
  permRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 4, gap: space.sm },
  checkbox: {
    width: 20,
    height: 20,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bg,
  },
  checkboxChecked: { backgroundColor: colors.primary, borderColor: colors.primary },
  checkmark: { color: '#fff', fontSize: 12, fontWeight: '800' },
  permLabel: { fontSize: 13, color: colors.muted, flex: 1 },
  permLabelOn: { color: colors.text },
  approvalToggle: {
    paddingHorizontal: space.sm,
    paddingVertical: 2,
    borderRadius: radius.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  approvalToggleOn: { backgroundColor: '#fff8c5', borderColor: '#7d4e00' },
  approvalToggleText: { fontSize: 10, fontWeight: '700', color: colors.muted },
  approvalToggleTextOn: { color: '#7d4e00' },
  editActions: { flexDirection: 'row', gap: space.sm, marginTop: space.sm },
  modal: { flex: 1, backgroundColor: colors.bg },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: space.lg,
    backgroundColor: colors.card,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  modalTitle: { fontSize: 20, fontWeight: '800', color: colors.text },
  modalClose: { fontSize: 15, color: colors.primary, fontWeight: '600' },
  createActions: { marginTop: space.lg, paddingHorizontal: space.lg, paddingBottom: space.xl },
});
