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
  config: resolveConfig({ blocks: ["webhooks"] }, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [],
  ...(database === undefined ? {} : { database }),
});

const database = (rows: Record<string, unknown>[]): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: the rows hold the columns the query selects.
  query: (() => Promise.resolve(rows)) as LiveDatabase["query"],
});

const run = (ctx: DoctorContext, code: string) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

describe("BS363", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS363")).toBe(true);
  });

  it("skips without a database", async () => {
    expect(await run(context(undefined), "BS363")).toEqual([]);
  });

  it("flags a live partial index with another predicate", async () => {
    const findings = await run(
      context(
        database([
          {
            name: "webhook_deliveries_due_idx",
            table: "better_supabase.webhook_deliveries",
            predicate:
              "(status = ANY (ARRAY['pending'::text, 'retrying'::text]))",
          },
        ]),
      ),
      "BS363",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]!.message).toContain("webhook_deliveries_due_idx");
  });

  it("accepts the current predicate", async () => {
    expect(
      await run(
        context(
          database([
            {
              name: "webhook_deliveries_due_idx",
              table: "better_supabase.webhook_deliveries",
              predicate:
                "(status = ANY (ARRAY['pending'::text, 'retrying'::text, 'delivering'::text]))",
            },
          ]),
        ),
        "BS363",
      ),
    ).toEqual([]);
  });

  it("reports a failed comparison instead of throwing", async () => {
    const failing: LiveDatabase = {
      describe: "test database",
      session: true,
      query: () => Promise.reject(new Error("connection reset")),
    };

    const findings = await run(context(failing), "BS363");

    expect(findings).toHaveLength(1);
    expect(findings[0]!.message).toContain("connection reset");
  });

  it("ignores a live index the modules do not create", async () => {
    expect(
      await run(
        context(
          database([
            { name: "other_idx", table: "public.other", predicate: "(a = 1)" },
          ]),
        ),
        "BS363",
      ),
    ).toEqual([]);
  });
});
