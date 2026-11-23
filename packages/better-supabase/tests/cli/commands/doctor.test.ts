import { parseArgs } from "citty";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { DoctorValues } from "../../../src/cli/commands/doctor.ts";
import type { CliIo, CommandResult } from "../../../src/cli/core/io.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { doctorCommand, runDoctor } from "../../../src/cli/commands/doctor.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { runSql } from "../../../src/cli/commands/sql.ts";
import {
  completionValues,
  parseCommandArgs,
} from "../../../src/cli/core/command.ts";
import { run } from "../../../src/cli/core/run.ts";
import { serializeGenerator } from "../../../src/cli/introspect/typegen.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";
import { usageError } from "../fixtures/usage.ts";

interface Report {
  findings: { code: string; severity: string; message: string }[];
}

const TEMP_FILES = [
  "pg_stat_database",
  [{ temp_files: 3, temp_bytes: 3 * 1024 * 1024, work_mem: "4MB" }],
] as const;

describe("doctor command", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-doctor-cmd-"));
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await rm(root, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }

  const doctor = (
    argv: string[],
    options: Parameters<typeof runDoctor>[3] = {},
    config: BetterSupabaseConfig = {},
    env: Record<string, string> = {},
  ) =>
    runDoctor(
      resolveConfig(config, root),
      parseCommandArgs(doctorCommand, argv) as DoctorValues,
      env,
      options,
    );

  const findings = (result: CommandResult): Report["findings"] =>
    (result.data as Report).findings;

  // Without the TypeScript tier a receiver rule adds an info finding that
  // says it matched names only; these tests are about the other findings.
  const reported = (result: CommandResult): Report["findings"] =>
    findings(result).filter((finding) => finding.severity !== "info");

  it("rejects conflicting or malformed claims before reading anything", async () => {
    const user = "8a6f1c3e-2b4d-4e5f-9a7b-1c2d3e4f5a6b";
    expect(
      await usageError(() => doctor(["--as", user, "--claims", "{}"])),
    ).toBe("Pass --as or --claims, not both");
    expect(await usageError(() => doctor(["--as", "alice"]))).toBe(
      '--as takes a user id (uuid), got "alice"',
    );
    expect(await usageError(() => doctor(["--claims", "[1]"]))).toBe(
      "--claims takes a JSON object",
    );
    expect(await usageError(() => doctor(["--claims", "{nope"]))).toMatch(
      /^--claims is not valid JSON: /,
    );
  });

  it("rejects --claims without --explain instead of ignoring it", async () => {
    expect(
      await usageError(() => doctor(["--claims", '{"role":"authenticated"}'])),
    ).toBe(
      "--claims plans a query, so it needs --explain <table> or --explain-write <table>.",
    );
  });

  it("reads the snapshot and the live checks over one connection, then closes it", async () => {
    const db = fakeSql([TEMP_FILES]);
    const open = fakeConnect(db.pg);

    const result = await doctor(["--only", "BS208", "--json"], {
      connect: open.connect,
      dbUrl: "postgresql://u:pw@h/db",
    });

    expect(result.code).toBe(0);
    expect(findings(result)).toEqual([
      expect.objectContaining({
        code: "BS208",
        severity: "warning",
        message: expect.stringContaining(
          "3 temporary files (3.0 MB) since the statistics were reset; work_mem is 4MB.",
        ),
      }),
    ]);
    expect(open.urls).toEqual(["postgresql://u:pw@h/db"]);
    expect(open.closed()).toBe(1);
  });

  it("reads only, format and output from the doctor config", async () => {
    const config: BetterSupabaseConfig = {
      tooling: {
        doctor: { only: ["BS208"], format: "sarif", file: "doctor.sarif" },
      },
    };

    const options = () => ({
      connect: fakeConnect(fakeSql([TEMP_FILES]).pg).connect,
      dbUrl: "postgresql://u:pw@h/db",
    });

    const sarif = await doctor([], options(), config);
    expect(sarif.code).toBe(0);

    const written = JSON.parse(
      await readFile(join(root, "doctor.sarif"), "utf-8"),
    ) as { runs: { results: { ruleId: string }[] }[] };

    expect(written.runs[0]!.results.map((result) => result.ruleId)).toEqual([
      "BS208",
    ]);

    await rm(join(root, "doctor.sarif"));
    const json = await doctor(["--json"], options(), config);
    expect(findings(json).map((finding) => finding.code)).toEqual(["BS208"]);
    await expect(readFile(join(root, "doctor.sarif"), "utf-8")).rejects.toThrow(
      /ENOENT/,
    );
  });

  it("closes the shared connection when introspection fails", async () => {
    const open = fakeConnect({
      query: () => Promise.reject(new Error("permission denied")),
    });

    await expect(
      doctor(["--only", "BS208", "--json"], {
        connect: open.connect,
        dbUrl: "postgresql://u:pw@h/db",
      }),
    ).rejects.toThrow("permission denied");
    expect(open.closed()).toBe(1);
  });

  it("runs splinter over the database and reports a download it cannot verify", async () => {
    const api = fakeFetch(() => ({ text: "select 'tampered';" }));
    vi.stubGlobal("fetch", api.fetch);
    const db = fakeSql();
    const open = fakeConnect(db.pg);

    const result = await doctor(
      ["--only", "BS100,BS200", "--json"],
      { connect: open.connect },
      {},
      { DATABASE_URL: "postgresql://env/db" },
    );

    const reported = findings(result);
    expect(reported.map((finding) => finding.code)).toEqual(["BS100", "BS200"]);
    expect(reported[0]!.message).toMatch(
      /^The security advisor could not run \(database \(splinter\)\): /,
    );
    expect(api.calls).toHaveLength(1);
    expect(api.calls[0]!.url).toMatch(/\/splinter\.sql$/);
    expect(db.texts().some((text) => text.includes("tampered"))).toBe(false);
    expect(open.closed()).toBe(1);
  });

  it("reads a hosted project's advisors and statistics through the Management API", async () => {
    const api = fakeFetch((call) => {
      if (call.url.includes("/advisors/")) {
        return { body: { lints: [] } };
      }

      const query = JSON.parse(String(call.body)) as { query: string };

      return {
        body: query.query.includes("pg_stat_database") ? TEMP_FILES[1] : [],
      };
    });

    vi.stubGlobal("fetch", api.fetch);
    const open = fakeConnect(fakeSql().pg);

    const result = await doctor(
      ["--project-ref", "abc", "--only", "BS100,BS208", "--json"],
      { connect: open.connect },
      {},
      { SUPABASE_ACCESS_TOKEN: "sbp_test" },
    );

    expect(findings(result).map((finding) => finding.code)).toEqual(["BS208"]);
    expect(open.urls).toEqual([]);
    const urls = api.calls.map((call) => call.url);
    expect(urls).toContain(
      "https://api.supabase.com/v1/projects/abc/advisors/security",
    );
    expect(
      urls.every((url) =>
        url.startsWith("https://api.supabase.com/v1/projects/abc/"),
      ),
    ).toBe(true);
  });

  it("skips the advisors and live checks for a saved snapshot", async () => {
    await write("snapshot.json", JSON.stringify(fixture));

    const result = await doctor([
      "--snapshot",
      "snapshot.json",
      "--only",
      "BS100,BS208",
      "--json",
    ]);

    expect(findings(result)).toEqual([
      expect.objectContaining({
        code: "BS100",
        severity: "info",
        message:
          "Skipped the security advisor: reading the saved snapshot snapshot.json; set $DATABASE_URL or $SUPABASE_DB_URL, or pass --db-url-stdin or --project-ref, to check a database.",
      }),
    ]);
  });

  it("prints only the hook grant SQL with --fix-grants", async () => {
    expect(
      await doctor(["--fix-grants"], {
        snapshot: await parseSnapshot(fixture),
      }),
    ).toEqual({
      code: 0,
      output: "-- Every configured Auth hook function has its grants.",
    });
  });

  it("runs the fixes with --yes after consent, and drops the fixed findings", async () => {
    const ran: string[] = [];

    const database = {
      describe: "test",
      session: true,
      query: async (sql: string) => {
        ran.push(sql);

        if (sql.includes("pg_constraint")) {
          return [
            {
              schema: "public",
              table: "invoices",
              name: "invoices_currency_not_null",
              expression: "(currency IS NOT NULL)",
            },
          ];
        }

        return sql.startsWith("select exists") ? [{ failing: false }] : [];
      },
    };

    const requireConsent = vi.fn();
    const log = vi.fn();
    const snapshot = await parseSnapshot(fixture);

    const result = await doctor(
      ["--only", "BS236", "--yes", "--json"],
      // SAFETY: the fake returns the rows BS236 asks for.
      { snapshot, database, requireConsent, log } as Parameters<
        typeof runDoctor
      >[3],
      {},
      { DATABASE_URL: "postgres://u:p@db.example.com:5432/postgres" },
    );

    expect(ran).toContain(
      'begin; set local statement_timeout = 0; alter table "public"."invoices" validate constraint "invoices_currency_not_null"; commit;',
    );
    expect(log).toHaveBeenCalledWith(
      "Fixed BS236 public.invoices:invoices_currency_not_null.",
    );
    expect(findings(result)).toEqual([]);

    const local = await doctor(
      ["--only", "BS236", "--yes", "--json"],
      // SAFETY: as above, with a fix that fails.
      {
        snapshot,
        requireConsent,
        database: {
          ...database,
          query: async (sql: string) => {
            if (sql.startsWith("begin;")) {
              throw new Error("check constraint is violated by some row");
            }

            return database.query(sql);
          },
        },
      } as Parameters<typeof runDoctor>[3],
      {},
      { DATABASE_URL: "postgres://postgres:postgres@127.0.0.1:54322/postgres" },
    );

    expect(requireConsent).toHaveBeenCalledExactlyOnceWith({
      effect: "database-write",
      detail: "doctor --yes runs 1 fix(es) against db.example.com:5432",
    });
    expect(findings(local)).toEqual([
      expect.objectContaining({
        code: "BS236",
        message: expect.stringContaining(
          "doctor --yes failed: check constraint is violated by some row",
        ),
      }),
    ]);
    expect(ran.at(-1)).toBe("rollback");
  });

  it("asks no consent when nothing is fixable, and names the database without a URL", async () => {
    const snapshot = await parseSnapshot(fixture);
    const requireConsent = vi.fn();

    const constraints = [
      {
        schema: "public",
        table: "invoices",
        name: "invoices_currency_not_null",
        expression: "(currency IS NOT NULL)",
      },
    ];

    const clean = await doctor(
      ["--only", "BS236", "--yes", "--json"],
      // SAFETY: the fake answers BS236 with no not valid checks.
      {
        snapshot,
        requireConsent,
        database: { describe: "test", session: true, query: async () => [] },
      },
    );

    expect(findings(clean)).toEqual([]);
    expect(requireConsent).not.toHaveBeenCalled();

    const quiet = await doctor(
      ["--only", "BS236", "--yes", "--json"],
      // SAFETY: the fake returns BS236's rows and runs the fix; no log is passed.
      {
        snapshot,
        database: {
          describe: "test",
          session: true,
          query: async (sql: string) => {
            if (sql.includes("pg_constraint")) {
              return constraints;
            }

            return sql.startsWith("select exists") ? [{ failing: false }] : [];
          },
        },
      } as Parameters<typeof runDoctor>[3],
      {},
      { DATABASE_URL: "postgres://postgres:postgres@127.0.0.1:54322/postgres" },
    );

    expect(findings(quiet)).toEqual([]);

    const failed = await doctor(
      ["--only", "BS236", "--yes", "--json"],
      // SAFETY: the fake returns BS236's rows, then fails the fix and its rollback.
      {
        snapshot,
        requireConsent,
        database: {
          describe: "test",
          session: true,
          query: async (sql: string) => {
            if (sql.startsWith("begin;") || sql === "rollback") {
              throw new Error("connection lost");
            }

            if (sql.includes("pg_constraint")) {
              return constraints;
            }

            return sql.startsWith("select exists") ? [{ failing: false }] : [];
          },
        },
      } as Parameters<typeof runDoctor>[3],
    );

    expect(requireConsent).toHaveBeenCalledExactlyOnceWith({
      effect: "database-write",
      detail: "doctor --yes runs 1 fix(es) against the database",
    });
    expect(findings(failed)).toEqual([
      expect.objectContaining({
        code: "BS236",
        message: expect.stringContaining(
          "doctor --yes failed: connection lost",
        ),
      }),
    ]);
  }, 60_000);

  it("writes a baseline, leaves out its findings and fails on a stale entry", async () => {
    const snapshot = await parseSnapshot({
      ...fixture,
      extras: { ...fixture.extras, roleSettings: {} },
    });

    const config = {
      tooling: { doctor: { baseline: "doctor-baseline.json" } },
    };

    await write("src/a.ts", "db.notes.list({ facetCounts: true });\n");

    expect(
      await usageError(() => doctor(["--update-baseline"], { snapshot })),
    ).toMatch(/^--update-baseline rewrites tooling\.doctor\.baseline/);

    await doctor(
      ["--only", "BS210", "--update-baseline"],
      { snapshot },
      config,
    );

    const written = JSON.parse(
      await readFile(join(root, "doctor-baseline.json"), "utf-8"),
    ) as { code: string; reason: string; target: string }[];

    expect(written.map((entry) => entry.code)).toEqual(["BS210"]);

    const unexplained = await doctor(
      ["--only", "BS210", "--json"],
      { snapshot },
      config,
    );

    expect(reported(unexplained)).toEqual([
      expect.objectContaining({
        code: "BS210",
        severity: "error",
        title: "A baseline entry has no reason",
      }),
    ]);

    await write(
      "doctor-baseline.json",
      JSON.stringify([
        {
          code: "BS210",
          reason: "facets are small here",
          targets: written.map((entry) => entry.target),
        },
      ]),
    );

    await doctor(["--only", "BS210", "--update"], { snapshot }, config);

    const regrouped = JSON.parse(
      await readFile(join(root, "doctor-baseline.json"), "utf-8"),
    ) as { reason: string; targets: string[] }[];

    expect(regrouped).toEqual([
      expect.objectContaining({ reason: "facets are small here" }),
    ]);

    const accepted = await doctor(
      ["--only", "BS210", "--json"],
      { snapshot },
      config,
    );

    expect(reported(accepted)).toEqual([]);
    expect(accepted.code).toBe(0);

    await rm(join(root, "src/a.ts"));

    const stale = await doctor(
      ["--only", "BS210", "--json"],
      { snapshot },
      config,
    );

    expect(reported(stale)).toEqual([
      expect.objectContaining({
        code: "BS210",
        severity: "error",
        message: expect.stringContaining("doctor --update-baseline"),
      }),
    ]);
    expect(stale.code).toBe(1);
  });

  it("reads a snapshot from the CLI's cache file", async () => {
    await write("cache.json", JSON.stringify({ key: "k", snapshot: fixture }));

    const result = await doctor([
      "--snapshot",
      "cache.json",
      "--only",
      "BS100",
      "--json",
    ]);

    expect(findings(result)).toEqual([
      expect.objectContaining({ code: "BS100", severity: "info" }),
    ]);
  });

  it("runs the source checks without a database", async () => {
    const open = fakeConnect({
      query: () => Promise.reject(new Error("connection refused")),
    });

    await write(
      "src/a.ts",
      "export const load = (db: Db, ids: string[]) =>\n  Promise.all(ids.map((id) => db.notes.get(id)));\n",
    );

    const result = await doctor(["--only", "BS634,BS635", "--json"], {
      connect: open.connect,
      dbUrl: "postgresql://u:pw@h/db",
    });

    expect(findings(result)).toEqual([
      expect.objectContaining({ code: "BS634", severity: "warning" }),
      expect.objectContaining({
        code: "BS635",
        severity: "info",
        message: expect.stringContaining(
          "Ran without the schema (connection refused)",
        ),
      }),
      expect.objectContaining({
        code: "BS634",
        severity: "info",
        message: expect.stringContaining("by receiver name only"),
      }),
    ]);

    await expect(
      doctor(["--only", "BS634,BS208", "--json"], {
        connect: open.connect,
        dbUrl: "postgresql://u:pw@h/db",
      }),
    ).rejects.toThrow("connection refused");
  });

  it("scans doctor.sources, skipping node_modules", async () => {
    const snapshot = await parseSnapshot({
      ...fixture,
      extras: { ...fixture.extras, roleSettings: {} },
    });

    await write("node_modules/dep/index.ts", "db.notes.aggregate({});\n");

    const clean = await doctor(["--only", "BS210", "--json"], { snapshot });

    expect(findings(clean)).toEqual([]);

    await write("src/z.ts", "\n\ndb.notes.aggregate({});\n");
    await write("src/a.ts", "db.notes.list({ facetCounts: true });\n");

    const result = await doctor(["--only", "BS210", "--json"], { snapshot });

    expect(reported(result)).toEqual([
      expect.objectContaining({
        code: "BS210",
        message: expect.stringMatching(/^src\/a\.ts uses aggregates/),
      }),
    ]);
  });

  it("skips the read-sets module file when config.readSets cannot load", async () => {
    const snapshot = await parseSnapshot(fixture);
    const config = { blocks: ["read-sets"] };

    const loaded = await doctor(
      ["--only", "BS304", "--json"],
      { snapshot },
      config,
    );

    expect(findings(loaded).map((finding) => finding.message)).toEqual([
      expect.stringContaining(
        "supabase/schemas/900_better_supabase_000_prelude.sql",
      ),
      expect.stringContaining(
        "supabase/schemas/900_better_supabase_014_read_sets.sql",
      ),
      expect.stringContaining(
        "supabase/better-supabase-data/900_better_supabase_014_read_sets.sql",
      ),
    ]);

    const skipped = await doctor(
      ["--only", "BS304", "--json"],
      { snapshot },
      { ...config, gen: { readSets: ["src/missing.ts"] } },
    );

    expect(findings(skipped)).toEqual([]);
  });

  it("finds no BS304 right after add renders a module under sql.api", async () => {
    const config: BetterSupabaseConfig = { database: { sql: { api: "api" } } };

    const added = await runSql(
      resolveConfig(config, root),
      parseArgs(["add", "rate-limit"], SQL_ARGS),
    );

    expect(added.code).toBe(0);
    const dir = join(root, "supabase/schemas");
    const files = await readdir(dir);

    const texts = await Promise.all(
      files.map((file) => readFile(join(dir, file), "utf-8")),
    );

    expect(texts.join("\n")).toContain('function "api"."set_rate_limit"');

    const result = await doctor(
      ["--only", "BS304", "--json"],
      { snapshot: await parseSnapshot(fixture) },
      { ...config, blocks: ["rate-limit", "housekeeping"] },
    );

    expect(findings(result)).toEqual([]);
  });

  it("reads the content mapper setup from the project for BS602", async () => {
    await write("tsconfig.json", JSON.stringify({ compilerOptions: {} }));
    await write(
      "package.json",
      JSON.stringify({ scripts: { typecheck: "tsc --noEmit" } }),
    );

    const result = await doctor(
      ["--only", "BS602", "--json"],
      { snapshot: await parseSnapshot(fixture) },
      { gen: { contentMapper: true } },
    );

    expect(findings(result)).toEqual([
      expect.objectContaining({ code: "BS602", target: "tsconfig.json" }),
      expect.objectContaining({ code: "BS602", target: "typescript" }),
      expect.objectContaining({ code: "BS602", target: "package.json" }),
    ]);
  });

  it("reads the installed release and the lockfile for BS607", async () => {
    await write(
      "node_modules/better-supabase/package.json",
      JSON.stringify({ name: "better-supabase", version: "0.33.0" }),
    );
    await write(
      "pnpm-lock.yaml",
      "packages:\n\n  better-supabase@0.34.0:\n    resolution: {}\n",
    );

    const result = await doctor(
      ["--only", "BS607", "--json"],
      { snapshot: await parseSnapshot(fixture) },
      {},
    );

    expect(findings(result)).toEqual([
      expect.objectContaining({ code: "BS607", target: "pnpm-lock.yaml" }),
    ]);
  });

  it("rejects --args without --explain, --args that is not JSON and --update-baseline without a baseline", async () => {
    expect(await usageError(() => doctor(["--args", "[]"]))).toBe(
      "--args passes arguments to a function, so it needs --explain <function>.",
    );
    expect(
      await usageError(() => doctor(["--explain", "notes", "--args", "{nope"])),
    ).toMatch(/^--args is not valid JSON: /);
    expect(await usageError(() => doctor(["--update-baseline"]))).toMatch(
      /^--update-baseline rewrites tooling\.doctor\.baseline/,
    );
  });

  it("reads the pulled Vercel env files with --vercel even when --only leaves them out", async () => {
    await write(".vercel/.env.development.local", "OTHER=1\n");

    const result = await doctor(["--only", "BS607", "--vercel", "--json"], {
      snapshot: await parseSnapshot(fixture),
    });

    expect(findings(result)).toContainEqual(
      expect.objectContaining({
        code: "BS513",
        message: expect.stringContaining("development"),
      }),
    );
  });

  it("keeps the unfixable findings of --yes and names the project it writes to", async () => {
    const requireConsent = vi.fn();
    const ran: string[] = [];

    const result = await doctor(
      [
        "--only",
        "BS100,BS236",
        "--yes",
        "--project-ref",
        "abcdefghijklmnopqrst",
        "--json",
      ],
      // SAFETY: the fake returns the rows BS236 asks for and records the fix.
      {
        snapshot: await parseSnapshot(fixture),
        advisors: { skipped: "offline" },
        requireConsent,
        database: {
          describe: "test",
          session: true,
          query: async (sql: string) => {
            ran.push(sql);

            if (sql.includes("pg_constraint")) {
              return [
                {
                  schema: "public",
                  table: "invoices",
                  name: "c",
                  expression: "(a IS NOT NULL)",
                },
              ];
            }

            return sql.startsWith("select exists") ? [{ failing: false }] : [];
          },
        },
      } as Parameters<typeof runDoctor>[3],
    );

    expect(requireConsent).toHaveBeenCalledExactlyOnceWith({
      effect: "database-write",
      detail:
        "doctor --yes runs 1 fix(es) against project abcdefghijklmnopqrst",
    });
    expect(ran.some((sql) => sql.includes('validate constraint "c"'))).toBe(
      true,
    );
    expect(findings(result).map((finding) => finding.code)).toEqual(["BS100"]);
  });

  it("rejects a baseline file that does not parse", async () => {
    await write("doctor-baseline.json", "{ nope");

    await expect(
      doctor(
        ["--only", "BS210"],
        { snapshot: await parseSnapshot(fixture) },
        { tooling: { doctor: { baseline: "doctor-baseline.json" } } },
      ),
    ).rejects.toMatchObject({ code: "invalid_input" });
  });

  it("fails on warnings in strict mode and rejects an unknown --fail-on", async () => {
    await write(
      "src/a.ts",
      "export const load = (db: Db, ids: string[]) =>\n  Promise.all(ids.map((id) => db.notes.get(id)));\n",
    );

    const snapshot = await parseSnapshot(fixture);
    const strict = { tooling: { doctor: { strict: true } } };

    expect(
      await doctor(["--only", "BS634"], { snapshot }, strict),
    ).toMatchObject({
      code: 1,
      errorCode: "findings",
      error: expect.stringContaining("(--fail-on warning)"),
    });
    expect(
      await doctor(
        ["--only", "BS634", "--fail-on", "never"],
        { snapshot },
        strict,
      ),
    ).toMatchObject({ code: 0 });
    expect(
      await usageError(() =>
        doctor(["--only", "BS634", "--fail-on", "info"], { snapshot }),
      ),
    ).toBe('--fail-on takes error, warning or never, got "info".');
  });

  it("still reports when the workspace file the dependency readers need cannot be read", async () => {
    await write("package.json", JSON.stringify({ dependencies: { pg: "8" } }));
    await mkdir(join(root, "pnpm-workspace.yaml"));

    const result = await doctor(
      ["--only", "BS100", "--json"],
      {
        snapshot: await parseSnapshot(fixture),
        advisors: { skipped: "offline" },
      },
      { tooling: { doctor: { sources: ["src/**/*.ts"] } } },
    );

    expect(result.code).toBe(0);
    expect(findings(result).map((finding) => finding.code)).toEqual(["BS100"]);
  });

  it("completes formats and rule codes, live ones included", () => {
    const completions = completionValues(doctorCommand);
    const codes = completions["only"]?.();

    expect(completions["format"]?.()).toEqual(["text", "sarif", "github"]);
    expect(codes).toEqual(expect.arrayContaining(["BS217", "BS209"]));
    expect(new Set(codes).size).toBe(codes?.length);
    expect(completions["ignore"]?.()).toEqual(codes);
  });
});

describe("doctor --metadata", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-doctor-meta-"));
    await writeFile(
      join(root, "better-supabase.config.ts"),
      "export default {};\n",
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const doctorMeta = async (args: readonly string[], stdin: string) => {
    const out: string[] = [];
    const err: string[] = [];

    const io: CliIo = {
      stdout: (text) => {
        out.push(text);
      },
      stderr: (text) => {
        err.push(text);
      },
      stdin: () => Promise.resolve(stdin),
    };

    const result = await run(
      ["doctor", "--metadata", "-", ...args, "--cwd", root],
      { io },
    );

    return { code: result.code, stdout: out.join(""), stderr: err.join("") };
  };

  it("checks a GeneratorMetadata document without a database", async () => {
    const document = await serializeGenerator(
      (await parseSnapshot(fixture)).generator,
    );

    const result = await doctorMeta(["--only", "BS208", "--json"], document);

    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      status: "success",
      data: { findings: [] },
    });
  });

  it("exits 65 for a document it rejects", async () => {
    const result = await doctorMeta([], "{ not json");

    expect(result.code).toBe(65);
    expect(result.stderr).toMatch(/is not JSON/);
  });

  it("names every database flag it refuses", async () => {
    const result = await doctorMeta(
      [
        "--explain",
        "notes",
        "--explain-write",
        "notes",
        "--args",
        "[]",
        "--as",
        "u",
        "--yes",
      ],
      "{}",
    );

    for (const flag of [
      "--explain",
      "--explain-write",
      "--args",
      "--as",
      "--yes",
    ]) {
      expect(result.stderr).toContain(flag);
    }
  });

  it("passes on an error that is not a rejected document", async () => {
    const err: string[] = [];

    const result = await run(["doctor", "--metadata", "-", "--cwd", root], {
      io: { stdout: () => {}, stderr: (text) => void err.push(text) },
    });

    expect(result.code).not.toBe(65);
    expect(err.join("")).toContain("nothing is piped in");
  });

  it("refuses flags that need a database", async () => {
    const result = await doctorMeta(["--stats"], "{}");

    expect(result.code).not.toBe(0);
    expect(result.stderr).toContain("--stats");
  });
});
