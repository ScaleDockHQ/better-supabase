import { describe, expect, it } from "vitest";

import type { BlockSql } from "../../src/sql/module-types.ts";

import { createModuleContext } from "../../src/sql/context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import {
  deprecationWrappers,
  moduleDeprecations,
  upgradePlan,
} from "../../src/sql/upgrade.ts";

const widget: BlockSql = {
  name: "widget",
  title: "Widget",
  description: "A test module.",
  requires: [],
  target: "schema",
  sql: "select 1;",
  build: () => "select 1;",
  version: 4,
  modes: ["managed", "custom"],
  upgrades: [
    {
      from: 3,
      description: "Renames count to total.",
      sql: (ctx) =>
        `alter table ${ctx.schema}.widgets rename column count to total;`,
    },
    {
      from: 1,
      description: "Renames the table.",
      sql: () => "alter table a rename to b;",
    },
    { from: 2, description: "Nothing to run.", sql: () => "  " },
  ],
  deprecated: [
    {
      kind: "function",
      symbol: "better_supabase.widget_count",
      use: "better_supabase.widget_total()",
      since: "0.5.0",
      wrapper: (ctx) =>
        `create or replace function ${ctx.schema}.widget_count() returns int language sql as $$ select ${ctx.schema}.widget_total() $$;\ncomment on function ${ctx.schema}.widget_count() is 'deprecated: use widget_total()';`,
    },
    {
      kind: "claim",
      symbol: "widget_ids",
      use: "widgets",
      since: "0.3.0",
      removed: "0.4.0",
    },
    {
      kind: "function",
      symbol: "better_supabase.old_widget",
      use: "nothing",
      since: "0.5.0",
    },
  ],
};

const modules = { widget };

describe("upgradePlan", () => {
  it("orders the steps from the installed version to the current one", () => {
    expect(
      upgradePlan([{ module: "widget", version: 2 }], {}, modules),
    ).toEqual([
      {
        module: "widget",
        from: 2,
        to: 4,
        steps: [
          { from: 2, description: "Nothing to run.", sql: "" },
          {
            from: 3,
            description: "Renames count to total.",
            sql: 'alter table "better_supabase".widgets rename column count to total;',
          },
        ],
      },
    ]);
  });

  it("renders steps for the module's configured schema", () => {
    const [plan] = upgradePlan(
      [{ module: "widget", version: 3 }],
      { modules: { widget: { schema: "app" } } },
      modules,
    );

    expect(plan!.steps.map((step) => step.sql)).toEqual([
      'alter table "app".widgets rename column count to total;',
    ]);
  });

  it("renders steps with the provider's scope id type", () => {
    const typed: BlockSql = {
      ...widget,
      upgrades: [
        {
          from: 3,
          description: "Retypes the tenant.",
          sql: (ctx) => `alter table w alter column t type ${ctx.idType};`,
        },
      ],
    };

    const accessProvider = {
      name: "stub",
      scope: "organization",
      idType: "bigint",
      functions: { idsWith: "authz.ids({permission})", isPlatform: "false" },
    } as const;

    const [plan] = upgradePlan(
      [{ module: "widget", version: 3 }],
      { accessProvider },
      { widget: typed },
    );

    expect(plan!.steps[0]!.sql).toBe(
      "alter table w alter column t type bigint;",
    );
  });

  it("skips current, unknown and custom-mode modules", () => {
    expect(
      upgradePlan([{ module: "widget", version: 4 }], {}, modules),
    ).toEqual([]);
    expect(upgradePlan([{ module: "nope", version: 1 }], {}, modules)).toEqual(
      [],
    );
    expect(
      upgradePlan(
        [{ module: "widget", version: 1 }],
        { modules: { widget: { mode: "custom" } } },
        modules,
      ),
    ).toEqual([]);
  });

  it("plans the tenant module's upgrade from version 1", () => {
    expect(upgradePlan([{ module: "memberships", version: 1 }])).toMatchObject([
      {
        module: "memberships",
        from: 1,
        to: 3,
        steps: [
          {
            from: 1,
            sql: expect.stringContaining(
              'alter table "better_supabase"."memberships" rename column "org_id" to "organization_id";',
            ),
          },
          { from: 2, sql: "" },
        ],
      },
    ]);
  });
});

describe("NAMES.migrations", () => {
  const comments = SQL_MODULES["comments"]!;

  const moved: BlockSql = {
    ...comments,
    names: {
      ...comments.names!,
      migrations: [
        {
          from: comments.version! - 1,
          description:
            "Renames comment_links to comment_tasks and work_item_id to task_id.",
          table: "tasks",
          was: "comment_links",
          columns: { task: "work_item_id" },
        },
      ],
    },
  };

  const steps = (layout: object): string[] =>
    upgradePlan(
      [{ module: "comments", version: comments.version! - 1 }],
      layout,
      { ...SQL_MODULES, comments: moved },
    )[0]!.steps.map((step) => step.sql);

  it("renames the declared table and columns before the module's own steps", () => {
    const [first] = steps({});

    expect(first).toContain(
      'alter table "better_supabase"."comment_links" rename to "comment_tasks"',
    );
    expect(first).toContain('rename column "work_item_id" to "task_id"');
  });

  it("follows the config's table rename", () => {
    expect(
      steps({
        modules: { comments: { tables: { tasks: "comment_todos" } } },
      })[0],
    ).toContain(
      'alter table "better_supabase"."comment_links" rename to "comment_todos"',
    );
  });

  it("skips installs at or past the move", () => {
    expect(
      upgradePlan(
        [{ module: "comments", version: comments.version! }],
        {},
        { ...SQL_MODULES, comments: moved },
      ),
    ).toEqual([]);
  });

  it("renders a step before the move against the table's old name", () => {
    const plan = upgradePlan([
      { module: "compliance", version: 1 },
      { module: "acknowledgements", version: 1 },
    ]).find((each) => each.module === "compliance");

    const [acknowledgements, rename] = plan!.steps;

    expect(acknowledgements!.sql).toContain(
      'from "better_supabase"."policies" x',
    );
    expect(acknowledgements!.sql).not.toContain('."compliance_policies"');
    expect(rename!.sql).toContain(
      'alter table "better_supabase"."policies" rename to "compliance_policies"',
    );
  });
});

describe("deprecations", () => {
  it("writes wrappers only for symbols not removed yet", () => {
    const ctx = createModuleContext("widget", () => undefined);
    const wrappers = deprecationWrappers(widget, ctx);
    expect(wrappers).toContain(
      "-- Deprecated since 0.5.0: use better_supabase.widget_total().",
    );
    expect(wrappers).toContain(
      'comment on function "better_supabase".widget_count()',
    );
    expect(wrappers).not.toContain("widget_ids");
    expect(wrappers).not.toContain("old_widget");
    const { deprecated: _, ...plain } = widget;
    expect(deprecationWrappers(plain, ctx)).toBe("");
  });

  it("lists every deprecated symbol with its module", () => {
    expect(moduleDeprecations(modules).map((entry) => entry.symbol)).toEqual([
      "better_supabase.widget_count",
      "widget_ids",
      "better_supabase.old_widget",
    ]);
    expect(moduleDeprecations()).toContainEqual(
      expect.objectContaining({
        module: "memberships",
        symbol: "better_supabase.current_org_id",
        removed: "0.2.0",
      }),
    );
  });
});

describe("module upgrade steps", () => {
  it.each(
    Object.values(SQL_MODULES).filter((module) => (module.version ?? 1) > 1),
  )("lists a described step for each version $name moved past", (module) => {
    const to = module.version ?? 1;

    const [plan] = upgradePlan([{ module: module.name, version: 1 }], {
      modules: {},
    });

    expect(plan).toMatchObject({ from: 1, to });

    for (const step of plan!.steps) {
      expect(step.from).toBeLessThan(to);
      expect(step.description).not.toBe("");
      expect(typeof step.sql).toBe("string");
    }
  });
});
