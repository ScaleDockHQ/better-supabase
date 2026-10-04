import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { parseCommandArgs } from "../../src/cli/command.ts";
import {
  runSql,
  sqlCommand,
  type SqlArgs,
} from "../../src/cli/commands/sql.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { SQL_MODULES } from "../../src/sql/kit.ts";

const SUPABASE = resolve(
  import.meta.dirname,
  "../../../../node_modules/.bin/supabase",
);
const DB_PORT = 56422;
// read-sets and vector-search render nothing without app config; pgtap is a test file.
const NAMES = Object.keys(SQL_MODULES).filter(
  (name) => !["pgtap", "read-sets", "vector-search"].includes(name),
);

const available =
  existsSync(SUPABASE) &&
  spawnSync("docker", ["info"], { stdio: "ignore" }).status === 0;

const supabase = (cwd: string, args: string[]) => {
  const run = spawnSync(SUPABASE, args, { cwd, encoding: "utf8" });
  if (run.status !== 0)
    throw new Error(`supabase ${args.join(" ")}:\n${run.stdout}${run.stderr}`);
  return run.stdout;
};

describe.skipIf(!available)(
  "SQL kit through pg-delta's declarative sync",
  () => {
    let root = "";

    const sql = (argv: string[]) =>
      runSql(
        resolveConfig({ sql: { kit: NAMES } }, root),
        // SAFETY: parseCommandArgs returns the declared args of sqlCommand.
        parseCommandArgs(sqlCommand, argv) as SqlArgs,
      );

    beforeAll(async () => {
      root = await mkdtemp(join(tmpdir(), "bs-pgdelta-"));
      await mkdir(join(root, "supabase/migrations"), { recursive: true });
      await writeFile(
        join(root, "supabase/config.toml"),
        `project_id = "bs-pgdelta-roundtrip"
[api]
port = 56421
[db]
port = ${String(DB_PORT)}
shadow_port = 56420
major_version = 17
[experimental.pgdelta]
enabled = true
declarative_schema_path = "./schemas"
`,
      );
    });

    afterAll(async () => {
      if (root === "") return;
      spawnSync(SUPABASE, ["stop", "--no-backup"], {
        cwd: root,
        stdio: "ignore",
      });
      await rm(root, { recursive: true, force: true });
    });

    it("plans every module and ships the rows in the data migration", async () => {
      expect((await sql(["sync"])).output).toContain(
        "run `better-supabase sql data`",
      );
      supabase(root, [
        "db",
        "schema",
        "declarative",
        "sync",
        "--no-apply",
        "--strict-coverage",
        "-f",
        "kit",
      ]);
      expect((await sql(["data"])).output).toMatch(
        /^Wrote supabase\/migrations\/\d{14}_better_supabase_kit_data\.sql$/,
      );

      const migrations = (
        await readdir(join(root, "supabase/migrations"))
      ).toSorted();
      expect(migrations).toHaveLength(2);
      expect(migrations[1]).toMatch(/_better_supabase_kit_data\.sql$/);
      const schema = await readFile(
        join(root, "supabase/migrations", migrations[0]!),
        "utf8",
      );
      expect(schema).not.toMatch(/^insert into/im);

      supabase(root, ["db", "start"]);
      const client = new Client({
        connectionString: `postgresql://postgres:postgres@127.0.0.1:${String(DB_PORT)}/postgres`,
      });
      await client.connect();
      try {
        const { rows: modules } = await client.query<{ name: string }>(
          "select name from better_supabase.kit_modules order by name",
        );
        expect(modules.map((row) => row.name)).toEqual(NAMES.toSorted());
        const { rows: slugs } = await client.query<{ n: number }>(
          "select count(*)::int as n from better_supabase.reserved_slugs",
        );
        expect(slugs[0]!.n).toBeGreaterThan(0);
        const { rows: settings } = await client.query<{ setconfig: string[] }>(
          "select s.setconfig from pg_catalog.pg_db_role_setting s join pg_catalog.pg_roles r on r.oid = s.setrole where r.rolname = 'authenticator'",
        );
        expect(settings.flatMap((row) => row.setconfig)).toContain(
          "pgrst.db_pre_request=better_supabase.check_request",
        );
        const { rows: triggers } = await client.query<{ tgname: string }>(
          "select tgname from pg_catalog.pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal order by 1",
        );
        expect(triggers.map((row) => row.tgname)).toEqual([
          "bs_profile_email",
          "bs_profile_sync",
        ]);
      } finally {
        await client.end();
      }
    }, 300_000);
  },
);
