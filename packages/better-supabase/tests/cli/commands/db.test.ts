import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  type DbDiffDeps,
  dbDiffCommand,
  dbQueryCommand,
  runDbDiff,
  runDbQuery,
} from "../../../src/cli/commands/db.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { run } from "../../../src/cli/core/run.ts";
import {
  type InStackDiffOptions,
  MIGRATION_HEADER,
} from "../../../src/cli/in-stack-diff.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

describe("db query", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-db-"));
    await writeFile(join(root, "a.sql"), "select 1; select 2;");
    await writeFile(join(root, "b.sql"), "select 3;");
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function run(
    argv: string[],
    fail?: string,
  ): { done: ReturnType<typeof runDbQuery>; sent: string[] } {
    const sent: string[] = [];

    const open = fakeConnect({
      query: (text: string) => {
        sent.push(text);

        return text === fail
          ? Promise.reject(new Error("boom"))
          : Promise.resolve({ rows: [] });
      },
    });

    const done = runDbQuery(
      resolveConfig({}, root),
      parseCommandArgs(dbQueryCommand, argv),
      { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" },
      open.connect,
    );

    return { done, sent };
  }

  it("runs each file as one script, in order", async () => {
    const { done, sent } = run(["a.sql", "b.sql"]);
    const result = await done;

    expect(sent).toEqual(["select 1; select 2;", "select 3;"]);
    expect(result.code).toBe(0);
  });

  it("wraps the files in one transaction when asked", async () => {
    const { done, sent } = run(["--single-transaction", "a.sql", "b.sql"]);
    await done;

    expect(sent).toEqual([
      "begin",
      "select 1; select 2;",
      "select 3;",
      "commit",
    ]);
  });

  it("rolls back and names the failing file", async () => {
    const { done, sent } = run(
      ["--single-transaction", "a.sql", "b.sql"],
      "select 3;",
    );

    const result = await done;

    expect(sent.at(-1)).toBe("rollback");
    expect(result).toMatchObject({ code: 1, data: { failed: "b.sql" } });
  });

  it("reports an unreadable file", async () => {
    await expect(run(["missing.sql"]).done).rejects.toThrow("Could not read");
  });

  it("asks for consent on a remote database", async () => {
    const requests: string[] = [];
    const open = fakeConnect({ query: () => Promise.resolve({ rows: [] }) });

    const result = await runDbQuery(
      resolveConfig({}, root),
      parseCommandArgs(dbQueryCommand, ["a.sql"]),
      {},
      open.connect,
      "postgresql://postgres@db.example.com:5432/postgres",
      (request) => {
        requests.push(request.effect);
      },
    );

    expect(result.code).toBe(0);
    expect(requests).toEqual(["database-write"]);
  });
});

describe("db diff", () => {
  let root: string;

  const env = {
    DATABASE_URL: "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  };

  const SHADOW =
    "failed to start shadow database: could not create shared memory segment: No space left on device";

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-db-diff-"));
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(join(root, "supabase/schemas/a.sql"), "create table a ();");
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function deps(
    cli: { code: number; stdout?: string; stderr?: string },
    sql = "create table a ();",
  ): {
    deps: DbDiffDeps;
    calls: string[][];
    inStack: InStackDiffOptions[];
    lines: string[];
  } {
    const calls: string[][] = [];
    const inStack: InStackDiffOptions[] = [];
    const lines: string[] = [];

    return {
      calls,
      inStack,
      lines,
      deps: {
        supabase: (args) => {
          calls.push([...args]);

          return Promise.resolve({ stdout: "", stderr: "", ...cli });
        },
        inStackDiff: (options) => {
          inStack.push(options);

          return Promise.resolve(sql);
        },
        now: () => new Date("2026-10-21T08:00:00Z"),
        log: (line) => lines.push(line),
      },
    };
  }

  const diff = (
    argv: string[],
    harness: ReturnType<typeof deps>,
    workflow: "pg-delta" | "migra" | "migrations" = "pg-delta",
    url = env,
  ): ReturnType<typeof runDbDiff> =>
    runDbDiff(
      resolveConfig({ sql: { workflow } }, root),
      parseCommandArgs(dbDiffCommand, argv),
      url,
      harness.deps,
    );

  it("runs the Supabase CLI from $SUPABASE_BIN through the command tree", async () => {
    const bin = join(root, "fake-supabase");

    await writeFile(
      bin,
      '#!/bin/sh\necho "$@" > "$(dirname "$0")/args"\necho "Created a migration"\n',
    );
    await chmod(bin, 0o755);

    const result = await run(["db", "diff", "-f", "add", "--cwd", root], {
      env: { ...env, SUPABASE_BIN: bin },
      io: { stdout: () => {}, stderr: () => {} },
    });

    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Created a migration");
    expect(await readFile(join(root, "args"), "utf-8")).toBe(
      "db schema declarative sync --no-apply -f add\n",
    );
  });

  it("runs the Supabase CLI's sync when it can start a shadow database", async () => {
    const harness = deps({
      code: 0,
      stdout: "Created supabase/migrations/1_add.sql",
    });

    const result = await diff(["-f", "add"], harness);

    expect(harness.calls).toEqual([
      ["db", "schema", "declarative", "sync", "--no-apply", "-f", "add"],
    ]);
    expect(harness.inStack).toHaveLength(0);
    expect(result.output).toBe("Created supabase/migrations/1_add.sql");
  });

  it("falls back to the running stack when the shadow database can't start", async () => {
    const harness = deps({ code: 1, stderr: SHADOW });
    const result = await diff(["-f", "add"], harness);
    const path = "supabase/migrations/20261021080000_add.sql";

    expect(harness.inStack[0]?.files).toEqual(["supabase/schemas/a.sql"]);
    expect(harness.lines[0]).toMatch(/could not start its shadow database/);
    expect(result.data).toMatchObject({
      engine: "in-stack",
      fellBack: true,
      file: path,
    });
    expect(await readFile(join(root, path), "utf-8")).toBe(
      `${MIGRATION_HEADER}\ncreate table a ();\n`,
    );
  });

  it("reports other CLI failures instead of falling back", async () => {
    const harness = deps({
      code: 1,
      stderr: 'ERROR: syntax error at or near "tabel"',
    });

    const result = await diff(["-f", "add"], harness);

    expect(result.code).toBe(1);
    expect(result.errorCode).toBe("supabase_cli_failed");
    expect(harness.inStack).toHaveLength(0);
  });

  it("prints a pg-delta diff from the stack, since sync always writes a file", async () => {
    const harness = deps({ code: 0 });
    const result = await diff([], harness);

    expect(harness.calls).toHaveLength(0);
    expect(result.output).toBe("create table a ();");
  });

  it("prints the migra diff with the Supabase CLI", async () => {
    const harness = deps({ code: 0, stdout: "create table a ();\n" });
    const result = await diff([], harness, "migra");

    expect(harness.calls).toEqual([["db", "diff"]]);
    expect(result.output).toBe("create table a ();");
  });

  it("writes a named migra diff and says so when it prints nothing", async () => {
    const harness = deps({ code: 0 });
    const result = await diff(["-f", "add"], harness, "migra");

    expect(harness.calls).toEqual([["db", "diff", "-f", "add"]]);
    expect(result.output).toBe("No schema changes.");
  });

  it("says so when nothing changed", async () => {
    const result = await diff(["--in-stack"], deps({ code: 0 }, ""));

    expect(result.output).toBe("No schema changes.");
  });

  it("rejects the migrations workflow, a bad name and a remote database", async () => {
    await expect(diff([], deps({ code: 0 }), "migrations")).rejects.toThrow(
      /writes migrations directly/,
    );
    await expect(diff(["-f", "../x"], deps({ code: 0 }))).rejects.toThrow(
      /must be letters/,
    );
    await expect(
      diff(["--in-stack"], deps({ code: 0 }), "pg-delta", {
        DATABASE_URL:
          "postgresql://postgres:secret@db.example.supabase.co:5432/postgres",
      }),
    ).rejects.toThrow(/works on a local stack/);
  });
});
