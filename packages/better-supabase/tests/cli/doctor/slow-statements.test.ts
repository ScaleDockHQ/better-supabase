import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (database: LiveDatabase | undefined): DoctorContext => ({
  config: resolveConfig({}, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [],
  ...(database === undefined ? {} : { database }),
});

const database = (
  answer: (sql: string) => readonly object[] | Error,
): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: each answer holds the columns the query selects.
  query: ((sql: string) => {
    const rows = answer(sql);

    return rows instanceof Error ? Promise.reject(rows) : Promise.resolve(rows);
  }) as LiveDatabase["query"],
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS732"),
  );

describe("BS732", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS732")).toBe(true);
  });

  it("skips without a database", async () => {
    expect(await run(context(undefined))).toEqual([]);
  });

  it("names slow statements and functions", async () => {
    const findings = await run(
      context(
        database((sql) =>
          sql.includes("pg_stat_user_functions")
            ? [{ name: "public.funding_award_usage", calls: "8", mean_ms: 61 }]
            : [
                {
                  query: "select  *\n from   public.customers",
                  calls: "12",
                  mean_ms: 240.55,
                  total_ms: 2886.6,
                },
              ],
        ),
      ),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        message: expect.stringContaining(
          "mean of 240.6 ms (2887 ms in total): select * from public.customers",
        ),
      }),
      expect.objectContaining({
        target: "public.funding_award_usage",
        message: expect.stringContaining("mean of 61.0 ms"),
      }),
    ]);
  });

  it("reports nothing when the extension is not installed", async () => {
    const missing = new Error('relation "pg_stat_statements" does not exist');

    expect(await run(context(database(() => missing)))).toEqual([]);
  });

  it("reports another failure", async () => {
    const findings = await run(
      context(database(() => new Error("permission denied"))),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        message: expect.stringContaining("permission denied"),
      }),
    ]);
  });
});
