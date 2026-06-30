import type { RouteProp } from '@react-navigation/native';
import { useRoute } from '@react-navigation/native';
import React from 'react';
import { Empty } from '../components/ui';
import { useI18n } from '../lib/i18n';
import { destByKey } from '../navigation/destinations';
import type { RootStackParamList } from '../navigation/types';
import { Placeholder } from './PlaceholderScreen';

/** Renders any destination by key — the target for destinations the user hasn't
 * pinned as a bottom tab. Built screens render directly; the rest show a
 * placeholder. */
export default function ModuleScreen() {
  const { destKey } = useRoute<RouteProp<RootStackParamList, 'Module'>>().params;
  const { t } = useI18n();
  const dest = destByKey(destKey);
  if (!dest) return <Empty message={t('common.unknownScreen')} />;
  if (dest.component) {
    const Component = dest.component;
    return <Component />;
  }
  return <Placeholder dest={dest} />;
}
