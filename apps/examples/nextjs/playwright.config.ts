import { defineConfig, devices } from "@playwright/test";

import { baseURL, port } from "./e2e/server";

/**
 * `instant()` checks against a production build. The build must expose the
 * testing API, so `webServer` builds with `EXPOSE_TESTING_API=1` itself
 * instead of reusing a server that may have been built without it.
 */
export default defineConfig({
  testDir: "e2e",
  fullyParallel: false,
  workers: 1,
  // An `instant()` guard is deterministic: a retry would hide the regression.
  retries: 0,
  forbidOnly: true,
  reporter: [["list"]],
  use: { baseURL, trace: "retain-on-failure" },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
      dependencies: ["setup"],
    },
  ],
  webServer: {
    command: `next build && next start -p ${String(port)}`,
    url: `${baseURL}/login`,
    env: { EXPOSE_TESTING_API: "1" },
    reuseExistingServer: false,
    timeout: 300_000,
  },
});
