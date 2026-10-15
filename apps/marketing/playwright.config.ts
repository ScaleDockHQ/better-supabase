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
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `pnpm --dir ../.. exec turbo run build --filter=marketing && pnpm exec next start -p ${String(port)}`,
    url: `http://127.0.0.1:${String(port)}/create`,
    reuseExistingServer: false,
    timeout: 600_000,
  },
});
