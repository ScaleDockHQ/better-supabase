import { useConflicts, useDebouncedSearch } from "better-supabase/react";
import { router } from "expo-router";
import { useState } from "react";
import { Button, Text, TextInput, View } from "react-native";

import { useCustomerPage } from "../lib/customer-page";
import { signOut } from "../lib/push";
import { customerList } from "../lists";
import { CustomerRows } from "./customer-rows";
import { UnreadBadge } from "./unread-badge";

/**
 * IOS and Android: the same list over the synced SQLite database, read again
 * when a synced or local change touches `customers`.
 */
export function CustomerList() {
  const search = useDebouncedSearch();
  const [page, setPage] = useState(1);

  const query =
    search.term === undefined
      ? { ...customerList.defaults, page }
      : { ...customerList.defaults, q: search.term, page };

  const list = useCustomerPage(query);
  const conflicts = useConflicts();

  const onSearch = (value: string) => {
    search.setValue(value);
    setPage(1);
  };

  return (
    <View style={{ flex: 1 }}>
      <UnreadBadge />
      <TextInput
        value={search.value}
        onChangeText={onSearch}
        placeholder="Search by name or KvK"
      />
      {list.error ? <Text>{list.error.message}</Text> : null}
      {list.data ? (
        <CustomerRows
          rows={list.data.items}
          footer={
            <View>
              <Text>{list.data.page.total} customers on this device</Text>
              <Button
                title="Previous"
                disabled={page === 1}
                onPress={() => {
                  setPage((current) => current - 1);
                }}
              />
              <Button
                title="Next"
                disabled={!list.data.page.hasMore}
                onPress={() => {
                  setPage((current) => current + 1);
                }}
              />
              {conflicts.changes.length > 0 ? (
                <Button
                  title={`Dismiss ${conflicts.changes.length} refused changes`}
                  onPress={() => {
                    conflicts.dismiss();
                  }}
                />
              ) : null}
              <Button
                title="Notifications and search"
                onPress={() => {
                  router.push("/activity");
                }}
              />
              <Button
                title="Members, API keys and audit log"
                onPress={() => {
                  router.push("/team");
                }}
              />
              <Button title="Sign out" onPress={() => void signOut()} />
            </View>
          }
        />
      ) : (
        <Text>Loading</Text>
      )}
    </View>
  );
}
