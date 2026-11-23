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

    const findings = await run(
      context(
        database(() => [{ key: "sales" }], seen),
        { claims: { startStage: { category: "active" } } },
      ),
    );

    expect(seen[0]).toContain("::text = 'active'");
    expect(findings[0]?.message).toContain(
      "claims.startStage names the category active, which sales has no live stage for",
    );
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

  it("joins several pipelines and skips malformed options", async () => {
    const findings = await run(
      context(
        database(() => [{ key: "a" }, { key: "b" }]),
        {
          hold: "x",
          claims: { startStage: { category: 1 }, expiredStage: "done" },
        },
      ),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain(
      "claims.expiredStage names the stage done, which a, b have no live stage for",
    );
  });

  it.each([
    ["a missing table stays silent", "relation x does not exist", []],
    [
      "another error is a finding",
      "permission denied",
      [
        {
          message:
            "Could not read the task pipelines (test database): permission denied",
        },
      ],
    ],
  ])("%s", async (_name, text, expected) => {
    const failing = database(() => {
      throw new Error(text);
    });

    expect(await run(context(failing, { hold: { stage: "x" } }))).toMatchObject(
      expected,
    );
  });

  it("stays silent for a skipped database", async () => {
    const skipped = { skipped: "saved snapshot" } as unknown as LiveDatabase;

    expect(await run(context(skipped, { hold: { stage: "x" } }))).toEqual([]);
  });
});
