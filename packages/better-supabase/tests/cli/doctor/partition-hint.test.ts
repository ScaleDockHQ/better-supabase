import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { PARTITION_HINT_ROWS } from "../../../src/cli/doctor/partition-hint.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (
  database: LiveDatabase | undefined,
  blocks: string[] = ["audit"],
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

const database = (rows: number | string): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: the rows hold the column the query selects.
  query: (() => Promise.resolve([{ rows }])) as LiveDatabase["query"],
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS399"),
  );

describe("BS399", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS399")).toBe(true);
  });

  it("skips without a database and without the audit block", async () => {
    expect(await run(context(undefined))).toEqual([]);
    expect(
      await run(context(database(PARTITION_HINT_ROWS * 5), ["webhooks"])),
    ).toEqual([]);
  });

  it("hints at a log of a million rows or more", async () => {
    const findings = await run(context(database(String(PARTITION_HINT_ROWS))));

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "info",
        target: "better_supabase.audit_events",
      }),
    ]);
    expect(findings[0]!.message).toContain("convert_audit_log_to_partitioned");
  });

  it("passes a smaller log, a never analyzed one and a partitioned one", async () => {
    expect(await run(context(database(PARTITION_HINT_ROWS - 1)))).toEqual([]);
    expect(await run(context(database(-1)))).toEqual([]);

    const partitioned: LiveDatabase = {
      describe: "test database",
      session: true,
      query: () => Promise.resolve([]),
    };

    expect(await run(context(partitioned))).toEqual([]);
  });

  it("reports a failed read instead of throwing", async () => {
    const failing: LiveDatabase = {
      describe: "test database",
      session: true,
      query: () => Promise.reject(new Error("connection reset")),
    };

    const findings = await run(context(failing));

    expect(findings).toHaveLength(1);
    expect(findings[0]!.message).toContain("connection reset");
  });
});
