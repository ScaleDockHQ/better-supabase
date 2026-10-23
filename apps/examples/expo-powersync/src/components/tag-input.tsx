// #region recipe:tag-input
import { useState } from "react";
import {
  ActivityIndicator,
  Button,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";

import { useTagInput } from "../hooks/use-tags";

/**
 * A customer's tags as chips that remove themselves when pressed, the
 * organization's other tags as suggestions, and a field that adds or creates
 * one by name.
 */
export function TagInput({ customerId }: { readonly customerId: string }) {
  const [name, setName] = useState("");

  const { tags, available, pending, error, add, remove, create } = useTagInput({
    subject: { type: "customer", id: customerId },
    kind: "customer",
  });

  if (tags === undefined) {
    return <ActivityIndicator />;
  }

  const applied = new Set(tags.map((tag) => tag.id));
  const suggestions = (available ?? []).filter((tag) => !applied.has(tag.id));

  const chip = (label: string, busy: boolean, onPress: () => void) => (
    <Pressable
      key={label}
      accessibilityRole="button"
      disabled={busy}
      onPress={onPress}
      style={{
        borderWidth: 1,
        borderRadius: 16,
        paddingHorizontal: 10,
        paddingVertical: 2,
        opacity: busy ? 0.5 : 1,
      }}
    >
      <Text>{label}</Text>
    </Pressable>
  );

  return (
    <View style={{ gap: 8 }}>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
        {tags.length === 0 ? <Text>No tags yet.</Text> : null}
        {tags.map((tag) =>
          chip(`${tag.name} ×`, pending.includes(tag.id), () => {
            void remove(tag.id);
          }),
        )}
      </View>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
        {suggestions.map((tag) =>
          chip(`+ ${tag.name}`, pending.includes(tag.id), () => {
            void add(tag.id);
          }),
        )}
      </View>
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
      <TextInput
        value={name}
        onChangeText={setName}
        placeholder="Add a tag"
        maxLength={80}
        style={{ borderWidth: 1, borderRadius: 8, padding: 8 }}
      />
      <Button
        title="Add"
        disabled={!name.trim()}
        onPress={() =>
          void create(name).then((result) => {
            if (result.ok) {
              setName("");
            }
          })
        }
      />
    </View>
  );
}
// #endregion recipe:tag-input
