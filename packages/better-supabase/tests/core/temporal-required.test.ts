import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, onTestFinished, vi } from "vitest";

import { DbException } from "../../src/core/errors.ts";
import { temporal, temporalMissing } from "../../src/core/temporal-required.ts";
import { TEMPORAL_POLYFILL } from "../../src/core/temporal.ts";

describe("temporal", () => {
  it("returns the runtime's Temporal", () => {
    expect(temporal()).toBe(globalThis.Temporal);
  });

  it("throws an unexpected error that names the polyfill when Temporal is missing", () => {
    vi.stubGlobal("Temporal", undefined);
    onTestFinished(() => {
      vi.unstubAllGlobals();
    });
    expect(() => temporal()).toThrow(DbException);
    expect(temporalMissing()).toMatchObject({
      kind: "unexpected",
      status: 500,
      message: expect.stringContaining(TEMPORAL_POLYFILL),
    });
  });
});

const SRC = join(import.meta.dirname, "../../src");
/** The two modules that read the runtime's Temporal; everything else goes through them. */
const READERS = new Set(["core/temporal.ts", "core/temporal-required.ts"]);
const GLOBAL_USE =
  /\bTemporal\.[A-Z]\w*\.\w|\bnew Temporal\.|globalThis\.Temporal\b/;

describe("Temporal in src", () => {
  // Vitest's setup installs a polyfill, so a global call would pass every
  // other test and only fail in a runtime without Temporal.
  it("never reads the global Temporal outside src/core", () => {
    const found: string[] = [];
    for (const entry of readdirSync(SRC, { recursive: true })) {
      const file = String(entry);
      if (!file.endsWith(".ts") || READERS.has(file)) continue;
      const lines = readFileSync(join(SRC, file), "utf8").split("\n");
      for (const [index, line] of lines.entries()) {
        const code = line.replace(/\/\/.*$/, "").trim();
        if (code.startsWith("*") || code.startsWith("/*")) continue;
        if (GLOBAL_USE.test(code)) found.push(`${file}:${index + 1}`);
      }
    }
    expect(found).toEqual([]);
  });
});
