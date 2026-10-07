import { describe, expect, it } from "vitest";

import {
  declaredTableColumns,
  declaredTables,
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
    expect([...columns.get("public.organizations")!].sort()).toEqual([
      "id",
      "name",
      "slug",
    ]);
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

describe("extensionSchema", () => {
  it("finds the schema an extension is created in, outside module files", () => {
    expect(
      extensionSchema(
        [
          {
            text: "-- @bs-module vector-search@1 managed\ncreate extension if not exists vector with schema extensions;",
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
