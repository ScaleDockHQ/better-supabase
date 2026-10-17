// #region recipe:command-search
import { useCommandSearch } from "better-supabase/blocks/search/react";
import {
  Modal,
  Pressable,
  SectionList,
  Text,
  TextInput,
  View,
} from "react-native";

import { API_SCHEMA } from "../lib/blocks";

function heading(key: string): string {
  if (key === "favorites") {
    return "Favorites";
  }
  if (key === "recents") {
    return "Recent";
  }
  if (key === "customer") {
    return "Customers";
  }
  return key;
}

/** Search over the search index: customers by name, plus recents and favorites. */
export function CommandSearch() {
  // Native has no Cmd+K, so the button opens it.
  const search = useCommandSearch({ schema: API_SCHEMA, shortcut: false });
  return (
    <>
      <Pressable
        accessibilityRole="button"
        onPress={() => {
          search.setOpen(true);
        }}
        style={{ padding: 8 }}
      >
        <Text>Search</Text>
      </Pressable>
      <Modal
        visible={search.open}
        animationType="slide"
        onRequestClose={() => {
          search.setOpen(false);
        }}
      >
        <View style={{ flex: 1, gap: 12, padding: 16 }}>
          <TextInput
            value={search.query}
            onChangeText={search.setQuery}
            placeholder="Search customers"
            accessibilityLabel="Search customers"
            style={{ borderWidth: 1, borderRadius: 8, padding: 8 }}
          />
          {search.error === undefined ? null : (
            <Text>Search failed. Try again.</Text>
          )}
          <SectionList
            sections={search.groups.map((group) => ({
              key: group.key,
              title: heading(group.key),
              data: group.items,
            }))}
            keyExtractor={(item) => `${item.subjectType}:${item.subjectId}`}
            renderSectionHeader={({ section }) => (
              <Text style={{ color: "#737373", marginTop: 12 }}>
                {section.title}
              </Text>
            )}
            renderItem={({ item }) => (
              <Pressable
                accessibilityRole="link"
                onPress={() => void search.select(item)}
                style={{ paddingVertical: 8 }}
              >
                <Text>{item.title ?? item.subjectId}</Text>
              </Pressable>
            )}
            ListEmptyComponent={
              search.loading ? null : (
                <Text>
                  {search.query.trim() === ""
                    ? "Type to search."
                    : "No matches."}
                </Text>
              )
            }
          />
          <Pressable
            accessibilityRole="button"
            onPress={() => {
              search.setOpen(false);
            }}
          >
            <Text>Close</Text>
          </Pressable>
        </View>
      </Modal>
    </>
  );
}
// #endregion recipe:command-search
