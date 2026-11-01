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
      context("await chats.runs.setCost(id, 120, usage);"),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location).toEqual({ file: "route.ts", line: 1 });
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
