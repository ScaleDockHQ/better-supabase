import { describe, expect, it } from "vitest";

import { appTablesOf, isAppDefault } from "../../src/config/app-tables.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("resolveConfig appTables", () => {
  it("defaults to no app tables", () => {
    expect(resolveConfig({}, "/app").appTables).toEqual({});
  });

  it("keeps a valid table as written", () => {
    const appTables = {
      projects: {
        columns: {
          name: { type: "text", nullable: false },
          budget: { type: "bigint", default: "0" },
          currency: { type: "text", default: "'EUR'" },
          owner: {
            type: "uuid",
            references: { table: "auth.users", onDelete: "set null" },
          },
        },
      },
      tasks: {
        scope: "user",
        timestamps: false,
        columns: {
          project_id: {
            type: "uuid",
            nullable: false,
            references: { table: "projects", onDelete: "cascade" },
          },
          contact_id: {
            type: "uuid",
            references: { block: "crm", table: "contacts" },
          },
          labels: { type: "text[]", default: "'{}'" },
        },
      },
    } as const;

    expect(resolveConfig({ appTables }, "/app").appTables).toEqual(appTables);
  });
});

describe("appTablesOf", () => {
  const fails = (value: unknown, message: string, tenant?: string): void => {
    expect(() => appTablesOf(value, tenant)).toThrow(
      expect.objectContaining({
        name: "TypeError",
        message: expect.stringContaining(message),
      }),
    );
  };

  it("refuses a table name that isn't lower snake", () => {
    fails(
      { Projects: {} },
      'appTables.Projects: "Projects" is not a lower snake',
    );
    fails({ pg_things: {} }, "appTables.pg_things");
  });

  it("refuses unknown keys", () => {
    fails({ a: { rls: true } }, 'appTables.a: unknown key "rls"');
    fails(
      { a: { columns: { b: { type: "text", check: "x" } } } },
      'appTables.a.columns.b: unknown key "check"',
    );
  });

  it("refuses the reserved columns", () => {
    for (const name of ["id", "created_at", "updated_at", "user_id"]) {
      fails(
        { a: { columns: { [name]: { type: "text" } } } },
        `appTables.a.columns.${name}: "${name}" is a column every app table gets`,
      );
    }

    fails(
      { a: { columns: { organization_id: { type: "uuid" } } } },
      "organization_id",
    );
    fails(
      { a: { columns: { workspace_id: { type: "uuid" } } } },
      "workspace_id",
      "workspace",
    );
    expect(
      appTablesOf(
        { a: { columns: { organization_id: { type: "uuid" } } } },
        "workspace",
      ),
    ).toBeDefined();
  });

  it("refuses a type outside the list and points money at minor units", () => {
    fails(
      { a: { columns: { b: { type: "varchar" } } } },
      "appTables.a.columns.b.type must be one of text, uuid",
    );
    fails(
      { a: { columns: { price: { type: "money" } } } },
      "bigint minor units next to a text currency column",
    );
  });

  it("refuses a default outside the allowlist", () => {
    fails(
      {
        a: { columns: { b: { type: "text", default: "now(); drop table x" } } },
      },
      "appTables.a.columns.b.default",
    );
    fails(
      { a: { columns: { b: { type: "integer", default: "now()" } } } },
      "is not an allowed integer default",
    );
  });

  it("refuses a scope outside the list", () => {
    fails(
      { a: { scope: "tenant" } },
      "appTables.a.scope must be inherit, user or none",
    );
  });

  it("refuses a reference to a table that is neither an app table nor auth.users", () => {
    fails(
      {
        a: {
          columns: { b: { type: "uuid", references: { table: "missing" } } },
        },
      },
      'appTables.a.columns.b.references.table: "missing" is neither an app table',
    );
    fails(
      {
        a: {
          columns: { b: { type: "text", references: { table: "auth.users" } } },
        },
      },
      "needs a uuid column, not text",
    );
    fails(
      {
        a: {
          columns: {
            b: {
              type: "uuid",
              nullable: false,
              references: { table: "auth.users", onDelete: "set null" },
            },
          },
        },
      },
      '"set null" needs a nullable column',
    );
    fails(
      {
        a: {
          columns: {
            b: {
              type: "uuid",
              references: { block: "Crm", table: "contacts" },
            },
          },
        },
      },
      "references.block must be a block name",
    );
  });

  it("refuses values of the wrong shape", () => {
    const column = (value: unknown): unknown => ({
      a: { columns: { b: value } },
    });

    const reference = (value: unknown): unknown =>
      column({ type: "uuid", references: value });

    fails([], "appTables must be an object keyed by table name");
    fails({ a: "table" }, "appTables.a must be an object");
    fails({ a: { columns: [] } }, "appTables.a.columns must be an object");
    fails({ a: { columns: { B: { type: "text" } } } }, "appTables.a.columns.B");
    fails(column("text"), "appTables.a.columns.b must be an object");
    fails(column({ type: "text", unique: "yes" }), "must be true or false");
    fails(reference("auth.users"), "references must be an object");
    fails(reference({ table: 1 }), "references.table must be a string");
    fails(reference({ table: "auth.users", onDelete: "drop" }), "onDelete");
    fails(
      reference({ block: "crm", table: "Contacts" }),
      '"Contacts" is not a logical table name of the crm block',
    );
  });
});

describe("isAppDefault", () => {
  it.each([
    ["timestamptz", "now()", true],
    ["uuid", "gen_random_uuid()", true],
    ["uuid", "auth.uid()", true],
    ["boolean", "false", true],
    ["integer", "-12", true],
    ["integer", "1.5", false],
    ["numeric", "1.5", true],
    ["text", "'it''s'", true],
    ["text", "'a' || 'b'", false],
    ["jsonb", "'{}'", true],
    ["jsonb", "'[]'", true],
    ["text[]", "'[]'", false],
  ] as const)("%s accepts %s: %s", (type, value, expected) => {
    expect(isAppDefault(type, value)).toBe(expected);
  });
});
