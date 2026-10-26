import {
  createNotifications,
  rpcTransport,
} from "better-supabase/blocks/notifications";
import { createOrganizations } from "better-supabase/blocks/organizations";
import {
  createUploadConnector,
  membershipsRoute,
  notificationRecipientsRoute,
} from "better-supabase/powersync";

import { API_SCHEMA } from "../blocks";
import { server, supabase } from "../supabase/supabase.native";

/** On the Data API, not the device database, so a replay reaches the server. */
const notifications = createNotifications({
  transport: rpcTransport(supabase, { schema: API_SCHEMA }),
  types: {},
});

const organizations = createOrganizations({
  transport: rpcTransport(supabase),
  schema: API_SCHEMA,
});

/**
 * Replays local changes through `server.db.customers`, so RLS and validation
 * run as they do online, marks read or dismissed through the notifications
 * functions, and replays leaving an organization through the organizations
 * functions. Transient errors retry, refused changes land in
 * `connector.rejected` for `useConflicts()`.
 */
export const connector = createUploadConnector({
  endpoint: process.env.EXPO_PUBLIC_POWERSYNC_URL,
  supabase,
  tables: {
    customers: server.db.customers,
    notification_recipients: notificationRecipientsRoute(notifications),
    memberships: membershipsRoute(organizations),
  },
});
