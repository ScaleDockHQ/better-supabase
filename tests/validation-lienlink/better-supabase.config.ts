import { defineConfig } from "better-supabase/config";

// Blocks own the better_supabase tables. The app's views in public project
// them, and its files alter them.
export default defineConfig({
  blocks: {
    organizations: {},
    memberships: {},
    profiles: {},
    teams: {},
    attachments: {},
    seeds: {},
  },
  database: { source: { snapshot: "snapshot.json" } },
  gen: {
    powersync: {
      instances: ["attachments", "memberships", "teams", "profiles"],
      // job_parties syncs with the jobs of the user's organizations.
      children: [
        { table: "public.job_parties", parent: "job", column: "job_id" },
      ],
    },
  },
});
