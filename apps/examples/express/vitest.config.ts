import { defineConfig } from "vitest/config";

// Workspace packages resolve to their TypeScript source, so tests run without
// building them first. The rest is Vite's default server condition list.
const conditions = [
  "@better-supabase/source",
  "module",
  "node",
  "development|production",
];

export default defineConfig({
  resolve: { conditions },
  ssr: { resolve: { conditions } },
  test: {
    env: {
      // `pnpm env:local` writes it; without it the suite skips like it does
      // when the stack is down.
      SUPABASE_URL:
        process.env["SUPABASE_URL"] ?? "http://supabase-url-not-set.invalid",
      SUPABASE_PUBLISHABLE_KEY:
        process.env["SUPABASE_PUBLISHABLE_KEY"] ??
        "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
    },
  },
});
