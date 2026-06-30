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
import { apiKeys, ApiKey, ApiKeyCreated, AiScopeGroup, ApiError } from '../lib/api';
import { dateTime } from '../lib/format';
import { useI18n } from '../lib/i18n';
import { colors, radius, space } from '../theme';

export default function ApiKeysScreen() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);

  const listQuery = useQuery({
    queryKey: ['api-keys'],
    queryFn: () => apiKeys.list(),
  });

  const scopesQuery = useQuery({
    queryKey: ['api-keys', 'scopes'],
    queryFn: () => apiKeys.scopes(),
  });

  if (listQuery.isLoading) return <Loading />;
  if (listQuery.isError)
    return (
      <ErrorView message={(listQuery.error as ApiError).message} onRetry={listQuery.refetch} />
    );

  const keys = listQuery.data ?? [];
  const scopes = scopesQuery.data ?? [];

  return (
    <View style={styles.screen}>
      <FlatList
        data={keys}
        refreshing={listQuery.isRefetching}
        onRefresh={() => {
          listQuery.refetch();
          scopesQuery.refetch();
        }}
        keyExtractor={(k) => k.id}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
        ListEmptyComponent={<Empty message={t('apiKeys.empty')} />}
        ListHeaderComponent={
          <View style={styles.header}>
            <Text style={styles.headerTitle}>
              {t('apiKeys.title', { n: keys.length, plural: keys.length !== 1 ? 's' : '' })}
            </Text>
            <Button
              title={t('apiKeys.newKey')}
              variant="primary"
              onPress={() => setShowCreate(true)}
            />
          </View>
        }
        renderItem={({ item: k }) => (
          <ApiKeyRow
            apiKey={k}
            onRevoke={() => {
              Alert.alert(t('apiKeys.revokeTitle'), t('apiKeys.revokeBody', { name: k.name }), [
                { text: t('approvals.cancel'), style: 'cancel' },
                {
                  text: t('apiKeys.revoke'),
                  style: 'destructive',
                  onPress: () => {
                    apiKeys
                      .revoke(k.id)
                      .then(() => queryClient.invalidateQueries({ queryKey: ['api-keys'] }))
                      .catch((e: ApiError) => Alert.alert('Error', e.message));
                  },
                },
              ]);
            }}
          />
        )}
      />

      <CreateKeyModal
        visible={showCreate}
        scopes={scopes}
        onClose={() => setShowCreate(false)}
        onCreated={() => {
          queryClient.invalidateQueries({ queryKey: ['api-keys'] });
        }}
      />
    </View>
  );
}

function ApiKeyRow({ apiKey: k, onRevoke }: { apiKey: ApiKey; onRevoke: () => void }) {
  const { t } = useI18n();
  return (
    <View style={styles.row}>
      <View style={{ flex: 1 }}>
        <View style={styles.nameRow}>
          <Text style={styles.name}>{k.name}</Text>
          {k.revoked && (
            <View style={styles.revokedBadge}>
              <Text style={styles.revokedBadgeText}>{t('apiKeys.revoked')}</Text>
            </View>
          )}
        </View>
        <View style={styles.scopeRow}>
          {k.scopes.map((s) => (
            <View key={s} style={styles.scopeChip}>
              <Text style={styles.scopeChipText}>{s}</Text>
            </View>
          ))}
        </View>
        <Text style={styles.meta}>
          {k.lastUsedAt
            ? `${t('apiKeys.created', { date: dateTime(k.createdAt) })} · ${t('apiKeys.lastUsed', { date: dateTime(k.lastUsedAt) })}`
            : `${t('apiKeys.created', { date: dateTime(k.createdAt) })} · ${t('apiKeys.neverUsed')}`}
        </Text>
      </View>
      {!k.revoked && <Button title={t('apiKeys.revoke')} variant="danger" onPress={onRevoke} />}
    </View>
  );
}

function CreateKeyModal({
  visible,
  scopes,
  onClose,
  onCreated,
}: {
  visible: boolean;
  scopes: AiScopeGroup[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [created, setCreated] = useState<ApiKeyCreated | null>(null);

  const createMut = useMutation({
    mutationFn: () => apiKeys.create({ name, scopes: [...selected] }),
    onSuccess: (result) => {
      setCreated(result);
      onCreated();
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const handleClose = () => {
    setName('');
    setSelected(new Set());
    setCreated(null);
    onClose();
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={styles.modal}>
        <View style={styles.modalHeader}>
          <Text style={styles.modalTitle}>{t('apiKeys.createTitle')}</Text>
          <Pressable onPress={handleClose}>
            <Text style={styles.modalClose}>{t('apiKeys.close')}</Text>
          </Pressable>
        </View>

        {created ? (
          <View style={styles.revealSection}>
            <Text style={styles.revealWarning}>{t('apiKeys.revealWarning')}</Text>
            <View style={styles.revealBox}>
              <Text style={styles.revealKey} selectable>
                {created.plaintext}
              </Text>
            </View>
            <Text style={styles.revealHint}>
              {t('apiKeys.revealHint', { scopes: created.scopes.join(', ') })}
            </Text>
          </View>
        ) : (
          <KeyboardAwareScrollView contentContainerStyle={{ gap: space.sm, padding: space.lg }}>
            <Text style={styles.fieldLabel}>{t('apiKeys.keyName')}</Text>
            <TextInput
              style={styles.input}
              value={name}
              onChangeText={setName}
              placeholder={t('apiKeys.namePlaceholder')}
            />

            <Text style={styles.fieldLabel}>{t('apiKeys.scopes')}</Text>
            {scopes.map((group) => (
              <View key={group.group} style={styles.scopeGroup}>
                <Text style={styles.scopeGroupName}>{group.group}</Text>
                {group.scopes.map((s) => {
                  const checked = selected.has(s.key);
                  return (
                    <Pressable
                      key={s.key}
                      onPress={() => {
                        const next = new Set(selected);
                        checked ? next.delete(s.key) : next.add(s.key);
                        setSelected(next);
                      }}
                      style={styles.scopeRow}
                    >
                      <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
                        {checked && <Text style={styles.checkmark}>✓</Text>}
                      </View>
                      <Text style={[styles.scopeLabel, checked && styles.scopeLabelOn]}>
                        {s.label}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            ))}

            <View style={styles.createActions}>
              <Button
                title={createMut.isPending ? t('apiKeys.creating') : t('apiKeys.createKey')}
                variant="primary"
                onPress={() => {
                  if (!name.trim()) {
                    Alert.alert('Error', t('apiKeys.nameRequired'));
                    return;
                  }
                  if (selected.size === 0) {
                    Alert.alert('Error', t('apiKeys.scopeRequired'));
                    return;
                  }
                  createMut.mutate();
                }}
                disabled={createMut.isPending}
              />
            </View>
          </KeyboardAwareScrollView>
        )}
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
    alignItems: 'center',
    padding: space.lg,
    backgroundColor: colors.card,
    gap: space.sm,
  },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  name: { fontSize: 15, fontWeight: '700', color: colors.text },
  revokedBadge: {
    backgroundColor: '#ffebe9',
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
  },
  revokedBadgeText: { fontSize: 10, fontWeight: '700', color: '#cf222e' },
  scopeRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: 6 },
  scopeChip: {
    backgroundColor: colors.bg,
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
  },
  scopeChipText: { fontSize: 10, fontWeight: '600', color: colors.muted },
  meta: { fontSize: 11, color: colors.muted, marginTop: 4 },
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
  scopeGroup: { marginTop: space.xs },
  scopeGroupName: { fontSize: 12, fontWeight: '700', color: colors.muted, marginBottom: space.xs },
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
  scopeLabel: { fontSize: 13, color: colors.muted, flex: 1 },
  scopeLabelOn: { color: colors.text },
  createActions: { marginTop: space.lg, paddingBottom: space.xl },
  revealSection: { padding: space.lg, gap: space.md },
  revealWarning: {
    fontSize: 14,
    fontWeight: '700',
    color: '#cf222e',
    textAlign: 'center',
  },
  revealBox: {
    backgroundColor: '#1a1a2e',
    borderRadius: radius.md,
    padding: space.lg,
    borderWidth: 1,
    borderColor: colors.primary,
  },
  revealKey: {
    fontSize: 14,
    fontFamily: 'monospace',
    color: '#4ade80',
    lineHeight: 22,
  },
  revealHint: { fontSize: 12, color: colors.muted, textAlign: 'center', lineHeight: 18 },
});
