import { describe, expect, it } from "vitest";

import {
  planOf,
  renameMigration,
  renameNames,
} from "../../src/cli/codemod-adopt-names.ts";
import { scanSql } from "../../src/cli/schema-reader/index.ts";
import { resolveConfig } from "../../src/config/index.ts";

const plan = {
  from: { schema: "public", name: "seats" },
  to: { schema: "public", name: "memberships" },
  columns: new Map([["org_id", "organization_id"]]),
};

const SQL = `create table public.seats (id uuid, org_id uuid);
create policy p on seats using (org_id is not null);
create index i on "public"."seats" (org_id);
comment on table public.seats is 'seats, org_id';
create table public.other (org_id uuid);`;

describe("adopt-names", () => {
  it("renames the table and its columns where a statement names the table", async () => {
    const { text, statements } = renameNames(SQL, await scanSql(SQL), plan);

    expect(statements).toBe(4);
    expect(text).toContain(
      "create table public.memberships (id uuid, organization_id uuid)",
    );
    expect(text).toContain(
      "on memberships using (organization_id is not null)",
    );
    expect(text).toContain("'seats, org_id'");
    expect(text).toContain("create table public.other (org_id uuid)");
  });

  it("writes the rename migration", () => {
    expect(renameMigration(plan)).toContain(
      "alter table public.seats rename to memberships;\nalter table public.memberships rename column org_id to organization_id;",
    );
  });

  it("refuses a table outside the block's schema", () => {
    const config = resolveConfig(
      { blocks: { memberships: { tables: { memberships: "app.seats" } } } },
      "/tmp/adopt",
    );

    expect(planOf(config, "memberships.memberships")).toContain(
      "blocks.memberships.schema",
    );
  });
});
