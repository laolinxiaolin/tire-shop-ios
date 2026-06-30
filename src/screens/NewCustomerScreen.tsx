import type { RouteProp } from '@react-navigation/native';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import React, { useLayoutEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Button, Field, KeyboardAwareScrollView } from '../components/ui';
import { ApiError, customers, Customer, NewCustomer } from '../lib/api';
import { useI18n } from '../lib/i18n';
import { normalizeUsPhone } from '../lib/phone';
import type { RootStackParamList } from '../navigation/types';
import { useQuote } from '../state/quote';
import { colors, space } from '../theme';

export default function NewCustomerScreen() {
  const nav = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const route = useRoute<RouteProp<RootStackParamList, 'NewCustomer'>>();
  const forQuote = route.params?.forQuote ?? false;
  const edit = route.params?.edit;
  const isEdit = !!edit;
  const qc = useQueryClient();
  const quote = useQuote();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();

  const text = (value: string | null | undefined) => value ?? '';
  const [name, setName] = useState(edit?.name ?? '');
  const [company, setCompany] = useState(text(edit?.company));
  const [phone, setPhone] = useState(text(edit?.phone));
  const [email, setEmail] = useState(text(edit?.email));
  const [address, setAddress] = useState(text(edit?.address));
  const [notes, setNotes] = useState(text(edit?.notes));
  const [taxExempt, setTaxExempt] = useState(edit?.taxExempt ?? false);
  const [taxExemptNumber, setTaxExemptNumber] = useState(text(edit?.taxExemptNumber));

  const trimmedName = name.trim();

  const save = useMutation({
    mutationFn: async () => {
      // Pre-check the phone the same way the web client / API do, so the user
      // sees a clear error instead of a 400.
      let phoneDigits = '';
      try {
        phoneDigits = normalizeUsPhone(phone) ?? '';
      } catch {
        throw new ApiError(0, t('newCustomer.phoneError'));
      }
      const trim = (v: string) => v.trim();

      if (isEdit && edit) {
        // Profile fields go to PATCH /customers/:id; tax status has its own route.
        await customers.update(edit.id, {
          name: trimmedName,
          company: trim(company),
          phone: phoneDigits,
          email: trim(email),
          address: trim(address),
          notes: trim(notes),
        });
        return customers.setTaxStatus(edit.id, {
          taxExempt,
          taxExemptNumber: taxExempt ? trim(taxExemptNumber) || undefined : undefined,
        });
      }

      const body: NewCustomer = { name: trimmedName };
      const opt = (v: string) => (trim(v).length ? trim(v) : undefined);
      body.company = opt(company);
      body.phone = phoneDigits || undefined;
      body.email = opt(email);
      body.address = opt(address);
      body.notes = opt(notes);
      if (taxExempt) {
        body.taxExempt = true;
        body.taxExemptNumber = opt(taxExemptNumber);
      }
      return customers.create(body);
    },
    onSuccess: (saved: Customer) => {
      qc.invalidateQueries({ queryKey: ['customers'] });
      qc.invalidateQueries({ queryKey: ['customer', saved.id] });
      if (forQuote) {
        quote.setCustomer({
          id: saved.id,
          name: saved.name,
          company: saved.company,
          taxExempt: saved.taxExempt,
        });
        nav.navigate('Main', { screen: 'newQuote' });
      } else if (isEdit) {
        nav.goBack();
      } else {
        nav.goBack();
        nav.navigate('CustomerDetail', { id: saved.id, name: saved.name });
      }
    },
    onError: (e) =>
      Alert.alert(
        isEdit ? t('newCustomer.saveFailedEdit') : t('newCustomer.createFailed'),
        e instanceof ApiError ? e.message : t('common.error'),
      ),
  });

  useLayoutEffect(() => {
    nav.setOptions({
      title: isEdit ? t('screen.editCustomer') : t('screen.newCustomer'),
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={t('common.cancel')}
          disabled={save.isPending}
          hitSlop={10}
          onPress={() => nav.goBack()}
          style={({ pressed }) => [styles.closeBtn, pressed ? { opacity: 0.55 } : null]}
        >
          <Text style={styles.closeText}>×</Text>
        </Pressable>
      ),
    });
  }, [nav, isEdit, t, save.isPending]);

  return (
    <KeyboardAwareScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: space.lg, paddingBottom: space.xl + insets.bottom }}
    >
      <Field
        label={t('newCustomer.name')}
        value={name}
        onChangeText={setName}
        placeholder="John Smith"
        autoCapitalize="words"
        editable={!save.isPending}
      />
      <Field
        label={t('newCustomer.company')}
        value={company}
        onChangeText={setCompany}
        placeholder="Smith Trucking"
        autoCapitalize="words"
        editable={!save.isPending}
      />
      <Field
        label={t('newCustomer.phone')}
        value={phone}
        onChangeText={setPhone}
        placeholder="478-555-0100"
        keyboardType="phone-pad"
        editable={!save.isPending}
      />
      <Field
        label={t('newCustomer.email')}
        value={email}
        onChangeText={setEmail}
        placeholder="john@example.com"
        keyboardType="email-address"
        autoCapitalize="none"
        editable={!save.isPending}
      />
      <Field
        label={t('newCustomer.address')}
        value={address}
        onChangeText={setAddress}
        placeholder="123 Main St, Macon, GA"
        editable={!save.isPending}
      />
      <Field
        label={t('newCustomer.notes')}
        value={notes}
        onChangeText={setNotes}
        placeholder={t('newCustomer.notesPlaceholder')}
        multiline
        editable={!save.isPending}
        style={styles.notes}
      />

      <View style={styles.switchRow}>
        <View style={{ flex: 1, paddingRight: space.md }}>
          <Text style={styles.switchLabel}>{t('newCustomer.taxExempt')}</Text>
          <Text style={styles.switchHint}>{t('newCustomer.taxExemptHint')}</Text>
        </View>
        <Switch value={taxExempt} onValueChange={setTaxExempt} disabled={save.isPending} />
      </View>
      {taxExempt ? (
        <Field
          label={t('newCustomer.taxExemptNumber')}
          value={taxExemptNumber}
          onChangeText={setTaxExemptNumber}
          placeholder="ST5-123456"
          autoCapitalize="characters"
          editable={!save.isPending}
        />
      ) : null}

      <View style={{ marginTop: space.lg }}>
        <Button
          title={
            isEdit
              ? t('newCustomer.saveChanges')
              : forQuote
                ? t('newCustomer.createUseQuote')
                : t('newCustomer.create')
          }
          onPress={() => save.mutate()}
          loading={save.isPending}
          disabled={trimmedName.length === 0}
        />
      </View>
      {isEdit && taxExempt ? <Text style={styles.docHint}>{t('newCustomer.docHint')}</Text> : null}
    </KeyboardAwareScrollView>
  );
}

const styles = StyleSheet.create({
  closeBtn: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeText: { fontSize: 28, lineHeight: 30, color: colors.primary, fontWeight: '500' },
  notes: { minHeight: 80, textAlignVertical: 'top' },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.md,
    marginBottom: space.md,
  },
  switchLabel: { fontSize: 15, fontWeight: '600', color: colors.text },
  switchHint: { fontSize: 12, color: colors.muted, marginTop: 2 },
  docHint: { fontSize: 13, color: colors.muted, marginTop: space.md, textAlign: 'center' },
});
