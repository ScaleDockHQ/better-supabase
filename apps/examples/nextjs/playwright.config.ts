import { defineConfig, devices } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { latencyURL, baseURL } from "./e2e/server";

/**
 * The running stack's secret key, for account deletion; never written to a
 * file. Empty when no stack runs (Knip loads this config), so only the
 * account-deletion spec fails then.
 */
function stackSecretKey(): string {
  const fromEnv = process.env["SUPABASE_SECRET_KEY"];
  if (fromEnv) return fromEnv;
  try {
    const status = execFileSync(
      "pnpm",
      ["exec", "supabase", "status", "--output", "env"],
      {
        cwd: fileURLToPath(new URL("../../..", import.meta.url)),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      },
    );
    return /^SECRET_KEY="?([^"\n]+)"?$/m.exec(status)?.[1] ?? "";
  } catch {
    return "";
  }
}

/**
 * `instant()` checks against a production build. The build must expose the
 * testing API, so `webServer` builds with `EXPOSE_TESTING_API=1` itself
 * instead of reusing a server that may have been built without it. The
 * `latency` project runs against a second server on the same build whose
 * Supabase requests wait 3 s (`e2e/serve.ts`).
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
    env: { EXPOSE_TESTING_API: "1", SUPABASE_SECRET_KEY: stackSecretKey() },
    reuseExistingServer: false,
    timeout: 300_000,
  },
});
