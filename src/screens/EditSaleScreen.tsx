import type { RouteProp } from '@react-navigation/native';
import { useRoute } from '@react-navigation/native';
import { useQuery } from '@tanstack/react-query';
import React, { useEffect } from 'react';
import { ApiError, customers, sales } from '../lib/api';
import { Empty, ErrorView, Loading } from '../components/ui';
import { useI18n } from '../lib/i18n';
import type { RootStackParamList } from '../navigation/types';
import { useQuote } from '../state/quote';
import NewQuoteScreen from './NewQuoteScreen';

/**
 * Edit an existing draft sale. The shared quote cart (used by the SKU /
 * customer pickers) is the single line-editing surface, so editing simply
 * seeds that cart from the sale and reuses the new-sale builder — which
 * switches to "Save changes" once `editingSaleId` is set. The cart is cleared
 * on unmount so backing out of an edit doesn't leave the New Quote tab dirty.
 */
export default function EditSaleScreen() {
  const { id } = useRoute<RouteProp<RootStackParamList, 'EditSale'>>().params;
  const { t } = useI18n();
  // Destructure the stable callbacks so the effects below don't re-fire on every
  // cart edit (the `quote` object's identity changes whenever a line changes).
  const { seedFrom, editingSaleId, clear } = useQuote();

  const saleQ = useQuery({ queryKey: ['sale', id], queryFn: () => sales.get(id) });
  const sale = saleQ.data;
  const customerQ = useQuery({
    queryKey: ['customer', sale?.customerId],
    queryFn: () => customers.get(sale!.customerId),
    enabled: !!sale?.customerId,
  });

  // Seed the cart once both the sale and its customer are loaded.
  const seeded = editingSaleId === id;
  useEffect(() => {
    if (sale && sale.status === 'DRAFT' && customerQ.data && editingSaleId !== id) {
      const c = customerQ.data;
      seedFrom(sale, { id: c.id, name: c.name, company: c.company, taxExempt: c.taxExempt });
    }
  }, [sale, customerQ.data, id, editingSaleId, seedFrom]);

  // Leave the cart clean for the next New Quote when leaving the edit screen.
  useEffect(() => () => clear(), [clear]);

  if (saleQ.isLoading || (sale?.customerId && customerQ.isLoading)) return <Loading />;
  if (saleQ.isError)
    return <ErrorView message={(saleQ.error as ApiError).message} onRetry={saleQ.refetch} />;
  if (sale && sale.status !== 'DRAFT') {
    return <Empty message={t('editSale.notEditable', { status: t(`status.${sale.status}`) })} />;
  }
  if (!seeded) return <Loading />;

  return <NewQuoteScreen embeddedInStack />;
}
