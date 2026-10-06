import { describe, expect, it } from "vitest";

import {
  declaredTables,
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
