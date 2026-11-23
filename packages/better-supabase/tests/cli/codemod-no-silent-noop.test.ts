import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

/** A TypeScript file no parser reads, so no codemod can have followed it. */
const BROKEN = 'import { x } from "better-supabase";\nconst = ;\n';

/**
 * The codemods that rewrite no source file: they change SQL, the generated
 * folder or the project's files, and have their own tests for a review line. A
 * codemod that gains a source stage leaves this list and joins the loop.
 */
const NO_SOURCE_STAGE = new Set([
  "extra-columns",
  "owned-columns",
  "config",
  "table-tags",
  "adopt-names",
  "declared-rows",
  "doctor-baseline",
  "table-modules",
]);

describe("no silent no-ops", () => {
  it("classifies every registered codemod", () => {
    for (const [key, codemod] of Object.entries(CODEMODS)) {
      const stages =
        codemod.source !== undefined ||
        codemod.imports !== undefined ||
        codemod.subpaths !== undefined;

      expect(
        stages || NO_SOURCE_STAGE.has(key),
        `${key} rewrites source but is listed as not doing so`,
      ).toBe(true);
      expect(
        !stages || !NO_SOURCE_STAGE.has(key),
        `${key} has a source stage; remove it from NO_SOURCE_STAGE`,
      ).toBe(true);
    }
  });

  it.each(
    Object.entries(CODEMODS).filter(
      ([, codemod]) =>
        codemod.source !== undefined ||
        codemod.imports !== undefined ||
        codemod.subpaths !== undefined,
    ),
  )("%s changes a file it cannot parse, or lists it", (_key, codemod) => {
    const result = applyCodemod(codemod, BROKEN, undefined, "app.ts");

    expect(
      result.text !== BROKEN || result.review.length > 0,
      "the codemod returned the file with no change and no review line",
    ).toBe(true);
  });
});
