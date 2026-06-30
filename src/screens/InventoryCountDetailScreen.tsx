import { useNavigation, useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useEffect, useMemo, useState } from 'react';
import { Alert, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import {
  Button,
  Card,
  Divider,
  Empty,
  ErrorView,
  KeyboardAwareScrollView,
  Loading,
} from '../components/ui';
import {
  ApiError,
  approvals,
  inventoryCounts,
  InventoryCountDetail,
  InventoryCountLine,
  isApprovalResult,
} from '../lib/api';
import { dateTime, money } from '../lib/format';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useAuth } from '../state/auth';
import { colors, radius, space } from '../theme';

const SCOPE_LABEL_KEYS: Record<string, string> = {
  LT: 'tire.category.LT',
  SEMI: 'tire.category.SEMI',
  STEER: 'tire.position.STEER',
  DRIVE: 'tire.position.DRIVE',
  TRAILER: 'tire.position.TRAILER',
  ALL_POSITION: 'tire.position.ALL_POSITION',
};

const STATUS_COLOR: Record<string, { bg: string; fg: string }> = {
  OPEN: { bg: '#fff8c5', fg: '#7d4e00' },
  POSTED: { bg: '#dafbe1', fg: '#1a7f37' },
  VOIDED: { bg: '#ffebe9', fg: '#cf222e' },
};

/** Mirrors the server-side parser: accepts "12" or "40+50+10" with whitespace. */
function tryEvalExpr(raw: string): { ok: true; value: number } | { ok: false } {
  const s = raw.trim();
  if (!s) return { ok: false };
  if (!/^\d+(\s*\+\s*\d+)*$/.test(s)) return { ok: false };
  return { ok: true, value: s.split('+').reduce((sum, p) => sum + Number(p.trim()), 0) };
}

export default function InventoryCountDetailScreen() {
  const { id } = useRoute<RouteProp<RootStackParamList, 'InventoryCountDetail'>>().params;
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const qc = useQueryClient();
  const { has, canActOrRequest } = useAuth();
  const { t } = useI18n();

  const canManage = has('inventory.count.manage');
  const canPost = canActOrRequest('inventory.count.post');

  const query = useQuery({
    queryKey: ['inventory-count', id],
    queryFn: () => inventoryCounts.get(id),
  });

  // A post/reverse already awaiting approval — show that instead of the buttons.
  // Only relevant to users who can act; plain viewers see no action buttons.
  const pending = useQuery({
    enabled: canPost || canManage,
    queryKey: ['inventory-count-pending', id],
    queryFn: async () => {
      const list = await approvals.list({ status: 'PENDING', pageSize: 50 });
      return (
        list.items.find(
          (r) =>
            (r.action === 'inventory.count.post' || r.action === 'inventory.count.reverse') &&
            r.entityId === id,
        ) ?? null
      );
    },
  });

  const post = useMutation({
    mutationFn: () => inventoryCounts.post(id),
    onSuccess: (res) => {
      if (isApprovalResult(res)) {
        qc.invalidateQueries({ queryKey: ['approvals'] });
        pending.refetch();
        Alert.alert(t('inventoryCount.submittedApproval'), t('inventoryCount.postApprovalBody'));
        return;
      }
      qc.invalidateQueries({ queryKey: ['inventory-counts'] });
      qc.invalidateQueries({ queryKey: ['skus'] });
      query.refetch();
    },
    onError: (e) =>
      Alert.alert(
        t('inventoryCount.couldNotPost'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  const reverse = useMutation({
    mutationFn: () => inventoryCounts.reverse(id),
    onSuccess: (res) => {
      if (isApprovalResult(res)) {
        qc.invalidateQueries({ queryKey: ['approvals'] });
        pending.refetch();
        Alert.alert(t('inventoryCount.submittedApproval'), t('inventoryCount.reverseApprovalBody'));
        return;
      }
      qc.invalidateQueries({ queryKey: ['inventory-counts'] });
      qc.invalidateQueries({ queryKey: ['skus'] });
      query.refetch();
    },
    onError: (e) =>
      Alert.alert(
        t('inventoryCount.couldNotReverse'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  const remove = useMutation({
    mutationFn: () => inventoryCounts.remove(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inventory-counts'] });
      nav.goBack();
    },
    onError: (e) =>
      Alert.alert(
        t('inventoryCount.couldNotDelete'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  const busy = post.isPending || reverse.isPending || remove.isPending;

  function confirmPost() {
    Alert.alert(t('inventoryCount.confirmPostTitle'), t('inventoryCount.confirmPostBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      { text: t('inventoryCount.postCount'), onPress: () => post.mutate() },
    ]);
  }

  function confirmReverse() {
    Alert.alert(t('inventoryCount.confirmReverseTitle'), t('inventoryCount.confirmReverseBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('inventoryCount.reverseCount'),
        style: 'destructive',
        onPress: () => reverse.mutate(),
      },
    ]);
  }

  function confirmDelete() {
    Alert.alert(t('inventoryCount.confirmDeleteTitle'), t('inventoryCount.confirmDeleteBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('inventoryCount.deleteCount'),
        style: 'destructive',
        onPress: () => remove.mutate(),
      },
    ]);
  }

  // Projected totals from the saved counts (recomputed on every line save).
  const summary = useMemo(() => {
    const c = query.data;
    if (!c) return null;
    let counted = 0;
    let missing = 0;
    let unitsDelta = 0;
    let signedCost = 0;
    for (const l of c.lines) {
      if (l.countedQty == null) {
        missing += 1;
        continue;
      }
      counted += 1;
      const delta = l.countedQty - l.expectedQty;
      unitsDelta += delta;
      signedCost += delta * Number(l.unitCost);
    }
    return { counted, missing, unitsDelta, signedCost };
  }, [query.data]);

  if (query.isLoading) return <Loading />;
  if (query.isError)
    return <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />;

  const c = query.data!;
  const sc = STATUS_COLOR[c.status] ?? { bg: colors.border, fg: colors.muted };
  const isOpen = c.status === 'OPEN';
  const isPosted = c.status === 'POSTED';
  const editable = isOpen && canManage;
  const hasPending = !!pending.data;
  const varianceValue = isPosted ? Number(c.costVariance) : (summary?.signedCost ?? 0);

  function onLineSaved(updated: InventoryCountLine) {
    qc.setQueryData<InventoryCountDetail>(['inventory-count', id], (prev) =>
      prev
        ? {
            ...prev,
            lines: prev.lines.map((l) => (l.id === updated.id ? { ...l, ...updated } : l)),
          }
        : prev,
    );
  }

  function scopeLabel(key: string): string {
    return t(SCOPE_LABEL_KEYS[key] ?? key);
  }

  return (
    <KeyboardAwareScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: space.md }}
      refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={query.refetch} />}
    >
      {/* Header */}
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>{t('inventoryCount.title', { n: c.ref ?? '' })}</Text>
          <Text style={styles.sub}>
            {[c.scopeCategory, c.scopePosition]
              .filter(Boolean)
              .map((p) => scopeLabel(p!))
              .join(' · ') || t('inventoryCount.allTires')}
            {c.location ? ` · ${c.location}` : ''}
          </Text>
        </View>
        <View style={[styles.statusBadge, { backgroundColor: sc.bg }]}>
          <Text style={[styles.statusText, { color: sc.fg }]}>
            {t(`inventoryCount.status.${c.status}`)}
          </Text>
        </View>
      </View>

      {/* Summary cards */}
      <View style={styles.grid}>
        <Card style={styles.stat}>
          <Text style={styles.statLabel}>{t('inventoryCount.lines')}</Text>
          <Text style={styles.statValue}>{c.lines.length}</Text>
        </Card>
        <Card style={styles.stat}>
          <Text style={styles.statLabel}>{t('inventoryCount.counted')}</Text>
          <Text style={styles.statValue}>{summary?.counted ?? 0}</Text>
        </Card>
        <Card style={styles.stat}>
          <Text style={styles.statLabel}>{t('inventoryCount.missing')}</Text>
          <Text
            style={[
              styles.statValue,
              { color: (summary?.missing ?? 0) > 0 ? colors.warnText : colors.text },
            ]}
          >
            {summary?.missing ?? 0}
          </Text>
        </Card>
        <Card style={styles.stat}>
          <Text style={styles.statLabel}>
            {isPosted ? t('inventoryCount.variance') : t('inventoryCount.projected')}
          </Text>
          <Text style={[styles.statValue, varianceValue < 0 ? { color: colors.danger } : null]}>
            {money(varianceValue)}
          </Text>
        </Card>
      </View>

      {/* Actions */}
      {(isOpen || isPosted) && (canPost || canManage) ? (
        <View style={styles.actions}>
          {hasPending ? (
            <View style={[styles.pendingBadge]}>
              <Text style={styles.pendingText}>{t('inventoryCount.awaitingApproval')}</Text>
            </View>
          ) : (
            <>
              {isOpen && canPost ? (
                <Button
                  title={t('inventoryCount.postCount')}
                  onPress={confirmPost}
                  loading={post.isPending}
                  disabled={busy}
                />
              ) : null}
              {isPosted && canPost ? (
                <Button
                  title={t('inventoryCount.reverseCount')}
                  variant="secondary"
                  onPress={confirmReverse}
                  loading={reverse.isPending}
                  disabled={busy}
                />
              ) : null}
              {isOpen && canManage ? (
                <Button
                  title={t('inventoryCount.deleteCount')}
                  variant="danger"
                  onPress={confirmDelete}
                  loading={remove.isPending}
                  disabled={busy}
                />
              ) : null}
            </>
          )}
        </View>
      ) : null}

      {/* Meta */}
      <Card style={{ marginBottom: space.md }}>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('inventoryCount.created')}</Text>
          <Text style={styles.infoValue}>{dateTime(c.createdAt)}</Text>
        </View>
        {c.postedAt ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('inventoryCount.posted')}</Text>
              <Text style={styles.infoValue}>{dateTime(c.postedAt)}</Text>
            </View>
          </>
        ) : null}
        {c.voidedAt ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('inventoryCount.voided')}</Text>
              <Text style={styles.infoValue}>{dateTime(c.voidedAt)}</Text>
            </View>
          </>
        ) : null}
        {c.notes ? (
          <>
            <Divider />
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Notes</Text>
              <Text style={styles.infoValue}>{c.notes}</Text>
            </View>
          </>
        ) : null}
      </Card>

      {/* Lines */}
      <Text style={styles.sectionTitle}>{t('inventoryCount.lines')}</Text>
      <Card style={{ marginBottom: space.xl }}>
        {c.lines.length === 0 ? (
          <Empty message={t('inventoryCount.noLines')} />
        ) : (
          c.lines.map((l, i) => (
            <LineRow
              key={l.id}
              line={l}
              countId={id}
              editable={editable}
              showDivider={i > 0}
              onSaved={onLineSaved}
            />
          ))
        )}
      </Card>
    </KeyboardAwareScrollView>
  );
}

function LineRow({
  line,
  countId,
  editable,
  showDivider,
  onSaved,
}: {
  line: InventoryCountLine;
  countId: string;
  editable: boolean;
  showDivider: boolean;
  onSaved: (l: InventoryCountLine) => void;
}) {
  const { t } = useI18n();
  const initial = line.countExpr ?? (line.countedQty != null ? String(line.countedQty) : '');
  const [draft, setDraft] = useState(initial);

  // Resync when the saved value changes (e.g. after refetch).
  useEffect(() => {
    setDraft(line.countExpr ?? (line.countedQty != null ? String(line.countedQty) : ''));
  }, [line.countExpr, line.countedQty]);

  const save = useMutation({
    mutationFn: () => {
      const trimmed = draft.trim();
      return inventoryCounts.updateLine(countId, line.id, {
        countExpr: trimmed || null,
        countedQty: null,
      });
    },
    onSuccess: (updated) => onSaved(updated),
    onError: (e) => {
      // Revert to the last saved value and surface the reason.
      setDraft(line.countExpr ?? (line.countedQty != null ? String(line.countedQty) : ''));
      Alert.alert(
        t('inventoryCount.couldNotSave'),
        e instanceof ApiError ? e.message : t('common.error'),
      );
    },
  });

  const parsed = draft.trim() ? tryEvalExpr(draft) : null;
  const invalid = parsed != null && !parsed.ok;
  const total = parsed && parsed.ok ? parsed.value : line.countedQty;
  const diff = total != null ? total - line.expectedQty : null;
  const dirty = draft.trim() !== initial;

  function commit() {
    if (dirty && !invalid) save.mutate();
  }

  const countedDisplay = line.countedQty != null ? line.countedQty : '—';

  return (
    <View>
      {showDivider ? <Divider /> : null}
      <View style={styles.lineRow}>
        <View style={{ flex: 1, paddingRight: space.sm }}>
          <Text style={styles.lineSku} numberOfLines={1}>
            {line.sku.sku}
          </Text>
          <Text style={styles.lineTire} numberOfLines={1}>
            {line.sku.brand} {line.sku.model} · {line.sku.size}
          </Text>
          <Text style={styles.lineExp}>
            {t('inventoryCount.expected', { n: line.expectedQty })}
          </Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          {editable ? (
            <>
              <TextInput
                value={draft}
                onChangeText={setDraft}
                onEndEditing={commit}
                onBlur={commit}
                placeholder="—"
                placeholderTextColor={colors.muted}
                keyboardType="number-pad"
                editable={!save.isPending}
                style={[styles.input, invalid ? styles.inputInvalid : null]}
              />
              {parsed && parsed.ok && draft.includes('+') ? (
                <Text style={styles.exprSum}>= {parsed.value}</Text>
              ) : null}
            </>
          ) : (
            <View style={styles.qtyRow}>
              <Text style={styles.qtyExp}>{line.expectedQty}</Text>
              <Text style={styles.qtyArrow}>→</Text>
              <Text
                style={[styles.qtyCounted, diff !== null && diff !== 0 ? styles.qtyChanged : null]}
              >
                {countedDisplay}
              </Text>
            </View>
          )}
          {diff !== null && diff !== 0 ? (
            <Text style={[styles.diff, diff > 0 ? styles.diffPos : styles.diffNeg]}>
              {diff > 0 ? '+' : ''}
              {diff} · {money(diff * Number(line.unitCost))}
            </Text>
          ) : null}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: space.md },
  title: { fontSize: 20, fontWeight: '800', color: colors.text },
  sub: { fontSize: 14, color: colors.muted, marginTop: 2 },
  statusBadge: {
    borderRadius: radius.sm,
    paddingHorizontal: space.md,
    paddingVertical: 6,
  },
  statusText: { fontSize: 13, fontWeight: '700' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.md, marginBottom: space.md },
  stat: { flexGrow: 1, flexBasis: '44%', alignItems: 'center', padding: space.md },
  statLabel: { fontSize: 12, fontWeight: '600', color: colors.muted },
  statValue: { fontSize: 20, fontWeight: '800', color: colors.text, marginTop: 4 },
  actions: { gap: space.sm, marginBottom: space.md },
  pendingBadge: {
    backgroundColor: '#fff8c5',
    borderRadius: radius.md,
    paddingVertical: space.md,
    alignItems: 'center',
  },
  pendingText: { color: '#7d4e00', fontWeight: '700', fontSize: 14 },
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
  infoLabel: { fontSize: 14, color: colors.muted, width: 70 },
  infoValue: { fontSize: 14, fontWeight: '600', color: colors.text, flex: 1 },
  lineRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: space.sm },
  lineSku: { fontSize: 14, fontWeight: '700', color: colors.text },
  lineTire: { fontSize: 13, color: colors.muted, marginTop: 2 },
  lineExp: { fontSize: 12, color: colors.muted, marginTop: 2 },
  input: {
    minWidth: 84,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 6,
    fontSize: 16,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'right',
    backgroundColor: colors.bg,
  },
  inputInvalid: { borderColor: colors.danger },
  exprSum: { fontSize: 11, color: colors.muted, marginTop: 2 },
  qtyRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  qtyExp: { fontSize: 14, color: colors.muted },
  qtyArrow: { fontSize: 12, color: colors.muted },
  qtyCounted: { fontSize: 16, fontWeight: '700', color: colors.text },
  qtyChanged: { color: colors.primary },
  diff: { fontSize: 12, fontWeight: '600', marginTop: 2 },
  diffPos: { color: colors.success },
  diffNeg: { color: colors.danger },
});
