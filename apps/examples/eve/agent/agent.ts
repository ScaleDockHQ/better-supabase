import { defineAgent } from "eve";

export default defineAgent({
  model: "anthropic/claude-opus-5.5",
  experimental: {
    // Sessions run on the Supabase World; it reads SUPABASE_DB_URL.
    workflow: { world: "better-supabase/workflow-sdk/world" },
  },
});
