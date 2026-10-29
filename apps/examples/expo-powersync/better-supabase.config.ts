import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: {
    source: { snapshot: "../../../supabase/snapshot.json" },
    // The Next.js example owns the database and writes the block SQL; this
    // app reads the same blocks through their `api` wrappers.
    sql: { api: "api" },
  },
  gen: {
    casing: "snake",
    output: "src/lib/supabase/generated.ts",
    hooks: "react",
    // Only the TypeScript: the block SQL and the PowerSync publication
    // migration belong to the Next.js example.
    tasks: ["types"],
    // The instances the PowerSync database serves on native. `gen` marks the
    // other block instances as needing the network, and `better-supabase
    // powersync streams` writes powersync/sync-streams.yaml for them.
    powersync: {
      instances: ["notifications", "memberships", "teams", "profiles"],
    },
  },
  blocks: {
    memberships: { api: false, tables: { memberships: "public.memberships" } },
    organizations: { tables: { organizations: "public.organizations" } },
    permissions: { model: "catalog", activeTenant: "claim" },
    comments: {},
    tags: {},
    notifications: {},
    teams: {},
    profiles: {},
    // A role change bumps the user's authorization version. The native
    // SessionProvider hears it on authz:<uid>, refreshes the token and
    // reconnects PowerSync, so the sync service drops the rows they lost.
    // `bootstrap` names better_supabase.bootstrap_islands, which the web
    // activity loader reads in one call.
    sessions: {
      options: {
        authzVersions: true,
        bootstrap: { islands: "public.island_counts" },
      },
    },
  },
});
