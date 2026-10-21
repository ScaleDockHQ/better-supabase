import { defineConfig, devices } from "@playwright/test";

const port = 3467;

/**
 * Smoke tests against a production build. `webServer` builds the site through
 * Turbo, so the catalog and the recipe index are generated first.
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
    url: `http://127.0.0.1:${String(port)}/`,
    reuseExistingServer: false,
    timeout: 600_000,
  },
});
