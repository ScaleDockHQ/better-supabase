import { defineConfig } from "better-supabase/config";

// No organizations and no memberships: the modules below read the signed-in
// user and never a tenant.
export default defineConfig({
  blocks: {
    profiles: {
      tables: { profiles: "public.profiles" },
      columns: { profiles: { key: "user_id" } },
    },
    sessions: {},
  },
});
