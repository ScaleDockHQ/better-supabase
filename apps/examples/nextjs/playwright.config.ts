import { defineConfig, devices } from "@playwright/test";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

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

// Both instances keep `"use cache: remote"` entries here; tests/islands.spec.ts
// reads one instance's entry from the other on port 3101.
const remoteCacheDir = path.join(tmpdir(), "bsb-example-remote-cache");

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
    command: "next build && { next start -p 3101 & next start -p 3100; }",
    url: `${baseURL}/en/login`,
    env: { EXPOSE_TESTING_API: "1", BSB_REMOTE_CACHE_DIR: remoteCacheDir },
    reuseExistingServer: process.env["CI"] === undefined,
    timeout: 600_000,
  },
});
