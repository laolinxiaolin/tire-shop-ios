import type { NavigatorScreenParams } from '@react-navigation/native';
import type { TireSku } from '../lib/api';

/** Bottom tabs are user-customizable, so they're keyed dynamically by
 * destination key (see navigation/destinations) plus the always-present More tab. */
export type TabParamList = { [key: string]: undefined };

export type RootStackParamList = {
  Main: NavigatorScreenParams<TabParamList> | undefined;
  Module: { destKey: string };
  CustomizeTabs: undefined;
  SkuDetail: { sku: TireSku };
  SkuForm: { sku?: TireSku } | undefined;
  AdjustStock: { sku: TireSku };
  SaleDetail: { id: string };
  EditSale: { id: string };
  StartReturn: { saleId: string; saleRef: string | null };
  WorkOrderDetail: { id: string };
  InventoryCountDetail: { id: string };
  NewInventoryCount: undefined;
  ContainerDetail: { id: string };
  TapToPay: { invoiceId: string; amount: number };
  CustomerDetail: { id: string; name: string };
  Profile: undefined;
  SkuPicker: undefined;
  CustomerPicker: undefined;
  /** `forQuote` returns the new customer straight into the quote being built;
   * `edit` switches the form to editing an existing customer. */
  NewCustomer:
    | {
        forQuote?: boolean;
        edit?: {
          id: string;
          name: string;
          company: string | null;
          phone: string | null;
          email: string | null;
          address: string | null;
          notes: string | null;
          taxExempt: boolean;
          taxExemptNumber: string | null;
        };
      }
    | undefined;
};
