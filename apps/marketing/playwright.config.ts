import { defineConfig, devices } from "@playwright/test";

const port = 3467;

/**
 * Smoke tests against a production build. `webServer` builds the site
 * through Turbo, so the catalog and the recipe index are generated first.
 */
export default defineConfig({
  testDir: "e2e",
  retries: 0,
  forbidOnly: true,
  reporter: [["list"]],
  use: {
    baseURL: `http://127.0.0.1:${String(port)}`,
    trace: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      testIgnore: /mobile\.spec\.ts/,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "mobile",
      testMatch: /mobile\.spec\.ts/,
      use: { ...devices["iPhone 13"], defaultBrowserType: "chromium" },
    },
  ],
  webServer: {
    command: `pnpm --dir ../.. exec turbo run build --filter=marketing && pnpm exec next start -p ${String(port)}`,
    url: `http://127.0.0.1:${String(port)}/create`,
    reuseExistingServer: false,
    timeout: 600_000,
    // Placeholder OAuth keys turn the Deploy button on; e2e/deploy.spec.ts
    // mocks every /create/supabase call, so Supabase is never reached.
    env: {
      SUPABASE_OAUTH_CLIENT_ID: "e2e-client",
      SUPABASE_OAUTH_CLIENT_SECRET: "e2e-secret",
      SUPABASE_OAUTH_COOKIE_SECRET: "e2e-cookie-secret-of-at-least-32-chars",
    },
  },
});
