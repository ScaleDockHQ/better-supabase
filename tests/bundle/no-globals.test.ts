import { execFile } from "node:child_process";
import { resolve } from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";

const run = promisify(execFile);
const PACKAGE = resolve(import.meta.dirname, "../../packages/better-supabase");

/**
 * Runtimes such as React Native and some Jest environments ship no encoders at
 * import time.
 */
const SCRIPT = (specifier: string) => `
delete globalThis.TextEncoder;
delete globalThis.TextDecoder;
const entry = await import(${JSON.stringify(specifier)});
if (Object.keys(entry).length === 0) throw new Error("empty entry");
`;

describe("entries without TextEncoder and TextDecoder", () => {
  it.each(["better-supabase", "better-supabase/client"])(
    "%s loads",
    async (specifier) => {
      await expect(
        run(
          process.execPath,
          ["--input-type=module", "--eval", SCRIPT(specifier)],
          { cwd: PACKAGE },
        ),
      ).resolves.toBeDefined();
    },
  );
});
