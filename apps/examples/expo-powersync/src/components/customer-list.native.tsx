import { useConflicts, useWatch } from "better-supabase/powersync/react";
import { useDebouncedSearch } from "better-supabase/react";
import { useState } from "react";
import { Button, Text, TextInput, View } from "react-native";

import { connector } from "../lib/powersync/connector";
import { customerTables, local, powersync } from "../lib/powersync/database";
import { signOut } from "../lib/push";
import { customerColumns, customerList } from "../lists";
import { CustomerRows } from "./customer-rows";

/** iOS and Android: the same list over the synced SQLite database, rerun on every change. */
export function CustomerList() {
  const search = useDebouncedSearch();
  const [page, setPage] = useState(1);
  const query =
    search.term === undefined
      ? { ...customerList.defaults, page }
      : { ...customerList.defaults, q: search.term, page };
  const list = useWatch({
    db: powersync,
    query: () => customerList.run(local, query, { select: customerColumns }),
    tables: customerTables,
    deps: [search.term, page],
  });
  const conflicts = useConflicts(connector);

  const onSearch = (value: string) => {
    search.setValue(value);
    setPage(1);
  };

  return (
    <View style={{ flex: 1 }}>
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
