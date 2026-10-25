import {
  column,
  PowerSyncDatabase,
  Schema,
  Table,
} from "@powersync/react-native";

/**
 * The synced columns of `public.customers` and the notification tables
 * (`better-supabase powersync streams --instance notifications` writes them);
 * PowerSync adds the text `id`.
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
  notification_events: new Table({
    organization_id: column.text,
    type: column.text,
    data: column.text,
    actor_id: column.text,
    subject_type: column.text,
    subject_id: column.text,
    subject_label: column.text,
    summary: column.text,
    action_path: column.text,
    actions: column.text,
    priority: column.text,
    created_at: column.text,
  }),
  notification_recipients: new Table({
    event_id: column.text,
    user_id: column.text,
    organization_id: column.text,
    created_at: column.text,
    read_at: column.text,
    resolved_at: column.text,
    resolution: column.text,
    dismissed_at: column.text,
  }),
});

export const powersync = new PowerSyncDatabase({
  schema,
  database: { dbFilename: "better-supabase-example.db" },
});
