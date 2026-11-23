import { describe, expect, it } from "vitest";

import type { SameTenantEntry } from "../../src/blocks/memberships/options.ts";
import type { CodemodProject } from "../../src/cli/codemod.ts";
import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import {
  sameTenantMoves,
  withColumnTag,
} from "../../src/cli/codemod-same-tenant.ts";
import { primeSchemaFacts } from "../../src/cli/sql-facts.ts";
import { resolveConfig } from "../../src/config/index.ts";

const SCHEMA = `create table public.projects (id uuid primary key, organization_id uuid not null, region text not null);
create table public.roles (id uuid primary key, organization_id uuid);
create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  region text not null,
  project_id uuid references public.projects,
  role_id uuid references public.roles,
  parent_id uuid references public.tasks
);
`;

const ENTRIES = [
  {
    table: "public.tasks",
    column: "project_id",
    references: "public.projects",
    match: { region: "region" },
  },
  {
    table: "public.tasks",
    column: "role_id",
    references: { table: "public.roles", column: "id" },
    shared: true,
  },
  { table: "public.tasks", column: "parent_id", references: "public.tasks" },
  {
    table: "public.tasks",
    column: "project_id",
    references: {
      table: "public.projects",
      column: "id",
      where: "{row}.region is not null",
    },
    deferrable: true,
  },
];

const CONFIG_TEXT = `export default defineConfig({
  blocks: {
    memberships: {
      options: {
        sameTenant: [
          { table: "public.tasks", column: "project_id", references: "public.projects", match: { region: "region" } },
          { table: "public.tasks", column: "role_id", references: { table: "public.roles", column: "id" }, shared: true },
          { table: "public.tasks", column: "parent_id", references: "public.tasks" },
        ],
      },
    },
  },
});
`;

const input = (entries: SameTenantEntry[]): BetterSupabaseConfig => ({
  blocks: { memberships: { options: { sameTenant: entries } } },
});

async function run(
  entries: SameTenantEntry[],
  text: string = SCHEMA,
): ReturnType<typeof sameTenantMoves> {
  const sql = [{ path: "/project/supabase/schemas/tasks.sql", text }];

  await primeSchemaFacts(sql, "/project");

  const project: CodemodProject = {
    config: resolveConfig(input(entries), "/project"),
    sql,
    configFile: "/project/better-supabase.config.ts",
    configText: CONFIG_TEXT,
  };

  return sameTenantMoves(project, {
    modules: { memberships: { options: { sameTenant: entries } } },
  });
}

describe("withColumnTag", () => {
  it("starts a comment, and adds to one that has tags", () => {
    const created = withColumnTag(
      "create table a.b (c int);",
      "a.b",
      "c",
      "@bsb same-tenant shared=false",
    );

    expect(created).toContain(
      `comment on column "a"."b"."c" is '@bsb same-tenant shared=false';`,
    );
    expect(
      withColumnTag(
        "comment on column a.b.c is '@bsb x=1';",
        "a.b",
        "c",
        "@bsb y=2",
      ),
    ).toContain(`is '@bsb x=1; y=2'`);
  });
});

describe("sameTenantMoves", () => {
  it("moves an entry whose tag renders the same trigger statement", async () => {
    const result = await run(ENTRIES.slice(0, 2));

    expect(result.moved).toBe(2);
    expect(result.review).toEqual([]);

    const schema = result.files.find((file) => file.path.endsWith("tasks.sql"));

    expect(schema?.contents).toContain(
      `comment on column "public"."tasks"."project_id" is '@bsb same-tenant match=region=region';`,
    );
    expect(schema?.contents).toContain(
      `comment on column "public"."tasks"."role_id" is '@bsb same-tenant shared=true';`,
    );

    const config = result.files.find((file) =>
      file.path.endsWith(".config.ts"),
    );

    expect(config?.contents).not.toContain("project_id");
    expect(config?.contents).not.toContain("role_id");
    expect(config?.contents).toContain("parent_id");
  });

  it("leaves an entry that equals the derived one to config --prune", async () => {
    const result = await run([ENTRIES[2]!]);

    expect(result.moved).toBe(0);
    expect(result.review[0]?.message).toContain("codemod config --prune");
  });

  it("keeps an entry whose statement would change", async () => {
    // The foreign key is not deferrable, so the tag cannot say deferrable.
    const result = await run([ENTRIES[3]!]);

    expect(result.moved).toBe(0);
    expect(result.review[0]?.message).toContain("would not render the same");
  });

  it("keeps an entry with no foreign key and one with a table nobody creates", async () => {
    const result = await run([
      { table: "public.tasks", column: "title", references: "public.projects" },
      {
        table: "public.ghosts",
        column: "project_id",
        references: "public.projects",
      },
    ]);

    expect(result.moved).toBe(0);
    expect(result.review.map((line) => line.message)).toEqual([
      expect.stringContaining("no foreign key holds the column"),
      expect.stringContaining("no schema file creates the table"),
    ]);
  });
});
