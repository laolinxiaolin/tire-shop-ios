import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../lib/i18n';
import { DESTINATIONS, DestGroup, GROUP_LABEL_KEY, GROUP_ORDER } from '../navigation/destinations';
import type { RootStackParamList } from '../navigation/types';
import { useOpenDestination } from '../navigation/useOpenDestination';
import { useAuth } from '../state/auth';
import { useTabs } from '../state/tabs';
import { colors, radius, space } from '../theme';

function MenuRow({
  icon,
  title,
  hint,
  onPress,
  first,
}: {
  icon: string;
  title: string;
  hint?: string;
  onPress: () => void;
  first?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      android_ripple={{ color: colors.border }}
      style={({ pressed }) => [
        styles.row,
        first ? null : styles.rowBorder,
        pressed ? { opacity: 0.6 } : null,
      ]}
    >
      <Text style={styles.icon}>{icon}</Text>
      <Text style={styles.title}>{title}</Text>
      {hint ? <Text style={styles.hint}>{hint}</Text> : null}
      <Text style={styles.chevron}>›</Text>
    </Pressable>
  );
}

export default function MoreMenuScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { has } = useAuth();
  const { pinned } = useTabs();
  const open = useOpenDestination();
  const { t } = useI18n();

  const visible = DESTINATIONS.filter((d) => !d.permission || has(d.permission));

  return (
    <ScrollView style={styles.screen} contentContainerStyle={{ paddingBottom: space.xl }}>
      {GROUP_ORDER.map((group: DestGroup) => {
        const items = visible.filter((d) => d.group === group);
        if (items.length === 0) return null;
        return (
          <View key={group} style={styles.section}>
            {GROUP_LABEL_KEY[group] ? (
              <Text style={styles.sectionTitle}>{t(GROUP_LABEL_KEY[group])}</Text>
            ) : null}
            <View style={styles.card}>
              {items.map((d, i) => (
                <MenuRow
                  key={d.key}
                  first={i === 0}
                  icon={d.icon}
                  title={t(d.titleKey)}
                  hint={pinned.includes(d.key) ? t('more.onTabBar') : undefined}
                  onPress={() => open(d.key)}
                />
              ))}
            </View>
          </View>
        );
      })}

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('nav.group.app')}</Text>
        <View style={styles.card}>
          <MenuRow
            first
            icon="✏️"
            title={t('more.customizeTabs')}
            onPress={() => nav.navigate('CustomizeTabs')}
          />
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  section: { marginTop: space.lg },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    marginBottom: space.sm,
    marginLeft: space.lg,
  },
  card: {
    backgroundColor: colors.card,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: space.lg,
  },
  rowBorder: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
  icon: { fontSize: 20, width: 30 },
  title: { flex: 1, fontSize: 16, color: colors.text, fontWeight: '500' },
  hint: { fontSize: 12, color: colors.muted, marginRight: space.sm },
  chevron: { fontSize: 22, color: colors.muted },
});
