import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "enrollments" && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("enrollments module", () => {
  it("writes the tables, their read policies and the functions", () => {
    const sql = sqlOf(["enrollments"]);

    expect(sql).toMatch(/create table if not exists \S+"enrollment_programs"/);
    expect(sql).toMatch(/create table if not exists \S+"enrollments"/);
    expect(sql).toMatch(/create table if not exists \S+"enrollment_steps"/);
    expect(sql).toContain("unique nulls not distinct");
    expect(sql).toContain("'enrollments.read'");
    expect(sql).toContain("'enrollments.enroll'");
    expect(sql).toContain("'enrollments.manage'");
    expect(sql).toContain("a program holds at most 100 steps");
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."enrollment_mark"',
    );
    expect(sql).not.toContain("emit_event");
  });

  it("writes events and audit entries with the outbox and audit", () => {
    const sql = sqlOf(["outbox", "audit", "enrollments"]);

    expect(sql).toContain("'enrollment.step_completed'");
    expect(sql).toContain("'enrollment.completed'");
    expect(sql).toContain("'enrollment_program.created'");
    expect(sql).toContain("audit_event");
  });

  it("renders step assignees and due dates into the steps", () => {
    const sql = sqlOf(["enrollments"]);

    expect(sql).toContain('"assignee_role" text');
    expect(sql).toContain('"assignee_user_id" uuid references auth.users');
    expect(sql).toContain('"due_at" timestamptz');
    expect(sql).toContain('"starts_at" timestamptz');
    expect(sql).toContain('"ends_at" timestamptz');
    expect(sql).toContain('"completed_at" timestamptz default now()');
    expect(sql).toContain("a step due date is { days, from }");
    expect(sql).toMatch(/function \S+"enrollment_schedule"\(target uuid\)/);
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."enrollment_schedule"',
    );
    expect(sql).toMatch(/function \S+"set_enrollment_dates"\(/);
    expect(sql).toMatch(/function \S+"open_enrollment_steps"\(/);
    expect(sql).toContain(
      'perform "better_supabase"."enrollment_schedule"(v_id);',
    );
  });

  it("leaves schedules out when an adopted table has no columns for them", () => {
    const sql = sqlOf(["enrollments"], {
      modules: { enrollments: { columns: { steps: { dueAt: null } } } },
    });

    expect(sql).not.toContain("enrollment_schedule");
    expect(sql).not.toContain("set_enrollment_dates");
    expect(sql).not.toContain("open_enrollment_steps");
    expect(sql).not.toContain("'schedule'");
  });

  it("takes maxSteps from the options", () => {
    expect(
      sqlOf(["enrollments"], {
        modules: { enrollments: { options: { maxSteps: 12 } } },
      }),
    ).toContain("a program holds at most 12 steps");

    expect(() =>
      sqlOf(["enrollments"], {
        modules: { enrollments: { options: { maxSteps: 0 } } },
      }),
    ).toThrow("blocks.enrollments.options.maxSteps must be a whole number");
  });

  it("renders nothing for its tables in custom mode", () => {
    const sql = sqlOf(["enrollments"], {
      modules: { enrollments: { mode: "custom" } },
    });

    expect(sql).not.toContain("create table");
  });

  it("renders before onboarding", () => {
    const order = renderBlocks(["onboarding"], {})
      .filter((file) => file.kind === "schema")
      .map((file) => file.module);

    expect(order.indexOf("enrollments")).toBeLessThan(
      order.indexOf("onboarding"),
    );
  });
});
