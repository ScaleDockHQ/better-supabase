import {
  column,
  PowerSyncDatabase,
  Schema,
  Table,
} from "@powersync/react-native";

import { blockTables } from "../../../powersync/schema";

/**
 * The synced columns of `public.customers`, and the block tables
 * `better-supabase powersync streams` writes to `powersync/schema.ts` for the
 * notifications, memberships, teams and profiles instances. PowerSync adds the
 * text `id`, `<organization>:<user>` for a membership.
 */
const schema = new Schema({
  customers: new Table({
    organization_id: column.text,
    name: column.text,
    status: column.text,
    kvk: column.text,
    created_at: column.text,
    updated_at: column.text,
  }),
  ...blockTables,
});

export const powersync = new PowerSyncDatabase({
  schema,
  database: { dbFilename: "better-supabase-example.db" },
});
