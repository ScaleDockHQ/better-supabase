import { describe, expect, it } from "vitest";

import type { PgQueryable } from "../../../src/cli/db.ts";

import {
  backfillStatements,
  dbBackfillCommand,
  parseColumnPath,
  runBackfill,
} from "../../../src/cli/commands/backfill.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

const LOCAL = { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" };

interface Fake {
  readonly sent: string[];
  readonly client: PgQueryable;
}

/**
 * A database where every column exists, `project_id` references `projects.id`,
 * and the batches fill `batches` in turn, then 0.
 */
function fakeDb(
  options: {
    batches?: readonly number[];
    remaining?: number;
    missing?: string;
    key?: string | null;
  } = {},
): Fake {
  const sent: string[] = [];
  const batches = [...(options.batches ?? [])];

  return {
    sent,
    client: {
      // SAFETY: each branch returns the row shape its query selects.
      query: ((text: string, values?: readonly unknown[]) => {
        sent.push(text);

        if (text.includes("pg_attribute a\n  join")) {
          return Promise.resolve({
            rows: [{ found: values?.[2] !== options.missing }],
          });
        }

        if (text.includes("c.contype = 'f'")) {
          return Promise.resolve({
            rows: options.key === null ? [] : [{ key: options.key ?? "id" }],
          });
        }

        if (text.startsWith("with batch")) {
          return Promise.resolve({ rows: [{ filled: batches.shift() ?? 0 }] });
        }

        if (text.includes("not exists (select 1")) {
          return Promise.resolve({ rows: [{ count: "2" }] });
        }

        if (text.startsWith("select count(*)")) {
          return Promise.resolve({
            rows: [{ count: String(options.remaining ?? 0) }],
          });
        }

        return Promise.resolve({ rows: [] });
      }) as unknown as PgQueryable["query"],
    },
  };
}

const args = (argv: string[]) => parseCommandArgs(dbBackfillCommand, argv);

const config = resolveConfig({}, "/tmp/backfill");

describe("parseColumnPath", () => {
  it("defaults to public", () => {
    expect(parseColumnPath("invoices.organization_id", "column")).toEqual({
      schema: "public",
      table: "invoices",
      column: "organization_id",
    });
    expect(parseColumnPath("billing.invoices.org", "column")).toEqual({
      schema: "billing",
      table: "invoices",
      column: "org",
    });
  });

  it("rejects a bare name", () => {
    expect(() => parseColumnPath("invoices", "--from")).toThrow(
      "table.column or schema.table.column",
    );
  });
});

describe("backfillStatements", () => {
  const target = {
    schema: "public",
    table: "invoices",
    column: "organization_id",
  };

  it("reads and writes only null rows, one batch at a time", () => {
    const { batch, pending } = backfillStatements(
      target,
      {
        kind: "column",
        from: {
          schema: "public",
          table: "projects",
          column: "organization_id",
        },
        via: "project_id",
        key: "id",
      },
      500,
    );

    expect(batch).toContain('where t."organization_id" is null');
    expect(batch).toContain('s."organization_id" is not null');
    expect(batch).toContain(
      'join "public"."projects" s on s."id" = t."project_id"',
    );
    expect(batch).toContain("limit 500");
    expect(batch).toContain("for update of t skip locked");
    expect(pending).toContain('t."organization_id" is null');
  });

  it("sets a literal", () => {
    const { batch } = backfillStatements(
      target,
      { kind: "value", value: "'EUR'" },
      10,
    );

    expect(batch).toContain(`set "organization_id" = 'EUR'`);
    expect(batch).toContain('where t."organization_id" is null');
  });
});

describe("db backfill", () => {
  it("fills in batches until none is left, and logs progress", async () => {
    const db = fakeDb({ batches: [1000, 1000, 12] });
    const open = fakeConnect(db.client);
    const lines: string[] = [];

    const result = await runBackfill(
      config,
      args([
        "invoices.organization_id",
        "--from",
        "projects.organization_id",
        "via",
        "project_id",
      ]),
      LOCAL,
      { open: open.connect, log: (line) => lines.push(line) },
    );

    expect(result).toMatchObject({
      code: 0,
      data: {
        column: "public.invoices.organization_id",
        from: "public.projects.organization_id",
        via: "project_id",
        key: "id",
        filled: 2012,
        batches: 3,
        remaining: 0,
      },
    });
    expect(lines).toHaveLength(3);
    expect(lines.at(-1)).toContain("2012 rows");
    expect(result.output).toContain("doctor --fix");
    expect(open.closed()).toBe(1);
  });

  it("takes --via as a flag too", async () => {
    const db = fakeDb();
    const open = fakeConnect(db.client);

    const result = await runBackfill(
      config,
      args([
        "invoices.organization_id",
        "--from",
        "projects.organization_id",
        "--via",
        "project_id",
      ]),
      LOCAL,
      { open: open.connect },
    );

    expect(result.code).toBe(0);
    expect(result.output).toContain("no null values to fill");
  });

  it("writes nothing with --dry-run", async () => {
    const db = fakeDb({ remaining: 40 });
    const open = fakeConnect(db.client);
    const consent: string[] = [];

    const result = await runBackfill(
      config,
      args([
        "invoices.organization_id",
        "--from",
        "projects.organization_id",
        "via",
        "project_id",
        "--dry-run",
      ]),
      {},
      {
        open: open.connect,
        requireConsent: (request) => consent.push(request.effect),
      },
      "postgresql://postgres@db.example.com:5432/postgres",
    );

    expect(result).toMatchObject({
      code: 0,
      data: { dryRun: true, pending: 40, remaining: 2, filled: 0 },
    });
    expect(db.sent.some((text) => text.startsWith("with batch"))).toBe(false);
    expect(consent).toEqual([]);
  });

  it("asks for consent on a remote database", async () => {
    const open = fakeConnect(fakeDb().client);
    const consent: string[] = [];

    await runBackfill(
      config,
      args(["invoices.currency", "--value", "'EUR'"]),
      {},
      {
        open: open.connect,
        requireConsent: (request) => consent.push(request.detail),
      },
      "postgresql://postgres@db.example.com:5432/postgres",
    );

    expect(consent).toEqual([
      "db backfill fills public.invoices.currency on db.example.com:5432",
    ]);
  });

  it("reports rows it could not fill", async () => {
    const open = fakeConnect(fakeDb({ batches: [3], remaining: 2 }).client);

    const result = await runBackfill(
      config,
      args([
        "invoices.organization_id",
        "--from",
        "projects.organization_id",
        "via",
        "project_id",
      ]),
      LOCAL,
      { open: open.connect },
    );

    expect(result).toMatchObject({
      code: 0,
      data: { filled: 3, remaining: 2 },
    });
    expect(result.output).toContain("2 rows are still null");
  });

  it.each([
    [["invoices.organization_id"], "--from <table.column>"],
    [
      ["invoices.organization_id", "--value", "'x'", "--from", "a.b"],
      "--from <table.column>",
    ],
    [
      ["invoices.organization_id", "--from", "projects.organization_id"],
      "via <column>",
    ],
    [["invoices.currency", "--value", "now()"], "SQL literal"],
    [["invoices.currency", "--value", "'x'; drop table a"], "SQL literal"],
    [
      ["invoices.currency", "--value", "1", "--batch-size", "0"],
      "--batch-size",
    ],
    [["invoices.currency", "with", "x", "--value", "1"], "Unexpected with x"],
    [
      ["invoices.organization_id", "--value", "1", "via", "project_id"],
      "--value needs none",
    ],
  ])("rejects %j", async (argv, message) => {
    const open = fakeConnect(fakeDb().client);

    await expect(
      runBackfill(config, args(argv), LOCAL, { open: open.connect }),
    ).rejects.toThrow(message);
  });

  it.each([
    "'EUR'",
    "'00000000-0000-4000-8000-000000000001'::uuid",
    "42",
    "-1.5",
    "true",
    "'it''s'::varchar(10)",
  ])("accepts the literal %s", async (value) => {
    const open = fakeConnect(fakeDb().client);

    const result = await runBackfill(
      config,
      args(["invoices.currency", "--value", value]),
      LOCAL,
      { open: open.connect },
    );

    expect(result.code).toBe(0);
  });

  it("fails on a missing column", async () => {
    const open = fakeConnect(fakeDb({ missing: "organization_id" }).client);

    await expect(
      runBackfill(
        config,
        args(["invoices.organization_id", "--value", "1"]),
        LOCAL,
        { open: open.connect },
      ),
    ).rejects.toThrow("no column public.invoices.organization_id");
  });

  it("fails without a key to follow", async () => {
    const open = fakeConnect(fakeDb({ key: null }).client);

    await expect(
      runBackfill(
        config,
        args([
          "invoices.organization_id",
          "--from",
          "projects.organization_id",
          "via",
          "project_id",
        ]),
        LOCAL,
        { open: open.connect },
      ),
    ).rejects.toThrow("has no foreign key to public.projects");
  });

  it("names the key in a dry run that leaves rows null", async () => {
    const open = fakeConnect(fakeDb().client);

    const result = await runBackfill(
      config,
      args([
        "invoices.organization_id",
        "--from",
        "projects.organization_id",
        "via",
        "project_id",
        "--dry-run",
      ]),
      LOCAL,
      { open: open.connect },
    );

    expect(result.output).toContain(
      "2 rows would stay null: their project_id is null or has no match with a value.",
    );
  });

  it("says a value fill left rows another session held", async () => {
    const open = fakeConnect(fakeDb({ batches: [1], remaining: 1 }).client);

    const result = await runBackfill(
      config,
      args(["invoices.currency", "--value", "'EUR'"]),
      LOCAL,
      { open: open.connect },
    );

    expect(result.output).toContain(
      "Filled 1 row of public.invoices.currency in 1 batch.",
    );
    expect(result.output).toContain(
      "1 row is still null because another session held them. Run this again.",
    );
  });

  it("fails on a missing column to follow", async () => {
    const open = fakeConnect(fakeDb({ missing: "project_id" }).client);

    await expect(
      runBackfill(
        config,
        args([
          "invoices.organization_id",
          "--from",
          "projects.organization_id",
          "via",
          "project_id",
        ]),
        LOCAL,
        { open: open.connect },
      ),
    ).rejects.toThrow("no column public.invoices.project_id to follow");
  });

  it("returns a database error as a failed result", async () => {
    const open = fakeConnect({
      // SAFETY: the fake only ever rejects.
      query: () =>
        Promise.reject(new Error("canceling statement due to lock timeout")),
    });

    const result = await runBackfill(
      config,
      args(["invoices.currency", "--value", "'EUR'"]),
      LOCAL,
      { open: open.connect },
    );

    expect(result).toMatchObject({
      code: 1,
      errorCode: "failed",
      error:
        "db backfill public.invoices.currency failed: canceling statement due to lock timeout",
    });
  });
});
