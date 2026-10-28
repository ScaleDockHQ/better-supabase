import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "templates")
    .map((file) => file.contents)
    .join("\n");

describe("recurring records", () => {
  it("keeps schedules with their rules in reminders' recurrence_rules", () => {
    const sql = sqlOf(["reminders", "templates"]);

    expect(sql).toContain(`"better_supabase"."template_schedules"`);
    expect(sql).toContain(`primary key ("schedule_id", "occurrence_at")`);
    expect(sql).toContain(`'template_schedule'`);
    expect(sql).toContain("TEMPLATE_SCHEDULE_INVALID");
    expect(sql).toContain("pg_catalog.pg_timezone_names");
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."claim_template_occurrence"\(uuid, timestamptz\) to service_role;/,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."save_template_schedule"\([^)]*\) to authenticated, service_role;/,
    );
    expect(sql).toContain(
      `create trigger "bsb_template_schedule_removed" after delete`,
    );
  });

  it("renders nothing without reminders, or with its column rules", () => {
    expect(sqlOf(["templates"])).not.toContain("template_schedules");
    expect(
      sqlOf(["reminders", "templates"], {
        modules: { reminders: { options: { ruleFormat: "columns" } } },
      }),
    ).not.toContain("template_schedules");
    expect(
      sqlOf(["reminders", "templates"], {
        modules: { templates: { tables: { schedules: null } } },
      }),
    ).not.toContain("save_template_schedule");
  });

  it("lists the schedule functions in the contract only with reminders", () => {
    const templates = SQL_MODULES["templates"];

    expect(templates?.integrates).toContain("reminders");
    expect(templates?.internal).toContain("template_brand");
  });
});
