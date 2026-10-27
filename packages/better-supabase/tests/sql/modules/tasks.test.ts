import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderBlocks>[1] = {},
  extra: readonly string[] = [],
): string =>
  renderBlocks([module, ...extra], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("tasks module", () => {
  it("binds work items to pipelines per team with Linear's categories", () => {
    const pipelines = body("pipelines", {}, ["tasks"]);
    expect(pipelines).toContain(
      'create trigger bsb_pipeline_work_item before insert or update of "stage_id", "pipeline_id" on "better_supabase"."work_items"',
    );
    expect(pipelines).toContain('new."team_id"::text');
    expect(pipelines).toContain("('in_review', 'In review', 'started', 'open'");
    expect(pipelines).toContain("when 'canceled' then 'canceled'");
  });

  it("checks the create and delete keys and the author's delete", () => {
    const all = body("tasks");
    expect(all).toContain('x."created_by" = auth.uid() or');

    const keyed = body("tasks", {
      modules: {
        tasks: {
          permissions: { create: "task.create", delete: "task.delete" },
          options: { authorCanDelete: false },
        },
      },
    });

    expect(keyed).toContain("'task.create'");
    expect(keyed).toContain("'task.delete'");
    expect(keyed).not.toContain('x."created_by" = auth.uid() or');
  });

  it("renders projects and iterations unless turned off", () => {
    const all = body("tasks");
    expect(all).toContain('references "better_supabase"."projects"');
    expect(all).toContain("save_iteration");

    const bare = body("tasks", {
      modules: { tasks: { tables: { projects: null, iterations: null } } },
    });

    expect(bare).not.toContain("save_project");
    expect(bare).not.toContain('references "better_supabase"."projects"');
  });

  it("caps assignees, notifies them and uses numbering when configured", () => {
    expect(
      body("tasks", { modules: { tasks: { options: { maxAssignees: 1 } } } }),
    ).toContain("cardinality(v_users) > 1");
    expect(body("tasks")).not.toContain("WORK_ITEM_ASSIGNEES_LIMIT");
    expect(body("tasks", {}, ["notifications"])).toContain(
      "'type', 'work_item.assigned'",
    );
    expect(
      body(
        "tasks",
        {
          modules: {
            numbering: {
              options: {
                entities: { work_item: { period: "none", format: "ENG-{n}" } },
              },
            },
          },
        },
        ["numbering"],
      ),
    ).toContain("format_assigned_number('ENG-{n}'");
    expect(
      body(
        "tasks",
        {
          modules: {
            numbering: {
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
        ["numbering"],
      ),
    ).toContain(`format_assigned_number("better_supabase"."number_format"(`);
  });

  it("declares the assignee variables only for the notification and watch it renders", () => {
    const assignees = (sql: string): string =>
      sql.slice(
        sql.indexOf('function "better_supabase"."set_work_item_assignees"'),
        sql.indexOf('function "better_supabase"."archive_work_item"'),
      );

    const quiet = assignees(
      body("tasks", { modules: { tasks: { options: { notify: false } } } }, [
        "notifications",
      ]),
    );

    expect(quiet).toContain("v_users uuid[]");
    expect(quiet).not.toContain("v_new");
    expect(quiet).not.toContain("v_claims");

    const notified = assignees(body("tasks", {}, ["notifications"]));
    expect(notified).toContain("v_new uuid[];");
    expect(notified).toContain("v_claims text;");
  });

  it("rejects a bad assignee cap and renders nothing in custom mode", () => {
    expect(() =>
      body("tasks", { modules: { tasks: { options: { maxAssignees: -1 } } } }),
    ).toThrow(/maxAssignees/);
    expect(
      body("tasks", { modules: { tasks: { mode: "custom" } } }),
    ).not.toContain("create_work_item");
  });

  it("links files, repeats with extra columns and watches without a tenant column", () => {
    expect(
      body(
        "tasks",
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
        "tasks",
        {
          modules: {
            tasks: { options: { extraColumns: { severity: "text" } } },
          },
        },
        ["reminders"],
      ),
    ).toContain(`jsonb_build_object('fields', jsonb_build_object('severity'`);

    const watch = body(
      "tasks",
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
