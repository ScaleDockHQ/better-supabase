import { describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderModules } from "../../src/sql/render.ts";

// The SQL `appTables` renders (ADR 0040): per tenant, per user, in the
// shared space and with the tenant renamed.

const TABLES: AppTablesConfig = {
  projects: {
    columns: {
      name: { type: "text", nullable: false },
      budget_minor: { type: "bigint", nullable: false, default: "0" },
      currency: { type: "text", nullable: false, default: "'EUR'" },
      owner_id: {
        type: "uuid",
        references: { table: "auth.users", onDelete: "set null" },
      },
    },
  },
  tasks: {
    columns: {
      project_id: {
        type: "uuid",
        nullable: false,
        references: { table: "projects", onDelete: "cascade" },
      },
      title: { type: "text", nullable: false },
      done: { type: "boolean", nullable: false, default: "false" },
      labels: { type: "text[]", default: "'{}'" },
    },
  },
};

const BLOCKS = ["tenant", "organizations", "updated-at"];

function render(
  names: readonly string[],
  layout: ModuleLayout,
): ReturnType<typeof renderModules> {
  return renderModules(names, layout).filter(
    (file) => file.module === APP_TABLES_MODULE,
  );
}

const golden = (files: ReturnType<typeof renderModules>): string =>
  files
    .map((file) => `-- ==== ${file.kind} ${file.path}\n${file.contents}`)
    .join("\n");

describe("appTables SQL", () => {
  it("renders nothing without app tables", () => {
    expect(render(BLOCKS, {})).toEqual([]);
    expect(render(BLOCKS, { appTables: {} })).toEqual([]);
  });

  it("renders without any block outside tenant scope", () => {
    expect(
      render([], { scope: "user", appTables: TABLES }).map((file) => file.path),
    ).toEqual([
      "supabase/schemas/900_better_supabase_app_tables.sql",
      "supabase/tests/900_better_supabase_app_tables.test.sql",
    ]);
  });

  it("renders the golden SQL per tenant", async () => {
    await expect(
      golden(render(BLOCKS, { appTables: TABLES })),
    ).toMatchFileSnapshot("__golden__/app-tables/tenant.sql");
  });

  it("renders the golden SQL per user", async () => {
    await expect(
      golden(render(["updated-at"], { scope: "user", appTables: TABLES })),
    ).toMatchFileSnapshot("__golden__/app-tables/user.sql");
  });

  it("renders the golden SQL in the shared space", async () => {
    await expect(
      golden(render([], { scope: "none", appTables: TABLES })),
    ).toMatchFileSnapshot("__golden__/app-tables/none.sql");
  });

  it("renders the golden SQL with the tenant renamed", async () => {
    await expect(
      golden(
        render(BLOCKS, {
          naming: { tenant: "workspace" },
          appTables: TABLES,
        }),
      ),
    ).toMatchFileSnapshot("__golden__/app-tables/workspace.sql");
  });

  it("lets a table keep rows per user or shared in tenant scope", () => {
    const [schema] = render(BLOCKS, {
      appTables: {
        drafts: { scope: "user" },
        settings: { scope: "none", timestamps: false },
      },
    });

    expect(schema?.contents).toContain(
      '"user_id" uuid default auth.uid() references auth.users (id) on delete cascade',
    );
    expect(schema?.contents).toContain(
      'create policy "settings_select" on "public"."settings" for select to authenticated using (((select auth.uid()) is not null));',
    );
    expect(schema?.contents).not.toContain('"settings_insert"');
    expect(schema?.contents).toContain(
      'grant select on "public"."settings" to authenticated;',
    );
  });

  it("references a block table through its renames", () => {
    const [schema] = render(["tenant", "organizations", "tags"], {
      modules: { tags: { tables: { tags: "labels" } } },
      appTables: {
        pins: {
          columns: {
            tag_id: {
              type: "uuid",
              references: { block: "tags", table: "tags", onDelete: "cascade" },
            },
          },
        },
      },
    });

    expect(schema?.contents).toContain(
      'add column if not exists "tag_id" uuid references "better_supabase"."labels" ("id") on delete cascade;',
    );
    expect(schema?.contents).toContain(
      'create index if not exists "pins_tag_id_idx" on "public"."pins" ("tag_id");',
    );
  });

  it("leaves the grants of an exposed table to expose", () => {
    const [schema, test] = render(BLOCKS, {
      grants: [
        { table: "public.projects", role: "anon", privileges: ["select"] },
      ],
      appTables: { projects: {} },
    });

    expect(schema?.contents).toContain(
      '-- expose sets the grants on "public"."projects".',
    );
    expect(schema?.contents).not.toContain("revoke all");
    expect(test?.contents).not.toContain("table_privs_are");
  });

  it("skips the updated_at trigger without the updated-at block", () => {
    const [schema] = render([], {
      scope: "user",
      appTables: { projects: {} },
    });

    expect(schema?.contents).not.toContain("set_updated_at");
  });

  it("counts every check in the pgTAP plan", () => {
    const [, test] = render(BLOCKS, { appTables: TABLES });

    const checks = (test?.contents ?? "")
      .split("\n")
      .filter((line) => /^select extensions\.(?!plan)/.test(line)).length;

    expect(test?.contents).toContain(
      `select extensions.plan(${String(checks)});`,
    );
  });
});

describe("appTables SQL errors", () => {
  it("needs the tenant block in tenant scope", () => {
    expect(() => render([], { appTables: { projects: {} } })).toThrow(
      'appTables.projects: tenant scope needs the tenant block, which checks membership; add it to blocks, or set the table\'s scope to "user" or "none"',
    );
  });

  it("refuses a reference to a block that isn't installed", () => {
    expect(() =>
      render(BLOCKS, {
        appTables: {
          deals: {
            columns: {
              contact_id: {
                type: "uuid",
                references: { block: "crm", table: "contacts" },
              },
            },
          },
        },
      }),
    ).toThrow(
      "appTables.deals.columns.contact_id.references: the crm block is not installed; add it to blocks",
    );
  });

  it("refuses a table the block doesn't keep", () => {
    expect(() =>
      render(["tenant", "organizations", "tags"], {
        appTables: {
          pins: {
            columns: {
              tag_id: {
                type: "uuid",
                references: { block: "tags", table: "labels" },
              },
            },
          },
        },
      }),
    ).toThrow(
      'appTables.pins.columns.tag_id.references: the tags block has no table "labels" (tags, taggings)',
    );
  });

  it("refuses a name a block table already has", () => {
    expect(() =>
      render(["tenant", "organizations", "tags"], {
        appTables: { tags: {} },
      }),
    ).toThrow(
      "appTables.tags: the tags block already keeps a table named tags; choose another name",
    );
  });

  it("refuses the renamed tenant table's name", () => {
    expect(() =>
      render(BLOCKS, {
        naming: { tenant: "workspace" },
        appTables: { workspaces: {} },
      }),
    ).toThrow("the organizations block already keeps a table named workspaces");
  });
});
