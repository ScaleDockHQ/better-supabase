import { syncWithAuth } from "better-supabase/powersync";
import { useEffect } from "react";

import { bs } from "../supabase/native";
import { connector } from "./connector";
import { powersync } from "./database";

/**
 * Syncs while a user is signed in. Signing out, or another user signing
 * in, disconnects and clears the device database.
 */
export function useSync(): void {
  useEffect(() => syncWithAuth(powersync, bs.auth, { connector }), []);
}
