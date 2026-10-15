// #region recipe:notification-list
import { useNotifications } from "better-supabase/blocks/notifications/react";
import { tenantOf, useAuth, useSupabase } from "better-supabase/react";
import { ActivityIndicator, FlatList, Text, View } from "react-native";

import { blocks } from "../lib/blocks";

/**
 * The caller's latest notifications, loaded again after each broadcast on
 * their private topic `notifications:<user id>`: a new one, or one marked read.
 */
export function NotificationList() {
  const auth = useAuth();
  const supabase = useSupabase();
  const tenant = tenantOf(auth);
  const userId = auth.user?.id;
  const { items } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: async () => {
      if (!tenant) return [];
      const result = await blocks(supabase).notifications.list({
        tenant,
        limit: 20,
      });
      return result.ok ? result.data : [];
    },
  });
  if (items === undefined) return <ActivityIndicator />;
  return (
    <FlatList
      data={items}
      keyExtractor={(item) => item.id}
      ListEmptyComponent={<Text>Nothing here yet</Text>}
      renderItem={({ item }) => (
        <View style={{ flexDirection: "row", gap: 8, paddingVertical: 12 }}>
          <Text style={{ flex: 1 }}>{item.data.title}</Text>
          {item.readAt ? null : <Text style={{ fontWeight: "600" }}>New</Text>}
          <Text style={{ color: "#737373" }}>
            {item.createdAt.toLocaleString(undefined, {
              dateStyle: "medium",
              timeStyle: "short",
            })}
          </Text>
        </View>
      )}
    />
  );
}
// #endregion recipe:notification-list
