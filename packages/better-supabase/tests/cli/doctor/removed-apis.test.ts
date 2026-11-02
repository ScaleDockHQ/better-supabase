import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { REMOVED_API_RULES } from "../../../src/cli/doctor/removed-apis.ts";

const rule = REMOVED_API_RULES.find((candidate) => candidate.code === "BS509")!;

const context = (text: string): DoctorContext =>
  // SAFETY: BS509 reads only the app sources.
  ({ sources: [{ path: "route.ts", text }] }) as unknown as DoctorContext;

describe("BS509", () => {
  it("reports a block call with positional arguments", async () => {
    const findings = await rule.check(
      context(
        'import { bsb } from "@/lib/supabase/server";\nawait chats.runs.setCost(id, 120, usage);',
      ),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location).toEqual({ file: "route.ts", line: 2 });
  });

  it("ignores a file that never reaches a block client", async () => {
    const findings = await rule.check(
      context("actions.addRule(createFilterRule({ id }), true);"),
    );

    expect(findings).toEqual([]);
  });

  it("accepts a call that passes one object", async () => {
    const findings = await rule.check(
      context(
        "await chats.runs.setCost({ generationId: id, costMicroUsd: 1, usage });",
      ),
    );

    expect(findings).toEqual([]);
  });
});

const renamed = REMOVED_API_RULES.find(
  (candidate) => candidate.code === "BS418",
)!;

describe("BS418", () => {
  it("reports renamed subpaths, plugin and spec moves and removed names", async () => {
    const findings = await renamed.check(
      context(
        [
          'import { a } from "better-supabase/plugins/tenant";',
          'import { b } from "better-supabase/plugins/validation";',
          'import { c } from "better-supabase/openapi";',
          "const handler: RuleActionHandler = x;",
          "sequence_enrollments",
        ].join("\n"),
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([
      1, 2, 3, 5, 4,
    ]);
    expect(findings[0]?.message).toContain(
      "better-supabase/blocks/memberships",
    );
    expect(findings[1]?.message).toContain("renamed to `better-supabase`");
    expect(findings[2]?.message).toContain("better-supabase/spec");
  });

  it("reports a renamed block export and ignores current imports", async () => {
    const findings = await renamed.check(
      context(
        [
          'import { type Foo as F, createBlocks } from "better-supabase/blocks";',
          'import { x } from "better-supabase/blocks/drive";',
        ].join("\n"),
      ),
    );

    expect(
      findings.every((finding) => finding.target?.startsWith("route.ts:")),
    ).toBe(true);
  });
});
