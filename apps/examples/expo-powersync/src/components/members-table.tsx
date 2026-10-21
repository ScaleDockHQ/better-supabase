// #region recipe:members-table
import { useMembers } from "better-supabase/blocks/organizations/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { ActivityIndicator, Pressable, Text, View } from "react-native";

import { API_SCHEMA } from "../lib/blocks";

/**
 * The active organization's members. Pressing a role switches it between member
 * and admin at once; the organizations module refuses a role above the
 * caller's, and the row shows the old role again.
 */
export function MembersTable() {
  const auth = useAuth();

  const { members, pending, error, setRole, remove } = useMembers({
    organizationId: tenantOf(auth),
    schema: API_SCHEMA,
  });

  if (members === undefined) {
    return <ActivityIndicator />;
  }

  return (
    <View style={{ gap: 4 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Members</Text>
      {members.map((member) => {
        const busy = pending.includes(member.userId);

        const editable =
          member.userId !== auth.user?.id && member.role !== "owner";

        const next = member.role === "admin" ? "member" : "admin";

        return (
          <View
            key={member.userId}
            accessibilityState={{ busy }}
            style={{
              flexDirection: "row",
              alignItems: "center",
              gap: 8,
              paddingVertical: 8,
              opacity: busy ? 0.5 : 1,
            }}
          >
            <Text style={{ flex: 1 }} numberOfLines={1}>
              {member.userId === auth.user?.id ? "You" : member.userId}
            </Text>
            <Pressable
              accessibilityRole="button"
              accessibilityHint={editable ? `Changes the role to ${next}` : ""}
              disabled={!editable || busy}
              onPress={() => void setRole(member.userId, next)}
            >
              <Text style={{ color: editable ? "#2563eb" : "#737373" }}>
                {member.role}
              </Text>
            </Pressable>
            {editable ? (
              <Pressable
                accessibilityRole="button"
                disabled={busy}
                onPress={() => void remove(member.userId)}
              >
                <Text style={{ color: "#b91c1c" }}>Remove</Text>
              </Pressable>
            ) : null}
          </View>
        );
      })}
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
    </View>
  );
}
// #endregion recipe:members-table
