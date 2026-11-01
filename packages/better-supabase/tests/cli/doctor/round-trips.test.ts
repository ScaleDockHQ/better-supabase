import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { ROUND_TRIP_RULES } from "../../../src/cli/doctor/round-trips.ts";

function check(
  sources: readonly TextFile[],
): readonly { message: string; location?: { line: number } }[] {
  const [rule] = ROUND_TRIP_RULES;
  // SAFETY: BS609 reads only `sources`.
  const findings = rule?.check({ sources } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS609 runs synchronously");
  }

  return findings;
}

const page = (entries: string[]): TextFile => ({
  path: "src/app/page.tsx",
  text: [
    "export default async function Page() {",
    "  const [a, b, c] = await Promise.all([",
    ...entries.map((entry) => `    ${entry},`),
    "  ]);",
    "}",
  ].join("\n"),
});

describe("BS609", () => {
  it("hints at a read set for three parallel database reads", () => {
    const findings = check([
      page([
        "db.customers.list().orThrow()",
        "db.orders.list({ limit: 5 }).orThrow()",
        "blocks.deals.health(pipelineId).orThrow()",
      ]),
    ]);

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain("3 database reads");
    expect(findings[0]?.location?.line).toBe(2);
  });

  it("stays quiet for fewer reads or reads that aren't the database's", () => {
    expect(
      check([
        page(["db.customers.list()", "db.orders.list()", "fetch(url)"]),
        page(["fetch(a)", "fetch(b)", "fetch(c)"]),
      ]),
    ).toEqual([]);
  });
});
