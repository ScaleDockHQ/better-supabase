import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import * as v from "valibot";

const Status = v.record(v.string(), v.unknown());

/**
 * The running stack's URLs and keys from `supabase status`; the CLI picks the
 * ports for each checkout. Empty when no stack runs (Knip loads the Playwright
 * config), so only the specs that need the stack fail then.
 */
export function stackStatus(): Readonly<Record<string, string>> {
  try {
    const stdout = execFileSync(
      "pnpm",
      ["exec", "supabase", "status", "--env", "--output-format", "json"],
      {
        cwd: fileURLToPath(new URL("../../../..", import.meta.url)),
        encoding: "utf-8",
        stdio: ["ignore", "pipe", "ignore"],
      },
    );
    const status = v.parse(
      Status,
      JSON.parse(stdout.slice(stdout.indexOf("{"))),
    );
    return Object.fromEntries(
      Object.entries(status).flatMap(([key, value]) =>
        v.is(v.string(), value) ? [[key, value]] : [],
      ),
    );
  } catch {
    return {};
  }
}
