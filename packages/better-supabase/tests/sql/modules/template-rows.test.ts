import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const body = (
  modules: readonly string[],
  layout: Parameters<typeof renderBlocks>[1],
): string =>
  renderBlocks(modules, layout)
    .map((file) => file.contents)
    .join("\n");

const withTemplates = {
  modules: {
    tasks: { options: { templates: true } },
    templates: {},
    pipelines: {},
    search: {},
    numbering: {
      options: {
        entities: {
          task: {
            period: "none",
            format: "TASK-{n}",
            table: "better_supabase.tasks",
            column: "identifier",
          },
        },
      },
    },
  },
  subjects: {
    task: { table: "better_supabase.tasks", template: "template_id" },
  },
};

describe("template rows", () => {
  it("leaves the default task SQL without a template column", () => {
    const sql = body(["tasks"], {});

    expect(sql).not.toContain("template_id");
    expect(sql).toContain("clone_task");
  });

  it("skips numbers, events and pipeline history for a template task", () => {
    const sql = body(
      ["tasks", "templates", "pipelines", "numbering", "search"],
      withTemplates,
    );

    expect(sql).toContain("template_id");
    expect(sql).toContain("TASK_TEMPLATE_IMMUTABLE");
    expect(sql).toContain(
      "nullif(create_task.attrs ->> 'templateId', '') is null",
    );
    expect(sql).toContain('new."template_id" is null');
    expect(sql).toContain("instantiate_template");
    expect(sql).toContain("clone_row");
  });
});
