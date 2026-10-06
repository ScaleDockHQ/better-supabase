import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  errorText,
  ident,
  literal,
  summarizePlan,
} from "../../../src/cli/doctor/live.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeSql, pgError, type SqlRule } from "../fixtures/fake-sql.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

function context(extra: Partial<DoctorContext> = {}): DoctorContext {
  return {
    config: resolveConfig({}, "/project"),
    snapshot,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

function database(
  rules: readonly SqlRule[],
  session = true,
): LiveDatabase & { texts: () => string[] } {
  const sql = fakeSql(rules);
  return {
    describe: "test db",
    session,
    // SAFETY: tests script rows that match the statement they answer.
    query: async <R>(text: string) => (await sql.pg.query(text)).rows as R[],
    texts: sql.texts,
  };
}

const only = (code: string) => RULES.filter((rule) => rule.code === code);
const check = (code: string, extra: Partial<DoctorContext>) =>
  runRules(context(extra), only(code));

describe("helpers", () => {
  it("quotes identifiers and literals and prints errors", () => {
    expect(ident('a"b')).toBe('"a""b"');
    expect(literal("it's")).toBe("'it''s'");
    expect(errorText(new Error("boom"))).toBe("boom");
    expect(errorText("plain")).toBe("plain");
  });

  it("summarizes a plan without timings or children", () => {
    expect(summarizePlan({ Plan: { "Node Type": "Result" } })).toEqual({
      nodes: ["Result 0.00 ms ×1"],
      initPlans: 0,
      perRowSubPlans: [],
      executionMs: 0,
    });
  });
});

describe("BS208 temporary files", () => {
  const stats = (files: number | string, bytes: number | string = 0) =>
    [
      /pg_stat_database/,
      [{ temp_files: files, temp_bytes: bytes, work_mem: "4MB" }],
    ] as const;

  it("needs a live database", async () => {
    expect(await check("BS208", {})).toEqual([]);
    expect(await check("BS208", { database: { skipped: "offline" } })).toEqual(
      [],
    );
  });

  it("passes without temporary files or statistics", async () => {
    expect(await check("BS208", { database: database([stats(0)]) })).toEqual(
      [],
    );
    expect(await check("BS208", { database: database([]) })).toEqual([]);
  });

  it("reports spills without pg_stat_statements", async () => {
    const [finding] = await check("BS208", {
      database: database([stats("2", "1048576")]),
    });
    expect(finding).toMatchObject({
      code: "BS208",
      severity: "warning",
      target: "pg_stat_database:temp_files",
      message:
        "2 temporary files (1.0 MB) since the statistics were reset; work_mem is 4MB. Add indexes so large sorts go away, or raise work_mem for the role that runs them.",
    });
  });

  it("leaves out the top statements when they can't be read or there are none", async () => {
    const extension = [/pg_extension/, [{ schema: "ext" }]] as const;
    const failing = database([
      stats(1),
      extension,
      [/temp_blks_written > 0/, { throws: pgError("42501", "denied") }],
    ]);
    const [denied] = await check("BS208", { database: failing });
    expect(denied!.message).not.toContain("Top statements");
    expect(failing.texts().at(-1)).toContain('from "ext".pg_stat_statements');
    const [none] = await check("BS208", {
      database: database([stats(1), extension]),
    });
    expect(none!.message).not.toContain("Top statements");
  });

  it("reports a statistics view it can't read as info", async () => {
    expect(
      await check("BS208", {
        database: database([
          [/pg_stat_database/, { throws: new Error("no access") }],
        ]),
      }),
    ).toMatchObject([
      {
        severity: "info",
        message: "Could not read pg_stat_database (test db): no access",
      },
    ]);
  });
});

describe("BS209 slow statements", () => {
  const extension = [/pg_extension/, [{ schema: "extensions" }]] as const;

  it("runs only with --stats and a live database", async () => {
    const db = database([extension]);
    expect(await check("BS209", { database: db })).toEqual([]);
    expect(await check("BS209", { stats: true })).toEqual([]);
    expect(
      await check("BS209", { stats: true, database: { skipped: "a file" } }),
    ).toMatchObject([{ severity: "info", message: "Skipped --stats: a file" }]);
  });

  it("asks for pg_stat_statements when it is missing", async () => {
    expect(
      await check("BS209", { stats: true, database: database([]) }),
    ).toMatchObject([
      {
        severity: "info",
        message: expect.stringContaining("create extension pg_stat_statements"),
      },
    ]);
  });

  it("names the table a statement reads, quoted or not", async () => {
    const long = `select * from public.notes where ${"x = 1 and ".repeat(30)}true`;
    const findings = await check("BS209", {
      stats: true,
      database: database([
        extension,
        [
          /mean_exec_time >/,
          [
            {
              queryid: "1",
              query: long,
              calls: "2000",
              mean_exec_time: "60",
            },
            {
              queryid: "2",
              query: "select 1",
              calls: 5000,
              mean_exec_time: 70.04,
            },
          ],
        ],
      ]),
    });
    expect(findings[0]).toMatchObject({
      target: "pg_stat_statements:1",
      object: { kind: "table", schema: "public", name: "notes" },
    });
    expect(findings[0]!.message).toMatch(/^60\.0 ms mean over 2000 calls: /);
    expect(findings[0]!.message.endsWith("…")).toBe(true);
    expect(findings[1]).not.toHaveProperty("object");
    expect(findings[1]!.message).toBe("70.0 ms mean over 5000 calls: select 1");
  });

  it("reports a failing query as info", async () => {
    expect(
      await check("BS209", {
        stats: true,
        database: database([
          extension,
          [/mean_exec_time >/, { throws: "timeout" }],
        ]),
      }),
    ).toMatchObject([
      {
        severity: "info",
        message: "Could not read pg_stat_statements (test db): timeout",
      },
    ]);
  });
});

describe("BS212 --explain", () => {
  const plan = {
    "Execution Time": 2,
    Plan: {
      "Node Type": "Seq Scan",
      "Relation Name": "notes",
      "Actual Total Time": 1.5,
      "Actual Loops": 1,
      Plans: [
        {
          "Node Type": "Index Scan",
          "Parent Relationship": "SubPlan",
          "Subplan Name": "SubPlan 1",
          "Actual Total Time": 0.01,
          "Actual Loops": 40,
        },
      ],
    },
  };

  const explainDb = (rules: readonly SqlRule[] = []) => {
    let reads = 0;
    return database([
      ...rules,
      [
        /pg_stat_xact_user_functions/,
        () => {
          reads += 1;
          return reads === 1
            ? [{ name: "private.is_member", calls: 2, self_time: 0.1 }]
            : [
                { name: "private.is_member", calls: "42", self_time: "1.1" },
                { name: "public.idle", calls: 0, self_time: 0 },
                { name: "public.other", calls: 1, self_time: 0.2 },
              ];
        },
      ],
      [/^explain/, [{ "QUERY PLAN": JSON.stringify([plan]) }]],
    ]);
  };

  it("needs a direct session", async () => {
    const explain = { tables: ["notes"], claims: {} };
    expect(await check("BS212", { explain })).toMatchObject([
      {
        severity: "warning",
        message:
          "--explain needs a direct database connection (local stack, $DATABASE_URL or --db-url-stdin).",
      },
    ]);
    expect(
      await check("BS212", { explain, database: { skipped: "saved file" } }),
    ).toMatchObject([
      { message: expect.stringMatching(/--db-url-stdin\): saved file$/) },
    ]);
  });

  it("plans a table as the claims and reports function time and per-row SubPlans", async () => {
    const db = explainDb();
    const [finding] = await check("BS212", {
      database: db,
      explain: {
        tables: ["notes"],
        claims: { role: "authenticated", sub: "u1" },
      },
    });
    expect(finding).toMatchObject({
      severity: "warning",
      target: "public.notes:explain",
      object: { kind: "table", schema: "public", name: "notes" },
    });
    expect(finding!.message).toBe(
      "public.notes as authenticated u1: 2.00 ms, 0 InitPlans. Plan: Seq Scan on notes 1.50 ms ×1 > SubPlan 1: Index Scan 0.01 ms ×40. Per-row SubPlans: SubPlan 1: Index Scan ×40; wrap the policy's function calls in `(select ...)` so they run once as an InitPlan. Function time: private.is_member 1.00 ms over 40 calls (50%), public.other 0.20 ms over 1 call (10%).",
    );
    const texts = db.texts();
    expect(texts.slice(0, 4)).toEqual([
      "begin",
      "set local statement_timeout = '30s'",
      "savepoint bs_track",
      "set local track_functions = 'all'",
    ]);
    expect(texts).toContain('set local role "authenticated"');
    expect(texts).toContain(
      `select set_config('request.jwt.claims', '{"role":"authenticated","sub":"u1"}', true)`,
    );
    expect(texts.find((text) => text.startsWith("explain"))).toBe(
      'explain (analyze, buffers, format json) select * from "public"."notes" limit 1000',
    );
    expect(texts.at(-1)).toBe("rollback");
  });

  it("shows the plan only when the role may not track functions", async () => {
    const db = database([
      [/track_functions/, { throws: pgError("42501", "permission denied") }],
      [
        /^explain/,
        [
          {
            "QUERY PLAN": [
              { Plan: { "Node Type": "Seq Scan", "Relation Name": "tags" } },
            ],
          },
        ],
      ],
    ]);
    const [finding] = await check("BS212", {
      database: db,
      explain: { tables: ["public.tags"], claims: { role: "anon" } },
    });
    expect(finding!.severity).toBe("info");
    expect(finding!.message).toBe(
      "public.tags as anon: 0.00 ms, 0 InitPlans. Plan: Seq Scan on tags 0.00 ms ×1. Function times need `track_functions`, which this role may not set; showing the plan only.",
    );
    expect(db.texts()).toContain("rollback to savepoint bs_track");
    expect(
      db.texts().some((text) => text.includes("pg_stat_xact_user_functions")),
    ).toBe(false);
  });

  it("says when no tracked function ran", async () => {
    const [finding] = await check("BS212", {
      database: database([
        [/^explain/, [{ "QUERY PLAN": [{ Plan: { "Node Type": "Result" } }] }]],
      ]),
      explain: { tables: ["notes"], claims: {} },
    });
    expect(finding!.message).toContain(
      "public.notes as anon: 0.00 ms, 0 InitPlans. Plan: Result 0.00 ms ×1. No tracked function ran",
    );
  });

  it("gives every function a share of 0 when the plan took no time", async () => {
    let reads = 0;
    const zero = database([
      [
        /pg_stat_xact_user_functions/,
        () => [{ name: "f.g", calls: reads++, self_time: 0.5 * reads }],
      ],
      [/^explain/, [{ "QUERY PLAN": [{ Plan: { "Node Type": "Result" } }] }]],
    ]);
    const [finding] = await check("BS212", {
      database: zero,
      explain: { tables: ["notes"], claims: {} },
    });
    expect(finding!.message).toContain(
      "Function time: f.g 0.50 ms over 1 call (0%).",
    );
  });

  it("reports unknown tables, bad roles, missing plans and failures, and always rolls back", async () => {
    const empty = database([]);
    const findings = await check("BS212", {
      database: empty,
      explain: {
        tables: ["nope", "better_supabase.memberships", "notes"],
        claims: { role: "x; drop" },
      },
    });
    expect(findings).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining('--explain: no table "nope"'),
      },
      {
        target: "better_supabase.memberships:explain",
        message:
          '--explain better_supabase.memberships failed: Invalid role "x; drop" in the claims',
      },
      { target: "public.notes:explain" },
    ]);

    const noPlan = database([]);
    const [missing] = await check("BS212", {
      database: noPlan,
      explain: { tables: ["notes"], claims: {} },
    });
    expect(missing!.message).toBe(
      "--explain public.notes failed: EXPLAIN returned no plan",
    );
    expect(noPlan.texts().at(-1)).toBe("rollback");

    const [failed] = await check("BS212", {
      database: database([
        [/^explain/, { throws: pgError("57014", "canceling statement") }],
      ]),
      explain: { tables: ["notes"], claims: {} },
    });
    expect(failed!.message).toBe(
      "--explain public.notes failed: canceling statement",
    );
  });
});
