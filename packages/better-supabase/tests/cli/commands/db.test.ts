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
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { DbDiffDeps } from "../../../src/cli/commands/db.ts";
import type {
  InStackDiffOptions,
  InStackDiffResult,
} from "../../../src/cli/in-stack-diff.ts";

import {
  dbDiffCommand,
  dbQueryCommand,
  runDbDiff,
  runDbQuery,
} from "../../../src/cli/commands/db.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { run } from "../../../src/cli/core/run.ts";
import { MIGRATION_HEADER } from "../../../src/cli/in-stack-diff.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { gatePlan } from "../../../src/create/plan-gate.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

describe("db query", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-db-"));
    await writeFile(join(root, "a.sql"), "select 1; select 2;");
    await writeFile(join(root, "b.sql"), "select 3;");
  });

  afterEach(async () => {
    vi.useRealTimers();
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

  const remote = {
    DATABASE_URL:
      "postgresql://postgres:secret@db.example.supabase.co:5432/postgres",
  };

  const SHADOW =
    "failed to start shadow database: could not create shared memory segment: No space left on device";

  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-21T08:00:00Z"));
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
    plan: Partial<InStackDiffResult> = {},
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

          return Promise.resolve({
            sql,
            gate: gatePlan({ actions: [], renameCandidates: [] }),
            issues: [],
            diagnostics: [],
            skipped: [],
            ...plan,
          });
        },
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
      resolveConfig({ database: { sql: { workflow } } }, root),
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
      env: { ...remote, SUPABASE_BIN: bin },
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

    const result = await diff(["-f", "add"], harness, "pg-delta", remote);

    expect(harness.calls).toEqual([
      ["db", "schema", "declarative", "sync", "--no-apply", "-f", "add"],
    ]);
    expect(harness.inStack).toHaveLength(0);
    expect(result.output).toBe("Created supabase/migrations/1_add.sql");
  });

  it("falls back to the running stack when the shadow database can't start", async () => {
    const harness = deps({ code: 1, stderr: SHADOW });
    const result = await diff(["-f", "add"], harness, "migra");
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

    const result = await diff(["-f", "add"], harness, "pg-delta", remote);

    expect(result.code).toBe(1);
    expect(result.errorCode).toBe("supabase_cli_failed");
    expect(harness.inStack).toHaveLength(0);
  });

  it("plans a local pg-delta project with the library, not the Supabase CLI", async () => {
    const harness = deps({ code: 0 });
    const result = await diff([], harness);

    expect(harness.calls).toHaveLength(0);
    expect(harness.inStack[0]?.allowDataLoss).toBe(false);
    expect(result.output).toBe("create table a ();");
    expect(result.data).toMatchObject({ engine: "in-stack", fellBack: false });
  });

  it("passes the renames recorded in the migrations to the plan", async () => {
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/20260101000000_init.sql"),
      "-- bsb: rename old -> fresh\nalter table old rename to fresh;\n",
    );

    const harness = deps({ code: 0 });

    await diff([], harness);

    expect(harness.inStack[0]?.hints).toEqual([{ from: "old", to: "fresh" }]);
  });

  it("stops on data loss and writes nothing, then writes with --allow-data-loss", async () => {
    const gate = gatePlan({
      actions: [
        { sql: "drop table b;", verb: "drop", dataLoss: "destructive" },
      ],
      renameCandidates: [],
    });

    const blocked = deps({ code: 0 }, "", { gate, issues: gate.issues });
    const result = await diff(["-f", "drop"], blocked);

    expect(result.code).toBe(1);
    expect(result.errorCode).toBe("check_failed");
    expect(result.error).toContain("drop table b;");
    expect(result.error).toContain("--allow-data-loss");

    const allowed = deps({ code: 0 }, "drop table b;");
    const written = await diff(["--allow-data-loss"], allowed);

    expect(allowed.inStack[0]?.allowDataLoss).toBe(true);
    expect(written.code).toBe(0);
  });

  it("logs the plan's rename questions", async () => {
    const gate = gatePlan({
      actions: [],
      renameCandidates: [
        {
          kind: "table",
          from: "table:public.old",
          to: "table:public.fresh",
          status: "unambiguous",
        },
      ],
    });

    const harness = deps({ code: 0 }, "create table a ();", {
      gate,
      issues: gate.issues,
    });

    await diff([], harness);

    expect(harness.lines.join("\n")).toContain("Is table:public.old renamed");
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

  it("falls back to the library with the default dependencies", async () => {
    const bin = join(root, "fake-supabase");

    await writeFile(bin, `#!/bin/sh\necho "${SHADOW}" >&2\nexit 1\n`);
    await chmod(bin, 0o755);

    const result = await run(["db", "diff", "--cwd", root], {
      env: { ...remote, SUPABASE_BIN: bin },
      io: { stdout: () => {}, stderr: () => {} },
    });

    expect(result.code).not.toBe(0);
  });

  it("uses the Supabase CLI when no database URL resolves, and fails for --in-stack", async () => {
    const harness = deps({ code: 0, stdout: "synced" });
    const none = { SUPABASE_BIN: "x" };

    const config = resolveConfig(
      { database: { sql: { workflow: "pg-delta" } } },
      root,
    );

    const ok = await runDbDiff(
      config,
      parseCommandArgs(dbDiffCommand, ["-f", "add"]),
      none,
      harness.deps,
    );

    expect(ok.output).toBe("synced");
    await expect(
      runDbDiff(
        config,
        parseCommandArgs(dbDiffCommand, ["--in-stack"]),
        none,
        harness.deps,
      ),
    ).rejects.toThrow(/No database to connect to/);
  });

  it("rejects the migrations workflow, a bad name and a remote database", async () => {
    await expect(diff([], deps({ code: 0 }), "migrations")).rejects.toThrow(
      /writes migrations directly/,
    );
    await expect(diff(["-f", "../x"], deps({ code: 0 }))).rejects.toThrow(
      /must be letters/,
    );
    await expect(
      diff(["--in-stack"], deps({ code: 0 }), "pg-delta", remote),
    ).rejects.toThrow(/works on a local stack/);
  });
});
