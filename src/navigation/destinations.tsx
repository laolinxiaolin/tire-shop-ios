import type { ComponentType } from 'react';
import AccountingScreen from '../screens/AccountingScreen';
import ActivityScreen from '../screens/ActivityScreen';
import ApiKeysScreen from '../screens/ApiKeysScreen';
import ApprovalsScreen from '../screens/ApprovalsScreen';
import CashAccountsScreen from '../screens/CashAccountsScreen';
import CustomersListScreen from '../screens/CustomersListScreen';
import DashboardScreen from '../screens/DashboardScreen';
import EodScreen from '../screens/EodScreen';
import FetScreen from '../screens/FetScreen';
import InventoryCountsListScreen from '../screens/InventoryCountsListScreen';
import InventoryListScreen from '../screens/InventoryListScreen';
import MoneyScreen from '../screens/MoneyScreen';
import NewQuoteScreen from '../screens/NewQuoteScreen';
import PurchasingScreen from '../screens/PurchasingScreen';
import ReturnsListScreen from '../screens/ReturnsListScreen';
import RolesScreen from '../screens/RolesScreen';
import SalesListScreen from '../screens/SalesListScreen';
import ShopSettingsScreen from '../screens/ShopSettingsScreen';
import SkuManagementScreen from '../screens/SkuManagementScreen';
import UsersScreen from '../screens/UsersScreen';
import WorkOrdersListScreen from '../screens/WorkOrdersListScreen';

/** Grouping mirrors the web sidebar (Operations / Finance / Admin); `main` is
 * the ungrouped landing destination (Dashboard). */
export type DestGroup = 'main' | 'operations' | 'finance' | 'team' | 'admin';

/** Translation key for each group heading (resolve with `t()`); `main` is
 * ungrouped and has no heading. */
export const GROUP_LABEL_KEY: Record<DestGroup, string> = {
  main: '',
  operations: 'nav.group.operations',
  finance: 'nav.group.finance',
  team: 'nav.group.team',
  admin: 'nav.group.admin',
};

export const GROUP_ORDER: DestGroup[] = ['main', 'operations', 'finance', 'team', 'admin'];

export type Destination = {
  /** Stable id — persisted in the pinned-tabs list and used as the Module route param. */
  key: string;
  /** English label — also the fallback when a translation is missing. */
  title: string;
  /** Translation key for the label (resolve with `t()`). */
  titleKey: string;
  /** Emoji icon (matches the existing tab-icon convention). */
  icon: string;
  group: DestGroup;
  /** RBAC permission key; undefined means any authenticated user may see it. */
  permission?: string;
  /** The screen to render. When omitted the module isn't built yet and a
   * "coming soon" placeholder is shown (kept navigable so the shell is complete). */
  component?: ComponentType<unknown>;
  /** One-line description shown on the placeholder for unbuilt modules. */
  blurb?: string;
};

/** Every destination the web app exposes, in display order. Single source of
 * truth for both the customizable bottom tabs and the More menu. */
export const DESTINATIONS: Destination[] = [
  {
    key: 'dashboard',
    title: 'Home',
    titleKey: 'nav.dashboard',
    icon: '⌂',
    group: 'main',
    permission: 'dashboard.view',
    component: DashboardScreen,
  },
  {
    key: 'notifications',
    title: 'Notifications',
    titleKey: 'nav.notifications',
    icon: '🔔',
    group: 'main',
  },
  {
    key: 'newQuote',
    title: 'New Sale',
    titleKey: 'nav.newQuote',
    icon: '➕',
    group: 'operations',
    permission: 'sales.manage',
    // NewQuoteScreen takes an optional `embeddedInStack` prop (used by
    // EditSaleScreen); as a pinned tab it renders with the default.
    component: NewQuoteScreen as ComponentType<unknown>,
  },
  {
    key: 'sales',
    title: 'Sales',
    titleKey: 'nav.sales',
    icon: '💳',
    group: 'operations',
    permission: 'sales.view',
    component: SalesListScreen,
  },
  {
    key: 'orders',
    title: 'Web Orders',
    titleKey: 'nav.orders',
    icon: '🛒',
    group: 'operations',
    permission: 'orders.manage',
  },
  {
    key: 'inventory',
    title: 'Inventory',
    titleKey: 'nav.inventory',
    icon: '🛞',
    group: 'operations',
    permission: 'inventory.view',
    component: InventoryListScreen,
  },
  {
    key: 'skuManagement',
    title: 'SKU Management',
    titleKey: 'nav.skuManagement',
    icon: '🏷',
    group: 'operations',
    permission: 'inventory.manage',
    component: SkuManagementScreen,
  },
  {
    key: 'tireAttributes',
    title: 'Tire Attributes',
    titleKey: 'nav.tireAttributes',
    icon: '⚙',
    group: 'operations',
    permission: 'inventory.config',
  },
  {
    key: 'brandInfo',
    title: 'Brand Info',
    titleKey: 'nav.brandInfo',
    icon: '📘',
    group: 'operations',
    permission: 'brands.manage',
  },
  {
    key: 'inventoryCounts',
    title: 'Inventory Counts',
    titleKey: 'nav.inventoryCounts',
    icon: '✓',
    group: 'operations',
    permission: 'inventory.count.view',
    component: InventoryCountsListScreen,
  },
  {
    key: 'purchasing',
    title: 'Purchasing',
    titleKey: 'nav.purchasing',
    icon: '🚢',
    group: 'operations',
    permission: 'purchasing.view',
    component: PurchasingScreen,
  },
  {
    key: 'vendors',
    title: 'Vendors',
    titleKey: 'nav.vendors',
    icon: '🚚',
    group: 'operations',
    permission: 'vendors.view',
  },
  {
    key: 'customers',
    title: 'Customers',
    titleKey: 'nav.customers',
    icon: '👤',
    group: 'operations',
    permission: 'customers.view',
    component: CustomersListScreen,
  },
  {
    key: 'customerRelations',
    title: 'Customer Relations',
    titleKey: 'nav.customerRelations',
    icon: '♡',
    group: 'operations',
    permission: 'crm.view',
  },
  {
    key: 'workOrders',
    title: 'Work Orders',
    titleKey: 'nav.workOrders',
    icon: '🔧',
    group: 'operations',
    permission: 'workorders.view',
    component: WorkOrdersListScreen,
  },
  {
    key: 'returns',
    title: 'Returns',
    titleKey: 'nav.returns',
    icon: '↩',
    group: 'operations',
    permission: 'returns.view',
    component: ReturnsListScreen,
  },
  {
    key: 'money',
    title: 'Money',
    titleKey: 'nav.money',
    icon: '$',
    group: 'finance',
    permission: 'receivables.view',
    component: MoneyScreen,
  },
  {
    key: 'accounting',
    title: 'Accounting',
    titleKey: 'nav.accounting',
    icon: '📒',
    group: 'finance',
    permission: 'accounting.view',
    component: AccountingScreen,
  },
  {
    key: 'cashAccounts',
    title: 'Cash Accounts',
    titleKey: 'nav.cashAccounts',
    icon: '🏦',
    group: 'finance',
    permission: 'accounting.view',
    component: CashAccountsScreen,
  },
  {
    key: 'fet',
    title: 'FET',
    titleKey: 'nav.fet',
    icon: '🧾',
    group: 'finance',
    permission: 'accounting.view',
    component: FetScreen,
  },
  {
    key: 'eod',
    title: 'End of Day',
    titleKey: 'nav.eod',
    icon: '☾',
    group: 'finance',
    permission: 'accounting.view',
    component: EodScreen,
  },
  {
    key: 'monthlySales',
    title: 'Monthly Sales',
    titleKey: 'nav.monthlySales',
    icon: '▦',
    group: 'finance',
    permission: 'accounting.view',
  },
  {
    key: 'employees',
    title: 'Employees',
    titleKey: 'nav.employees',
    icon: '👥',
    group: 'team',
    permission: 'employees.view',
  },
  {
    key: 'commissions',
    title: 'Commissions',
    titleKey: 'nav.commissions',
    icon: '%',
    group: 'team',
    permission: 'employees.view',
  },
  {
    key: 'approvals',
    title: 'Approvals',
    titleKey: 'nav.approvals',
    icon: '☑',
    group: 'admin',
    component: ApprovalsScreen,
  },
  {
    key: 'activity',
    title: 'Activity',
    titleKey: 'nav.activity',
    icon: '⌁',
    group: 'admin',
    permission: 'activity.view',
    component: ActivityScreen,
  },
  {
    key: 'users',
    title: 'Users',
    titleKey: 'nav.users',
    icon: '👤',
    group: 'admin',
    permission: 'users.manage',
    component: UsersScreen,
  },
  {
    key: 'roles',
    title: 'Roles',
    titleKey: 'nav.roles',
    icon: '🛡',
    group: 'admin',
    permission: 'users.manage',
    component: RolesScreen,
  },
  {
    key: 'apiKeys',
    title: 'API Keys',
    titleKey: 'nav.apiKeys',
    icon: '🔑',
    group: 'admin',
    permission: 'apikeys.manage',
    component: ApiKeysScreen,
  },
  {
    key: 'shopSettings',
    title: 'Shop Settings',
    titleKey: 'nav.shopSettings',
    icon: '⚙',
    group: 'admin',
    permission: 'settings.manage',
    component: ShopSettingsScreen,
  },
];

const BY_KEY: Record<string, Destination> = Object.fromEntries(DESTINATIONS.map((d) => [d.key, d]));

export function destByKey(key: string): Destination | undefined {
  return BY_KEY[key];
}

/** Default bottom tabs (besides the always-present More tab). */
export const DEFAULT_PINNED = ['dashboard', 'newQuote', 'sales', 'inventory'];

/** Max custom tabs; a 5th "More" tab is always appended. */
export const MAX_PINNED = 4;
