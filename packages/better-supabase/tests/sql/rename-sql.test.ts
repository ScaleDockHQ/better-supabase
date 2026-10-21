import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import {
  nameMigrationSql,
  qualified,
  renameColumn,
  renameTable,
  unquote,
} from "../../src/sql/rename-sql.ts";

describe("rename helpers", () => {
  it("reads quoted and bare names, with the schema as a fallback", () => {
    expect(qualified('"app"."my ""table"""', "x")).toEqual({
      schema: "app",
      name: 'my "table"',
    });
    expect(qualified("notes", "app")).toEqual({ schema: "app", name: "notes" });
    expect(unquote("plain")).toBe("plain");
  });

  it("guards a table rename on the old name existing and the new one free", () => {
    expect(
      renameTable(
        { schema: "app", name: "notes" },
        { schema: "app", name: "comments" },
      ),
    ).toBe(
      `do $$ begin if to_regclass('"app"."notes"') is not null and to_regclass('"app"."comments"') is null then alter table "app"."notes" rename to "comments"; end if; end $$;`,
    );
    expect(renameColumn({ schema: "app", name: "c" }, "a", "b")).toContain(
      "column_name = 'a'",
    );
  });
});

describe("nameMigrationSql", () => {
  const ctx = moduleContext("comments");

  it("renames only the columns when the table kept its name", () => {
    const sql = nameMigrationSql(ctx, {
      from: 1,
      description: "",
      table: "comments",
      columns: { body: "text", parent: "parent_id" },
    });

    expect(sql).toContain('rename column "text" to "body"');
    expect(sql).not.toContain("parent_id");
    expect(sql).not.toContain('alter table "better_supabase"."notes"');
  });

  it("renders nothing for a table the config leaves out", () => {
    expect(
      nameMigrationSql(
        moduleContext("invitations", {
          modules: { invitations: { tables: { platformInvitations: null } } },
        }),
        {
          from: 1,
          description: "",
          table: "platformInvitations",
          was: "staff_invitations",
        },
      ),
    ).toBe("");
  });

  it("rejects a table the module doesn't declare", () => {
    expect(SQL_MODULES["comments"]?.names?.tables).not.toHaveProperty(
      "missing",
    );
    expect(() =>
      nameMigrationSql(ctx, {
        from: 1,
        description: "",
        table: "missing",
        was: "gone",
      }),
    ).toThrow('Module "comments" has no table "missing"');
  });
});
