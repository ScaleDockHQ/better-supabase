import { defineConfig, devices } from "@playwright/test";

import { latencyURL, baseURL } from "./e2e/server";
import { stackStatus } from "./e2e/stack";

const stack = stackStatus();

// Destructured: typedEnv declares only the keys in local env files, in dev.
const { SUPABASE_SECRET_KEY, WORKFLOW_POSTGRES_URL } = process.env;

/**
 * The running stack for the build and the servers. The secret key is for
 * account deletion and is never written to a file. The developer settings
 * (webhooks, jobs) read module tables over the database URL.
 */
const stackEnv = {
  NEXT_PUBLIC_SUPABASE_URL:
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? stack["API_URL"] ?? "",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
    stack["PUBLISHABLE_KEY"] ??
    "",
  SUPABASE_SECRET_KEY: SUPABASE_SECRET_KEY ?? stack["SECRET_KEY"] ?? "",
  WORKFLOW_POSTGRES_URL: WORKFLOW_POSTGRES_URL ?? stack["DB_URL"] ?? "",
};

/**
 * `instant()` checks against a production build. The build must expose the
 * testing API, so `webServer` builds with `EXPOSE_TESTING_API=1` itself instead
 * of reusing a server that may have been built without it. The `latency`
 * project runs against a second server on the same build whose Supabase
 * requests wait 3 s (`e2e/serve.ts`).
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
      testIgnore: /latency\.spec\.ts/,
      use: { ...devices["Desktop Chrome"] },
      dependencies: ["setup"],
    },
    {
      name: "latency",
      testMatch: /latency\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], baseURL: latencyURL },
      dependencies: ["setup"],
    },
  ],
  webServer: {
    command: "node e2e/serve.ts",
    url: `${latencyURL}/en/login`,
    env: { EXPOSE_TESTING_API: "1", ...stackEnv },
    reuseExistingServer: false,
    timeout: 300_000,
  },
});
