import { Text } from "react-native";

import { useUnreadCount } from "../lib/notifications";

/** iOS and Android: the unread count from the shared notifications hook. */
export function UnreadBadge() {
  const { count, status } = useUnreadCount();
  return (
    <Text accessibilityLabel={`Notifications, ${String(count ?? 0)} unread`}>
      {count === undefined ? "Counting…" : `${String(count)} unread`}
      {status === "subscribed" ? "" : " (offline)"}
    </Text>
  );
}
