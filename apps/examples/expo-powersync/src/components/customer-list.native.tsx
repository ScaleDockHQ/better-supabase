import { useConflicts, useDebouncedSearch } from "better-supabase/react";
import { router } from "expo-router";
import { Button, Text, TextInput, View } from "react-native";

import { useInfiniteCustomers } from "../lib/customer-page";
import { signOut } from "../lib/push";
import { CustomerRows } from "./customer-rows";
import { UnreadBadge } from "./unread-badge";

const PAGE_SIZE = 25;

/**
 * IOS and Android: customers from the synced SQLite database, one cursor page
 * after another. A synced or local change to `customers` reads the page again.
 */
export function CustomerList() {
  const search = useDebouncedSearch();

  const list = useInfiniteCustomers(
    search.term === undefined
      ? { size: PAGE_SIZE }
      : { size: PAGE_SIZE, q: search.term },
  );

  const conflicts = useConflicts();

  return (
    <View style={{ flex: 1 }}>
      <UnreadBadge />
      <TextInput
        value={search.value}
        onChangeText={search.setValue}
        placeholder="Search by name or KvK"
      />
      {list.error ? <Text>{list.error.message}</Text> : null}
      {list.isPending && list.items.length === 0 ? <Text>Loading</Text> : null}
      <CustomerRows
        rows={list.items}
        onEndReached={list.hasMore ? list.fetchNextPage : undefined}
        footer={
          <View>
            <Text>
              {list.items.length} customers loaded
              {list.hasMore ? ", more below" : ""}
            </Text>
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
    </View>
  );
}
