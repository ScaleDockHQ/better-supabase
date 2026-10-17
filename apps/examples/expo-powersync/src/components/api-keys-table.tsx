// #region recipe:api-keys-table
import { useApiKeys } from "better-supabase/blocks/api-keys/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { useState } from "react";
import {
  ActivityIndicator,
  Button,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";

import { API_SCHEMA } from "../lib/blocks";

/**
 * The organization's API keys with a field that creates one, whose token
 * shows only until it is dismissed, and a revoke button per key. Members
 * who can't manage the organization's keys create personal ones.
 */
export function ApiKeysTable({ personal = false }: { personal?: boolean }) {
  const [name, setName] = useState("");

  const { keys, created, creating, revoking, error, create, revoke, dismiss } =
    useApiKeys({ organizationId: tenantOf(useAuth()), schema: API_SCHEMA });

  const submit = async () => {
    if ((await create({ name: name.trim(), personal })).ok) {
      setName("");
    }
  };

  if (keys === undefined) {
    return <ActivityIndicator />;
  }

  return (
    <View style={{ gap: 8 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>API keys</Text>
      {keys.map((key) => {
        const revoked = key.state === "revoked" || key.state === "expired";

        return (
          <View
            key={key.id}
            style={{ flexDirection: "row", alignItems: "center", gap: 8 }}
          >
            <View style={{ flex: 1 }}>
              <Text>{key.name}</Text>
              <Text style={{ color: "#737373", fontFamily: "monospace" }}>
                {key.prefix}_{key.publicId}…
              </Text>
            </View>
            {revoked ? (
              <Text style={{ color: "#737373" }}>Revoked</Text>
            ) : (
              <Pressable
                accessibilityRole="button"
                disabled={revoking.includes(key.id)}
                onPress={() => void revoke(key.id)}
              >
                <Text style={{ color: "#b91c1c" }}>Revoke</Text>
              </Pressable>
            )}
          </View>
        );
      })}
      {created ? (
        <View style={{ gap: 4, padding: 8, backgroundColor: "#f5f5f5" }}>
          <Text>Copy the key now. It is not shown again.</Text>
          <Text selectable style={{ fontFamily: "monospace" }}>
            {created.token}
          </Text>
          <Button title="Done" onPress={dismiss} />
        </View>
      ) : null}
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
      <TextInput
        value={name}
        onChangeText={setName}
        placeholder="Key name, such as CI"
        maxLength={80}
        style={{ borderWidth: 1, borderRadius: 8, padding: 8 }}
      />
      <Button
        title="Create key"
        disabled={creating || !name.trim()}
        onPress={() => void submit()}
      />
    </View>
  );
}
// #endregion recipe:api-keys-table
