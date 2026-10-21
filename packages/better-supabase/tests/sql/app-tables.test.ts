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

const FORMATS: AppTablesConfig = {
  contacts: {
    id: "bigint",
    comment: "People the team talks to.",
    unique: [["organization_id", "code"]],
    indexes: [["stage", "created_at"]],
    columns: {
      number: { type: "bigint", identity: true },
      email: { type: "text", format: "email" },
      website: { type: "text", format: "url" },
      phone: { type: "text", format: "phone" },
      stage: { type: "text", options: ["lead", "won", "it's lost"] },
      labels: { type: "text[]", options: ["red", "blue"] },
      score: { type: "integer", format: "rating" },
      share: { type: "numeric", format: "percent", max: 50 },
      code: {
        type: "text",
        min: 2,
        max: 8,
        comment: "The short code, unique per tenant.",
      },
      price_minor: { type: "bigint", format: "currency" },
      price_currency: { type: "text", min: 3, max: 3 },
    },
  },
  notes: {
    columns: {
      contact_id: {
        type: "bigint",
        references: { table: "contacts", onDelete: "cascade" },
      },
    },
  },
};

const COMPUTED: AppTablesConfig = {
  projects: {
    columns: { name: { type: "text", nullable: false } },
    rollups: {
      done_tasks: {
        table: "tasks",
        via: "project_id",
        aggregate: "count",
        where: { column: "status", equals: "done" },
      },
      estimate_total: {
        table: "tasks",
        via: "project_id",
        aggregate: "sum",
        column: "estimate",
      },
      last_due: {
        table: "tasks",
        via: "project_id",
        aggregate: "max",
        column: "due_on",
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
      status: { type: "text", options: ["todo", "done"] },
      estimate: { type: "integer" },
      due_on: { type: "date" },
    },
    lookups: { project_name: { via: "project_id", column: "name" } },
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

  it("renders a subject's rank and soft-delete columns and its search trigger", async () => {
    const appTables: AppTablesConfig = {
      projects: {
        columns: {
          name: { type: "text", nullable: false },
          stage: { type: "text" },
        },
        subject: {
          type: "project",
          title: "name",
          search: {},
          rank: { group: "stage" },
          softDelete: true,
        },
      },
    };

    const files = render([...BLOCKS, "subjects", "search"], {
      appTables,
      subjects: {
        project: {
          table: "public.projects",
          idType: "uuid",
          title: "name",
          search: {},
          deletedAt: "deleted_at",
          rank: { column: "rank", group: "stage" },
        },
      },
    });

    const search = renderModules([...BLOCKS, "subjects", "search"], {
      appTables,
      subjects: {
        project: { table: "public.projects", title: "name", search: {} },
      },
    }).find((file) => file.module === "search" && file.kind === "schema");

    expect(search?.contents).not.toContain("bs_search_project_index");
    await expect(golden(files)).toMatchFileSnapshot(
      "__golden__/app-tables/subject.sql",
    );
  });

  it("renders the golden SQL with the tenant renamed", async () => {
    await expect(
      golden(
        render(BLOCKS, {
          modules: { tenant: { entities: { organization: "workspace" } } },
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
    const [schema] = render([], { scope: "user", appTables: { projects: {} } });

    expect(schema?.contents).not.toContain("set_updated_at");
  });

  it("expects the session policy on the tables the sessions block covers", () => {
    const [, test] = render(["sessions"], {
      scope: "user",
      appTables: TABLES,
      declaredTables: ["public.projects", "public.tasks"],
      modules: {
        sessions: { options: { policies: true, exclude: ["public.tasks"] } },
      },
    });

    expect(test?.contents).toContain(
      `array['projects_select', 'projects_insert', 'projects_update', 'projects_delete', 'bs_session_active']`,
    );
    expect(test?.contents).toContain(
      `array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete']`,
    );
  });

  it("renders the golden SQL of formats, options, bounds and keys", async () => {
    await expect(
      golden(render(BLOCKS, { appTables: FORMATS })),
    ).toMatchFileSnapshot("__golden__/app-tables/formats.sql");
  });

  it("names each check and unique key, and drops it before adding it", () => {
    const [schema, test] = render(BLOCKS, { appTables: FORMATS });

    expect(schema?.contents).toContain(
      `alter table "public"."contacts" drop constraint if exists "contacts_email_check";
alter table "public"."contacts" add constraint "contacts_email_check" check ("email" ~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');`,
    );
    expect(schema?.contents).toContain(
      `check ("stage" in ('lead', 'won', 'it''s lost'))`,
    );
    expect(schema?.contents).toContain(
      `check ("labels" <@ array['red', 'blue']::text[])`,
    );
    expect(schema?.contents).toContain(`check ("score" >= 1 and "score" <= 5)`);
    expect(schema?.contents).toContain(
      `check (char_length("code") >= 2 and char_length("code") <= 8)`,
    );
    expect(schema?.contents).toContain(
      `check (char_length("price_currency") >= 3 and char_length("price_currency") <= 3)`,
    );
    expect(schema?.contents).toContain(
      `add constraint "contacts_organization_id_code_key" unique ("organization_id", "code");`,
    );
    expect(schema?.contents).toContain(
      `create index if not exists "contacts_stage_created_at_idx" on "public"."contacts" ("stage", "created_at");`,
    );
    expect(schema?.contents).toContain(
      `comment on column "public"."contacts"."code" is 'The short code, unique per tenant.';`,
    );
    expect(schema?.contents).toContain(
      `add column if not exists "number" bigint generated by default as identity;`,
    );
    expect(schema?.contents).toContain(
      "id bigint generated by default as identity primary key",
    );
    expect(test?.contents).toContain(
      `select extensions.col_has_check('public'::name, 'contacts'::name, 'email'::name,`,
    );
    expect(test?.contents).not.toContain(`'phone'::name`);
  });

  it("checks the tenant of a reference between tenant-scoped tables", () => {
    const [schema, test] = render(BLOCKS, {
      appTables: {
        ...TABLES,
        folders: {
          columns: {
            parent_id: {
              type: "uuid",
              references: { table: "folders", onDelete: "set null" },
            },
          },
        },
        drafts: {
          scope: "user",
          columns: {
            project_id: { type: "uuid", references: { table: "projects" } },
          },
        },
      },
    });

    expect(schema?.contents).toContain(
      'add column if not exists "project_id" uuid not null;',
    );
    expect(schema?.contents).toContain(
      `create unique index if not exists "projects_organization_id_id_key" on "public"."projects" ("organization_id", id);`,
    );
    expect(schema?.contents).toContain(
      `alter table "public"."tasks" drop constraint if exists "tasks_project_id_fkey";
alter table "public"."tasks" add constraint "tasks_project_id_fkey" foreign key ("organization_id", "project_id") references "public"."projects" ("organization_id", id) on delete cascade;`,
    );
    expect(schema?.contents).toContain(
      `foreign key ("organization_id", "parent_id") references "public"."folders" ("organization_id", id) on delete set null ("parent_id");`,
    );
    expect(schema?.contents).toContain(
      `add column if not exists "project_id" uuid references "public"."projects" (id);`,
    );
    expect(test?.contents).toContain(
      `'public.tasks.project_id references a row of the same tenant'`,
    );
  });

  it("renders the golden SQL of rollups and lookups as a view", async () => {
    await expect(
      golden(render(BLOCKS, { appTables: COMPUTED })),
    ).toMatchFileSnapshot("__golden__/app-tables/computed.sql");
  });

  it("reads rollups and lookups through a security_invoker view", () => {
    const [schema, test] = render(BLOCKS, { appTables: COMPUTED });

    expect(schema?.contents).toContain(
      `create view "public"."projects_view" with (security_invoker = true) as`,
    );
    expect(schema?.contents).toContain(
      `left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'done') r0 on true`,
    );
    expect(schema?.contents).toContain(
      `left join lateral (select coalesce(sum(c."estimate"), 0) as value from "public"."tasks" c where c."project_id" = t.id) r1 on true`,
    );
    expect(schema?.contents).toContain(
      `left join lateral (select r."name" as value from "public"."projects" r where r.id = t."project_id") l0 on true`,
    );
    expect(schema?.contents).toContain(
      `grant select on "public"."tasks_view" to authenticated;`,
    );
    expect(test?.contents).toContain(
      `'public.projects_view runs with the caller''s row level security'`,
    );
    expect(test?.contents).toContain(
      `select extensions.is((select count(*)::integer from "public"."projects_view"), 0, 'a stranger sees no rows of public.projects_view');`,
    );
  });

  it("renders no view for a table without rollups or lookups", () => {
    const [schema] = render(BLOCKS, { appTables: TABLES });

    expect(schema?.contents).not.toContain("create view");
  });

  it("counts every check in the pgTAP plan", () => {
    const [, test] = render(BLOCKS, { appTables: COMPUTED });

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
      render(["tenant", "organizations", "tags"], { appTables: { tags: {} } }),
    ).toThrow(
      "appTables.tags: the tags block already keeps a table named tags; choose another name",
    );
  });

  it("refuses a composite key on a column the table lacks", () => {
    expect(() =>
      render(["updated-at"], {
        scope: "user",
        appTables: { items: { unique: [["organization_id"]] } },
      }),
    ).toThrow(
      'appTables.items.unique: the table has no column "organization_id" (id, user_id, created_at, updated_at)',
    );
  });

  it("refuses the renamed tenant table's name", () => {
    expect(() =>
      render(BLOCKS, {
        modules: { tenant: { entities: { organization: "workspace" } } },
        appTables: { workspaces: {} },
      }),
    ).toThrow("the organizations block already keeps a table named workspaces");
  });

  it("renders the golden SQL of events through the outbox", async () => {
    await expect(
      golden(
        render([...BLOCKS, "outbox"], {
          appTables: {
            tasks: {
              columns: {
                title: { type: "text", nullable: false },
                status: { type: "text", options: ["todo", "done"] },
              },
              subject: { type: "task" },
              events: { include: ["status"] },
            },
            notes: {
              columns: { body: { type: "text" } },
              events: { on: ["deleted"] },
            },
          },
        }),
      ),
    ).toMatchFileSnapshot("__golden__/app-tables/events.sql");
  });

  it("checks the auto snapshot trigger of a versioned subject", () => {
    const test = render([...BLOCKS, "versions"], {
      appTables: {
        tasks: {
          columns: { title: { type: "text" } },
          subject: { type: "task", versions: true },
        },
      },
    }).find((file) => file.kind === "test");

    expect(test?.contents).toContain(
      "select extensions.has_trigger('public'::name, 'tasks'::name, 'bs_versions_task_auto'::name, 'public.tasks snapshots a version on each change');",
    );
  });

  it("renders app_table_set for the bulk action over subject tables", () => {
    const schema = render([...BLOCKS, "access", "bulk"], {
      appTables: {
        tasks: {
          columns: {
            title: { type: "text" },
            number: { type: "bigint", identity: true },
          },
          subject: { type: "task" },
        },
        notes: { columns: { body: { type: "text" } } },
      },
    }).find((file) => file.kind === "schema")?.contents;

    expect(schema).toContain(
      'create or replace function public."app_table_set"(tenant uuid, subject_type text, subject_id text, args jsonb)',
    );
    expect(schema).toContain("only these columns of tasks can be set: title");
    expect(schema).toContain(
      `"title" = case when v_values ? 'title' then r."title" else t."title" end`,
    );
    expect(schema).toContain(
      `where t.id = app_table_set.subject_id::uuid\n        and t."organization_id" = app_table_set.tenant;`,
    );
    expect(schema).not.toContain("'note' then");
  });

  it("refuses subject versions without the versions block", () => {
    expect(() =>
      render(BLOCKS, {
        appTables: { tasks: { subject: { type: "task", versions: true } } },
      }),
    ).toThrow(
      "appTables.tasks.subject.versions needs the versions block; add it to blocks",
    );
  });

  it("refuses events without the outbox block", () => {
    expect(() =>
      render(BLOCKS, { appTables: { tasks: { events: true } } }),
    ).toThrow(
      "appTables.tasks.events needs the outbox block; add it to blocks",
    );
  });
});

describe("appTables column access", () => {
  const ACCESS: AppTablesConfig = {
    projects: {
      columns: {
        name: { type: "text", nullable: false },
        budget: { type: "numeric", access: "read" },
        internal_notes: { type: "text", access: "server" },
      },
      rollups: {
        open_tasks: { table: "tasks", via: "project_id", aggregate: "count" },
      },
    },
    tasks: {
      columns: {
        project_id: {
          type: "uuid",
          nullable: false,
          references: { table: "projects", onDelete: "cascade" },
        },
      },
    },
    rates: {
      scope: "none",
      columns: { cost: { type: "numeric", access: "server" } },
    },
  };

  it("renders column grants, the view's columns and the allow and deny checks", async () => {
    const files = render(BLOCKS, { appTables: ACCESS });
    const schema = files.find((file) => file.kind === "schema")?.contents;
    const test = files.find((file) => file.kind === "test")?.contents;

    expect(schema).toContain(
      'grant select ("id", "organization_id", "created_at", "updated_at", "name", "budget") on "public"."projects" to authenticated;',
    );
    expect(schema).toContain(
      'grant insert ("id", "organization_id", "created_at", "updated_at", "name"), update ("id", "organization_id", "created_at", "updated_at", "name") on "public"."projects" to authenticated;',
    );
    expect(schema).toContain(
      'grant select ("id", "created_at", "updated_at") on "public"."rates" to authenticated;',
    );
    expect(schema).not.toContain('t."internal_notes"');
    expect(test).toContain(
      "a signed-in user cannot read public.projects.internal_notes",
    );
    expect(test).toContain(
      "a signed-in user cannot write public.projects.budget",
    );

    await expect(golden(files)).toMatchFileSnapshot(
      "__golden__/app-tables/access.sql",
    );
  });

  it("refuses access on a table that expose grants", () => {
    expect(() =>
      render(BLOCKS, {
        appTables: ACCESS,
        grants: [
          { table: "public.projects", role: "anon", privileges: ["select"] },
        ],
      }),
    ).toThrow("expose sets the grants");
  });
});
