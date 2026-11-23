import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type { BlocksInput } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (
  database: LiveDatabase | undefined,
  blocks: BlocksInput,
): DoctorContext => ({
  config: resolveConfig({ blocks }, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [],
  ...(database === undefined ? {} : { database }),
});

const database = (
  answer: (sql: string) => Record<string, unknown>[],
): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: each answer holds the columns its query selects.
  query: ((sql: string) =>
    Promise.resolve(answer(sql))) as LiveDatabase["query"],
});

const EXEMPT: BlocksInput = {
  audit: { options: { exempt: [{ table: "public.*", reason: "fixture" }] } },
};

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS639"),
  );

describe("BS639", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS639")).toBe(true);
  });

  it("lists each exempt table with its reason and last entry", async () => {
    let first = "";

    const findings = await run(
      context(
        database((sql) => {
          const names = [...sql.matchAll(/'([^']+)'/g)].map((m) => m[1]!);
          first = names[0] ?? "";

          return names.map((name, index) => ({
            name,
            last: index === 0 ? "2026-11-01 10:00:00+00" : null,
          }));
        }),
        EXEMPT,
      ),
    );

    expect(findings.length).toBeGreaterThan(1);
    expect(findings[0]).toMatchObject({
      code: "BS639",
      severity: "info",
      target: first,
      message: expect.stringContaining(
        "(fixture). Last audit entry: 2026-11-01 10:00:00+00.",
      ),
    });
    expect(findings[1]?.message).toContain("Last audit entry: never.");
  });

  it("skips without audit, an exemption or a database", async () => {
    expect(await run(context(undefined, EXEMPT))).toEqual([]);
    expect(
      await run(
        context(
          database(() => []),
          { audit: {} },
        ),
      ),
    ).toEqual([]);
  });
});
