import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (
  database: LiveDatabase | undefined,
  tasks: Record<string, unknown>,
): DoctorContext => ({
  config: resolveConfig(
    {
      blocks: {
        organizations: {},
        memberships: {},
        pipelines: {},
        tasks: { options: tasks },
      },
      // SAFETY: the block options are partial on purpose.
    },
    "/project",
  ),
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
  seen: string[] = [],
): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: each answer holds the columns its query selects.
  query: ((sql: string) => {
    seen.push(sql);

    return Promise.resolve(answer(sql));
  }) as LiveDatabase["query"],
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS245"),
  );

describe("BS245", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS245")).toBe(true);
  });

  it("names a pipeline that lacks the stage by key", async () => {
    const seen: string[] = [];

    const findings = await run(
      context(
        database(() => [{ key: "sales" }], seen),
        { hold: { stage: "on_hold" } },
      ),
    );

    expect(seen[0]).toContain("'on_hold'");
    expect(findings).toMatchObject([
      {
        code: "BS245",
        message: expect.stringContaining("hold.stage names the stage on_hold"),
      },
    ]);
  });

  it("matches a category", async () => {
    const seen: string[] = [];

    await run(
      context(
        database(() => [], seen),
        { claims: { startStage: { category: "active" } } },
      ),
    );

    expect(seen[0]).toContain("::text = 'active'");
  });

  it("stays silent without options, rows or a database", async () => {
    expect(
      await run(
        context(
          database(() => []),
          {},
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        context(
          database(() => []),
          { hold: { stage: "x" } },
        ),
      ),
    ).toEqual([]);
    expect(await run(context(undefined, { hold: { stage: "x" } }))).toEqual([]);
  });
});
