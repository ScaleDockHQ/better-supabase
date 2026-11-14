import { describe, expect, it } from "vitest";

import type { OwnIndex } from "../../src/sql/schema-scan.ts";

import { moduleContext } from "../../src/sql/module-context.ts";
import { runsOverAppTables } from "../../src/sql/module-types.ts";
import {
  overAppTables,
  withoutAppTableEdits,
  IMPLIED_UNIQUE_MARK,
  withoutCoveredIndexes,
  withoutImpliedUniqueIndexes,
  withoutUnmappedColumns,
  withoutUnmappedTables,
} from "../../src/sql/over-app-tables.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import {
  ALONE,
  OVER,
  registerAdoptedTables,
} from "./over-app-tables-adopted.ts";

const SQL = `create table if not exists public.invoices (
  -- the tenant's id (it scopes every row)
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  status text not null default 'draft',
  code text not null unique,
  unique (organization_id, code)
);

create index invoices_status on public.invoices (status);
`;

describe("overAppTables", () => {
  it("keeps the given order for columns that read each other", () => {
    const sql = `create table if not exists public.pairs (
  id uuid primary key,
  "a" int check ("b" > 0),
  "b" int check ("a" > 0)
);
`;

    const out = overAppTables(sql, new Set(["public.pairs"]), {
      "public.pairs": ["id"],
    });

    expect(out.indexOf('"a" int')).toBeGreaterThan(-1);
    expect(out.indexOf('"b" int')).toBeGreaterThan(-1);
  });

  it("adds a column after the new column its check reads", () => {
    const sql = `create table if not exists public.contacts (
  id uuid primary key,
  "mode" text not null default 'a' check ("mode" = 'a' or "user_id" is not null),
  "user_id" uuid
);
`;

    const out = overAppTables(sql, new Set(["public.contacts"]), {
      "public.contacts": ["id"],
    });

    expect(out.indexOf('add column if not exists "user_id"')).toBeGreaterThan(
      -1,
    );
    expect(out.indexOf('add column if not exists "user_id"')).toBeLessThan(
      out.indexOf('add column if not exists "mode"'),
    );
  });

  it("turns the create table of an app table into the columns it lacks", () => {
    expect(
      overAppTables(SQL, new Set(["public.invoices"]), {
        "public.invoices": ["id", "status"],
      }),
    )
      .toBe(`-- public.invoices is the app's table: this block adds only the columns it needs.
alter table public.invoices add column if not exists organization_id uuid references public.organizations (id);
alter table public.invoices add column if not exists code text;

create index invoices_status on public.invoices (status);
`);
  });

  it("adds every column when the app's columns are unknown", () => {
    const out = overAppTables(SQL, new Set(["public.invoices"]));

    expect(out).not.toContain("create table");
    expect(out).toContain(
      "add column if not exists id uuid default gen_random_uuid();",
    );
    expect(out).toContain(
      "add column if not exists status text not null default 'draft';",
    );
  });

  it("leaves the tables the block owns", () => {
    expect(overAppTables(SQL, new Set(["public.contacts"]))).toBe(SQL);
  });
});

describe("ctx.owns", () => {
  it("is false for a table the app has, and casts only its typed columns", () => {
    const ctx = moduleContext(
      "tags",
      { ownTables: { "better_supabase.tags": "supabase/schemas/tags.sql" } },
      ["tags"],
    );

    expect(ctx.owns("tags")).toBe(false);
    expect(ctx.owns("taggings")).toBe(true);
    expect(ctx.appOwned).toEqual(["tags"]);
    expect(ctx.manages).toBe(true);
    expect(ctx.cast("tags", "kind", "'label'")).toContain(
      "better_supabase.as_column_type('label'",
    );
    expect(ctx.cast("taggings", "subjectType", "'deal'")).toBe("'deal'");
  });

  it("is true for every table without ownTables", () => {
    const ctx = moduleContext("tags", {}, ["tags"]);

    expect(ctx.owns("tags")).toBe(true);
    expect(ctx.cast("tags", "kind", "'label'")).toBe("'label'");
  });
});

registerAdoptedTables(0);

describe("blocks over the app's tables", () => {
  it("shapes its SQL to the app's table, not to the block's mode", () => {
    const sql = (ownTables: Record<string, string>) =>
      renderBlocks(["audit"], { ownTables })
        .filter((file) => file.module === "audit")
        .map((file) => file.contents)
        .join("\n");

    expect(sql({})).toContain("$15::bigint");
    expect(
      sql({ "better_supabase.audit_events": "supabase/schemas/audit.sql" }),
    ).not.toContain("$15::bigint");
  });

  it("covers every table of a module that runs over app tables", () => {
    const over = new Set(OVER.map(([module]) => module));

    expect(
      [...over].filter((module) => {
        const definition = SQL_MODULES[module];

        return definition === undefined || !runsOverAppTables(definition);
      }),
    ).toEqual([]);
  });
});

// The tables a module creates without a `names.tables` entry, by module.
const SPECLESS: Readonly<Record<string, readonly string[]>> = {
  // ADR 0235: chain() creates the table for any chained app table.
  audit: ["chain_checkpoints"],
  // ADR 0844: internal notes an import run clears when it closes.
  search: ["import_search_dirty"],
  // ADR 0098: the Workflow SDK owns the shape of its world's tables.
  "workflow-sdk": [
    "workflow_event_slots",
    "workflow_events",
    "workflow_hooks",
    "workflow_invocations",
    "workflow_job_lock_holders",
    "workflow_run_keys",
    "workflow_runs",
    "workflow_snapshots",
    "workflow_start_hook_admissions",
    "workflow_steps",
    "workflow_stream_chunks",
    "workflow_waits",
  ],
};

/** The modules registry every module writes its row to. */
const REGISTRY = "blocks";

const CREATE_TABLE =
  /create (?:unlogged )?table (?:if not exists )?"?\w+"?\."?(\w+)"?/giu;

describe("every block table", () => {
  it("can be the app's own table", () => {
    const missing = Object.entries(SQL_MODULES).flatMap(
      ([module, definition]) =>
        Object.entries(definition.names?.tables ?? {})
          .filter(([, spec]) => spec.app === undefined)
          .map(([table]) => `${module}.${table}`),
    );

    expect(missing).toEqual([]);
  });

  it("has a names.tables entry", () => {
    const specless = Object.fromEntries(
      ALONE.flatMap((module) => {
        const names = new Set(
          Object.values(SQL_MODULES[module]?.names?.tables ?? {}).map(
            (spec) => spec.name,
          ),
        );

        const tables = [
          ...new Set(
            renderBlocks([module])
              .filter((file) => file.module === module)
              .flatMap((file) =>
                [...file.contents.matchAll(CREATE_TABLE)].map(
                  (match) => match[1] ?? "",
                ),
              ),
          ),
        ].filter((table) => table !== REGISTRY && !names.has(table));

        return tables.length === 0 ? [] : [[module, tables.toSorted()]];
      }),
    );

    expect(specless).toEqual(SPECLESS);
  });
});

describe("withoutAppTableEdits", () => {
  const sql = `alter table public.members drop constraint if exists members_role_check;
alter table public.members
  add constraint members_role_check check (role in ('owner', 'member'));
alter table public.members alter column role drop not null;
alter table public.members add column if not exists note text;
alter table public.members enable row level security;
revoke all on public.members from anon, authenticated;
grant select on public.members to authenticated;
alter table public.other add constraint other_check check (true);
`;

  it("leaves out constraints, column changes and revokes on the app's tables", () => {
    expect(withoutAppTableEdits(sql, new Set(["public.members"]))).toBe(
      `alter table public.members add column if not exists note text;
alter table public.members enable row level security;
grant select on public.members to authenticated;
alter table public.other add constraint other_check check (true);
`,
    );
  });

  it("changes nothing without app tables", () => {
    expect(withoutAppTableEdits(sql, new Set())).toBe(sql);
  });
});

describe("withoutUnmappedColumns", () => {
  it("drops the column additions and indexes of columns mapped to null", () => {
    expect(
      withoutUnmappedColumns(
        `alter table t add column if not exists "bsb_unmapped:t.note" text;
create index if not exists t_note on t ("bsb_unmapped:t.note");
select 1;
`,
        "notes",
      ),
    ).toBe("select 1;\n");
  });

  it("throws when the block needs the column elsewhere", () => {
    expect(() =>
      withoutUnmappedColumns(`select "bsb_unmapped:t.note" from t;`, "notes"),
    ).toThrow(
      'Module "notes" needs t.note, which blocks.notes.columns maps to null',
    );
  });
});

describe("withoutUnmappedTables", () => {
  it("drops the statements that build or change a table mapped to null", () => {
    expect(
      withoutUnmappedTables(
        `create table if not exists s."bsb_unmapped_table:extras" (id uuid);
create index if not exists extras_idx on s."bsb_unmapped_table:extras" (id);
create policy bsb_unmapped_table:extras_read on s."bsb_unmapped_table:extras" for select using (true);
create function f() returns int language sql as $$ select 1; $$;
`,
        "notes",
      ),
    ).toBe(
      "\ncreate function f() returns int language sql as $$ select 1; $$;\n",
    );
  });

  it("throws when a function needs the table", () => {
    expect(() =>
      withoutUnmappedTables(
        `create function f() returns int language sql as $$ select count(*) from s."bsb_unmapped_table:extras"; $$;`,
        "notes",
      ),
    ).toThrow(
      'Module "notes" needs table "extras", which blocks.notes.tables maps to null',
    );
  });
});

describe("withoutCoveredIndexes", () => {
  const sql = `create index if not exists members_user_idx on "public"."members" ("user_id");
create index if not exists members_pair_idx on "public"."members" ("organization_id", "user_id");
create index if not exists members_lower_idx on "public"."members" (lower("email"));
create unique index if not exists members_one on "public"."members" ("organization_id");
create index if not exists members_partial on "public"."members" ("team_id") where "team_id" is not null;
create index if not exists members_gin on "public"."members" using gin ("tags");
create index if not exists other_idx on "public"."others" ("organization_id");
`;

  it("drops a plain index an app index with the same leading columns covers", () => {
    const out = withoutCoveredIndexes(sql, new Set(["public.members"]), {
      "public.members": [
        {
          name: "members_by_org",
          columns: ["organization_id", "user_id", "team_id"],
        },
        { columns: ["team_id"] },
        { name: "members_user_idx", columns: ["user_id"] },
      ],
    });

    expect(out).toContain(
      "-- public.members already has an index on (organization_id, user_id), so this block adds none.",
    );
    expect(out).toContain("members_user_idx");
    expect(out).toContain("members_lower_idx");
    expect(out).toContain("members_one");
    expect(out).toContain("members_partial");
    expect(out).toContain("members_gin");
    expect(out).toContain("other_idx");
    expect(out).not.toContain("members_pair_idx");
  });

  it("leaves the SQL alone without app tables or known indexes", () => {
    expect(withoutCoveredIndexes(sql, new Set())).toBe(sql);
    expect(withoutCoveredIndexes(sql, new Set(["public.members"]), {})).toBe(
      sql,
    );
  });

  it("skips the teams index the app's membership index covers", () => {
    const files = renderBlocks(["teams"], {
      modules: {
        teams: {
          tables: { teams: "public.teams", members: "public.team_members" },
          columns: { members: { tenant: "organization_id" } },
        },
      },
      ownTables: {
        "public.teams": "app.sql",
        "public.team_members": "app.sql",
      },
      ownIndexes: {
        "public.team_members": [
          { columns: ["organization_id", "user_id", "team_id"] },
        ],
      },
    });

    const out = files.map((file) => file.contents).join("\n");

    expect(out).toContain("team_members_user_idx");
    expect(out).not.toContain("team_members_membership_idx");
    expect(out).toContain(
      "-- public.team_members already has an index on (organization_id, user_id)",
    );
  });
});

describe("withoutImpliedUniqueIndexes", () => {
  const sql = `create unique index if not exists a_key on "public"."t" ("org", "kind", "number");
create unique index if not exists b_key on "public"."t" ("org", "id");
${IMPLIED_UNIQUE_MARK}
create unique index if not exists c_key on "public"."t" ("org", "kind", "code");
create unique index if not exists d_key on "public"."t" ("x") nulls not distinct;
`;

  const tables = new Set(["public.t"]);

  it("leaves out an index over the app's unique key, and a marked one it implies", () => {
    const out = withoutImpliedUniqueIndexes(sql, tables, {
      "public.t": [
        { name: "mine", columns: ["org", "number"], unique: true },
        { name: "ids", columns: ["id", "org"], unique: true },
        { name: "codes", columns: ["org", "code"], unique: true },
        { columns: ["x"], unique: true },
      ],
    });

    // The weaker key is only left out when the module marks it.
    expect(out).toContain("create unique index if not exists a_key");
    expect(out).not.toContain("b_key on");
    expect(out).toContain(
      "-- public.t already has a unique key on (org, code), so this block adds none.",
    );

    expect(out).toContain("d_key");
    expect(out).not.toContain(IMPLIED_UNIQUE_MARK);
  });

  it("keeps a key an expression index does not imply", () => {
    const out = withoutImpliedUniqueIndexes(sql, tables, {
      "public.t": [
        { name: "expr", columns: ["org"], unique: true, plain: false },
      ],
    });

    expect(out).toContain("a_key");
    expect(out).toContain("b_key");
    expect(out).toContain("c_key");
  });

  it("keeps every index when the app has no unique key over them", () => {
    const out = withoutImpliedUniqueIndexes(sql, tables, {
      "public.t": [{ columns: ["org", "number"] }],
    });

    expect(out).toBe(sql.replace(`${IMPLIED_UNIQUE_MARK}\n`, ""));
  });

  it("renders invoices without a number key the app's stricter key implies", () => {
    const render = (ownIndexes: Record<string, OwnIndex[]>): string =>
      renderBlocks(["invoices"], {
        ownTables: { "public.invoices": "app.sql" },
        ownIndexes,
        modules: { invoices: { tables: { invoices: "public.invoices" } } },
      })
        .filter((entry) => entry.module === "invoices")
        .map((entry) => entry.contents)
        .join("\n");

    const key = "invoices_tenant_id_direction_kind_identifier_key";

    expect(render({})).toContain(key);

    const stricter = render({
      "public.invoices": [
        { name: "mine", columns: ["tenant_id", "identifier"], unique: true },
      ],
    });

    expect(stricter).not.toContain(key);
    expect(stricter).not.toContain(IMPLIED_UNIQUE_MARK);
  });
});
