import { tenantOf, useAuth } from "better-supabase/react";
import { Pressable, Text, View } from "react-native";

import { useMembers } from "../hooks/use-organizations";
import { API_SCHEMA } from "../lib/blocks";

/**
 * The organization's admins, each with a button that makes them a member. The
 * role change bumps their authorization version: their device hears it on
 * `authz:<uid>`, refreshes the token and reconnects PowerSync, so its access
 * checks and any stream that filters on the role follow the new role.
 */
export function RevokeAdmin() {
  const auth = useAuth();

  const { members, pending, error, setRole } = useMembers({
    organizationId: tenantOf(auth),
    schema: API_SCHEMA,
  });

  const admins = (members ?? []).filter(
    (member) => member.role === "admin" && member.userId !== auth.user?.id,
  );

  if (admins.length === 0) {
    return null;
  }

  return (
    <View style={{ gap: 4 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Revoke admin</Text>
      {admins.map((member) => (
        <Pressable
          key={member.userId}
          accessibilityRole="button"
          accessibilityHint="Makes this admin a member"
          disabled={pending.includes(member.userId)}
          onPress={() =>
            void setRole({ userId: member.userId, role: "member" })
          }
          style={{ paddingVertical: 8 }}
        >
          <Text style={{ color: "#b91c1c" }} numberOfLines={1}>
            {member.userId}
          </Text>
        </Pressable>
      ))}
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
    </View>
  );
}
