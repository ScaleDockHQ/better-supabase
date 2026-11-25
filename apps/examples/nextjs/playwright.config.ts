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

// `BSB_PORT` moves both instances (`BSB_PORT` and the next port) so a second
// checkout can run its own servers beside this one.
const port = Number(process.env["BSB_PORT"] ?? "3100");
const baseURL = `http://localhost:${String(port)}`;

const COUNTER_SPECS = [
  "**/bench-scopes.spec.ts",
  "**/islands.spec.ts",
  "**/auth-cost.spec.ts",
];

// Both instances keep `"use cache: remote"` entries here; tests/islands.spec.ts
// reads one instance's entry from the other on port 3101.
const remoteCacheDir =
  process.env["BSB_REMOTE_CACHE_DIR"] ??
  path.join(tmpdir(), "bsb-example-remote-cache");

// `instant()` needs a production build with the testing API exposed; under
// `next dev` the lock is ignored and every check passes without testing.
export default defineConfig({
  testDir: "tests",
  testMatch: "**/*.spec.ts",
  globalSetup: "./tests/support/postgres-cache-setup.ts",
  // The @scale specs need pnpm db:seed:scale; run them with --grep @scale.
  grepInvert: process.argv.includes("@scale") ? /(?!)/ : /@scale/,
  fullyParallel: false,
  retries: process.env["CI"] === undefined ? 0 : 1,
  use: { baseURL, trace: "retain-on-failure" },
  projects: [
    {
      name: "chromium",
      testIgnore: COUNTER_SPECS,
      use: { ...devices["Desktop Chrome"] },
    },
    // These read the server's global verification counters, so any other
    // spec's request would count; they run alone, after the rest.
    {
      name: "counters",
      testMatch: COUNTER_SPECS,
      dependencies: ["chromium"],
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: `next build && { next start -p ${String(port + 1)} & next start -p ${String(port)}; }`,
    url: `${baseURL}/login`,
    env: {
      EXPOSE_TESTING_API: "1",
      BSB_REMOTE_CACHE_DIR: remoteCacheDir,
      BSB_REMOTE_CACHE_STORE: process.env["BSB_REMOTE_CACHE_STORE"] ?? "file",
    },
    reuseExistingServer: process.env["CI"] === undefined,
    timeout: 600_000,
  },
});
