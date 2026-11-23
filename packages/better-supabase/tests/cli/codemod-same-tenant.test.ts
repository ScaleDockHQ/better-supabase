import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { SameTenantOption } from "../../src/blocks/memberships/options.ts";
import type { CodemodProject } from "../../src/cli/codemod.ts";
import type { ProjectSymbols } from "../../src/cli/typescript-symbols/index.ts";
import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import {
  projectSameTenantMoves,
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

const input = (sameTenant: unknown): BetterSupabaseConfig => ({
  // SAFETY: the tests also pass malformed options to reach the codemod's guards.
  blocks: {
    memberships: { options: { sameTenant: sameTenant as SameTenantOption } },
  },
});

const projectOf = (
  sameTenant: unknown,
  extra: Partial<CodemodProject> = {},
): CodemodProject => ({
  config: resolveConfig(input(sameTenant), "/project"),
  sql: [
    { path: "/project/supabase/schemas/tasks.sql", text: SCHEMA },
    { path: "/project/supabase/migrations/1_init.sql", text: SCHEMA },
  ],
  configFile: "/project/better-supabase.config.ts",
  configText: CONFIG_TEXT,
  ...extra,
});

async function run(
  entries: unknown,
  extra: Partial<CodemodProject> = {},
  rendered: unknown = entries,
): ReturnType<typeof sameTenantMoves> {
  const project = projectOf(entries, extra);

  await primeSchemaFacts(project.sql, "/project");

  return sameTenantMoves(project, {
    modules: { memberships: { options: { sameTenant: rendered } } },
  });
}

describe("withColumnTag", () => {
  it("starts a comment, and adds to one that has tags", async () => {
    const created = await withColumnTag(
      "create table a.b (c int);",
      "/p",
      "a.b",
      "c",
      "@bsb same-tenant shared=false",
    );

    expect(created).toContain(
      `comment on column "a"."b"."c" is '@bsb same-tenant shared=false';`,
    );
    expect(
      await withColumnTag(
        "comment on column a.b.c is '@bsb x=1';",
        "/p",
        "a.b",
        "c",
        "@bsb y=2",
      ),
    ).toContain(`is '@bsb x=1; y=2'`);
  });
});

describe("withColumnTag on a comment without tags", () => {
  it.each([
    ["is 'note';", "@bsb y=2", "is 'note\n@bsb y=2';"],
    ["is '';", "@bsb y='a'", "is '@bsb y=''a''';"],
  ])("%s takes %s", async (tail, line, expected) => {
    expect(
      await withColumnTag(
        `comment on column a.b.c ${tail}`,
        "/p",
        "a.b",
        "c",
        line,
      ),
    ).toBe(`comment on column a.b.c ${expected}`);
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

  it("reads the entries form and reports a path the config text lacks", async () => {
    const result = await run({ auto: true, entries: [ENTRIES[0]] });

    expect(result.moved).toBe(1);
    expect(result.files.map((file) => file.path)).toEqual([
      "/project/supabase/schemas/tasks.sql",
    ]);
    expect(result.review[0]?.message).toContain(
      "sameTenant.entries[0] moved to a tag, but the codemod could not find it",
    );
  });

  it("asks for a hand edit without a config file", async () => {
    const { configFile: _, ...project } = projectOf([ENTRIES[0]]);

    await primeSchemaFacts(project.sql, "/project");

    const result = await sameTenantMoves(project, {
      modules: { memberships: { options: { sameTenant: [ENTRIES[0]] } } },
    });

    expect(result.moved).toBe(1);
    expect(result.review).toEqual([
      {
        message: "No config file was found; remove the moved entries by hand.",
      },
    ]);
  });

  it.each([
    [{ table: "public.tasks" }, "it has no table and column"],
    [
      {
        table: "public.tasks",
        column: "project_id",
        references: "public.projects",
        through: { p: { table: "public.projects", column: "id" } },
      },
      "a through hop with its own key column does not fit a tag",
    ],
    [
      {
        table: "public.tasks",
        column: "project_id",
        references: { table: "public.projects", tenant: "organization_id" },
        tenant: "organization_id",
        match: { region: "region", project_id: "id" },
        through: { p: "public.projects" },
      },
      '@bsb same-tenant tenant=organization_id parent-tenant=organization_id match="region=region,project_id=id" through=p=public.projects',
    ],
  ])("keeps %o", async (entry, reason) => {
    // The rendered layout leaves out the entries its parser refuses.
    const result = await run(["junk", entry], {}, []);

    expect(result.moved).toBe(0);
    expect(result.review).toEqual([
      { message: expect.stringContaining(reason) },
    ]);
  });
});

describe("projectSameTenantMoves", () => {
  it.each([
    ["no memberships block", { config: resolveConfig({}, "/project") }],
    ["no entries", { config: resolveConfig(input(false), "/project") }],
  ])("does nothing with %s", async (_, extra) => {
    expect(await projectSameTenantMoves(projectOf([], extra))).toEqual({
      files: [],
      review: [],
      moved: 0,
    });
  });

  it("renders the project's own layout and moves the entries", async () => {
    const result = await projectSameTenantMoves(projectOf(ENTRIES.slice(0, 2)));

    expect(result.moved).toBe(2);
  });
});

describe("sameTenantMoves across files", () => {
  it("removes a moved entry from the file that declares the imported value", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-same-tenant-"));
    const file = join(root, "shared.ts");

    const shared = `export const shared = {
  memberships: {
    options: {
      sameTenant: [
        { table: "public.tasks", column: "project_id", references: "public.projects", match: { region: "region" } },
      ],
    },
  },
};
`;

    await writeFile(file, shared);

    const symbols: ProjectSymbols = {
      root,
      tier: {
        version: "7.1.0",
        references: () => [],
        declaration: () => ({
          file,
          start: shared.indexOf("export"),
          end: shared.length,
        }),
        typeOf: () => undefined,
        close: () => {},
      },
    };

    const configText =
      'import { shared } from "./shared.ts";\nexport default defineConfig({ blocks: shared });\n';

    const project = projectOf([ENTRIES[0]], {
      configFile: join(root, "better-supabase.config.ts"),
      configText,
      symbols,
    });

    await primeSchemaFacts(project.sql, "/project");

    const result = await sameTenantMoves(project, {
      modules: { memberships: { options: { sameTenant: [ENTRIES[0]] } } },
    });

    expect(result.moved).toBe(1);
    expect(result.review).toEqual([]);

    const edited = result.files.find((each) => each.path === file);

    expect(edited).toBeDefined();
    expect(edited?.contents).not.toContain("project_id");
  });
});
