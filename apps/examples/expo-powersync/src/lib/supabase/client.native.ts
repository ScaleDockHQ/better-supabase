import { createNativeClient, nativePorts } from "better-supabase/client/native";
import { powersyncEngine } from "better-supabase/powersync";
import * as Linking from "expo-linking";
import * as Notifications from "expo-notifications";

import { betterSupabase } from ".";
import { blockConfig } from "../blocks";
import { connector } from "../powersync/connector";
import { powersync } from "../powersync/database";
import { supabase } from "./supabase.native";

export { supabase } from "./supabase.native";

/**
 * `bsb.db` and the data hooks read and write the PowerSync database for the
 * synced `customers` table, offline too; PowerSync uploads the writes through
 * `connector`. Every other table, and what SQLite can't run, goes to PostgREST
 * as the signed-in user. The ports give the block hooks (`useNotifications` and
 * the rest) their React Native deep links, push token and uploads, and `blocks`
 * the schema they call.
 */
export const bsb = createNativeClient(betterSupabase, supabase, {
  blocks: blockConfig,
  engine: powersyncEngine(powersync, {
    connector,
    local: ["customers"],
    tables: { "customer-pages": ["customers"] },
  }),
  ports: nativePorts({
    supabase,
    linking: Linking,
    notifications: Notifications,
    projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
  }),
});
