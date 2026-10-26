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
    // other block instances as needing the network.
    powersync: { instances: ["notifications", "memberships"] },
  },
  blocks: {
    memberships: { api: false, tables: { memberships: "public.memberships" } },
    permissions: { model: "catalog", activeTenant: "claim" },
    comments: {},
    tags: {},
    notifications: {},
  },
});
