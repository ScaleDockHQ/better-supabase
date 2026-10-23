import { createUploadConnector } from "better-supabase/powersync";

import { server, supabase } from "../supabase/supabase.native";

/**
 * Replays local changes through `server.db.customers`, so RLS and validation
 * run as they do online. Transient errors retry, refused changes land in
 * `connector.rejected` for `useConflicts()`.
 */
export const connector = createUploadConnector({
  endpoint: process.env.EXPO_PUBLIC_POWERSYNC_URL,
  supabase,
  tables: { customers: server.db.customers },
});
