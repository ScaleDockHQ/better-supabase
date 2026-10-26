import { defineConfig, devices } from "@playwright/test";

const port = 3002;

/**
 * The docs app uses Cache Components and Partial Prefetching. The build must
 * prerender every page and expose the testing API, or an `instant()` check
 * passes without holding the navigation.
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
    command: `pnpm --dir ../.. exec turbo run build --filter=docs && pnpm exec next start -p ${String(port)}`,
    url: `http://127.0.0.1:${String(port)}/docs`,
    env: { EXPOSE_TESTING_API: "1", BSB_BUILD_SCOPE: "full" },
    reuseExistingServer: false,
    timeout: 900_000,
  },
});
