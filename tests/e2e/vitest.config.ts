import { defineConfig } from "vitest/config";

import { stack } from "./src/stack-config.ts";

export default defineConfig({
  test: {
    include: ["src/**/*.e2e.test.ts"],
    env: {
      SUPABASE_URL: stack.url,
      SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
    },
    testTimeout: 30_000,
    hookTimeout: 120_000,
  },
});
