import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { PgQueryable } from "../../src/cli/db.ts";
import type { PgDelta } from "../../src/cli/in-stack-diff.ts";

import {
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

  it("explains how to install pg-delta when it is missing", async () => {
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
          loadDiagnostics: [],
          targetDiagnostics: [],
          driftDiagnostics: [],
          skipped: [],
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
});
