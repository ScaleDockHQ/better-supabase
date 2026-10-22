// Stands in for the `src/lib/supabase/blocks.generated.ts` that
// `better-supabase gen` writes from the `blocks` config, so the items
// typecheck without an app.
import type { GeneratedBlocks } from "better-supabase/blocks";

export const blockConfig = {
  audit: { schema: "better_supabase", api: "api", options: {} },
  notifications: {
    schema: "better_supabase",
    api: "api",
    options: { topic: "notifications:{userId}" },
  },
  organizations: { schema: "better_supabase", api: "api", options: {} },
  automations: { schema: "better_supabase", api: "api", options: {} },
  search: { schema: "better_supabase", api: "api", options: {} },
} as const satisfies GeneratedBlocks;
