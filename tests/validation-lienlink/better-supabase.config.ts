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
});
