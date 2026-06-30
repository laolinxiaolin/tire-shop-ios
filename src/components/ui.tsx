import React, { useContext, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  EmitterSubscription,
  Keyboard,
  KeyboardAvoidingView,
  KeyboardEvent,
  Platform,
  Pressable,
  ScrollView,
  ScrollViewProps,
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  View,
  ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useI18n } from '../lib/i18n';
import { colors, radius, space, statusColor } from '../theme';

// Clearance kept between the focused field and the top of the keyboard. Set
// generously (a couple of button-heights) because under edge-to-edge the
// reported keyboard top sits lower than the area actually obscured by the
// keyboard + gesture bar; we'd rather over-lift than leave the box covered.
const KEYBOARD_GAP = 150;

// Lets the shared input components (`Field`, `SearchBar`) tell the enclosing
// KeyboardAwareScrollView that an input was focused, so it can re-scroll even
// when the keyboard is already open (switching between fields fires no
// keyboard event).
const FocusNotifyContext = React.createContext<(() => void) | null>(null);

/**
 * Scrollable screen body that keeps the focused input above the soft keyboard
 * (issue #314).
 *
 * Why this is hand-rolled instead of `KeyboardAvoidingView`: this app builds
 * edge-to-edge (`edgeToEdgeEnabled=true` in android/gradle.properties), which
 * makes Android draw *behind* the keyboard — `adjustResize` and RN's
 * `KeyboardAvoidingView` then only shrink the viewport without bringing a
 * bottom-anchored field fully into view (the box "doesn't move up enough").
 * Instead we measure the focused input and scroll it clear of the keyboard
 * ourselves, with a trailing spacer the height of the keyboard so there's
 * always room to scroll the last field (and the submit button) above it. Pure
 * JS — no native keyboard module needed.
 */
export function KeyboardAwareScrollView({
  children,
  contentContainerStyle,
  style,
  onScroll,
  ...rest
}: ScrollViewProps & { children: React.ReactNode }) {
  const insets = useSafeAreaInsets();
  const ref = useRef<ScrollView>(null);
  const offsetY = useRef(0);
  const keyboardTop = useRef(0); // screen-space Y of the top of the keyboard
  const pending = useRef(false); // a scroll is wanted once layout has room
  const [kbHeight, setKbHeight] = useState(0);

  useEffect(() => {
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';

    const onShow = (e: KeyboardEvent) => {
      // `screenY` is the absolute top of the keyboard — same coordinate space as
      // measureInWindow — which is reliable under edge-to-edge (unlike deriving
      // it from the window height).
      keyboardTop.current = e.endCoordinates?.screenY ?? 0;
      pending.current = true;
      setKbHeight(e.endCoordinates?.height ?? 0); // grows the spacer → onContentSizeChange
      // Fallback in case the content size doesn't change (keyboard already open).
      setTimeout(scrollFocusedIntoView, 120);
    };
    const onHide = () => {
      pending.current = false;
      setKbHeight(0);
    };

    const subs: EmitterSubscription[] = [
      Keyboard.addListener(showEvt, onShow),
      Keyboard.addListener(hideEvt, onHide),
    ];
    return () => subs.forEach((s) => s.remove());
  }, []);

  const scrollFocusedIntoView = () => {
    const input = TextInput.State.currentlyFocusedInput?.();
    const scroll = ref.current;
    if (!pending.current || !input || !scroll || keyboardTop.current <= 0) return;
    try {
      input.measureInWindow((_x, y, _w, h) => {
        // Coordinate fudge for edge-to-edge: measureInWindow's Y is relative to
        // the content area inside the system bars, while the keyboard's screenY
        // is full-screen, so without adding the insets back we under-scroll by
        // the status bar (top) + gesture/nav bar (bottom) — the bottom one is
        // roughly a button tall, which is the "still short" gap.
        const margin = KEYBOARD_GAP + insets.top + insets.bottom;
        const overlap = y + h + margin - keyboardTop.current;
        if (overlap > 0) scroll.scrollTo({ y: offsetY.current + overlap, animated: true });
        pending.current = false;
      });
    } catch {
      // measureInWindow can throw if the node unmounted mid-animation — ignore.
      pending.current = false;
    }
  };

  // Called by focused inputs (via context). If the keyboard is already up,
  // re-scroll to the newly focused field; otherwise the keyboard event handles it.
  const onChildFocus = () => {
    if (kbHeight > 0) {
      pending.current = true;
      requestAnimationFrame(scrollFocusedIntoView);
    }
  };

  return (
    <FocusNotifyContext.Provider value={onChildFocus}>
      <ScrollView
        ref={ref}
        style={[styles.flex, style]}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        scrollEventThrottle={16}
        onScroll={(e) => {
          offsetY.current = e.nativeEvent.contentOffset.y;
          onScroll?.(e);
        }}
        // Fires after the trailing spacer has grown, so there's room to scroll —
        // this is what fixes the focused field only moving up "a little".
        onContentSizeChange={scrollFocusedIntoView}
        contentContainerStyle={[{ paddingBottom: space.xl + insets.bottom }, contentContainerStyle]}
        {...rest}
      >
        {children}
        {/* Trailing spacer gives room to scroll the last field (and the submit
            button below it) above the keyboard. A spacer rather than
            contentContainer padding so a screen's own paddingBottom can't
            override it. */}
        <View style={{ height: kbHeight }} />
      </ScrollView>
    </FocusNotifyContext.Provider>
  );
}

/**
 * Keyboard-avoiding wrapper for full-screen modals (e.g. payment or create
 * sheets) whose fixed footer button must lift above the keyboard. `padding` on
 * iOS, `height` on Android — both stay active under edge-to-edge (a
 * `behavior={undefined}` would be a no-op on Android, issue #314).
 */
export function KeyboardAvoider({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: ViewStyle;
}) {
  return (
    <KeyboardAvoidingView
      style={[styles.flex, style]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      {children}
    </KeyboardAvoidingView>
  );
}

export function Card({ children, style }: { children: React.ReactNode; style?: ViewStyle }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function Row({
  title,
  subtitle,
  right,
  onPress,
}: {
  title: string;
  subtitle?: string | null;
  right?: React.ReactNode;
  onPress?: () => void;
}) {
  const body = (
    <View style={styles.row}>
      <View style={{ flex: 1, paddingRight: space.sm }}>
        <Text style={styles.rowTitle} numberOfLines={1}>
          {title}
        </Text>
        {subtitle ? (
          <Text style={styles.rowSub} numberOfLines={1}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {right ? <View style={styles.rowRight}>{right}</View> : null}
    </View>
  );
  if (!onPress) return body;
  return (
    <Pressable
      android_ripple={{ color: colors.border }}
      style={({ pressed }) => (pressed ? styles.pressed : null)}
      onPress={onPress}
    >
      {body}
    </Pressable>
  );
}

/** A tappable "＋ <label>" action row, e.g. above a list to create a new item. */
export function AddRow({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      android_ripple={{ color: colors.border }}
      style={({ pressed }) => [styles.addRow, pressed ? { opacity: 0.6 } : null]}
    >
      <Text style={styles.addRowText}>＋ {label}</Text>
    </Pressable>
  );
}

/** `label` keys the color (raw status enum); `text` is the displayed string —
 * pass a translated value to localize while keeping the status-based color. */
export function Badge({ label, text }: { label: string; text?: string }) {
  const c = statusColor[label] ?? { bg: colors.border, fg: colors.muted };
  return (
    <View style={[styles.badge, { backgroundColor: c.bg }]}>
      <Text style={[styles.badgeText, { color: c.fg }]}>{text ?? label}</Text>
    </View>
  );
}

type FocusHandler = NonNullable<TextInputProps['onFocus']>;

export function SearchBar(props: TextInputProps) {
  const notifyFocus = useContext(FocusNotifyContext);
  const onFocus: FocusHandler = (e) => {
    notifyFocus?.();
    props.onFocus?.(e);
  };
  return (
    <TextInput
      placeholderTextColor={colors.muted}
      autoCapitalize="none"
      autoCorrect={false}
      clearButtonMode="while-editing"
      returnKeyType="search"
      {...props}
      onFocus={onFocus}
      style={[styles.search, props.style]}
    />
  );
}

export function Field({ label, ...props }: TextInputProps & { label: string }) {
  const notifyFocus = useContext(FocusNotifyContext);
  const onFocus: FocusHandler = (e) => {
    notifyFocus?.();
    props.onFocus?.(e);
  };
  return (
    <View style={{ marginBottom: space.md }}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        placeholderTextColor={colors.muted}
        {...props}
        onFocus={onFocus}
        style={[styles.input, props.style]}
      />
    </View>
  );
}

export function Button({
  title,
  onPress,
  loading,
  disabled,
  variant = 'primary',
}: {
  title: string;
  onPress: () => void;
  loading?: boolean;
  disabled?: boolean;
  variant?: 'primary' | 'secondary' | 'danger';
}) {
  const isDisabled = disabled || loading;
  const bg =
    variant === 'secondary' ? colors.card : variant === 'danger' ? colors.danger : colors.primary;
  const fg = variant === 'secondary' ? colors.primary : colors.primaryText;
  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      style={({ pressed }) => [
        styles.button,
        {
          backgroundColor: bg,
          borderColor: variant === 'secondary' ? colors.primary : 'transparent',
        },
        isDisabled ? { opacity: 0.5 } : null,
        pressed ? { opacity: 0.85 } : null,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={fg} />
      ) : (
        <Text style={[styles.buttonText, { color: fg }]}>{title}</Text>
      )}
    </Pressable>
  );
}

export function Loading({ label }: { label?: string }) {
  return (
    <View style={styles.center}>
      <ActivityIndicator size="large" color={colors.primary} />
      {label ? <Text style={styles.centerText}>{label}</Text> : null}
    </View>
  );
}

export function ErrorView({ message, onRetry }: { message: string; onRetry?: () => void }) {
  const { t } = useI18n();
  return (
    <View style={styles.center}>
      <Text style={[styles.centerText, { color: colors.danger }]}>{message}</Text>
      {onRetry ? (
        <View style={{ marginTop: space.md }}>
          <Button title={t('common.retry')} variant="secondary" onPress={onRetry} />
        </View>
      ) : null}
    </View>
  );
}

export function Empty({ message }: { message: string }) {
  return (
    <View style={styles.center}>
      <Text style={styles.centerText}>{message}</Text>
    </View>
  );
}

export function Divider() {
  return <View style={styles.divider} />;
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    padding: space.lg,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: space.md,
    paddingHorizontal: space.lg,
    backgroundColor: colors.card,
  },
  rowTitle: { fontSize: 16, fontWeight: '600', color: colors.text },
  rowSub: { fontSize: 13, color: colors.muted, marginTop: 2 },
  rowRight: { alignItems: 'flex-end' },
  pressed: { opacity: 0.6 },
  addRow: {
    paddingHorizontal: space.lg,
    paddingVertical: space.md,
    backgroundColor: colors.card,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  addRowText: { color: colors.primary, fontSize: 16, fontWeight: '600' },
  badge: {
    borderRadius: radius.sm,
    paddingHorizontal: space.sm,
    paddingVertical: 2,
    alignSelf: 'flex-start',
  },
  badgeText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
  search: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    paddingHorizontal: space.md,
    paddingVertical: space.md,
    margin: space.md,
    fontSize: 16,
    color: colors.text,
  },
  label: { fontSize: 13, fontWeight: '600', color: colors.muted, marginBottom: space.xs },
  input: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    paddingHorizontal: space.md,
    paddingVertical: space.md,
    fontSize: 16,
    color: colors.text,
  },
  button: {
    borderRadius: radius.md,
    paddingVertical: 14,
    paddingHorizontal: space.lg,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  buttonText: { fontSize: 16, fontWeight: '700' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: space.xl },
  centerText: { marginTop: space.sm, color: colors.muted, textAlign: 'center', fontSize: 15 },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginLeft: space.lg,
  },
});
