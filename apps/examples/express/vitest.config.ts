import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    env: {
      SUPABASE_URL: process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421",
      SUPABASE_PUBLISHABLE_KEY:
        process.env["SUPABASE_PUBLISHABLE_KEY"] ??
        "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
    },
  },
});
