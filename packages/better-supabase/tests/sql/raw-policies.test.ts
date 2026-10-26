import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const MODULES = join(import.meta.dirname, "../../src/sql/modules");

/** `create policy` outside SQL line comments, which only document a recipe. */
function rawPolicies(text: string): number {
  return text
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("--"))
    .reduce((n, line) => n + line.split("create policy").length - 1, 0);
}

/**
 * ADR 0103: block modules emit `Policy` values through `renderPolicy`, so the
 * tenant scope, the matrix and the catalog read one typed shape. A module that
 * writes `create policy` by hand fails here.
 */
describe("raw create policy in block modules", () => {
  it("is absent: modules use policy() and renderPolicy()", () => {
    const raw = readdirSync(MODULES)
      .filter((file) => file.endsWith(".ts"))
      .filter(
        (file) => rawPolicies(readFileSync(join(MODULES, file), "utf-8")) > 0,
      );

    expect(raw, "raw create policy, use renderPolicy").toEqual([]);
  });
});
