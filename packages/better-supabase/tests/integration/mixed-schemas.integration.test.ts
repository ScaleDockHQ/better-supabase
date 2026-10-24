import type { QueryResult, QueryResultRow } from "pg";

import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { DoctorArgs } from "../../src/cli/commands/doctor.ts";
import type { CommandResult } from "../../src/cli/core/io.ts";

import {
  dbBackfillCommand,
  runBackfill,
} from "../../src/cli/commands/backfill.ts";
import { doctorCommand, runDoctor } from "../../src/cli/commands/doctor.ts";
import { runUpgrade, upgradeCommand } from "../../src/cli/commands/upgrade.ts";
import { parseCommandArgs } from "../../src/cli/core/command.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { MIXED_SCHEMAS_CONFIG } from "../fixtures/mixed-schemas/config.ts";
import { stackDbUrl } from "./stack-env.ts";

const FIXTURE = join(import.meta.dirname, "../fixtures/mixed-schemas");
const SCHEMAS = "supabase/schemas";
const INVOICES = `${SCHEMAS}/900_better_supabase_098_invoices.sql`;

/** The app's files in dependency order, as pg-delta applies them. */
const APP_FILES = [
  "public/types/invoice_status.sql",
  "public/tables/organizations.sql",
  "public/tables/invoices.sql",
  "public/tables/contacts.sql",
  "public/tables/notes.sql",
];

const BLOCK_FILES = [
  "900_better_supabase_001_updated_at.sql",
  "900_better_supabase_004_memberships.sql",
  "900_better_supabase_019_permissions.sql",
  "900_better_supabase_021_organizations.sql",
  "900_better_supabase_065_subjects.sql",
  "900_better_supabase_080_ledger.sql",
  "900_better_supabase_093_contacts.sql",
  "900_better_supabase_098_invoices.sql",
  "900_better_supabase_app_tables.sql",
];

/** What the Supabase platform gives every database and a scratch one lacks. */
const PLATFORM = `
create schema if not exists auth;
create schema if not exists extensions;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;
create or replace function auth.role() returns text language sql stable as $$
  select auth.jwt() ->> 'role'
$$;
grant usage on schema auth, extensions to anon, authenticated, service_role;
`;

const ORG_A = "0a000000-0000-4000-8000-00000000000a";
const ORG_B = "0b000000-0000-4000-8000-00000000000b";
const USER_A = "1a000000-0000-4000-8000-00000000000a";
const USER_B = "1b000000-0000-4000-8000-00000000000b";

/** Rows the app had before it installed the blocks. */
const APP_ROWS = `
insert into public.organizations (id, name) values ('${ORG_A}', 'A'), ('${ORG_B}', 'B');
insert into public.invoices (organization_id, number, status, currency) values
  ('${ORG_A}', 'A-1', 'issued', 'EUR'), ('${ORG_B}', 'B-1', 'paid', 'EUR');
insert into public.contacts (organization_id, name, email) values
  ('${ORG_A}', 'Ann', 'ann@a.test'), ('${ORG_B}', 'Bob', 'bob@b.test');
insert into public.notes (body) values ('written before the blocks');
`;

const MEMBERS = `
insert into auth.users (id, email) values ('${USER_A}', 'a@a.test'), ('${USER_B}', 'b@b.test');
insert into better_supabase.memberships (organization_id, user_id, role) values
  ('${ORG_A}', '${USER_A}', 'owner'), ('${ORG_B}', '${USER_B}', 'owner');
`;

const withDatabase = (url: string, name: string): string => {
  const parsed = new URL(url);
  parsed.pathname = `/${name}`;

  return parsed.toString();
};

describe("blocks over an app's own declarative schema, on the local stack", () => {
  const name = `bsb_mixed_${String(process.pid)}_${Date.now().toString(36)}`;
  let root: string;
  let url: string;
  let db: Client;

  const config = () => resolveConfig(MIXED_SCHEMAS_CONFIG, root);

  const apply = async (file: string): Promise<void> => {
    await db.query(await readFile(join(root, SCHEMAS, file), "utf-8"));
  };

  /**
   * Runs `sql` as `user` through the API roles, in a transaction rolled back
   * after.
   */
  async function as<T extends QueryResultRow>(
    user: string,
    sql: string,
  ): Promise<T[]> {
    await db.query("begin");

    try {
      await db.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: user, role: "authenticated" }),
      ]);
      await db.query("set local role authenticated");

      return (await db.query<T>(sql)).rows;
    } finally {
      await db.query("rollback");
    }
  }

  const doctor = (argv: string[]): Promise<CommandResult> =>
    runDoctor(
      config(),
      parseCommandArgs(doctorCommand, argv) as DoctorArgs,
      {},
      { dbUrl: url },
    );

  /** The codes the text report lists, one finding per line. */
  const codes = (result: CommandResult): string[] =>
    [
      ...(result.output ?? "").matchAll(/^(?:error|warning|info) +(BS\d+) /gm),
    ].map((match) => match[1] ?? "");

  beforeAll(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-mixed-stack-"));
    await cp(join(FIXTURE, "supabase"), join(root, "supabase"), {
      recursive: true,
    });

    const installed = await runUpgrade(
      config(),
      parseCommandArgs(upgradeCommand, []),
    );

    if (installed.code !== 0) {
      throw new Error(`upgrade failed: ${installed.error ?? ""}`);
    }

    const admin = new Client({ connectionString: stackDbUrl() });
    await admin.connect();
    await admin.query(`create database ${name}`);
    await admin.end();

    url = withDatabase(stackDbUrl(), name);
    db = new Client({ connectionString: url });
    await db.connect();

    await db.query(PLATFORM);

    for (const file of APP_FILES) {
      await apply(file);
    }

    await db.query(APP_ROWS);

    for (const file of BLOCK_FILES) {
      await apply(file);
    }

    await db.query(MEMBERS);
  }, 120_000);

  afterAll(async () => {
    await db.end();

    const admin = new Client({ connectionString: stackDbUrl() });
    await admin.connect();
    await admin.query(`drop database if exists ${name} with (force)`);
    await admin.end();

    await rm(root, { recursive: true, force: true });
  });

  it("passes the pgTAP file that proves the scope can't cross organizations", async () => {
    const script = await readFile(
      join(root, "supabase/tests/database/tenant_scope.test.sql"),
      "utf-8",
    );

    // SAFETY: pg returns one result per statement for a multi-statement query.
    const results = (await db.query(script).catch(async (cause: unknown) => {
      await db.query("rollback");
      throw cause;
    })) as unknown as QueryResult[];

    const lines = results.flatMap((result) =>
      result.rows.flatMap((row: Record<string, unknown>) =>
        Object.values(row).map(String),
      ),
    );

    expect(lines).toContain("1..13");
    expect(lines.filter((line) => line.startsWith("not ok"))).toEqual([]);
    expect(lines.filter((line) => line.startsWith("ok"))).toHaveLength(13);
  });

  it("refuses to overwrite a block file edited by hand until --force", async () => {
    const original = await readFile(join(root, INVOICES), "utf-8");
    await writeFile(join(root, INVOICES), `${original}\n-- mine\n`);

    const blocked = await runUpgrade(
      config(),
      parseCommandArgs(upgradeCommand, []),
    );

    expect(blocked.code).toBe(1);
    expect(blocked.error).toContain("was edited by hand");

    expect(
      (
        await runUpgrade(
          config(),
          parseCommandArgs(upgradeCommand, ["--force"]),
        )
      ).code,
    ).toBe(0);
    expect(await readFile(join(root, INVOICES), "utf-8")).toBe(original);
  });

  it("backfills the owner, then doctor --fix validates the check", async () => {
    expect(codes(await doctor(["--only", "BS236,BS238"]))).toEqual(["BS238"]);

    await expect(
      db.query(
        "update public.notes set body = body || '.' where organization_id is null",
      ),
    ).rejects.toThrow(/notes_organization_id_not_null/);

    const filled = await runBackfill(
      config(),
      parseCommandArgs(dbBackfillCommand, [
        "notes.organization_id",
        "--value",
        `'${ORG_A}'::uuid`,
      ]),
      {},
      {},
      url,
    );

    expect(filled.data).toMatchObject({ filled: 1, remaining: 0 });

    expect(codes(await doctor(["--only", "BS236,BS238"]))).toEqual(["BS236"]);
    expect((await doctor(["--only", "BS236", "--fix"])).code).toBe(0);

    const { rows } = await db.query<{ convalidated: boolean }>(
      "select convalidated from pg_constraint where conname = 'notes_organization_id_not_null'",
    );

    expect(rows).toEqual([{ convalidated: true }]);
    expect(codes(await doctor(["--only", "BS236,BS238"]))).toEqual([]);

    expect(
      await as(USER_A, "select body from public.notes order by 1"),
    ).toEqual([{ body: "written before the blocks" }]);
  });
});
