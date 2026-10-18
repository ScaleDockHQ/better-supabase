import { resolveConfig } from "better-supabase/config";
import {
  encodePreset,
  namedPreset,
  type Preset,
  type PresetName,
} from "better-supabase/preset";
import { moduleLayout, renderModules } from "better-supabase/sql";
import { describe, expect, test } from "vitest";

import {
  parseSchema,
  type SchemaSource,
  schemaRelations,
  tenantColumnOf,
} from "../../lib/schema";

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
  for (const name of ["saas", "commerce", "everything"] as const) {
    test(`reads every create table in the ${name} preset`, () => {
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
          table.columnCount === 0 ||
          table.keyColumns.length > table.columnCount ||
          !modules.has(table.module),
      );

      expect(wrong.map((table) => table.id)).toEqual([]);
    });
  }

  test("reads primary keys, foreign keys and the tenant column", () => {
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
    expect(organizations?.keyColumns[0]).toEqual({ name: "id", type: "uuid" });

    const relations = schemaRelations(tables);
    expect(relations.some((each) => each.to === "auth.users")).toBe(true);
    expect(
      new Set(relations.map((each) => `${each.from}>${each.to}`)).size,
    ).toBe(relations.length);
  });

  test("follows the preset's tenant name", () => {
    const { files, tenantColumn } = rendered("saas", {
      tenantName: "workspace",
    });

    expect(tenantColumn).toBe("workspace_id");

    const tables = parseSchema(files, { tenantColumn });
    expect(
      tables.find((table) => table.name === "memberships")?.tenantColumn,
    ).toBe("workspace_id");
    expect(tenantColumnOf({ ...namedPreset("saas"), scope: "user" })).toBe(
      null,
    );
  });

  test("reads table constraints and later alter table statements", () => {
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
        },
        {
          columns: ["owner"],
          target: { schema: "auth", table: "users", columns: ["id"] },
        },
        {
          columns: ["tenant_id"],
          target: { schema: "app", table: "tenants", columns: ["id"] },
        },
      ],
      tenantColumn: null,
      keyColumns: [
        { name: "order_id", type: "uuid" },
        { name: "position", type: "integer" },
        { name: "owner", type: "uuid" },
        { name: "tenant_id", type: "uuid" },
      ],
      columnCount: 6,
    });
  });

  test("throws on a create table it can't read", () => {
    expect(() =>
      parseSchema([
        { path: "b.sql", module: "b", contents: "\ncreate table %I.%I ();" },
      ]),
    ).toThrow("b.sql:2");
  });
});
