import { describe, expect, it } from "vitest";

import {
  declaredColumnTypes,
  declaredEnums,
  declaredIndexes,
  declaredTableColumns,
  declaredTables,
  declaredViews,
  extensionSchema,
  policyGrants,
  tableGlobs,
} from "../../src/sql/schema-scan.ts";

describe("policyGrants", () => {
  it("collects the permissive policies per table and role", () => {
    const grants = policyGrants(
      [
        {
          text: `create policy notes_read on public.notes for select to authenticated
  using (true);
-- create policy ignored on public.notes for delete to anon using (true);
create policy notes_write on notes for insert to authenticated with check (true);
create policy "Plans are public" on public."Plans" for select to anon, authenticated using (true);
create policy everyone on public.tags using (true);
create policy only_mfa on public.notes as restrictive for all to authenticated using (true);
create policy service on public.jobs for all to service_role using (true);
create policy internal on private.secrets for select to authenticated using (true);`,
        },
      ],
      ["public"],
    );

    expect(grants).toEqual([
      { table: "public.Plans", role: "anon", privileges: ["select"] },
      { table: "public.Plans", role: "authenticated", privileges: ["select"] },
      {
        table: "public.notes",
        role: "authenticated",
        privileges: ["select", "insert"],
      },
      {
        table: "public.tags",
        role: "authenticated",
        privileges: ["select", "insert", "update", "delete"],
      },
    ]);
  });
});

describe("declaredTableColumns", () => {
  it("reads column names and skips table constraints", () => {
    const columns = declaredTableColumns(
      [
        {
          text: `create table public.organizations (
  id uuid primary key,
  name text not null,
  slug text,
  unique (slug),
  constraint organizations_name_check check (length(name) > 0)
);`,
        },
      ],
      ["public"],
    );

    expect([...columns.get("public.organizations")!].toSorted()).toEqual([
      "id",
      "name",
      "slug",
    ]);
  });
});

describe("declaredColumnTypes", () => {
  it("reads each column's type without its options", () => {
    const types = declaredColumnTypes(
      [
        {
          text: `create table public.tags (
  id uuid primary key default gen_random_uuid(),
  kind public.tag_kind not null,
  "Label" character varying(80) collate "C" not null,
  rank text,
  ids bigint[] not null default '{}',
  unique (kind, "Label")
);`,
        },
      ],
      ["public"],
    );

    expect(Object.fromEntries(types.get("public.tags")!)).toEqual({
      id: "uuid",
      kind: "public.tag_kind",
      Label: "character varying(80)",
      rank: "text",
      ids: "bigint[]",
    });
  });
});

describe("declaredEnums", () => {
  it("lists the enum types, qualified", () => {
    expect([
      ...declaredEnums([
        {
          text: `create type public.tag_kind as enum ('task');
create type "App".status as enum ();
create type public.pair as (a int, b int);
-- create type public.ignored as enum ('x');`,
        },
      ]),
    ]).toEqual(["public.tag_kind", "App.status"]);
  });
});

describe("declaredTables", () => {
  it("lists the created tables in the schemas once", () => {
    expect(
      declaredTables(
        [
          {
            text: `create table public.notes (id int);
-- create table public.ignored (id int);
create table if not exists invoices (id int);
create unlogged table "public"."Cache" (key text);
create table private.secrets (id int);
create table public.notes (id int);`,
          },
        ],
        ["public"],
      ),
    ).toEqual(["public.notes", "public.invoices", "public.Cache"]);
  });

  it("matches globs on schema.table", () => {
    const [pattern] = tableGlobs(["public.audit_*"]);
    expect(pattern!.test("public.audit_log")).toBe(true);
    expect(pattern!.test("public.auditlog")).toBe(false);
  });
});

describe("declaredViews", () => {
  const views = (text: string) =>
    Object.fromEntries(declaredViews([{ text }], ["public"]));

  it("reads the select list's columns and whether Postgres writes through", () => {
    expect(
      views(`create view public.organization_memberships with (security_invoker = true) as
select distinct on (scope_id, user_id) scope_id as organization_id, user_id, role, created_at
from public.memberships where scope = 'organization'
order by scope_id, user_id, created_at, role;
create or replace view public.active_members as
  select m.organization_id, m.user_id, m.role from public.memberships m where m.disabled_at is null;
create view private.hidden as select 1 as one;`),
    ).toEqual({
      "public.organization_memberships": {
        columns: ["organization_id", "user_id", "role", "created_at"],
        updatable: false,
      },
      "public.active_members": {
        columns: ["organization_id", "user_id", "role"],
        updatable: true,
      },
    });
  });

  it("takes a column list and treats materialized views as read-only", () => {
    expect(
      views(`create view public.pairs (a, b) as select x, y from public.t;
create materialized view public.totals as select org, count(*) as n from public.t group by org;`),
    ).toEqual({
      "public.pairs": { columns: ["a", "b"], updatable: true },
      "public.totals": { columns: ["org", "n"], updatable: false },
    });
  });

  it("counts an instead of trigger as writable and forgets dropped views", () => {
    expect(
      views(`create view public.members as select a.id from public.a join public.b using (id);
create trigger members_write instead of insert on public.members
  for each row execute function public.members_write();
create view public.gone as select 1 as one;
drop view public.gone;`),
    ).toEqual({ "public.members": { columns: ["id"], updatable: true } });
  });

  it("leaves the columns unknown for select *", () => {
    expect(
      views("create view public.everything as select * from public.t;"),
    ).toEqual({ "public.everything": { columns: undefined, updatable: true } });
  });
});

describe("extensionSchema", () => {
  it("finds the schema an extension is created in, outside module files", () => {
    expect(
      extensionSchema(
        [
          {
            text: "-- @bsb-block vector-search@1 managed\ncreate extension if not exists vector with schema extensions;",
          },
          {
            text: "-- create extension vector schema nope;\ncreate table a (id int);",
          },
          {
            text: 'CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";',
          },
          { text: "create extension vector schema later;" },
        ],
        "vector",
      ),
    ).toBe("public");
    expect(
      extensionSchema(
        [{ text: "create extension pgcrypto schema x;" }],
        "vector",
      ),
    ).toBeUndefined();
  });
});

describe("dropped tables and policies", () => {
  it("forgets tables and policies a later statement drops", () => {
    const files = [
      {
        text: `create table public.old_notes (id int);
create policy old_read on public.old_notes for select to authenticated using (true);
create table public.notes (id int);
create policy notes_read on public.notes for select to authenticated using (true);
create policy notes_write on public.notes for insert to authenticated with check (true);`,
      },
      {
        text: `drop table if exists public.old_notes, public.gone;
drop policy if exists notes_write on public.notes;
create policy notes_write on public.notes for update to authenticated using (true);
drop policy "notes_read" on notes;`,
      },
    ];

    expect(declaredTables(files, ["public"])).toEqual(["public.notes"]);
    expect(policyGrants(files, ["public"])).toEqual([
      { table: "public.notes", role: "authenticated", privileges: ["update"] },
    ]);
  });
});

describe("declaredIndexes", () => {
  it("collects the leading columns of full btree indexes and key constraints", () => {
    const indexes = declaredIndexes(
      [
        {
          text: `create table public.members (
  id uuid primary key,
  team_id uuid not null,
  user_id uuid not null,
  organization_id uuid not null,
  email text unique,
  constraint members_pair unique (team_id, user_id),
  check (id is not null)
);
-- create index ignored_idx on public.members (email);
create index members_org_idx on public.members (organization_id, "user_id" desc nulls last);
create index if not exists on public.members (lower(email), user_id);
create unique index concurrently members_one on only members using btree (user_id);
create index members_partial on public.members (team_id) where team_id is not null;
create index members_gin on public.members using gin (email);
create index other_idx on private.things (id);`,
        },
      ],
      ["public"],
    );

    expect(indexes.get("public.members")).toEqual([
      { name: "members_org_idx", columns: ["organization_id", "user_id"] },
      { name: "members_one", columns: ["user_id"] },
      { columns: ["id"] },
      { columns: ["email"] },
      { columns: ["team_id", "user_id"] },
    ]);
    expect(indexes.has("private.things")).toBe(false);
  });
});
