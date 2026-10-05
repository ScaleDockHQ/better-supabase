import { sqliteTables, watch } from "better-supabase/powersync";
import { useEffect, useState } from "react";
import { Text } from "react-native";

import { conflicts } from "../lib/powersync/connector";
import { local, powersync } from "../lib/powersync/database";
import { betterSupabase } from "../lib/supabase";
import { customerColumns, customerList } from "../lists";
import { CustomerRows } from "./customer-rows";

const tables = sqliteTables(betterSupabase, ["customers"]);

const load = () =>
  customerList.run(local, customerList.defaults, { select: customerColumns });

type Loaded = Awaited<ReturnType<typeof load>>;

/** iOS and Android: the same list over the synced SQLite database, rerun on every change. */
export function CustomerList() {
  const [result, setResult] = useState<Loaded>();
  useEffect(() => watch(powersync, load, { tables, onResult: setResult }), []);
  if (!result) return <Text>Loading</Text>;
  if (!result.ok) return <Text>{result.error.message}</Text>;
  return (
    <CustomerRows
      rows={result.data.items}
      footer={
        <Text>
          {result.data.page.total} customers on this device, {conflicts.length}{" "}
          changes the server refused
        </Text>
      }
    />
  );
}
