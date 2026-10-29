// #region recipe:org-switcher
import type { OrganizationMembership } from "better-supabase/blocks/organizations";

import { ActivityIndicator, Pressable, Text, View } from "react-native";

import type { UseOrganizationsOptions } from "../hooks/use-organizations";

import { useOrganizations } from "../hooks/use-organizations";
import { API_SCHEMA } from "../lib/blocks";

/**
 * The caller's organizations. Pressing one switches to it, refreshes the
 * session so the token carries the new tenant, and loads the list again. `load`
 * reads them elsewhere, such as from the PowerSync database, and `onSwitched`
 * replaces the refresh, such as one that also reconnects sync.
 */
export function OrganizationSwitcher(
  props: Pick<
    UseOrganizationsOptions<OrganizationMembership>,
    "load" | "onSwitched"
  >,
) {
  const { organizations, activeId, switching, error, switchTo } =
    useOrganizations({ ...props, schema: API_SCHEMA });

  if (organizations === undefined) {
    return <ActivityIndicator />;
  }

  return (
    <View style={{ gap: 4 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Organizations</Text>
      {organizations.map((organization) => (
        <Pressable
          key={organization.id}
          accessibilityRole="button"
          accessibilityState={{
            selected: organization.id === activeId,
            busy: organization.id === switching,
          }}
          disabled={switching !== undefined || organization.id === activeId}
          onPress={() => void switchTo(organization.id)}
          style={{ flexDirection: "row", gap: 8, paddingVertical: 8 }}
        >
          <Text style={{ width: 16 }}>
            {organization.id === activeId ? "✓" : ""}
          </Text>
          <Text style={{ flex: 1 }}>{organization.name}</Text>
          <Text style={{ color: "#737373" }}>{organization.role}</Text>
        </Pressable>
      ))}
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
    </View>
  );
}
// #endregion recipe:org-switcher
