import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { SPEC_CLI_CODES } from "../../../src/cli/spec/diagnostics.ts";

const SOURCES = [
  "../../../src/cli/commands/spec.ts",
  "../../../src/cli/spec/render.ts",
  "../../../src/cli/spec/targets.ts",
  "../../../src/cli/spec/validate.ts",
];
const CODE_LINE = /\bcode\b[^\n]*/g;
const KEBAB = /"([a-z]+(?:-[a-z]+)+)"/g;

async function emittedCodes(): Promise<Set<string>> {
  const codes = new Set<string>();
  for (const path of SOURCES) {
    const source = await readFile(new URL(path, import.meta.url), "utf8");
    for (const [line] of source.matchAll(CODE_LINE))
      for (const [, code] of line.matchAll(KEBAB)) codes.add(code!);
  }
  return codes;
}

describe("SPEC_CLI_CODES", () => {
  it("registers every code the spec command reports, and no others", async () => {
    expect([...(await emittedCodes())].toSorted()).toEqual(
      Object.keys(SPEC_CLI_CODES).toSorted(),
    );
  });
});
