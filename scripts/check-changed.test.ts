import { describe, expect, it } from "vitest";

import { mirrorTest, planSteps, workspaceOf } from "./check-changed.ts";

describe("workspaceOf", () => {
  it("finds the nearest package", () => {
    expect(workspaceOf("packages/better-supabase/src/cli/diff.ts")).toBe(
      "packages/better-supabase",
    );
  });

  it("returns an empty string for root files", () => {
    expect(workspaceOf("scripts/check-changed.ts")).toBe("");
  });
});

describe("mirrorTest", () => {
  it("maps a source file to its test when the test exists", () => {
    expect(mirrorTest("packages/better-supabase/src/core/result.ts")).toBe(
      "packages/better-supabase/tests/core/result.test.ts",
    );
  });

  it("returns undefined for a file without a mirror", () => {
    expect(mirrorTest("scripts/check-changed.ts")).toBeUndefined();
  });
});

describe("planSteps", () => {
  it("skips generated files and plans lint and typecheck per workspace", () => {
    const names = planSteps([
      "packages/better-supabase/src/cli/diff.ts",
      "packages/better-supabase/src/blocks/hint-codes.generated.ts",
    ]).map((step) => step.name);

    expect(names).toContain("format 1 files");
    expect(names).toContain("lint packages/better-supabase");
    expect(names).toContain("typecheck packages/better-supabase");
  });

  it("passes lint when every changed file is lint-ignored", () => {
    const lint = planSteps([
      "apps/examples/nextjs/public/sw.js",
      "tests/init-fixture/nextjs/public/sw.js",
    ]).filter((step) => step.name.startsWith("lint"));

    expect(lint.length).toBeGreaterThan(0);

    for (const step of lint) {
      expect(step.args).toContain("--no-error-on-unmatched-pattern");
    }
  });
});
