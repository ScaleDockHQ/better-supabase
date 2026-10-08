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
      SUPABASE_URL: process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421",
      SUPABASE_PUBLISHABLE_KEY:
        process.env["SUPABASE_PUBLISHABLE_KEY"] ??
        "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
    },
  },
});
