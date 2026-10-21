import { describe, expect, it } from "vitest";

import type { SchemaSource } from "../../src/create/index.ts";
import type { Preset, PresetName } from "../../src/preset/index.ts";

import { resolveConfig } from "../../src/config/index.ts";
import {
  parseSchema,
  schemaRelations,
  tableStatements,
  tenantColumnOf,
} from "../../src/create/index.ts";
import { encodePreset, namedPreset } from "../../src/preset/index.ts";
import { moduleLayout, renderModules } from "../../src/sql/index.ts";

interface Rendered {
  readonly files: readonly SchemaSource[];
  readonly tenantColumn: string | null;
}

function rendered(name: PresetName, overrides: Partial<Preset> = {}): Rendered {
  const preset = { ...namedPreset(name), ...overrides };
  const config = resolveConfig({ preset: encodePreset(preset) }, "/");

  return {
    files: renderModules(config.blockNames, moduleLayout(config)),
    tenantColumn: tenantColumnOf(preset),
  };
}

const CREATE_NAME =
  /^\s*create\s+table\s+if\s+not\s+exists\s+("?[a-z_]+"?)\s*\.\s*("?[a-z_]+"?)\s*\(/gimu;

/** Every `create table` a file starts on its own line, read with a plain regex. */
function createdTables(files: readonly SchemaSource[]): Set<string> {
  return new Set(
    files.flatMap((file) =>
      [...file.contents.matchAll(CREATE_NAME)].map(
        (match) =>
          `${(match[1] ?? "").replaceAll('"', "")}.${(match[2] ?? "").replaceAll('"', "")}`,
      ),
    ),
  );
}

describe("parseSchema", () => {
  it.each(["saas", "commerce", "everything"] as const)(
    "reads every create table in the %s preset",
    (name) => {
      const { files, tenantColumn } = rendered(name);
      const tables = parseSchema(files, { tenantColumn });
      const ids = new Set(tables.map((table) => table.id));

      const missing = [...createdTables(files)].filter(
        (id) => id !== "better_supabase.modules" && !ids.has(id),
      );

      expect(missing).toEqual([]);

      const modules = new Set(files.map((file) => file.module));

      const wrong = tables.filter(
        (table) =>
          table.columns.length === 0 ||
          table.primaryKey.some(
            (key) => !table.columns.some((column) => column.name === key),
          ) ||
          !modules.has(table.module),
      );

      expect(wrong.map((table) => table.id)).toEqual([]);
    },
  );

  it("reads primary keys, foreign keys and the tenant column", () => {
    const { files, tenantColumn } = rendered("saas");
    const tables = parseSchema(files, { tenantColumn });
    const byId = new Map(tables.map((table) => [table.id, table]));

    expect(byId.has("better_supabase.modules")).toBe(false);

    const memberships = byId.get("better_supabase.memberships");
    expect(memberships?.module).toBe("tenant");
    expect(memberships?.tenantColumn).toBe("organization_id");
    expect(memberships?.foreignKeys.map((key) => key.target.table)).toContain(
      "organizations",
    );

    const organizations = byId.get("better_supabase.organizations");
    expect(organizations?.primaryKey).toEqual(["id"]);
    expect(organizations?.columns[0]).toMatchObject({
      name: "id",
      type: "uuid",
      nullable: false,
    });

    const relations = schemaRelations(tables);
    expect(relations.some((each) => each.to === "auth.users")).toBe(true);
    expect(
      new Set(relations.map((each) => `${each.from}>${each.to}`)).size,
    ).toBe(relations.length);
  });

  it("follows the preset's tenant name", () => {
    const { files, tenantColumn } = rendered("saas", {
      tenantName: "workspace",
    });

    expect(tenantColumn).toBe("workspace_id");

    const tables = parseSchema(files, { tenantColumn });
    expect(
      tables.find((table) => table.name === "memberships")?.tenantColumn,
    ).toBe("workspace_id");
    expect(
      tenantColumnOf({ ...namedPreset("saas"), scope: "user" }),
    ).toBeNull();
  });

  it("reads table constraints and later alter table statements", () => {
    const [table] = parseSchema([
      {
        path: "a.sql",
        module: "a",
        contents: `
          -- create table ignored.in_comment (id int);
          create table if not exists "app"."lines" (
            "order_id" uuid not null,
            "position" integer not null,
            "price" numeric(12, 2) default 0,
            "note" text check (note <> 'create table x ('),
            constraint lines_pk primary key ("order_id", "position"),
            foreign key ("order_id") references app.orders (id) on delete cascade
          );
          alter table "app"."lines" add column if not exists "owner" uuid references auth.users (id),
            add column "tenant_id" uuid;
          alter table app.lines add constraint lines_tenant foreign key (tenant_id) references app.tenants (id) not valid;
        `,
      },
    ]);

    expect(table).toEqual({
      id: "app.lines",
      schema: "app",
      name: "lines",
      module: "a",
      primaryKey: ["order_id", "position"],
      foreignKeys: [
        {
          columns: ["order_id"],
          target: { schema: "app", table: "orders", columns: ["id"] },
          onDelete: "cascade",
        },
        {
          columns: ["owner"],
          target: { schema: "auth", table: "users", columns: ["id"] },
          onDelete: "no action",
        },
        {
          columns: ["tenant_id"],
          target: { schema: "app", table: "tenants", columns: ["id"] },
          onDelete: "no action",
        },
      ],
      tenantColumn: null,
      columns: [
        {
          name: "order_id",
          type: "uuid",
          nullable: false,
          default: null,
          unique: false,
        },
        {
          name: "position",
          type: "integer",
          nullable: false,
          default: null,
          unique: false,
        },
        {
          name: "price",
          type: "numeric(12, 2)",
          nullable: true,
          default: "0",
          unique: false,
        },
        {
          name: "note",
          type: "text",
          nullable: true,
          default: null,
          unique: false,
        },
        {
          name: "owner",
          type: "uuid",
          nullable: true,
          default: null,
          unique: false,
        },
        {
          name: "tenant_id",
          type: "uuid",
          nullable: true,
          default: null,
          unique: false,
        },
      ],
    });
  });

  it("throws on a create table it can't read", () => {
    expect(() =>
      parseSchema([
        { path: "b.sql", module: "b", contents: "\ncreate table %I.%I ();" },
      ]),
    ).toThrow("b.sql:2");
  });
});

describe("tableStatements", () => {
  const files: readonly SchemaSource[] = [
    {
      path: "a.sql",
      module: "a",
      contents: `-- create table app.lines (in a comment);
create table if not exists app.lines (
  id uuid primary key,
  note text default ';'
);
create table app.other (id int);
alter table app.lines enable row level security;
`,
    },
    {
      path: "b.sql",
      module: "b",
      contents: "alter table app.lines add column owner uuid;\n",
    },
  ];

  it("returns the create table and the later alter table statements, as written", () => {
    expect(
      tableStatements(files, "app.lines").map((each) => each.trim()),
    ).toEqual([
      "create table if not exists app.lines (\n  id uuid primary key,\n  note text default ';'\n);",
      "alter table app.lines enable row level security;",
      "alter table app.lines add column owner uuid;",
    ]);
  });

  it("is empty for a table no file creates", () => {
    expect(tableStatements(files, "app.missing")).toEqual([]);
  });
});
