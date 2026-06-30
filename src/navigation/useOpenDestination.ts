import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useCallback } from 'react';
import { useTabs } from '../state/tabs';
import type { RootStackParamList } from './types';

/** Opens a destination the right way: jump to its bottom tab when it's pinned,
 * otherwise push it as a Module page. Lets the Dashboard and More menu link to
 * any destination without caring whether the user pinned it. */
export function useOpenDestination() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { pinned } = useTabs();
  return useCallback(
    (key: string) => {
      if (pinned.includes(key)) {
        nav.navigate('Main', { screen: key as never });
      } else {
        nav.navigate('Module', { destKey: key });
      }
    },
    [nav, pinned],
  );
}
