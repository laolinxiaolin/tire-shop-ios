import { NavigationContainer } from '@react-navigation/native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StripeTerminalProvider } from '@stripe/stripe-terminal-react-native';
import { Loading } from './src/components/ui';
import { payments } from './src/lib/api';
import { I18nProvider } from './src/lib/i18n';
import RootNavigator from './src/navigation/RootNavigator';
import LoginScreen from './src/screens/LoginScreen';
import { useI18n } from './src/lib/i18n';
import { AuthProvider, useAuth } from './src/state/auth';
import { QuoteProvider } from './src/state/quote';
import { TabsProvider } from './src/state/tabs';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 30_000 } },
});

// Mints a Terminal connection token from our backend. Called lazily by the SDK
// once the user reaches the Tap to Pay flow (by which point they're signed in).
const fetchConnectionToken = async () => (await payments.connectionToken()).secret;

function Gate() {
  const { ready, user } = useAuth();
  const { t } = useI18n();
  if (!ready) return <Loading label={t('common.loading')} />;
  return user ? <RootNavigator /> : <LoginScreen />;
}

export default function App() {
  return (
    <SafeAreaProvider>
      <QueryClientProvider client={queryClient}>
        <I18nProvider>
          <AuthProvider>
            <QuoteProvider>
              <TabsProvider>
                <StripeTerminalProvider tokenProvider={fetchConnectionToken} logLevel="verbose">
                  <NavigationContainer>
                    <Gate />
                  </NavigationContainer>
                </StripeTerminalProvider>
              </TabsProvider>
              <StatusBar style="dark" />
            </QuoteProvider>
          </AuthProvider>
        </I18nProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}
