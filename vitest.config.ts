import { defineConfig } from "vitest/config";

// Editor and ad hoc runs; CI runs each workspace's `test` task through Turbo.
export default defineConfig({
  test: {
    projects: [
      "packages/better-supabase",
      "packages/registry",
      "apps/docs",
      "apps/marketing",
      "apps/examples/express",
      "apps/examples/nextjs",
      "tests/bundle",
      "tests/validation-centrakit",
      "tests/validation-recipes",
      "tests/validation-presets",
      "tests/validation-crm",
      "tests/validation-monorepo",
      "tests/validation-request-context",
    ],
  },
});
