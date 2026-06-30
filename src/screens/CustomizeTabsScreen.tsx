import React from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../lib/i18n';
import { DESTINATIONS, MAX_PINNED } from '../navigation/destinations';
import { useAuth } from '../state/auth';
import { useTabs } from '../state/tabs';
import { colors, radius, space } from '../theme';

export default function CustomizeTabsScreen() {
  const { has } = useAuth();
  const { pinned, setPinned } = useTabs();
  const { t } = useI18n();

  const visible = DESTINATIONS.filter((d) => !d.permission || has(d.permission));

  function toggle(key: string) {
    if (pinned.includes(key)) {
      setPinned(pinned.filter((k) => k !== key));
    } else {
      if (pinned.length >= MAX_PINNED) {
        Alert.alert(t('customize.fullTitle'), t('customize.fullBody', { max: MAX_PINNED }));
        return;
      }
      setPinned([...pinned, key]);
    }
  }

  return (
    <ScrollView style={styles.screen} contentContainerStyle={{ paddingBottom: space.xl }}>
      <Text style={styles.intro}>
        {t('customize.intro', { max: MAX_PINNED, count: pinned.length })}
      </Text>
      <View style={styles.card}>
        {visible.map((d, i) => {
          const isPinned = pinned.includes(d.key);
          const order = pinned.indexOf(d.key) + 1;
          return (
            <Pressable
              key={d.key}
              onPress={() => toggle(d.key)}
              android_ripple={{ color: colors.border }}
              style={({ pressed }) => [
                styles.row,
                i === 0 ? null : styles.rowBorder,
                pressed ? { opacity: 0.6 } : null,
              ]}
            >
              <Text style={styles.icon}>{d.icon}</Text>
              <Text style={styles.title}>{t(d.titleKey)}</Text>
              {isPinned ? (
                <Text style={styles.order}>{t('customize.tabN', { n: order })}</Text>
              ) : null}
              <View style={[styles.check, isPinned ? styles.checkOn : null]}>
                {isPinned ? <Text style={styles.checkMark}>✓</Text> : null}
              </View>
            </Pressable>
          );
        })}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  intro: { fontSize: 14, color: colors.muted, padding: space.lg, lineHeight: 20 },
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
  order: { fontSize: 12, color: colors.muted, marginRight: space.md },
  check: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 1.5,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  checkMark: { color: colors.primaryText, fontSize: 14, fontWeight: '800' },
});
