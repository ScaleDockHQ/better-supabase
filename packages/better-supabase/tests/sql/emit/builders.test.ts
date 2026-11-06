import { describe, expect, it } from "vitest";

import { addColumn } from "../../../src/sql/emit/column.ts";
import { commentOn } from "../../../src/sql/emit/comment.ts";
import {
  addCheckConstraint,
  addForeignKeyConstraint,
} from "../../../src/sql/emit/constraint.ts";
import { createFunction } from "../../../src/sql/emit/function.ts";
import { grantExecute, grantTable } from "../../../src/sql/emit/grant.ts";
import { createIndex } from "../../../src/sql/emit/index.ts";
import { createPolicy } from "../../../src/sql/emit/policy.ts";
import { createTable, enableRowSecurity } from "../../../src/sql/emit/table.ts";
import { createTrigger } from "../../../src/sql/emit/trigger.ts";

describe("statement builders", () => {
  it("writes a table, a column and row security", () => {
    expect(createTable("a.t", ["id uuid", "n int"])).toBe(
      "create table a.t (\n  id uuid,\n  n int\n);",
    );
    expect(
      createTable("a.t", ["id uuid"], " partition by range (id)"),
    ).toContain(") partition by range (id);");
    expect(addColumn("a.t", "x text")).toBe(
      "alter table a.t add column x text;",
    );
    expect(enableRowSecurity("a.t")).toBe(
      "alter table a.t enable row level security;",
    );
  });

  it("writes constraints without a drop or an existence test", () => {
    expect(
      addCheckConstraint({ table: "a.t", name: "c", expression: "n > 0" }),
    ).toBe("alter table a.t add constraint c\n  check (n > 0);");
    expect(
      addCheckConstraint({
        table: "a.t",
        name: "c",
        expression: "n > 0",
        notValid: true,
      }),
    ).toContain("not valid;");
    expect(
      addForeignKeyConstraint({
        table: "a.t",
        name: "fk",
        column: "p",
        references: "a.p (id)",
        onDelete: "cascade",
      }),
    ).toContain("foreign key (p) references a.p (id) on delete cascade;");
  });

  it("writes indexes, triggers, functions and policies", () => {
    expect(
      createIndex({
        name: "i",
        table: "a.t",
        columns: ["x", "y"],
        unique: true,
        where: "x is not null",
        using: "btree",
      }),
    ).toBe(
      "create unique index i on a.t using btree (x, y) where x is not null;",
    );
    expect(createIndex({ name: "i", table: "a.t", columns: ["x"] })).toBe(
      "create index i on a.t (x);",
    );
    expect(
      createTrigger({
        name: "tr",
        timing: "before",
        events: ["insert", "update"],
        table: "a.t",
        fn: "a.f",
        args: ["'x'"],
        when: "true",
      }),
    ).toBe(
      "create trigger tr before insert or update on a.t\n  for each row\n  when (true)\n  execute function a.f('x');",
    );
    expect(
      createFunction({
        name: "a.f",
        args: "",
        returns: "trigger",
        language: "plpgsql",
        security: "definer",
        volatility: "stable",
        body: "begin return new; end;",
      }),
    ).toContain("security definer\nset search_path = ''\nas $$");
    expect(
      createPolicy({
        name: "p",
        table: "a.t",
        permissive: false,
        command: "select",
        roles: ["authenticated"],
        using: "true",
        check: null,
      }),
    ).toBe(
      "create policy p on a.t as restrictive\n  for select to authenticated\n  using (true);",
    );
  });

  it("writes grants and comments", () => {
    expect(grantExecute("a.f()", ["service_role"])).toBe(
      "revoke execute on function a.f() from public;\ngrant execute on function a.f() to service_role;",
    );
    expect(grantTable("a.t", ["select", "insert"], ["authenticated"])).toBe(
      "grant select, insert on a.t to authenticated;",
    );
    expect(commentOn("table", "a.t", "it's")).toBe(
      "comment on table a.t is 'it''s';",
    );
  });
});
