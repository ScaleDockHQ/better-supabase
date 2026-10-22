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
    expect(sql).toContain("'enrollment_program.saved'");
    expect(sql).toContain("audit_event");
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
