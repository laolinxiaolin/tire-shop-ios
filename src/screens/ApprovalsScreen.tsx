import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React, { useState } from 'react';
import { Alert, FlatList, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Button, Empty, ErrorView, Loading } from '../components/ui';
import {
  approvals,
  ApprovalContext,
  ApprovalRequest,
  ApprovalSale,
  ApprovalStatus,
  ApiError,
} from '../lib/api';
import { useI18n } from '../lib/i18n';
import { dateTime } from '../lib/format';
import { colors, radius, space } from '../theme';

const usd = (n: number) => `$${Number(n).toFixed(2)}`;

const ALL_STATUS: ApprovalStatus[] = ['PENDING', 'EXECUTED', 'DENIED', 'CANCELLED', 'FAILED'];

const STATUS_COLOR: Record<ApprovalStatus, { bg: string; fg: string }> = {
  PENDING: { bg: '#fff8c5', fg: '#7d4e00' },
  EXECUTED: { bg: '#dafbe1', fg: '#1a7f37' },
  DENIED: { bg: '#ffebe9', fg: '#cf222e' },
  CANCELLED: { bg: '#f3f4f6', fg: '#6b7280' },
  FAILED: { bg: '#ffebe9', fg: '#cf222e' },
};

export default function ApprovalsScreen() {
  const { t } = useI18n();
  const [filter, setFilter] = useState<ApprovalStatus | undefined>(undefined);
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['approvals', filter],
    queryFn: () => approvals.list({ status: filter, pageSize: 100 }),
  });

  const pendingQuery = useQuery({
    queryKey: ['approvals', 'pending-count'],
    queryFn: () => approvals.pendingCount(),
    refetchInterval: 30_000,
  });

  const approve = useMutation({
    mutationFn: (id: string) => approvals.approve(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['approvals'] });
      pendingQuery.refetch();
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const deny = useMutation({
    mutationFn: ({ id, note }: { id: string; note?: string }) => approvals.deny(id, note),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['approvals'] });
      pendingQuery.refetch();
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const cancel = useMutation({
    mutationFn: (id: string) => approvals.cancel(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['approvals'] });
      pendingQuery.refetch();
    },
    onError: (e: ApiError) => Alert.alert('Error', e.message),
  });

  const pendingCount = pendingQuery.data?.count ?? 0;

  return (
    <View style={styles.screen}>
      <View style={styles.chips}>
        <FlatList
          horizontal
          showsHorizontalScrollIndicator={false}
          data={ALL_STATUS}
          keyExtractor={(s) => s}
          contentContainerStyle={styles.chipsContent}
          renderItem={({ item: s }) => {
            const active = filter === s;
            const count = s === 'PENDING' && pendingCount > 0 ? ` ${pendingCount}` : '';
            return (
              <Pressable
                onPress={() => setFilter(active ? undefined : s)}
                style={[styles.chip, active && styles.chipActive]}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>
                  {s}
                  {count}
                </Text>
              </Pressable>
            );
          }}
        />
      </View>

      {query.isLoading ? (
        <Loading />
      ) : query.isError ? (
        <ErrorView message={(query.error as ApiError).message} onRetry={query.refetch} />
      ) : (
        <FlatList
          data={query.data?.items ?? []}
          refreshing={query.isRefetching}
          onRefresh={() => {
            query.refetch();
            pendingQuery.refetch();
          }}
          keyExtractor={(r) => r.id}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<Empty message={t('approvals.empty')} />}
          renderItem={({ item: r }) => (
            <ApprovalRow
              item={r}
              onApprove={() => approve.mutate(r.id)}
              onDeny={(note) => deny.mutate({ id: r.id, note })}
              onCancel={() => cancel.mutate(r.id)}
              busy={approve.isPending || deny.isPending || cancel.isPending}
            />
          )}
        />
      )}
    </View>
  );
}

function ApprovalRow({
  item: r,
  onApprove,
  onDeny,
  onCancel,
  busy,
}: {
  item: ApprovalRequest;
  onApprove: () => void;
  onDeny: (note?: string) => void;
  onCancel: () => void;
  busy: boolean;
}) {
  const { t } = useI18n();
  const [expanded, setExpanded] = useState(false);
  const [denyNote, setDenyNote] = useState('');
  const [showDenyInput, setShowDenyInput] = useState(false);

  // Pull the full request (with resolved transaction context) when opened.
  const detail = useQuery({
    queryKey: ['approval', r.id],
    queryFn: () => approvals.get(r.id),
    enabled: expanded,
  });
  const ctx = detail.data?.context ?? null;

  const c = STATUS_COLOR[r.status];

  return (
    <Pressable style={styles.row} onPress={() => setExpanded(!expanded)}>
      <View style={styles.rowHeader}>
        <View style={{ flex: 1 }}>
          <Text style={styles.action}>{r.action}</Text>
          <Text style={styles.meta}>
            {r.requestedBy.fullName} · {dateTime(r.requestedAt)}
          </Text>
          {r.entityType && (
            <Text style={styles.entity}>
              {r.entityType}
              {r.entityId ? ` #${r.entityId.slice(0, 8)}` : ''}
            </Text>
          )}
        </View>
        <View style={[styles.statusBadge, { backgroundColor: c.bg }]}>
          <Text style={[styles.statusText, { color: c.fg }]}>{r.status}</Text>
        </View>
      </View>

      {expanded && (
        <View style={styles.expanded}>
          {r.note && <Text style={styles.note}>{t('approvals.note', { text: r.note })}</Text>}

          {detail.isLoading ? (
            <Text style={styles.note}>{t('approvals.loadingDetails')}</Text>
          ) : ctx ? (
            <ContextView ctx={ctx} />
          ) : r.payload && Object.keys(r.payload).length > 0 ? (
            <View style={styles.payload}>
              {Object.entries(r.payload as Record<string, unknown>)
                .filter(([k]) => k !== 'id' && !/Id$/.test(k))
                .map(([k, v]) => (
                  <Text key={k} style={styles.payloadLine}>
                    <Text style={styles.payloadKey}>{k}: </Text>
                    {String(v)}
                  </Text>
                ))}
            </View>
          ) : null}

          {r.decidedBy && (
            <Text style={styles.decision}>
              {t('approvals.decidedBy', {
                status:
                  r.status === 'EXECUTED'
                    ? t('approvals.statusApproved')
                    : r.status === 'DENIED'
                      ? t('approvals.statusDenied')
                      : t('approvals.statusDecided'),
                name: r.decidedBy.fullName,
                date: dateTime(r.decidedAt!),
              })}
              {r.decisionNote ? ` — ${r.decisionNote}` : ''}
            </Text>
          )}

          {r.executionError && (
            <Text style={styles.error}>
              {t('approvals.executionError', { message: r.executionError })}
            </Text>
          )}

          {r.status === 'PENDING' && (
            <View style={styles.actions}>
              {showDenyInput && (
                <View style={styles.denyRow}>
                  <TextInput
                    style={styles.denyInput}
                    placeholder={t('approvals.denyPlaceholder')}
                    value={denyNote}
                    onChangeText={setDenyNote}
                    editable={!busy}
                  />
                  <Button
                    title={t('approvals.confirmDeny')}
                    variant="danger"
                    onPress={() => {
                      onDeny(denyNote || undefined);
                      setDenyNote('');
                      setShowDenyInput(false);
                    }}
                    disabled={busy}
                  />
                </View>
              )}
              <View style={styles.actionButtons}>
                <Button
                  title={t('approvals.approve')}
                  variant="primary"
                  onPress={onApprove}
                  disabled={busy}
                />
                <Button
                  title={t('approvals.deny')}
                  variant="danger"
                  onPress={() => setShowDenyInput(true)}
                  disabled={busy}
                />
                <Button
                  title={t('approvals.cancel')}
                  variant="secondary"
                  onPress={onCancel}
                  disabled={busy}
                />
              </View>
            </View>
          )}
        </View>
      )}
    </Pressable>
  );
}

function KV({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <View style={styles.kv}>
      <Text style={styles.kvLabel}>{label}</Text>
      <Text style={[styles.kvValue, strong ? styles.kvStrong : null]}>{value}</Text>
    </View>
  );
}

function SaleView({ s }: { s: ApprovalSale }) {
  const { t } = useI18n();
  const balance = +(s.total - s.paid).toFixed(2);
  return (
    <View style={styles.ctxBlock}>
      <View style={styles.ctxHeader}>
        <Text style={styles.ctxTitle}>{s.ref ?? t('approvals.saleNum', { n: s.ref ?? '' })}</Text>
        <Text style={styles.ctxStatus}>{s.status}</Text>
      </View>
      {s.customer ? (
        <Text style={styles.ctxCustomer}>
          {s.customer.name}
          {s.customer.company ? ` — ${s.customer.company}` : ''}
        </Text>
      ) : null}
      <View style={styles.ctxDivider} />
      {s.lines.map((l, i) => (
        <View key={i} style={styles.lineRow}>
          <Text style={styles.lineDesc} numberOfLines={2}>
            <Text style={styles.lineType}>
              {l.itemType === 'SERVICE' ? t('approvals.service') + ' ' : ''}
            </Text>
            {l.description} × {l.qty}
          </Text>
          <Text style={styles.lineTotal}>{usd(l.lineTotal)}</Text>
        </View>
      ))}
      <View style={styles.ctxDivider} />
      <KV label={t('approvals.subtotal')} value={usd(s.subtotal)} />
      <KV label={t('approvals.tax')} value={usd(s.taxAmount)} />
      <KV label={t('approvals.total')} value={usd(s.total)} strong />
      {s.ref != null ? (
        <>
          <KV label={t('approvals.paid')} value={usd(s.paid)} />
          <KV label={t('approvals.balance')} value={usd(balance)} />
        </>
      ) : null}
      {s.payments.length > 0 ? (
        <>
          <Text style={styles.ctxSection}>{t('approvals.payments')}</Text>
          {s.payments.map((p, i) => (
            <KV
              key={i}
              label={`${p.method ?? t('approvals.payment')}${p.reference ? ` · ${p.reference}` : ''}`}
              value={usd(p.amount)}
            />
          ))}
        </>
      ) : null}
    </View>
  );
}

/** Renders the resolved transaction behind an approval, mirroring the web. */
function ContextView({ ctx }: { ctx: ApprovalContext }) {
  const { t } = useI18n();
  if (ctx.kind === 'sale') return <SaleView s={ctx.sale} />;

  if (ctx.kind === 'payment') {
    const p = ctx.payment;
    return (
      <View style={{ gap: space.sm }}>
        <View style={styles.ctxBlock}>
          <Text style={styles.ctxSection}>{t('approvals.payment')}</Text>
          <KV label={t('approvals.amount')} value={usd(p.amount)} />
          <KV
            label={t('approvals.method')}
            value={p.method ?? (p.processor ? t('approvals.card') : '—')}
          />
          {p.reference ? <KV label={t('approvals.reference')} value={p.reference} /> : null}
        </View>
        {ctx.sale ? <SaleView s={ctx.sale} /> : null}
      </View>
    );
  }

  if (ctx.kind === 'sku') {
    const s = ctx.sku;
    return (
      <View style={styles.ctxBlock}>
        <Text style={styles.ctxTitle}>{`${s.size} · ${s.brand} ${s.model}`}</Text>
        <KV label="SKU" value={s.sku} />
        <KV label={t('approvals.categoryPosition')} value={`${s.category} · ${s.position}`} />
        <KV
          label={t('approvals.retailCost')}
          value={`${usd(s.priceRetail)} / ${usd(s.priceCost)}`}
        />
        <View style={styles.ctxDivider} />
        <KV label={t('approvals.onHand')} value={String(ctx.onHand)} />
        <KV label={t('approvals.change')} value={`${ctx.delta > 0 ? '+' : ''}${ctx.delta}`} />
        <KV label={t('approvals.resulting')} value={String(ctx.resulting)} strong />
      </View>
    );
  }

  if (ctx.kind === 'count') {
    const c = ctx.count;
    return (
      <View style={styles.ctxBlock}>
        <Text style={styles.ctxTitle}>
          {t('approvals.countNum', { n: c.ref ?? '' }) + ' · ' + c.status}
        </Text>
        <KV label={t('approvals.location')} value={c.location} />
        <KV label={t('approvals.linesCounted')} value={`${c.countedLines} / ${c.totalLines}`} />
        <KV label={t('approvals.costVariance')} value={usd(c.costVariance)} />
      </View>
    );
  }

  if (ctx.kind === 'payable') {
    return (
      <View style={styles.ctxBlock}>
        <Text style={styles.ctxTitle}>
          {ctx.vendor ? t('approvals.vendor', { name: ctx.vendor }) : t('approvals.payment')}
        </Text>
        {ctx.reference ? <KV label={t('approvals.reference')} value={ctx.reference} /> : null}
        {ctx.paidAt ? (
          <KV label={t('approvals.paidOn', { date: '' }).trim()} value={ctx.paidAt.slice(0, 10)} />
        ) : null}
        <View style={styles.ctxDivider} />
        {ctx.bills.map((b, i) => (
          <KV key={i} label={b.description} value={usd(b.amount)} />
        ))}
        <KV label={t('approvals.total')} value={usd(ctx.total)} strong />
      </View>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  chips: {
    backgroundColor: colors.card,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  chipsContent: { padding: space.md, gap: space.sm },
  chip: {
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderRadius: 20,
    backgroundColor: colors.bg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  chipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { fontSize: 13, fontWeight: '600', color: colors.muted },
  chipTextActive: { color: colors.primaryText },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border, marginLeft: space.lg },
  row: { padding: space.lg, backgroundColor: colors.card },
  rowHeader: { flexDirection: 'row', alignItems: 'flex-start', gap: space.sm },
  action: { fontSize: 15, fontWeight: '700', color: colors.text },
  meta: { fontSize: 12, color: colors.muted, marginTop: 2 },
  entity: { fontSize: 12, color: colors.muted, marginTop: 1 },
  statusBadge: { borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  statusText: { fontSize: 11, fontWeight: '700' },
  expanded: { marginTop: space.md, gap: space.sm },
  note: { fontSize: 13, color: colors.muted, fontStyle: 'italic' },
  payload: { backgroundColor: colors.bg, borderRadius: radius.md, padding: space.md },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    marginBottom: space.xs,
  },
  payloadLine: { fontSize: 13, color: colors.text, marginTop: 2 },
  payloadKey: { fontWeight: '600' },
  ctxBlock: { backgroundColor: colors.bg, borderRadius: radius.md, padding: space.md, gap: 2 },
  ctxHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  ctxTitle: { fontSize: 15, fontWeight: '800', color: colors.text },
  ctxStatus: { fontSize: 12, fontWeight: '700', color: colors.muted },
  ctxCustomer: { fontSize: 14, color: colors.text, marginTop: 2 },
  ctxDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginVertical: space.sm,
  },
  ctxSection: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    marginTop: space.sm,
    marginBottom: space.xs,
  },
  lineRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: space.sm,
    paddingVertical: 2,
  },
  lineDesc: { flex: 1, fontSize: 13, color: colors.text },
  lineType: { fontSize: 11, color: colors.muted },
  lineTotal: { fontSize: 13, fontWeight: '600', color: colors.text },
  kv: { flexDirection: 'row', justifyContent: 'space-between', gap: space.sm, paddingVertical: 1 },
  kvLabel: { fontSize: 13, color: colors.muted, flex: 1 },
  kvValue: { fontSize: 13, color: colors.text, fontWeight: '500', textAlign: 'right' },
  kvStrong: { fontWeight: '800' },
  decision: { fontSize: 13, color: colors.muted },
  error: { fontSize: 13, color: '#cf222e' },
  actions: { marginTop: space.sm, gap: space.sm },
  denyRow: { flexDirection: 'row', gap: space.sm, alignItems: 'center' },
  denyInput: {
    flex: 1,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    fontSize: 13,
    backgroundColor: colors.bg,
  },
  actionButtons: { flexDirection: 'row', gap: space.sm },
});
