import React from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../lib/i18n';
import type { Destination } from '../navigation/destinations';
import { colors, radius, space } from '../theme';

/** Shown for destinations that exist in the navigation shell but whose screen
 * isn't built on mobile yet — keeps the whole structure navigable. */
export function Placeholder({ dest }: { dest: Destination }) {
  const { t } = useI18n();
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <Text style={styles.icon}>{dest.icon}</Text>
      <Text style={styles.title}>{t(dest.titleKey)}</Text>
      {dest.blurb ? <Text style={styles.blurb}>{dest.blurb}</Text> : null}
      <View style={styles.note}>
        <Text style={styles.noteText}>{t('placeholder.comingSoon')}</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { alignItems: 'center', padding: space.xl, paddingTop: space.xl * 2 },
  icon: { fontSize: 56 },
  title: { fontSize: 22, fontWeight: '800', color: colors.text, marginTop: space.md },
  blurb: { fontSize: 15, color: colors.muted, textAlign: 'center', marginTop: space.sm },
  note: {
    marginTop: space.xl,
    backgroundColor: colors.warnBg,
    borderRadius: radius.md,
    padding: space.lg,
  },
  noteText: { color: colors.warnText, fontSize: 14, textAlign: 'center' },
});
