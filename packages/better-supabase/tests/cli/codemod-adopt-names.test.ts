import { describe, expect, it } from "vitest";

import type { CodemodProject } from "../../src/cli/codemod.ts";

import {
  adoptNamesCodemod,
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

const memberships = (entry: Record<string, unknown>) =>
  resolveConfig({ blocks: { memberships: entry } }, "/tmp/adopt");

describe("planOf", () => {
  it.each([
    ["memberships", "Name the table as <block>.<table>"],
    ["a.b.c", "Name the table as <block>.<table>"],
    ["nope.memberships", "is not a table of an installed block"],
    ["memberships.nope", "is not a table of an installed block"],
  ])("refuses %s", (target, message) => {
    expect(planOf(memberships({}), target)).toContain(message);
  });

  it("says the table already has the block's name when tables is unset", () => {
    expect(planOf(memberships({}), "memberships.memberships")).toContain(
      "is not set",
    );
  });

  it("maps string and record columns, and skips unknown or equal ones", () => {
    const resolved = planOf(
      memberships({
        schema: "public",
        tables: { memberships: "seats" },
        columns: {
          memberships: {
            tenant: "org_id",
            user: { column: "member_id" },
            role: "role",
            bogus: "x",
          },
        },
      }),
      "memberships.memberships",
    );

    expect(resolved).toMatchObject({
      block: "memberships",
      logical: "memberships",
      logicalColumns: ["tenant", "user", "role"],
      hasValues: false,
      plan: {
        from: { schema: "public", name: "seats" },
        to: { schema: "public", name: "memberships" },
      },
    });
    expect(
      typeof resolved === "string" ? [] : [...resolved.plan.columns],
    ).toEqual([
      ["org_id", "organization_id"],
      ["member_id", "user_id"],
    ]);
  });
});

describe("renameNames edges", () => {
  it.each([
    [
      "a qualified name outside public",
      {
        from: { schema: "app", name: "seats" },
        to: { schema: "app", name: "members" },
      },
      "select * from seats; select * from app.seats;",
      "select * from seats; select * from app.members;",
    ],
    [
      "a bare name into another schema",
      {
        from: { schema: "public", name: "seats" },
        to: { schema: "Core", name: "Members" },
      },
      "update seats set x = 1; select seats.x from t;",
      'update "Core"."Members" set x = 1; select seats.x from t;',
    ],
    [
      "a column reference after COLUMN and a quoted column",
      {
        from: { schema: "public", name: "seats" },
        to: { schema: "public", name: "members" },
      },
      `comment on column seats.org_id is 'x'; select "org_id" from public.seats -- seats\n;`,
      `comment on column members.organization_id is 'x'; select "organization_id" from public.members -- seats\n;`,
    ],
  ])("renames %s", async (_, names, sql, expected) => {
    const result = renameNames(sql, await scanSql(sql), {
      ...names,
      columns: new Map([["org_id", "organization_id"]]),
    });

    expect(result.text).toBe(expected);
  });
});

describe("renameMigration edges", () => {
  it("writes nothing when the names already match", () => {
    expect(
      renameMigration({
        from: { schema: "public", name: "m" },
        to: { schema: "public", name: "m" },
        columns: new Map(),
      }),
    ).toBe("");
  });

  it("moves the table to the block's schema and quotes odd names", () => {
    expect(
      renameMigration({
        from: { schema: "public", name: "Seats" },
        to: { schema: "app", name: "Seats" },
        columns: new Map(),
      }),
    ).toContain('alter table public."Seats" set schema app;');
  });
});

describe("adoptNamesCodemod", () => {
  const project = (
    table: string | undefined,
    entry: Record<string, unknown>,
  ): CodemodProject => ({
    config: memberships(entry),
    ...(table === undefined ? {} : { table }),
    configFile: "/tmp/adopt/better-supabase.config.ts",
    configText: `export default defineConfig({\n  blocks: {\n    memberships: {\n      schema: "public",\n      tables: { memberships: "seats" },\n      columns: { memberships: { tenant: "org_id" } },\n    },\n  },\n});\n`,
    sql: [
      {
        path: "/tmp/adopt/supabase/schemas/seats.sql",
        text: "create table public.seats (org_id uuid);",
      },
      {
        path: "/tmp/adopt/supabase/schemas/other.sql",
        text: "create table public.other (id uuid);",
      },
      {
        path: "/tmp/adopt/supabase/migrations/1_init.sql",
        text: "create table public.seats (org_id uuid);",
      },
      {
        path: "/tmp/adopt/supabase/schemas/900_better_supabase_x.sql",
        text: "select * from public.seats;",
      },
    ],
  });

  it.each([
    [undefined, "Pass --table <block>.<table>"],
    ["memberships", "Name the table as"],
  ])("only reviews when --table is %s", async (table, message) => {
    const result = await adoptNamesCodemod().project!(project(table, {}));

    expect(result.files).toEqual([]);
    expect(result.review[0]?.message).toContain(message);
  });

  it("rewrites the schema files, prunes the config and writes the migration", async () => {
    const result = await adoptNamesCodemod().project!(
      project("memberships.memberships", {
        schema: "public",
        tables: { memberships: "seats" },
        columns: { memberships: { tenant: "org_id" } },
        values: { memberships: { role: { owner: "admin" } } },
      }),
    );

    expect(
      result.files.map((file) => [file.path.split("/").at(-1), file.policy]),
    ).toEqual([
      ["seats.sql", "edit"],
      ["better-supabase.config.ts", "edit"],
      [
        expect.stringMatching(
          /_better_supabase_adopt_names(?:_v2)?[-_][0-9a-f]+\.sql$/u,
        ),
        "create",
      ],
    ]);
    expect(result.files[0]?.contents).toBe(
      "create table public.memberships (organization_id uuid);",
    );
    expect(result.files[1]?.contents).not.toContain("seats");
    expect(result.files[2]?.contents).toContain(
      "alter table public.seats rename to memberships;",
    );
    expect(result.review.map((line) => line.message).join("\n")).toMatch(
      /renamed in 1 statement[\s\S]*public\.seats is now public\.memberships; column org_id is now organization_id[\s\S]*values\.memberships stays/u,
    );
  });

  it("defaults to the better_supabase schema and lists only the column change", async () => {
    const result = await adoptNamesCodemod().project!({
      config: memberships({
        tables: { memberships: "memberships" },
        columns: { memberships: { tenant: "org_id", lastUsedAt: null } },
      }),
      table: "memberships.memberships",
      sql: [],
    });

    expect(result.files.map((file) => file.contents)).toEqual([
      expect.stringContaining(
        "alter table better_supabase.memberships rename column org_id to organization_id;",
      ),
    ]);
    expect(result.review.at(-1)?.message).toContain(
      "generated client: column org_id is now organization_id.",
    );
  });
});
