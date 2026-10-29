import type { SwitchResult } from "better-supabase/blocks/organizations";
import type { AuthSync } from "better-supabase/powersync";

import { syncWithAuth } from "better-supabase/powersync";

import { bsb, supabase } from "../supabase/client.native";
import { connector } from "./connector";
import { powersync } from "./database";

/**
 * Syncs while a user is signed in. Signing out, or another user signing in,
 * disconnects and clears the device database. A new token with another
 * organization or authorization version reconnects, so the sync service drops
 * the rows the user lost. The root layout hands it to `<SessionProvider>`.
 */
export const sync: AuthSync = syncWithAuth(powersync, bsb.auth, { connector });

/**
 * After a switch: refreshes the token so it carries the new organization, then
 * waits for the sync service to serve that organization's rows.
 */
export async function afterSwitch(result: SwitchResult): Promise<void> {
  if (result.refresh) {
    const { error } = await supabase.auth.refreshSession();

    if (error) {
      throw error;
    }
  }

  await sync.reconnect();
}
