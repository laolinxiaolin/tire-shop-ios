import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import React, { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../lib/i18n';
import { useAuth } from '../state/auth';
import { useTabs } from '../state/tabs';
import { colors } from '../theme';
import AdjustStockScreen from '../screens/AdjustStockScreen';
import ContainerDetailScreen from '../screens/ContainerDetailScreen';
import CustomerDetailScreen from '../screens/CustomerDetailScreen';
import CustomerPickerScreen from '../screens/CustomerPickerScreen';
import CustomizeTabsScreen from '../screens/CustomizeTabsScreen';
import EditSaleScreen from '../screens/EditSaleScreen';
import InventoryCountDetailScreen from '../screens/InventoryCountDetailScreen';
import ModuleScreen from '../screens/ModuleScreen';
import MoreMenuScreen from '../screens/MoreMenuScreen';
import NewCustomerScreen from '../screens/NewCustomerScreen';
import NewInventoryCountScreen from '../screens/NewInventoryCountScreen';
import ProfileScreen from '../screens/ProfileScreen';
import SaleDetailScreen from '../screens/SaleDetailScreen';
import SkuFormScreen from '../screens/SkuFormScreen';
import SkuDetailScreen from '../screens/SkuDetailScreen';
import SkuPickerScreen from '../screens/SkuPickerScreen';
import StartReturnScreen from '../screens/StartReturnScreen';
import TapToPayScreen from '../screens/TapToPayScreen';
import WorkOrderDetailScreen from '../screens/WorkOrderDetailScreen';
import { Loading } from '../components/ui';
import { DEFAULT_PINNED, Destination, destByKey } from './destinations';
import type { RootStackParamList, TabParamList } from './types';

const Tab = createBottomTabNavigator<TabParamList>();
const Stack = createNativeStackNavigator<RootStackParamList>();

function tabIcon(emoji: string) {
  return ({ focused }: { focused: boolean }) => (
    <Text style={{ fontSize: 20, opacity: focused ? 1 : 0.5 }}>{emoji}</Text>
  );
}

/** Header avatar that opens the profile screen — mirrors the web's user menu
 * button, which is also where signing out now lives. */
function ProfileButton() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { user } = useAuth();
  const { t } = useI18n();
  const initials = (user?.fullName ?? '?').slice(0, 1).toUpperCase();
  return (
    <Pressable
      onPress={() => navigation.navigate('Profile')}
      hitSlop={8}
      accessibilityLabel={t('common.profile')}
    >
      <View style={styles.avatar}>
        <Text style={styles.avatarText}>{initials}</Text>
      </View>
    </Pressable>
  );
}

function tabComponent(dest: Destination): React.ComponentType {
  return dest.component!;
}

function Tabs() {
  const { has } = useAuth();
  const { t } = useI18n();
  const { pinned, ready } = useTabs();

  const tabs = useMemo(() => {
    const keys = ready ? pinned : DEFAULT_PINNED;
    return keys
      .map(destByKey)
      .filter((d): d is Destination => !!d && (!d.permission || has(d.permission)));
  }, [has, pinned, ready]);

  if (!ready) return <Loading label={t('common.loading')} />;

  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: true,
        tabBarActiveTintColor: colors.primary,
        headerRight: () => <ProfileButton />,
        headerRightContainerStyle: { paddingRight: 16 },
      }}
    >
      {tabs.map((d) => (
        <Tab.Screen
          key={d.key}
          name={d.key}
          component={tabComponent(d)}
          options={{ title: t(d.titleKey), tabBarIcon: tabIcon(d.icon) }}
        />
      ))}
      <Tab.Screen
        name="more"
        component={MoreMenuScreen}
        options={{ title: t('nav.more'), tabBarIcon: tabIcon('☰') }}
      />
    </Tab.Navigator>
  );
}

const styles = StyleSheet.create({
  avatar: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: { color: colors.primaryText, fontSize: 13, fontWeight: '700' },
});

export default function RootNavigator() {
  const { t } = useI18n();
  return (
    <Stack.Navigator>
      <Stack.Screen name="Main" component={Tabs} options={{ headerShown: false }} />
      <Stack.Screen
        name="Profile"
        component={ProfileScreen}
        options={{ title: t('screen.profile') }}
      />
      <Stack.Screen
        name="Module"
        component={ModuleScreen}
        options={({ route }) => ({
          title: t(destByKey(route.params.destKey)?.titleKey ?? 'screen.fallbackTitle'),
        })}
      />
      <Stack.Screen
        name="CustomizeTabs"
        component={CustomizeTabsScreen}
        options={{ title: t('screen.customizeTabs') }}
      />
      <Stack.Screen
        name="SkuDetail"
        component={SkuDetailScreen}
        options={{ title: t('screen.skuDetail') }}
      />
      <Stack.Screen
        name="SkuForm"
        component={SkuFormScreen}
        options={({ route }) => ({
          title: route.params?.sku ? t('screen.editTire') : t('screen.newTire'),
        })}
      />
      <Stack.Screen
        name="AdjustStock"
        component={AdjustStockScreen}
        options={{ title: t('screen.adjustStock') }}
      />
      <Stack.Screen
        name="SaleDetail"
        component={SaleDetailScreen}
        options={{ title: t('screen.saleDetail') }}
      />
      <Stack.Screen
        name="EditSale"
        component={EditSaleScreen}
        options={{ title: t('screen.editSale') }}
      />
      <Stack.Screen
        name="TapToPay"
        component={TapToPayScreen}
        options={{ title: t('screen.tapToPay') }}
      />
      <Stack.Screen
        name="StartReturn"
        component={StartReturnScreen}
        options={{ title: t('screen.startReturn') }}
      />
      <Stack.Screen
        name="WorkOrderDetail"
        component={WorkOrderDetailScreen}
        options={{ title: t('screen.workOrderDetail') }}
      />
      <Stack.Screen
        name="InventoryCountDetail"
        component={InventoryCountDetailScreen}
        options={{ title: t('screen.inventoryCountDetail') }}
      />
      <Stack.Screen
        name="NewInventoryCount"
        component={NewInventoryCountScreen}
        options={{ title: t('screen.newCount') }}
      />
      <Stack.Screen
        name="ContainerDetail"
        component={ContainerDetailScreen}
        options={{ title: t('screen.containerDetail') }}
      />
      <Stack.Screen
        name="CustomerDetail"
        component={CustomerDetailScreen}
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Group screenOptions={{ presentation: 'modal' }}>
        <Stack.Screen
          name="SkuPicker"
          component={SkuPickerScreen}
          options={{ title: t('screen.addTire') }}
        />
        <Stack.Screen
          name="CustomerPicker"
          component={CustomerPickerScreen}
          options={{ title: t('screen.selectCustomer') }}
        />
        <Stack.Screen
          name="NewCustomer"
          component={NewCustomerScreen}
          options={{ title: t('screen.newCustomer') }}
        />
      </Stack.Group>
    </Stack.Navigator>
  );
}
