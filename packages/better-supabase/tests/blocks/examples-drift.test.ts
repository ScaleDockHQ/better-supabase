import { globSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

import { clientFunctions } from "../../src/sql/client-functions.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";

const ROOT = join(import.meta.dirname, "../../../..");
const EXAMPLES = join(ROOT, "apps/examples");

/**
 * Every SQL function a block client calls. An example that reaches one of them
 * through `$api`, `$rpc` or raw SQL reimplements a client method.
 */
const CLIENT_FUNCTION_NAMES: ReadonlySet<string> = new Set(
  Object.keys(SQL_MODULES).flatMap((name) => clientFunctions(name)),
);

/**
 * The calls that exist today, as `<file>:<function>`. The test fails on a call
 * that is not listed (new drift) and on a listed call that is gone (delete the
 * entry), so the list only shrinks. Each entry waits for a block client method
 * and the example moving onto it (ADR 0196).
 */
const BASELINE: ReadonlySet<string> = new Set<string>();

const CALL = /\.\$(?:api|rpc)\(\s*"([a-z_0-9]+)"/gu;

function drift(): Set<string> {
  const found = new Set<string>();

  for (const path of globSync("**/src/**/*.{ts,tsx}", { cwd: EXAMPLES })) {
    if (path.includes("node_modules") || path.includes("generated")) {
      continue;
    }

    const source = readFileSync(join(EXAMPLES, path), "utf-8");

    for (const match of source.matchAll(CALL)) {
      const name = match[1];

      if (name !== undefined && CLIENT_FUNCTION_NAMES.has(name)) {
        found.add(`${relative("", path)}:${name}`);
      }
    }
  }

  return found;
}

describe("examples use the block clients", () => {
  it("call no function a block client exposes through $api or $rpc", () => {
    const found = drift();

    expect(
      [...found].filter((entry) => !BASELINE.has(entry)),
      "an example calls a function a block client exposes; use the client method",
    ).toEqual([]);

    expect(
      [...BASELINE].filter((entry) => !found.has(entry)),
      "this baseline entry is gone; delete it",
    ).toEqual([]);
  });
});
