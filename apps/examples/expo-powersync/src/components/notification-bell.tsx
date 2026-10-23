// #region recipe:notification-bell
import type { NotificationCounts } from "better-supabase/blocks/notifications";

import { tenantOf, useAuth, useSupabase } from "better-supabase/react";
import { Pressable, Text, View } from "react-native";

import { useNotifications } from "../hooks/use-notifications";
import { blocks } from "../lib/blocks";

const unreadOf = (counts: readonly NotificationCounts[]): number =>
  counts[0]?.unread ?? 0;

/**
 * The unread count, loaded again after each broadcast on `notifications:<user
 * id>`.
 */
export function NotificationBell({
  onPress,
}: {
  readonly onPress: () => void;
}) {
  const auth = useAuth();
  const supabase = useSupabase();
  const tenant = tenantOf(auth);
  const userId = auth.user?.id;

  const { items, count } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: async () => {
      if (!tenant) {
        return [];
      }

      const result = await blocks(supabase).notifications.counts({ tenant });

      return result.ok ? [result.data] : [];
    },
    count: unreadOf,
  });

  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`Notifications, ${String(count)} unread`}
      style={{ flexDirection: "row", alignItems: "center", gap: 8, padding: 8 }}
    >
      <Text>Notifications</Text>
      <View
        style={{
          minWidth: 24,
          borderRadius: 12,
          paddingHorizontal: 8,
          backgroundColor: count ? "#111" : "#e5e5e5",
        }}
      >
        <Text style={{ color: count ? "#fff" : "#111", textAlign: "center" }}>
          {items === undefined ? "–" : count}
        </Text>
      </View>
    </Pressable>
  );
}
// #endregion recipe:notification-bell
