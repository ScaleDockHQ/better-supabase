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
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import {
  codemodCommand,
  runCodemod,
} from "../../../src/cli/commands/codemod.ts";
import { runSql } from "../../../src/cli/commands/sql.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { moduleLayoutFor } from "../../../src/cli/sql-layout.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const MEMBER = "22222222-2222-4222-8222-222222222222";
const DOC = "44444444-4444-4444-8444-444444444444";

const VIEW = "public.organization_memberships";
const APP_FILE = "supabase/schemas/010_memberships.sql";

const APP = `create table public.memberships (
  scope text not null,
  scope_id uuid not null,
  user_id uuid not null,
  role text not null,
  created_at timestamptz not null default now()
);

create view public.organization_memberships with (security_invoker = true) as
select distinct on (scope_id, user_id) scope_id as organization_id, user_id, role, created_at
from public.memberships where scope = 'organization'
order by scope_id, user_id, created_at, role;

create table public.docs (
  id uuid primary key,
  organization_id uuid not null
);
`;

/** The 0.14 config: the block adopted the view with `ownership: "adopt"`. */
const CONFIG_014 = `export default {
  blocks: {
    memberships: {
      ownership: "adopt",
      tables: { memberships: "${VIEW}" },
      columns: { memberships: { updatedAt: null, lastUsedAt: null } },
    },
    "share-links": { on: { doc: { table: "docs" } } },
  },
};
`;

const CONFIG: BetterSupabaseConfig = {
  blocks: {
    memberships: {
      tables: { memberships: VIEW },
      columns: { memberships: { updatedAt: null, lastUsedAt: null } },
    },
    "share-links": { on: { doc: { table: "docs" } } },
  },
};

const PRELUDE = `do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- PGlite loads no pgcrypto here; share tokens need random bytes and sha256.
create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;
`;

/** Statements that would change the view rather than read it. */
const VIEW_DDL =
  /^\s*(?:create table|alter table|create (?:unique )?index\b.* on|(?:grant|revoke)\b.* on(?: table)?|(?:create|alter|drop) policy\b.* on|(?:create|drop) trigger\b.* on|comment on (?:table|column))(?: if (?:not )?exists| only)*\s+"?public"?\."?organization_memberships\b/im;

describe("a 0.14 block adopted over the app's view", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-over-view-"));
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(join(root, APP_FILE), APP);
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[]) =>
    runSql(resolveConfig(CONFIG, root), parseArgs(argv, SQL_ARGS));

  it("finds the view, its columns and that Postgres can't write through it", async () => {
    const layout = await moduleLayoutFor(resolveConfig(CONFIG, root), {
      names: ["memberships", "share-links"],
    });

    expect(layout.ownTables).toMatchObject({ [VIEW]: APP_FILE });
    expect(layout.ownViews).toEqual({ [VIEW]: { updatable: false } });
    expect(layout.ownColumns?.[VIEW]).toEqual([
      "organization_id",
      "user_id",
      "role",
      "created_at",
    ]);
  });

  it("drops ownership after the codemod and writes SQL that leaves the view alone", async () => {
    await writeFile(join(root, "better-supabase.config.ts"), CONFIG_014);

    const codemod = await runCodemod(
      resolveConfig({}, root),
      // SAFETY: every codemod subcommand declares the same args, so any one parses `argv`.
      parseCommandArgs(codemodCommand("0.15"), ["0.15"]),
    );

    expect(codemod.code).toBe(0);
    expect(
      await readFile(join(root, "better-supabase.config.ts"), "utf-8"),
    ).not.toContain("ownership");

    expect((await sql(["sync"])).code).toBe(0);
    expect((await sql(["upgrade"])).code).toBe(0);

    const schemas = (await readdir(join(root, "supabase/schemas")))
      .filter((name) => name.startsWith("900_better_supabase_"))
      .toSorted();

    const migrations = (
      await readdir(join(root, "supabase/migrations"))
    ).toSorted();

    const blockFiles = await Promise.all(
      schemas.map((name) =>
        readFile(join(root, "supabase/schemas", name), "utf-8"),
      ),
    );

    const migrationFiles = await Promise.all(
      migrations.map((name) =>
        readFile(join(root, "supabase/migrations", name), "utf-8"),
      ),
    );

    expect(
      'alter table "public"."organization_memberships" enable row level security;',
    ).toMatch(VIEW_DDL);

    for (const text of [...blockFiles, ...migrationFiles]) {
      expect(text).not.toMatch(VIEW_DDL);
    }

    expect(blockFiles.join("\n")).toContain(
      `from "public"."organization_memberships" m`,
    );

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [PRELUDE, APP, ...blockFiles],
      seed: [
        `insert into public.memberships (scope, scope_id, user_id, role)
  values ('organization', '${ORG}', '${MEMBER}', 'owner');
insert into public.docs (id, organization_id) values ('${DOC}', '${ORG}');`,
        `do $$
declare
  v_link jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${MEMBER}"}', true);
  perform set_config('request.jwt.claim.sub', '${MEMBER}', true);
  v_link := better_supabase.create_share_link('${ORG}', 'doc', '${DOC}', 'view');
  if better_supabase.resolve_share_link(v_link ->> 'token') ->> 'subjectId' <> '${DOC}' then
    raise exception 'resolve_share_link missed the link';
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });
});
