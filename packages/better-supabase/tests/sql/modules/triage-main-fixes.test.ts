import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

/**
 * Regression tests for fixes that landed on main before the declarative base
 * layer work: each one reads the rendered module, so a later rewrite of the
 * emitters can't drop the behavior unnoticed.
 */
const sqlOf = (name: string): string => moduleBody(name, { modules: {} })!;

/** The body of the function `name`, up to the next `create or replace`. */
function functionBody(sql: string, name: string): string {
  const start = sql.indexOf(`function "better_supabase"."${name}"`);

  expect(start, `${name} is rendered`).toBeGreaterThan(-1);

  const next = sql.indexOf("create or replace function", start + 1);

  return sql.slice(start, next === -1 ? undefined : next);
}

describe("audit statement triggers", () => {
  it("write the restricted rows of a statement next to its entries", () => {
    const sql = moduleBody("audit", {
      modules: { audit: { options: { restricted: true } } },
    })!;

    const start = sql.indexOf(
      "function better_supabase.audit_statement_change()",
    );

    const body = sql.slice(
      start,
      sql.indexOf("create or replace function", start + 1),
    );

    expect(body).toContain("audit_events_restricted");
    expect(body).toMatch(/insert into [^\n]*audit_events_restricted/u);
    expect(sql).toContain(
      "referencing new table as new_rows for each statement",
    );
  });
});

describe("approval_eligible_ids", () => {
  it("answers with one set-based query and asks the authorizer once per permission", () => {
    const sql = sqlOf("approvals");
    const body = functionBody(sql, "approval_eligible_ids_in");

    expect(body).toContain("returns setof uuid");
    expect(body).toContain("needs as materialized");
    expect(body).toContain("granted as materialized");
    expect(body).toContain(
      "cross join lateral better_supabase.tenant_ids_with(k.p)",
    );
    expect(body).not.toContain("better_supabase.can(");
    expect(body).not.toMatch(/\bfor\s+\w+\s+in\b|\bloop\b/iu);
    expect(functionBody(sql, "approval_eligible_ids")).toContain(
      '"better_supabase"."approval_eligible_ids_in"(case when approval_eligible_ids.tenant is null then null else array[approval_eligible_ids.tenant] end)',
    );
  });

  it("is one stable query that writes no setting", () => {
    const body = functionBody(sqlOf("approvals"), "approval_eligible_ids_in");

    expect(body).toMatch(/language plpgsql\s+stable/u);
    expect(body).not.toContain("set_config");
    expect(body).not.toContain("memo_slot");
  });
});

describe("task set forms", () => {
  it("archive and delete a set of tasks in one statement", () => {
    const sql = sqlOf("tasks");

    expect(functionBody(sql, "archive_tasks")).toContain("ids uuid[]");
    expect(functionBody(sql, "delete_tasks")).toContain("ids uuid[]");
  });
});

describe("streams", () => {
  it("keep chunks as bytea and append an array of them", () => {
    const sql = sqlOf("streams");

    expect(sql).toMatch(/"data"\s+bytea not null/u);
    expect(sql).toContain("chunks bytea[]");
  });
});
