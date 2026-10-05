import {
  column,
  PowerSyncDatabase,
  Schema,
  Table,
} from "@powersync/react-native";
import { powersyncExecutor } from "better-supabase/powersync";

import { betterSupabase } from "../supabase";
import { connector } from "./connector";

/** The synced columns of `public.customers`; PowerSync adds the text `id`. */
const schema = new Schema({
  customers: new Table({
    organization_id: column.text,
    name: column.text,
    status: column.text,
    kvk: column.text,
    created_at: column.text,
    updated_at: column.text,
  }),
});

export const powersync = new PowerSyncDatabase({
  schema,
  database: { dbFilename: "better-supabase-example.db" },
});

/** Repositories over the device database: the same `db.customers` API, read offline. */
export const local = betterSupabase.connect(powersyncExecutor(powersync));

export async function startSync(): Promise<void> {
  await powersync.init();
  await powersync.connect(connector);
}
