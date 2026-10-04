import { describe, expect, it } from "vitest";

import { createKitContext } from "../../src/sql/context.ts";
import {
  deprecationWrappers,
  kitDeprecations,
  type SqlModule,
  upgradePlan,
} from "../../src/sql/kit.ts";

const widget: SqlModule = {
  name: "widget",
  title: "Widget",
  description: "A test module.",
  requires: [],
  target: "schema",
  sql: "select 1;",
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
      { kits: { widget: { schema: "app" } } },
      modules,
    );
    expect(plan!.steps.map((step) => step.sql)).toEqual([
      'alter table "app".widgets rename column count to total;',
    ]);
  });

  it("renders steps with PermDock's scope id type", () => {
    const typed: SqlModule = {
      ...widget,
      upgrades: [
        {
          from: 3,
          description: "Retypes the tenant.",
          sql: (ctx) => `alter table w alter column t type ${ctx.idType};`,
        },
      ],
    };
    const permdock = {
      schema: "authz",
      scope: "organization",
      idType: "bigint",
      memberships: [],
    } as const;
    const [plan] = upgradePlan(
      [{ module: "widget", version: 3 }],
      { permdock },
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
        { kits: { widget: { mode: "custom" } } },
        modules,
      ),
    ).toEqual([]);
  });

  it("plans the tenant module's upgrade from version 1", () => {
    expect(upgradePlan([{ module: "tenant", version: 1 }])).toMatchObject([
      {
        module: "tenant",
        from: 1,
        to: 2,
        steps: [
          {
            from: 1,
            sql: expect.stringContaining(
              'alter table "better_supabase"."memberships" rename column "org_id" to "organization_id";',
            ),
          },
        ],
      },
    ]);
  });
});

describe("deprecations", () => {
  it("writes wrappers only for symbols not removed yet", () => {
    const ctx = createKitContext("widget", () => undefined);
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
    expect(kitDeprecations(modules).map((entry) => entry.symbol)).toEqual([
      "better_supabase.widget_count",
      "widget_ids",
      "better_supabase.old_widget",
    ]);
    expect(kitDeprecations()).toContainEqual(
      expect.objectContaining({
        module: "tenant",
        symbol: "better_supabase.current_org_id",
        removed: "0.2.0",
      }),
    );
  });
});
