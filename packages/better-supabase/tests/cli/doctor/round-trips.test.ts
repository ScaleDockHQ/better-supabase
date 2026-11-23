import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { ROUND_TRIP_RULES } from "../../../src/cli/doctor/round-trips.ts";

function check(
  sources: readonly TextFile[],
  symbols?: DoctorContext["symbols"],
): readonly {
  message: string;
  target?: string;
  location?: { line: number };
}[] {
  const [rule] = ROUND_TRIP_RULES;

  // SAFETY: BS609 reads only `sources` and `doctor.parallelReads`.
  const findings = rule?.check({
    sources,
    ...(symbols ? { symbols } : {}),
    config: { doctor: { parallelReads: 3 } },
  } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS609 runs synchronously");
  }

  return findings;
}

/** The opening of a template placeholder, kept out of a string literal. */
const hole = "${";

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
    expect(findings[0]?.target).toBe("src/app/page.tsx#Page:Promise.all");
  });

  it("counts $rpc calls and block methods", () => {
    expect(
      check([
        page([
          'db.$rpc("a", {})',
          'bsb.db().$rpc("b", {})',
          "blocks.tags.list(id)",
        ]),
      ]),
    ).toHaveLength(1);
  });

  it("stays quiet for fewer reads or reads that aren't the database's", () => {
    expect(
      check([
        page(["db.customers.list()", "db.orders.list()", "fetch(url)"]),
        page(["fetch(a)", "fetch(b)", "fetch(c)"]),
      ]),
    ).toEqual([]);
  });

  it("reads the tree: a regex with a quote, a template and CRLF change nothing", () => {
    const text = [
      "const quote = /[\"']/;",
      `const label = \`${hole}\`a ${
        hole
      }'(' + '['}\`} Promise.all([db.x.get(), db.y.get(), db.z.get()])\`;`,
      "// Promise.all([db.a.get(), db.b.get(), db.c.get()])",
      "export default async function Page() {",
      "  return Promise.all([db.a.list(), db.b.list(), db.c.list()]);",
      "}",
    ].join("\r\n");

    const findings = check([{ path: "src/app/page.tsx", text }]);

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location?.line).toBe(5);
    expect(findings[0]?.target).toBe("src/app/page.tsx#Page:Promise.all");
  });

  it("ignores Promise.all written in JSX text", () => {
    const text = [
      "export default function Page() {",
      "  return <p>Promise.all([db.a.list(), db.b.list(), db.c.list()])</p>;",
      "}",
    ].join("\n");

    expect(check([{ path: "src/app/page.tsx", text }])).toEqual([]);
  });
});

describe("BS609 receiver types", () => {
  const text = [
    "export default async function Page() {",
    "  const [a, b, c] = await Promise.all([",
    "    db.customers.list().orThrow(),",
    "    db.orders.list().orThrow(),",
    "    db.notes.list().orThrow(),",
    "  ]);",
    "}",
  ].join("\n");

  const tier = (type: string | undefined): DoctorContext["symbols"] => ({
    root: "/app",
    tier: {
      version: "7.1.0",
      references: () => [],
      declaration: () => undefined,
      typeOf: () => type,
      close: () => {},
    },
  });

  it("drops reads on a receiver that TypeScript types as a Map", () => {
    expect(
      check([{ path: "src/app/page.tsx", text }], tier("Map<string, string>")),
    ).toEqual([]);
  });

  it("keeps reads on a client type or an unresolved receiver", () => {
    const sources = [{ path: "src/app/page.tsx", text }];

    expect(check(sources, tier("Db<Database>"))).toHaveLength(1);
    expect(check(sources, tier(undefined))).toHaveLength(1);
    expect(
      check(sources, { skipped: "typescript is not installed" }),
    ).toHaveLength(1);
  });
});
