import { defineConfig } from "better-supabase/config";

// The app owns its tables in supabase/schemas/010_app.sql. The blocks adopt
// them and write only their own module files.
export default defineConfig({
  blocks: {
    organizations: { tables: { organizations: "public.organizations" } },
    memberships: {
      tables: { memberships: "public.memberships" },
      columns: { memberships: { tenant: "organization_id" } },
    },
    profiles: {
      tables: { profiles: "public.profiles" },
      columns: { profiles: { key: "user_id" } },
    },
  },
});
