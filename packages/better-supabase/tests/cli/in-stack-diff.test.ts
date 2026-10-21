import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { PgQueryable } from "../../src/cli/db.ts";
import type { ExecResult } from "../../src/cli/exec.ts";

import {
  adminUrl,
  diffSql,
  inStackDiff,
  isShadowFailure,
  migrationFiles,
  migrationVersion,
  pendingMigrations,
  postgresBin,
  withDatabase,
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

  it("connects as the stack's superuser and swaps the database", () => {
    expect(adminUrl(STACK_URL)).toBe(
      "postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres",
    );
    expect(withDatabase(STACK_URL, "bsb_diff_x")).toBe(
      "postgresql://postgres:postgres@127.0.0.1:54322/bsb_diff_x",
    );
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

  it("reads the SQL from JSON output and falls back to text", () => {
    expect(diffSql('Connecting...\n{"diff":"create table a ();"}')).toBe(
      "create table a ();",
    );
    expect(diffSql("create table a ();")).toBe("create table a ();");
    expect(diffSql('{"other":1}')).toBe('{"other":1}');
    expect(diffSql("do $$ begin { end $$")).toBe("do $$ begin { end $$");
  });

  it("finds the postmaster's bin directory from its data directory", () => {
    const ps = [
      "  101 /usr/sbin/sshd -D",
      "  202 /cache/pg/17/bin/postgres -D /home/me/.supabase/stacks/abc/data/db -p 54322",
      "  303 /cache/pg/17/bin/postgres -D /home/me/.supabase/stacks/def/data/db",
    ].join("\n");

    expect(postgresBin(ps, "/home/me/.supabase/stacks/abc/data/db")).toBe(
      "/cache/pg/17/bin",
    );
    expect(postgresBin(ps, "/elsewhere")).toBeUndefined();
  });

  it("formats the migration version in UTC", () => {
    expect(migrationVersion(new Date("2026-10-21T08:09:10.500Z"))).toBe(
      "20261021080910",
    );
  });
});

describe("inStackDiff", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-in-stack-"));
    await mkdir(join(root, "supabase/schemas/app"), { recursive: true });
    await mkdir(join(root, "supabase/schemas/storage"), { recursive: true });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/app/b.sql"),
      "create table app.b ();",
    );
    await writeFile(
      join(root, "supabase/schemas/app/a.sql"),
      "create schema app;",
    );
    await writeFile(
      join(root, "supabase/schemas/storage/policies.sql"),
      "create policy p;",
    );
    await writeFile(
      join(root, "supabase/migrations/20260101000000_init.sql"),
      "",
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function harness(options: { applied?: string[]; badFile?: string } = {}): {
    sent: string[];
    commands: string[];
    open: ReturnType<typeof fakeConnect>;
    run: (command: string, args: readonly string[]) => Promise<ExecResult>;
  } {
    const sent: string[] = [];
    const commands: string[] = [];

    const rowsFor = (text: string): unknown[] => {
      if (text.includes("schema_migrations")) {
        return (options.applied ?? ["20260101000000"]).map((version) => ({
          version,
        }));
      }

      if (text === "show data_directory") {
        return [{ data_directory: "/stacks/abc/data/db" }];
      }

      if (text.startsWith("select nspname")) {
        return [
          { nspname: "public" },
          { nspname: "app" },
          { nspname: "storage" },
        ];
      }

      if (text.includes("pg_policies")) {
        return [{ tablename: "objects", policyname: "Owner reads" }];
      }

      return [];
    };

    const client: PgQueryable = {
      query: <R>(text: string) => {
        sent.push(text);

        if (options.badFile !== undefined && text === options.badFile) {
          return Promise.reject(new Error("relation does not exist"));
        }

        // SAFETY: the fake returns the row shape each query in inStackDiff selects.
        return Promise.resolve({ rows: rowsFor(text) as R[] });
      },
    };

    return {
      sent,
      commands,
      open: fakeConnect(client),
      run: (command, args) => {
        commands.push([command, ...args].join(" "));

        const stdout =
          command === "ps"
            ? "  9 /pg/bin/postgres -D /stacks/abc/data/db -p 54322"
            : "";

        return Promise.resolve({ code: 0, stdout, stderr: "" });
      },
    };
  }

  const files = [
    "supabase/schemas/app/a.sql",
    "supabase/schemas/app/b.sql",
    "supabase/schemas/storage/policies.sql",
  ];

  it("copies the stack, replaces the managed objects with the files and diffs", async () => {
    const { sent, commands, open, run } = harness();
    const diffs: string[][] = [];

    const sql = await inStackDiff({
      url: STACK_URL,
      root,
      env: {},
      files,
      schemasDir: "supabase/schemas",
      migrations: ["supabase/migrations/20260101000000_init.sql"],
      open: open.connect,
      run,
      supabase: (args) => {
        diffs.push([...args]);

        return Promise.resolve({
          code: 0,
          stdout: '{"diff":"alter table app.b add column c int;\\n"}',
          stderr: "",
        });
      },
    });

    expect(sql).toBe("alter table app.b add column c int;");
    expect(commands[0]).toBe("ps -axo pid=,command=");
    expect(commands[1]).toMatch(
      /^\/pg\/bin\/pg_dump --schema-only --file .+ postgresql:\/\/supabase_admin:/,
    );
    expect(commands[2]).toMatch(
      /^\/pg\/bin\/psql -X -q -v ON_ERROR_STOP=0 -d postgresql:\/\/supabase_admin:postgres@127\.0\.0\.1:54322\/bsb_diff_/,
    );
    expect(sent).toContain('drop schema "app" cascade');
    expect(sent.some((text) => text.startsWith("do $$"))).toBe(true);
    expect(sent).toContain('drop policy "Owner reads" on "storage"."objects"');
    expect(sent).not.toContain('drop schema "storage" cascade');
    expect(sent.indexOf("set role postgres")).toBeLessThan(
      sent.indexOf("create schema app;"),
    );
    expect(sent).toContain("create table app.b ();");
    expect(diffs[0]).toEqual(
      expect.arrayContaining(["--use-pg-delta", "--from", "local"]),
    );
    expect(sent.at(-1)).toMatch(
      /^drop database if exists "bsb_diff_.+" with \(force\)$/,
    );
    expect(open.closed()).toBe(2);
  });

  it("retries a file that depends on a later one", async () => {
    let schemaCreated = false;
    const { open, run } = harness();
    const base = await open.connect(STACK_URL);

    const client: PgQueryable = {
      query: <R>(text: string, values?: readonly unknown[]) => {
        if (text === "create schema app;") {
          schemaCreated = true;
        }

        if (text === "create table app.b ();" && !schemaCreated) {
          return Promise.reject(new Error('schema "app" does not exist'));
        }

        return base.client.query<R>(text, values);
      },
    };

    const reopened = fakeConnect(client);

    await expect(
      inStackDiff({
        url: STACK_URL,
        root,
        env: { BSB_PG_BIN: "/pg/bin" },
        files: ["supabase/schemas/app/b.sql", "supabase/schemas/app/a.sql"],
        schemasDir: "supabase/schemas",
        migrations: [],
        open: reopened.connect,
        run,
        supabase: () =>
          Promise.resolve({ code: 0, stdout: '{"diff":""}', stderr: "" }),
      }),
    ).resolves.toBe("");
  });

  it("drops the temporary database when a file never applies", async () => {
    const { sent, open, run } = harness({ badFile: "create table app.b ();" });

    await expect(
      inStackDiff({
        url: STACK_URL,
        root,
        env: { BSB_PG_BIN: "/pg/bin" },
        files,
        schemasDir: "supabase/schemas",
        migrations: [],
        open: open.connect,
        run,
        supabase: () => Promise.resolve({ code: 0, stdout: "", stderr: "" }),
      }),
    ).rejects.toThrow(
      /1 schema file\(s\) did not apply\. supabase\/schemas\/app\/b\.sql: relation does not exist/,
    );
    expect(sent.at(-1)).toMatch(
      /^drop database if exists "bsb_diff_.+" with \(force\)$/,
    );
  });

  it("refuses to diff a stack that lags behind the migrations", async () => {
    const { sent, open, run } = harness({ applied: [] });

    await expect(
      inStackDiff({
        url: STACK_URL,
        root,
        env: {},
        files,
        schemasDir: "supabase/schemas",
        migrations: ["supabase/migrations/20260101000000_init.sql"],
        open: open.connect,
        run,
      }),
    ).rejects.toThrow(
      /has not applied 1 migration\(s\) \(supabase\/migrations\/20260101000000_init\.sql\)/,
    );
    expect(sent.some((text) => text.startsWith("create database"))).toBe(false);
  });

  const exitWith =
    (code: number, failing: string, stderr = "") =>
    (command: string): Promise<ExecResult> =>
      Promise.resolve({
        code: command.endsWith(failing) ? code : 0,
        stdout: "",
        stderr: command.endsWith(failing) ? stderr : "",
      });

  const failingDiff = (
    run: (command: string) => Promise<ExecResult>,
    open: ReturnType<typeof fakeConnect>,
  ): Promise<string> =>
    inStackDiff({
      url: STACK_URL,
      root,
      env: { BSB_PG_BIN: "/pg/bin" },
      files,
      schemasDir: "supabase/schemas",
      migrations: [],
      open: open.connect,
      run,
      supabase: () => Promise.resolve({ code: 0, stdout: "", stderr: "" }),
    });

  it("asks for BSB_PG_BIN when pg_dump is missing", async () => {
    const { sent, open } = harness();

    await expect(
      failingDiff(exitWith(127, "pg_dump"), open),
    ).rejects.toMatchObject({
      code: "dependency_missing",
      message: expect.stringContaining("needs pg_dump and psql"),
    });
    expect(sent.some((text) => text.startsWith("create database"))).toBe(false);
  });

  it("reports a pg_dump that fails", async () => {
    const { open } = harness();

    await expect(
      failingDiff(exitWith(1, "pg_dump", "permission denied\n"), open),
    ).rejects.toMatchObject({
      code: "failed",
      message: "pg_dump failed: permission denied",
    });
  });

  it("asks for BSB_PG_BIN when psql is missing and drops the copy", async () => {
    const { sent, open } = harness();

    await expect(
      failingDiff(exitWith(127, "psql"), open),
    ).rejects.toMatchObject({
      code: "dependency_missing",
      message: expect.stringContaining("psql"),
    });
    expect(sent.at(-1)).toMatch(/^drop database if exists "bsb_diff_/);
  });

  it("reports a failed supabase db diff with its output", async () => {
    const { open, run } = harness();

    await expect(
      inStackDiff({
        url: `${STACK_URL}?application_name=bsb`,
        root,
        env: {},
        files,
        schemasDir: "supabase/schemas",
        migrations: [],
        open: open.connect,
        run,
        supabase: (args) => {
          expect(args.find((arg) => arg.includes("bsb_diff_"))).toMatch(
            /\?application_name=bsb&sslmode=disable$/,
          );

          return Promise.resolve({
            code: 1,
            stdout: "connection refused\n",
            stderr: "",
          });
        },
      }),
    ).rejects.toMatchObject({
      code: "supabase_cli_failed",
      message: "supabase db diff failed: connection refused",
    });
  });

  it("names the first three lagging migrations and treats a missing table as none applied", async () => {
    const { open, run } = harness();
    const base = await open.connect(STACK_URL);

    const migrations = [1, 2, 3, 4].map(
      (day) => `supabase/migrations/2026010${String(day)}000000_m.sql`,
    );

    const client: PgQueryable = {
      query: <R>(text: string, values?: readonly unknown[]) =>
        text.includes("schema_migrations")
          ? Promise.reject(new Error("relation does not exist"))
          : base.client.query<R>(text, values),
    };

    await expect(
      inStackDiff({
        url: STACK_URL,
        root,
        env: {},
        files,
        schemasDir: "supabase/schemas",
        migrations,
        open: fakeConnect(client).connect,
        run,
      }),
    ).rejects.toThrow(
      /has not applied 4 migration\(s\) \(.+20260101000000_m\.sql, .+20260102000000_m\.sql, .+20260103000000_m\.sql, \.\.\.\)/,
    );
  });

  it("runs pg_dump from the PATH when the data directory is unknown", async () => {
    const { open } = harness();
    const base = await open.connect(STACK_URL);
    const commands: string[] = [];

    const client: PgQueryable = {
      query: <R>(text: string, values?: readonly unknown[]) =>
        text === "show data_directory"
          ? Promise.resolve({ rows: [] as R[] })
          : base.client.query<R>(text, values),
    };

    await inStackDiff({
      url: STACK_URL,
      root,
      env: { BSB_PG_BIN: "" },
      files,
      schemasDir: "supabase/schemas",
      migrations: [],
      open: fakeConnect(client).connect,
      run: (command) => {
        commands.push(command);

        return Promise.resolve({ code: 0, stdout: "", stderr: "" });
      },
      supabase: () =>
        Promise.resolve({ code: 0, stdout: "select 1;", stderr: "" }),
    });

    expect(commands).toEqual(["ps", "pg_dump", "psql"]);
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
