import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { PgQueryable } from "../../src/cli/db.ts";
import type { PgDelta } from "../../src/cli/in-stack-diff.ts";

import {
  cloneStackDatabase,
  inStackDiff,
  isShadowFailure,
  loadPgDelta,
  openPgPool,
  migrationFiles,
  migrationVersion,
  pendingMigrations,
} from "../../src/cli/in-stack-diff.ts";
import { fakeConnect } from "./fixtures/fake-connect.ts";

const STACK_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

describe("in-stack diff helpers", () => {
  it("recognises a shadow database that could not start", () => {
    expect(
      isShadowFailure(
        "FATAL: could not create shared memory segment: No space left on device",
      ),
    ).toBe(true);
    expect(isShadowFailure("ERROR: syntax error at or near")).toBe(false);
  });

  it("lists the migrations the stack has not applied", () => {
    expect(
      pendingMigrations(
        [
          "supabase/migrations/20260101000000_a.sql",
          "supabase/migrations/20260102000000_b.sql",
          "supabase/migrations/notes.sql",
        ],
        new Set(["20260101000000"]),
      ),
    ).toEqual(["supabase/migrations/20260102000000_b.sql"]);
  });

  it("loads pg-delta and opens a pool without connecting", async () => {
    const delta = await loadPgDelta();
    const pool = await openPgPool(STACK_URL);

    expect(typeof delta.planSchemaFiles).toBe("function");
    await pool.end();
  });

  it("says to reinstall better-supabase when pg-delta does not load", async () => {
    await expect(
      loadPgDelta(() => Promise.reject(new Error("Cannot find package"))),
    ).rejects.toMatchObject({ code: "dependency_missing" });
  });

  it("formats the migration version in UTC", () => {
    expect(migrationVersion(new Date("2026-10-21T08:09:10Z"))).toBe(
      "20261021080910",
    );
  });
});

interface FakeCandidate {
  readonly kind: string;
  readonly from: { kind: string; schema: string; name: string };
  readonly to: { kind: string; schema: string; name: string };
  readonly status: "unambiguous" | "ambiguous" | "nearMiss";
  readonly reason?: string;
}

const table = (name: string): FakeCandidate["from"] => ({
  kind: "table",
  schema: "public",
  name,
});

describe("inStackDiff", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-in-stack-"));
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(join(root, "supabase/schemas/a.sql"), "create table a ();");
    await writeFile(
      join(root, "supabase/migrations/20260101000000_init.sql"),
      "",
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function harness(
    options: {
      applied?: string[];
      candidates?: FakeCandidate[];
      destructive?: boolean;
      provisionFails?: boolean;
      loadDiagnostics?: {
        code: string;
        severity: "error" | "warning";
        message: string;
      }[];
      verdict?: Record<string, unknown>;
    } = {},
  ): {
    events: string[];
    accepted: unknown[][];
    base: Parameters<typeof inStackDiff>[0];
  } {
    const events: string[] = [];
    const accepted: unknown[][] = [];

    const client: PgQueryable = {
      query: <R>(text: string) => {
        events.push(text.startsWith("select version") ? "applied" : text);

        // SAFETY: inStackDiff selects the version column only.
        const rows = (options.applied ?? ["20260101000000"]).map((version) => ({
          version,
        })) as R[];

        return Promise.resolve({ rows });
      },
    };

    const pool = (name: string) => ({
      end: () => {
        events.push(`end ${name}`);

        return Promise.resolve();
      },
    });

    const delta = {
      supabaseProfile: { id: "supabase" },
      hasBlockingDiagnostics: (
        items: { code: string; severity: string }[],
        flags: { strictCoverage?: boolean },
      ) =>
        items.some(
          (item) =>
            item.severity === "error" ||
            (flags.strictCoverage === true && item.code === "unmodeled_kind"),
        ),
      provePlan: () => {
        events.push("prove");

        return Promise.resolve({
          ok: true,
          driftDeltas: [],
          dataViolations: [],
          rewriteViolations: [],
          ...options.verdict,
        });
      },
      encodeId: (id: { schema: string; name: string }) =>
        `table:${id.schema}.${id.name}`,
      provisionCoLocatedShadow: (url: string) => {
        events.push(`shadow ${url}`);

        return options.provisionFails === true
          ? Promise.reject(new Error("permission denied to create database"))
          : Promise.resolve({
              url: "postgresql://shadow",
              name: "shadow",
              cleanup: () => {
                events.push("cleanup");

                return Promise.resolve();
              },
            });
      },
      planSchemaFiles: (
        _target: unknown,
        _shadow: unknown,
        files: { name: string }[],
        planOptions: { acceptRenames?: unknown[]; renames: string },
      ) => {
        events.push(`plan ${files.map((file) => file.name).join(",")}`);
        accepted.push(planOptions.acceptRenames ?? []);

        return Promise.resolve({
          plan: {
            renameCandidates: options.candidates ?? [],
            actions: [
              { sql: "create table a ()", verb: "create", dataLoss: "none" },
              {
                sql: "drop table b;",
                verb: "drop",
                dataLoss: options.destructive === true ? "destructive" : "none",
              },
            ],
          },
          loadDiagnostics: options.loadDiagnostics ?? [],
          targetDiagnostics: [],
          driftDiagnostics: [],
          skipped: [],
          profile: { proveOptions: {} },
          extract: () => Promise.resolve({ factBase: {} }),
        });
      },
    };

    return {
      events,
      accepted,
      base: {
        url: STACK_URL,
        root,
        env: {},
        files: ["supabase/schemas/a.sql"],
        schemasDir: "supabase/schemas",
        migrations: ["supabase/migrations/20260101000000_init.sql"],
        open: fakeConnect(client).connect,
        // SAFETY: the fake provides the parts of pg-delta that inStackDiff calls.
        loadDelta: () => Promise.resolve(delta as unknown as PgDelta),
        // SAFETY: the fake pool only needs end().
        openPool: (url) =>
          Promise.resolve(
            pool(url.includes("shadow") ? "shadow" : "target") as never,
          ),
      },
    };
  }

  it("plans the files in a shadow and joins the actions into SQL", async () => {
    const { base, events } = harness();
    const result = await inStackDiff(base);

    expect(result.sql).toBe("create table a ();\n\ndrop table b;");
    expect(result.gate.blocked).toBe(false);
    expect(events).toContain(`shadow ${STACK_URL}`);
    expect(events).toContain("plan supabase/schemas/a.sql");
    expect(events.at(-1)).toBe("cleanup");
    expect(events).toContain("end shadow");
    expect(events).toContain("end target");
  });

  it("reports _custom/ files that no migration delivers", async () => {
    const custom = join(root, "supabase/schemas/_custom");

    await mkdir(custom, { recursive: true });
    await writeFile(join(custom, "bare.sql"), "create cast (a as b);");
    await writeFile(join(custom, "none.sql"), "-- pgdelta-migration: none\n");
    await writeFile(
      join(custom, "gone.sql"),
      "-- pgdelta-migration: ../../migrations/9_gone.sql\n",
    );
    await writeFile(
      join(custom, "ok.sql"),
      "-- pgdelta-migration: ../../migrations/20260101000000_init.sql\n",
    );

    const listed: string[] = [];

    const result = await inStackDiff({
      ...harness().base,
      loadFrontends: () =>
        Promise.resolve({
          listCustomFiles: (base: string) => {
            listed.push(base);

            return [
              {
                path: "_custom/bare.sql",
                sql: "",
                migrations: [],
                hasNone: false,
                delivered: false,
              },
              {
                path: "_custom/gone.sql",
                sql: "",
                migrations: ["../../migrations/9_gone.sql"],
                hasNone: false,
                delivered: true,
              },
              {
                path: "_custom/none.sql",
                sql: "",
                migrations: [],
                hasNone: true,
                delivered: true,
              },
              {
                path: "_custom/ok.sql",
                sql: "",
                migrations: ["../../migrations/20260101000000_init.sql"],
                hasNone: false,
                delivered: true,
              },
            ];
          },
        }),
    });

    expect(listed).toEqual([join(root, "supabase/schemas")]);
    expect(result.custom).toEqual([
      { path: "_custom/bare.sql", status: "undelivered" },
      {
        path: "_custom/gone.sql",
        status: "dangling",
        migration: "../../migrations/9_gone.sql",
      },
    ]);
  });

  it("does not load the frontends without a _custom/ folder", async () => {
    const result = await inStackDiff({
      ...harness().base,
      loadFrontends: () => Promise.reject(new Error("must not load")),
    });

    expect(result.custom).toEqual([]);
  });

  const unmodeled = {
    code: "unmodeled_kind",
    severity: "warning" as const,
    message: "a user object of a kind pg-delta does not model",
  };

  it("stops on an object pg-delta cannot manage unless coverage is relaxed", async () => {
    const stopped = await inStackDiff(
      harness({ loadDiagnostics: [unmodeled] }).base,
    );

    expect(stopped.sql).toBe("");
    expect(stopped.blocking).toEqual([unmodeled]);

    const relaxed = await inStackDiff({
      ...harness({ loadDiagnostics: [unmodeled] }).base,
      strictCoverage: false,
    });

    expect(relaxed.blocking).toEqual([]);
    expect(relaxed.sql).toContain("create table a ()");
  });

  it("proves the plan on a clone and drops the clone", async () => {
    const { base, events } = harness();
    const cleaned: string[] = [];

    const result = await inStackDiff({
      ...base,
      prove: true,
      cloneStack: () =>
        Promise.resolve({
          url: "postgresql://clone",
          cleanup: () => {
            cleaned.push("clone");

            return Promise.resolve();
          },
        }),
    });

    expect(events).toContain("prove");
    expect(result.proof).toEqual({ status: "proved" });
    expect(cleaned).toEqual(["clone"]);
  });

  it("refuses a plan the proof rejects", async () => {
    const result = await inStackDiff({
      ...harness({
        verdict: {
          ok: false,
          dataViolations: [
            { table: { schema: "public", name: "b" }, before: 3, after: 0 },
          ],
        },
      }).base,
      prove: true,
      cloneStack: () =>
        Promise.resolve({
          url: "postgresql://clone",
          cleanup: () => Promise.resolve(),
        }),
    });

    expect(result.sql).toBe("");
    expect(result.proof).toEqual({
      status: "failed",
      problems: ["public.b lost data (3 rows before, 0 after)"],
    });
  });

  it("skips the proof when the stack cannot be cloned", async () => {
    const result = await inStackDiff({
      ...harness().base,
      prove: true,
      cloneStack: () => Promise.reject(new Error("permission denied")),
    });

    expect(result.sql).toContain("create table a ()");
    expect(result.proof).toMatchObject({ status: "skipped" });
  });

  it("treats an unreadable migrations table as nothing applied", async () => {
    const h = harness();

    const failing: PgQueryable = {
      query: () => Promise.reject(new Error("no table")),
    };

    await expect(
      inStackDiff({
        ...h.base,
        open: fakeConnect(failing).connect,
        migrations: ["supabase/migrations/20260101000000_a.sql"],
      }),
    ).rejects.toMatchObject({ code: "check_failed" });
  });

  it("blocks destructive actions unless data loss is allowed", async () => {
    const blocked = await inStackDiff(harness({ destructive: true }).base);

    expect(blocked.sql).toBe("");
    expect(blocked.gate.blocked).toBe(true);
    expect(blocked.issues[0]?.code).toBe("plan_data_loss");

    const allowed = await inStackDiff({
      ...harness({ destructive: true }).base,
      allowDataLoss: true,
    });

    expect(allowed.sql).toContain("drop table b;");
    expect(allowed.gate.blocked).toBe(false);
  });

  it("asks about a rename nobody confirmed and plans it once", async () => {
    const { base, accepted } = harness({
      candidates: [
        {
          kind: "table",
          from: table("old"),
          to: table("fresh"),
          status: "unambiguous",
        },
      ],
    });

    const result = await inStackDiff(base);

    expect(result.gate.questions).toHaveLength(1);
    expect(accepted).toEqual([[]]);
  });

  it("plans again with a rename a hint confirmed", async () => {
    const candidate: FakeCandidate = {
      kind: "table",
      from: table("old"),
      to: table("fresh"),
      status: "unambiguous",
    };

    const { base, accepted } = harness({ candidates: [candidate] });

    const result = await inStackDiff({
      ...base,
      hints: [{ from: "old", to: "fresh" }],
    });

    expect(result.gate.accepted).toHaveLength(1);
    expect(accepted).toEqual([[], [candidate]]);
  });

  it("reports an ambiguous rename with its reason", async () => {
    const { base } = harness({
      candidates: [
        {
          kind: "table",
          from: table("old"),
          to: table("fresh"),
          status: "nearMiss",
          reason: "an index names the table",
        },
      ],
    });

    const result = await inStackDiff(base);

    expect(result.gate.unresolved).toHaveLength(1);
    expect(result.issues[0]?.message).toContain("an index names the table");
  });

  it("refuses to diff a stack that lags behind the migrations", async () => {
    const { base } = harness({ applied: [] });

    await expect(
      inStackDiff({
        ...base,
        migrations: [1, 2, 3, 4].map(
          (day) => `supabase/migrations/2026010${String(day)}000000_m.sql`,
        ),
      }),
    ).rejects.toThrow(
      /has not applied 4 migration\(s\) \(.+20260101000000_m\.sql, .+20260102000000_m\.sql, .+20260103000000_m\.sql, \.\.\.\)/,
    );
  });

  it("reports a shadow database it can't create", async () => {
    const { base } = harness({ provisionFails: true });

    await expect(inStackDiff(base)).rejects.toThrow(
      /permission denied to create database/,
    );
  });

  it("lists the migration files in order", async () => {
    await writeFile(
      join(root, "supabase/migrations/20250101000000_older.sql"),
      "",
    );

    expect(await migrationFiles(root, "supabase")).toEqual([
      "supabase/migrations/20250101000000_older.sql",
      "supabase/migrations/20260101000000_init.sql",
    ]);
  });

  const clone = () =>
    Promise.resolve({
      url: "postgresql://clone",
      cleanup: () => Promise.resolve(),
    });

  it.each([
    [{ applyError: new Error("boom") }, ["an action failed: boom"]],
    [{ driftDeltas: [1, 2] }, ["2 difference(s) remain after the plan runs"]],
    [
      { rewriteViolations: [{ table: { schema: "public", name: "b" } }] },
      ["public.b was rewritten by an action that did not declare it"],
    ],
    [{}, ["the plan did not converge"]],
  ])("words the proof's finding %o", async (verdict, problems) => {
    const result = await inStackDiff({
      ...harness({ verdict: { ok: false, ...verdict } }).base,
      prove: true,
      cloneStack: clone,
    });

    expect(result.proof).toEqual({ status: "failed", problems });
  });

  it("names a clone failure that is not an Error", async () => {
    const result = await inStackDiff({
      ...harness().base,
      prove: true,
      cloneStack: () => Promise.reject("no template"),
    });

    expect(result.proof).toEqual({
      status: "skipped",
      reason: "the stack could not be cloned (no template)",
    });
  });

  it("clones through the pools it opens when no cloneStack is given", async () => {
    const queries: string[] = [];
    const h = harness();

    const result = await inStackDiff({
      ...h.base,
      prove: true,
      openPool: () =>
        Promise.resolve({
          query: (text: string) => {
            queries.push(text);

            return Promise.resolve({ rows: [] });
          },
          end: () => Promise.resolve(),
        } as never),
    });

    expect(result.proof).toEqual({ status: "proved" });
    expect(queries.some((text) => text.startsWith("create database"))).toBe(
      true,
    );
    expect(queries.at(-1)).toMatch(
      /^drop database if exists "bsb_proof_\w+" with \(force\)$/u,
    );
  });

  it("reads _custom/ files with pg-delta's own frontends", async () => {
    const custom = join(root, "supabase/schemas/_custom");

    await mkdir(custom, { recursive: true });
    await writeFile(join(custom, "bare.sql"), "create cast (a as b);");

    const result = await inStackDiff(harness().base);

    expect(result.custom).toEqual([
      { path: expect.stringContaining("bare.sql"), status: "undelivered" },
    ]);
  });
});

describe("cloneStackDatabase", () => {
  function fakePool(failures: number) {
    const calls: string[] = [];
    let left = failures;

    const pool = {
      query: (text: string, values?: unknown[]) => {
        calls.push(values === undefined ? text : `${text} ${String(values)}`);

        if (text.startsWith("create database") && left > 0) {
          left -= 1;

          return Promise.reject(new Error("source database is being accessed"));
        }

        if (text.startsWith("drop database")) {
          return Promise.reject(new Error("database is in use"));
        }

        return Promise.resolve({ rows: [] });
      },
      end: () => {
        calls.push("end");

        return Promise.resolve();
      },
    };

    const open = (url: string) => {
      calls.push(url);

      return Promise.resolve(pool as never);
    };

    return { calls, open };
  }

  it("copies the database from the admin database, retrying once, and drops it even when the drop fails", async () => {
    const { calls, open } = fakePool(1);

    const cloned = await cloneStackDatabase(
      "postgresql://postgres:pw@127.0.0.1:54322/my%20db",
      open,
    );

    const name = /\/(bsb_proof_\w+)$/u.exec(cloned.url)?.[1];

    expect(cloned.url).toMatch(
      /^postgresql:\/\/postgres:pw@127\.0\.0\.1:54322\/bsb_proof_/u,
    );
    expect(calls[0]).toBe("postgresql://postgres:pw@127.0.0.1:54322/postgres");
    expect(calls.filter((call) => call.startsWith("create database"))).toEqual([
      `create database "${String(name)}" template "my db"`,
      `create database "${String(name)}" template "my db"`,
    ]);
    expect(calls[1]).toContain("pg_terminate_backend");
    expect(calls[1]).toContain(" my db");

    await expect(cloned.cleanup()).resolves.toBeUndefined();

    expect(calls.slice(-2)).toEqual([
      `drop database if exists "${String(name)}" with (force)`,
      "end",
    ]);
  });

  it("ends the pool and rethrows when the copy fails twice", async () => {
    const { calls, open } = fakePool(2);

    await expect(cloneStackDatabase(STACK_URL, open)).rejects.toThrow(
      "source database is being accessed",
    );
    expect(calls.at(-1)).toBe("end");
  });
});
