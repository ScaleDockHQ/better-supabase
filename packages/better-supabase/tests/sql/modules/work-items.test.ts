import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderModules>[1] = {},
  extra: readonly string[] = [],
): string =>
  renderModules([module, ...extra], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("work-items module", () => {
  it("binds work items to pipelines per team with Linear's categories", () => {
    const pipelines = body("pipelines", {}, ["work-items"]);
    expect(pipelines).toContain(
      'create trigger bs_pipeline_work_item before insert or update of "stage_id", "pipeline_id" on "better_supabase"."work_items"',
    );
    expect(pipelines).toContain('new."team_id"::text');
    expect(pipelines).toContain("('in_review', 'In review', 'started', 'open'");
    expect(pipelines).toContain("when 'canceled' then 'canceled'");
  });

  it("renders projects and iterations unless turned off", () => {
    const all = body("work-items");
    expect(all).toContain('references "better_supabase"."projects"');
    expect(all).toContain("save_iteration");

    const bare = body("work-items", {
      modules: {
        "work-items": { tables: { projects: null, iterations: null } },
      },
    });

    expect(bare).not.toContain("save_project");
    expect(bare).not.toContain('references "better_supabase"."projects"');
  });

  it("caps assignees, notifies them and uses number-sequences when configured", () => {
    expect(
      body("work-items", {
        modules: { "work-items": { options: { maxAssignees: 1 } } },
      }),
    ).toContain("cardinality(v_users) > 1");
    expect(body("work-items")).not.toContain("WORK_ITEM_ASSIGNEES_LIMIT");
    expect(body("work-items", {}, ["notifications"])).toContain(
      "'type', 'work_item.assigned'",
    );
    expect(
      body(
        "work-items",
        {
          modules: {
            "number-sequences": {
              options: {
                entities: { work_item: { period: "none", format: "ENG-{n}" } },
              },
            },
          },
        },
        ["number-sequences"],
      ),
    ).toContain("format_assigned_number('ENG-{n}'");
    expect(
      body(
        "work-items",
        {
          modules: {
            "number-sequences": {
              options: {
                entities: {
                  work_item: {
                    period: "format",
                    format: "ENG-{n}",
                    formatFrom: { column: "public.organizations.task_format" },
                  },
                },
              },
            },
          },
        },
        ["number-sequences"],
      ),
    ).toContain(`format_assigned_number("better_supabase"."number_format"(`);
  });

  it("rejects a bad assignee cap and renders nothing in custom mode", () => {
    expect(() =>
      body("work-items", {
        modules: { "work-items": { options: { maxAssignees: -1 } } },
      }),
    ).toThrow(/maxAssignees/);
    expect(
      body("work-items", { modules: { "work-items": { mode: "custom" } } }),
    ).not.toContain("create_work_item");
  });

  it("links files, repeats with extra columns and watches without a tenant column", () => {
    expect(
      body(
        "work-items",
        {
          modules: {
            attachments: {
              options: { path: "{organization_id}/{subject_type}/{id}" },
            },
          },
        },
        ["attachments"],
      ),
    ).toContain("WORK_ITEM_ATTACHMENTS_PATH");
    expect(
      body(
        "work-items",
        {
          modules: {
            "work-items": { options: { extraColumns: { severity: "text" } } },
          },
        },
        ["reminders"],
      ),
    ).toContain(`jsonb_build_object('fields', jsonb_build_object('severity'`);

    const watch = body(
      "work-items",
      {
        modules: {
          notifications: { columns: { subscriptions: { tenant: null } } },
        },
      },
      ["notifications"],
    );

    expect(watch).toContain("watch_work_item");
    expect(watch).not.toContain('and s."organization_id" = x.');
  });
});
