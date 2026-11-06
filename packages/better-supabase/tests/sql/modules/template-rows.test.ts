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
      [
        "tasks",
        "templates",
        "pipelines",
        "numbering",
        "search",
        "subjects",
        "metrics",
        "segments",
        "state-machine",
      ],
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

  it("renders record templates, party checks and instantiation rules", () => {
    const sql = body(
      [
        "quotes",
        "invoices",
        "orders",
        "inventory",
        "templates",
        "jsonb-schemas",
      ],
      {
        modules: {
          quotes: { options: { templates: true, requireParty: true } },
          invoices: { options: { templates: true, requireParty: true } },
          orders: { options: { templates: true } },
          inventory: { options: { templates: true } },
          templates: {
            options: {
              types: {
                quote: {
                  storage: "rows",
                  table: "better_supabase.quotes",
                  templateColumn: "template_id",
                  clone: "better_supabase.clone_quote",
                  idColumn: "id",
                  settings: { type: "object" },
                  extension: "better_supabase.quote_templates",
                  children: [
                    {
                      table: "better_supabase.quote_lines",
                      parent: "parent_id",
                    },
                  ],
                  rules: {
                    dates: [
                      { column: "due_at", from: "now", days: "due_days" },
                      {
                        column: "start_at",
                        from: "issued_on",
                        days: "start_days",
                      },
                    ],
                    variables: ["title"],
                  },
                },
                note: { storage: "body" },
              },
            },
          },
        },
      },
    );

    expect(sql).toContain("clone_quote");
    expect(sql).toContain("clone_invoice");
    expect(sql).toContain("QUOTE_TEMPLATE");
    expect(sql).toContain("INVOICE_TEMPLATE");
    expect(sql).toContain("pack_template");
    expect(sql).toContain("unpack_template");
    expect(sql).toContain("source_template_id");
    expect(sql).toContain("jsonschema_validation_errors");
  });

  it("accepts a template column object, with and without children", () => {
    const object = body(["tasks", "pipelines", "templates"], {
      modules: {
        tasks: { options: { templates: true } },
        pipelines: {},
        templates: {},
      },
      subjects: {
        task: {
          table: "better_supabase.tasks",
          template: { column: "template_id" },
        },
      },
    });

    const children = body(["tasks", "search", "templates"], {
      modules: {
        tasks: { options: { templates: true } },
        search: {},
        templates: {},
      },
      subjects: {
        task: {
          table: "better_supabase.tasks",
          template: {
            column: "template_id",
            children: [{ table: "task_assignees", column: "task_id" }],
          },
        },
      },
    });

    expect(object).toContain("template_id");
    expect(children).toContain("template_id");
  });

  it("refuses the option without the templates block", () => {
    for (const name of ["tasks", "quotes", "invoices", "orders", "inventory"]) {
      expect(() =>
        body([name], { modules: { [name]: { options: { templates: true } } } }),
      ).toThrow(`blocks.${name}.options.templates needs the templates block`);
    }
  });

  it("refuses a template type or a child table that is not usable", () => {
    const types = (entry: unknown): void => {
      body(["templates"], {
        modules: { templates: { options: { types: entry } } },
      });
    };

    expect(() => {
      types("quote");
    }).toThrow("blocks.templates.options.types must be an object");
    expect(() => {
      types({ quote: "rows" });
    }).toThrow("blocks.templates.options.types.quote must be an object");
    expect(() => {
      types({ "Bad Type": { storage: "body" } });
    }).toThrow("is not a template type");
    expect(() => {
      types({ quote: { storage: "file" } });
    }).toThrow("storage must be");
    expect(() => {
      types({ quote: { storage: "rows" } });
    }).toThrow("table must be");
    expect(() => {
      types({ quote: { storage: "rows", table: "better_supabase.quotes" } });
    }).toThrow("templateColumn must be");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
        },
      });
    }).toThrow("clone must be");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
          clone: "better_supabase.clone_quote",
          idColumn: "1bad",
        },
      });
    }).toThrow("idColumn must be");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
          clone: "better_supabase.clone_quote",
          extension: "not a table",
        },
      });
    }).toThrow("extension must be");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
          clone: "better_supabase.clone_quote",
          children: [{ table: "Not A Table", parent: "parent_id" }],
        },
      });
    }).toThrow("must be { table:");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
          clone: "better_supabase.clone_quote",
          rules: { dates: [{ column: "due", from: "later", days: "1bad" }] },
        },
      });
    }).toThrow("rules.dates");
    expect(() => {
      types({
        quote: {
          storage: "rows",
          table: "better_supabase.quotes",
          templateColumn: "template_id",
          clone: "better_supabase.clone_quote",
          rules: { variables: ["1bad"] },
        },
      });
    }).toThrow("rules.variables");
    expect(() =>
      body(["tasks", "templates"], {
        modules: { tasks: { options: { templates: true } }, templates: {} },
        subjects: {
          task: {
            table: "better_supabase.tasks",
            template: {
              column: "template_id",
              children: [{ table: "not a table", column: "task_id" }],
            },
          },
        },
      }),
    ).toThrow("template.children[0].table");
  });
});
