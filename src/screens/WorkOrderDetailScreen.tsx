import { useNavigation, useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import React, { useCallback, useState } from 'react';
import {
  Alert,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  Button,
  Card,
  Divider,
  Empty,
  ErrorView,
  KeyboardAwareScrollView,
  Loading,
} from '../components/ui';
import { ApiError, workOrders, WorkOrderStatus } from '../lib/api';
import { dateTime, money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { colors, radius, space } from '../theme';

const NEXT: Partial<Record<WorkOrderStatus, WorkOrderStatus>> = {
  OPEN: 'IN_PROGRESS',
  IN_PROGRESS: 'DONE',
  DONE: 'OPEN',
  CANCELLED: 'OPEN',
};

const STATUS_COLOR: Record<WorkOrderStatus, { bg: string; fg: string }> = {
  OPEN: { bg: '#ddf4ff', fg: '#0969da' },
  IN_PROGRESS: { bg: '#fff8c5', fg: '#7d4e00' },
  DONE: { bg: '#dafbe1', fg: '#1a7f37' },
  CANCELLED: { bg: '#ffebe9', fg: '#cf222e' },
};

function StatusBadge({ status }: { status: WorkOrderStatus }) {
  const { t } = useI18n();
  const c = STATUS_COLOR[status];
  return (
    <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
      <Text style={[styles.statusText, { color: c.fg }]}>{t(`workOrder.status.${status}`)}</Text>
    </View>
  );
}

export default function WorkOrderDetailScreen() {
  const { t } = useI18n();
  const { id } = useRoute<RouteProp<RootStackParamList, 'WorkOrderDetail'>>().params;
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const [newTask, setNewTask] = useState('');
  const [editingNotes, setEditingNotes] = useState(false);
  const [notesDraft, setNotesDraft] = useState('');

  const query = useQuery({
    queryKey: ['work-order', id],
    queryFn: () => workOrders.get(id),
  });

  const updateMut = useMutation({
    mutationFn: (body: { status?: WorkOrderStatus; bay?: string; notes?: string }) =>
      workOrders.update(id, body),
    onSuccess: (data) => {
      qc.setQueryData(['work-order', id], data);
      qc.invalidateQueries({ queryKey: ['work-orders'] });
    },
    onError: (e) => Alert.alert(t('common.error'), (e as ApiError).message),
  });

  const addTaskMut = useMutation({
    mutationFn: (description: string) => workOrders.addTask(id, description),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['work-order', id] });
      setNewTask('');
    },
    onError: (e) => Alert.alert(t('common.error'), (e as ApiError).message),
  });

  const toggleTaskMut = useMutation({
    mutationFn: ({ taskId, done }: { taskId: string; done: boolean }) =>
      workOrders.toggleTask(id, taskId, done),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['work-order', id] }),
    onError: (e) => Alert.alert(t('common.error'), (e as ApiError).message),
  });

  const deleteTaskMut = useMutation({
    mutationFn: (taskId: string) => workOrders.deleteTask(id, taskId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['work-order', id] }),
    onError: (e) => Alert.alert(t('common.error'), (e as ApiError).message),
  });

  const advanceStatus = useCallback(() => {
    if (!query.data) return;
    const next = NEXT[query.data.status];
    if (next) updateMut.mutate({ status: next });
  }, [query.data, updateMut]);

  const startEditNotes = useCallback(() => {
    setNotesDraft(query.data?.notes ?? '');
    setEditingNotes(true);
  }, [query.data]);

  const saveNotes = useCallback(() => {
    updateMut.mutate({ notes: notesDraft });
    setEditingNotes(false);
  }, [notesDraft, updateMut]);

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const wo = query.data!;
  const nextStatus = NEXT[wo.status];
  const canManage = true; // permission check: workorders.manage

  return (
    <KeyboardAwareScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      {/* Header */}
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={styles.customer}>
            {wo.sale.customer?.company ?? wo.sale.customer?.name ?? t('workOrder.unknown')}
          </Text>
          <Text style={styles.sub}>
            {t('workOrder.title', { n: wo.sale.ref ?? '' })} ·{' '}
            {dateTime(wo.createdAt)}
          </Text>
        </View>
        <StatusBadge status={wo.status} />
      </View>

      {/* Info card */}
      <Card style={{ marginBottom: space.md }}>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('workOrder.bay', { n: '' }).trim()}</Text>
          <Text style={styles.infoValue}>{wo.bay ?? '—'}</Text>
        </View>
        <Divider />
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('workOrder.total')}</Text>
          <Text style={styles.infoValue}>{money(wo.sale.total)}</Text>
        </View>
        <Divider />
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('workOrder.lines')}</Text>
          <Text style={styles.infoValue}>
            {wo.sale.lines.map((l) => `${l.qty}x ${l.description}`).join(', ') || '—'}
          </Text>
        </View>
      </Card>

      {/* Tasks */}
      <Text style={styles.sectionTitle}>{t('workOrder.checklist')}</Text>
      <Card style={{ marginBottom: space.md }}>
        {wo.tasks.length === 0 ? (
          <Empty message={t('workOrder.noTasks')} />
        ) : (
          wo.tasks.map((task, i) => (
            <View key={task.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.taskRow}>
                <Pressable
                  onPress={() =>
                    canManage && toggleTaskMut.mutate({ taskId: task.id, done: !task.done })
                  }
                  style={[styles.checkbox, task.done ? styles.checkboxDone : null]}
                  disabled={!canManage}
                >
                  {task.done ? <Text style={styles.checkmark}>✓</Text> : null}
                </Pressable>
                <Text
                  style={[styles.taskDesc, task.done ? styles.taskDescDone : null]}
                  numberOfLines={2}
                >
                  {task.description}
                </Text>
                {canManage ? (
                  <Pressable
                    onPress={() => deleteTaskMut.mutate(task.id)}
                    style={styles.deleteBtn}
                    hitSlop={8}
                  >
                    <Text style={styles.deleteBtnText}>✕</Text>
                  </Pressable>
                ) : null}
              </View>
            </View>
          ))
        )}
        {canManage ? (
          <View style={styles.addTaskRow}>
            <TextInput
              value={newTask}
              onChangeText={setNewTask}
              placeholder={t('workOrder.addTask')}
              placeholderTextColor={colors.muted}
              style={styles.addTaskInput}
              onSubmitEditing={() => {
                if (newTask.trim()) addTaskMut.mutate(newTask.trim());
              }}
              returnKeyType="done"
            />
            <Button
              title={t('workOrder.add')}
              onPress={() => newTask.trim() && addTaskMut.mutate(newTask.trim())}
              loading={addTaskMut.isPending}
              disabled={!newTask.trim()}
            />
          </View>
        ) : null}
      </Card>

      {/* Notes */}
      <Text style={styles.sectionTitle}>{t('workOrder.notes')}</Text>
      <Card style={{ marginBottom: space.md }}>
        {editingNotes ? (
          <View>
            <TextInput
              value={notesDraft}
              onChangeText={setNotesDraft}
              placeholder={t('workOrder.notesPlaceholder')}
              placeholderTextColor={colors.muted}
              style={styles.notesInput}
              multiline
              numberOfLines={4}
              textAlignVertical="top"
            />
            <View style={styles.notesBtns}>
              <Button
                title={t('common.cancel')}
                variant="secondary"
                onPress={() => setEditingNotes(false)}
              />
              <View style={{ width: space.sm }} />
              <Button title={t('common.save')} onPress={saveNotes} loading={updateMut.isPending} />
            </View>
          </View>
        ) : (
          <Pressable onPress={canManage ? startEditNotes : undefined}>
            <Text style={[styles.notesText, !wo.notes ? styles.notesEmpty : null]}>
              {wo.notes || t('workOrder.noNotes')}
            </Text>
          </Pressable>
        )}
      </Card>

      {/* Actions */}
      {canManage && nextStatus ? (
        <Button
          title={t('workOrder.moveTo', { status: t(`workOrder.status.${nextStatus}`) })}
          onPress={advanceStatus}
          loading={updateMut.isPending}
        />
      ) : null}
      {canManage && wo.status !== 'CANCELLED' ? (
        <View style={{ marginTop: space.sm }}>
          <Button
            title={t('workOrder.cancelWo')}
            variant="danger"
            onPress={() =>
              Alert.alert(t('workOrder.cancelConfirmTitle'), t('workOrder.cancelConfirmBody'), [
                { text: t('workOrder.no'), style: 'cancel' },
                {
                  text: t('workOrder.yesCancel'),
                  style: 'destructive',
                  onPress: () => updateMut.mutate({ status: 'CANCELLED' }),
                },
              ])
            }
            loading={updateMut.isPending}
          />
        </View>
      ) : null}

      <View style={{ height: space.xl * 2 }} />
    </KeyboardAwareScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: space.md },
  customer: { fontSize: 20, fontWeight: '800', color: colors.text },
  sub: { fontSize: 14, color: colors.muted, marginTop: 2 },
  statusBadge: {
    borderRadius: radius.sm,
    paddingHorizontal: space.md,
    paddingVertical: 6,
  },
  statusText: { fontSize: 13, fontWeight: '700' },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.xs,
  },
  infoRow: { flexDirection: 'row', paddingVertical: space.sm },
  infoLabel: { fontSize: 14, color: colors.muted, width: 60 },
  infoValue: { fontSize: 14, fontWeight: '600', color: colors.text, flex: 1 },
  taskRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 4,
    borderWidth: 2,
    borderColor: colors.border,
    marginRight: space.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxDone: { backgroundColor: colors.success, borderColor: colors.success },
  checkmark: { color: '#fff', fontSize: 14, fontWeight: '800' },
  taskDesc: { flex: 1, fontSize: 15, color: colors.text },
  taskDescDone: { textDecorationLine: 'line-through', color: colors.muted },
  deleteBtn: { padding: space.xs },
  deleteBtnText: { color: colors.muted, fontSize: 14, fontWeight: '600' },
  addTaskRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm, marginTop: space.sm },
  addTaskInput: {
    flex: 1,
    backgroundColor: colors.bg,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    fontSize: 15,
    color: colors.text,
  },
  notesText: { fontSize: 15, color: colors.text },
  notesEmpty: { color: colors.muted, fontStyle: 'italic' },
  notesInput: {
    backgroundColor: colors.bg,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.md,
    fontSize: 15,
    color: colors.text,
    minHeight: 100,
  },
  notesBtns: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: space.md },
});
