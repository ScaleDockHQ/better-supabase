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

const INVOICES = {
  organizations: {},
  memberships: {},
  permissions: {},
  subjects: {},
  ledger: {},
  contacts: {},
  invoices: {},
};

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
    RULES.filter((rule) => rule.code === "BS638"),
  );

describe("BS638", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS638")).toBe(true);
  });

  it("names each organization whose stored open items drift", async () => {
    const seen: string[] = [];

    const findings = await run(
      context(
        database(
          (sql) =>
            sql.includes("to_regproc")
              ? [{ found: true }]
              : [{ tenant: "00000000-0000-4000-8000-000000000001", drift: 2 }],
          seen,
        ),
        INVOICES,
      ),
    );

    expect(seen[1]).toContain("open_items_drift_rows");
    expect(findings).toMatchObject([
      {
        code: "BS638",
        message: expect.stringContaining(
          "rebuild_open_items('00000000-0000-4000-8000-000000000001')",
        ),
      },
    ]);
  });

  it("stays quiet when the function isn't installed yet", async () => {
    const findings = await run(
      context(
        database(() => [{ found: false }]),
        INVOICES,
      ),
    );

    expect(findings).toEqual([]);
  });

  it("skips without invoices or a database", async () => {
    expect(await run(context(undefined, INVOICES))).toEqual([]);
    expect(
      await run(
        context(
          database(() => []),
          { organizations: {}, memberships: {} },
        ),
      ),
    ).toEqual([]);
  });
});
