import { describe, expect, it } from "vitest";

import defaultPlugin, {
  largeTables,
  plugin,
  type CallExpression,
  type RuleContext,
} from "./index.ts";

type Reported = { messageId: string; data?: Readonly<Record<string, string>> };

function member(name: string) {
  return {
    type: "MemberExpression",
    computed: false,
    property: { type: "Identifier", name },
  };
}

function literal(value: unknown) {
  return { type: "Literal", value };
}

function object(entries: Record<string, unknown>) {
  return {
    type: "ObjectExpression",
    properties: Object.entries(entries).map(([name, value]) => ({
      type: "Property",
      computed: false,
      key: { type: "Identifier", name },
      value,
    })),
  };
}

function call(method: string, ...args: unknown[]): CallExpression {
  return {
    type: "CallExpression",
    callee: member(method),
    arguments: args,
  } as CallExpression;
}

function run(
  rule: keyof typeof plugin.rules,
  node: CallExpression,
  options: unknown[] = [],
): Reported[] {
  const reported: Reported[] = [];
  const context: RuleContext = {
    options,
    report: ({ messageId, data }) =>
      reported.push(data ? { messageId, data } : { messageId }),
  };
  plugin.rules[rule].create(context).CallExpression(node);
  return reported;
}

describe("better-supabase/lint", () => {
  it("flags findMany without limit, skipping unreadable arguments", () => {
    expect(run("no-unbounded-find-many", call("findMany"))).toHaveLength(1);
    expect(
      run("no-unbounded-find-many", call("findMany", object({}))),
    ).toHaveLength(1);
    expect(
      run(
        "no-unbounded-find-many",
        call("findMany", object({ limit: literal(10) })),
      ),
    ).toEqual([]);
    expect(
      run(
        "no-unbounded-find-many",
        call("findMany", { type: "Identifier", name: "args" }),
      ),
    ).toEqual([]);
    expect(run("no-unbounded-find-many", call("findFirst"))).toEqual([]);
  });

  it("flags deleteMany without where", () => {
    expect(run("no-delete-many-without-where", call("deleteMany"))).toEqual([
      { messageId: "missing" },
    ]);
    expect(
      run(
        "no-delete-many-without-where",
        call("deleteMany", object({ where: object({}) })),
      ),
    ).toEqual([]);
  });

  it("caps literal limits with a configurable maximum", () => {
    const node = call("findMany", object({ limit: literal(5000) }));
    expect(run("max-limit", node)).toEqual([
      { messageId: "tooLarge", data: { limit: "5000", max: "1000" } },
    ]);
    expect(run("max-limit", node, [{ max: 10_000 }])).toEqual([]);
  });

  it("flags offset without orderBy", () => {
    expect(
      run(
        "require-order-by",
        call("findMany", object({ offset: literal(20) })),
      ),
    ).toHaveLength(1);
  });

  it("flags unbounded reads on large tables, or on any table when strict", () => {
    const on = (table: string, ...args: unknown[]): CallExpression =>
      ({
        type: "CallExpression",
        callee: {
          type: "MemberExpression",
          computed: false,
          object: member(table),
          property: { type: "Identifier", name: "findMany" },
        },
        arguments: args,
      }) as CallExpression;
    const tables = largeTables({
      extras: {
        tables: [
          { schema: "public", name: "order_items", large: true },
          { schema: "public", name: "tags" },
        ],
      },
    });
    expect(tables).toEqual(["public.order_items"]);

    expect(run("unbounded-read", on("orderItems"), [{ tables }])).toEqual([
      { messageId: "unbounded", data: { table: "orderItems" } },
    ]);
    expect(run("unbounded-read", on("order_items"), [{ tables }])).toHaveLength(
      1,
    );
    expect(
      run("unbounded-read", on("orderItems", object({ limit: literal(50) })), [
        { tables },
      ]),
    ).toEqual([]);
    expect(run("unbounded-read", on("tags"), [{ tables }])).toEqual([]);
    expect(run("unbounded-read", on("tags"), [{ strict: true }])).toHaveLength(
      1,
    );
    expect(run("unbounded-read", on("tags"))).toEqual([]);
  });

  it("ships a flat recommended config that registers itself", () => {
    expect(defaultPlugin).toBe(plugin);
    expect(plugin.configs.recommended.plugins["better-supabase"]).toBe(plugin);
    for (const id of Object.keys(plugin.configs.recommended.rules)) {
      expect(plugin.rules).toHaveProperty(id.replace("better-supabase/", ""));
    }
  });
});
