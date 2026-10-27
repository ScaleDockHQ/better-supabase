import { defineConfig, devices } from "@playwright/test";
import { existsSync } from "node:fs";

// The local stack's keys, with the repo root's per-branch ports first; `next
// build` would otherwise read .env.production. Earlier files win.
for (const file of [
  "../../../.env.development.local",
  ".env.development.local",
]) {
  if (existsSync(file)) {
    process.loadEnvFile(file);
  }
}

const baseURL = "http://localhost:3100";

// `instant()` needs a production build with the testing API exposed; under
// `next dev` the lock is ignored and every check passes without testing.
export default defineConfig({
  testDir: "tests",
  testMatch: "**/*.spec.ts",
  fullyParallel: false,
  retries: process.env["CI"] === undefined ? 0 : 1,
  use: { baseURL, trace: "retain-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "next build && next start -p 3100",
    url: `${baseURL}/en/login`,
    env: { EXPOSE_TESTING_API: "1" },
    reuseExistingServer: process.env["CI"] === undefined,
    timeout: 600_000,
  },
});
