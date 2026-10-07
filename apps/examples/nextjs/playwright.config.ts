import { defineConfig, devices } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { baseURL, port } from "./e2e/server";

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
    url: `${baseURL}/en/login`,
    env: { EXPOSE_TESTING_API: "1", SUPABASE_SECRET_KEY: stackSecretKey() },
    reuseExistingServer: false,
    timeout: 300_000,
  },
});
