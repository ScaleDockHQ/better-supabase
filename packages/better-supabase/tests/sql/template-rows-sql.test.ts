import { describe, expect, it } from "vitest";

import { templateGuardSql } from "../../src/sql/template-rows-sql.ts";

describe("templateGuardSql", () => {
  it("fixes the trigger function's search_path", () => {
    const sql = templateGuardSql({
      fn: "public.task_template_guard",
      trigger: "task_template",
      table: "public.tasks",
      column: "template_id",
      hint: "TASK_TEMPLATE_IMMUTABLE",
    });

    expect(sql).toMatch(
      /create or replace function public\.task_template_guard\(\)\nreturns trigger\nlanguage plpgsql\nset search_path = ''\nas \$\$/u,
    );
  });
});
