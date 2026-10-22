import { describe, expect, it } from "vitest";

import type { CallExpression, RuleContext } from "../../src/lint/index.ts";

import defaultPlugin, { largeTables, plugin } from "../../src/lint/index.ts";

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
  it("flags list without limit, skipping unreadable arguments", () => {
    expect(run("no-unbounded-list", call("list"))).toHaveLength(1);
    expect(run("no-unbounded-list", call("list", object({})))).toHaveLength(1);
    expect(
      run("no-unbounded-list", call("list", object({ limit: literal(10) }))),
    ).toEqual([]);
    expect(
      run(
        "no-unbounded-list",
        call("list", { type: "Identifier", name: "args" }),
      ),
    ).toEqual([]);
    expect(run("no-unbounded-list", call("get"))).toEqual([]);
  });

  it("flags update and delete with an empty where", () => {
    expect(
      run("no-empty-where", call("delete", object({ where: object({}) }))),
    ).toEqual([{ messageId: "empty", data: { method: "delete" } }]);
    expect(
      run(
        "no-empty-where",
        call("update", object({ where: object({}) }), object({})),
      ),
    ).toEqual([{ messageId: "empty", data: { method: "update" } }]);
    expect(
      run(
        "no-empty-where",
        call("delete", object({ where: object({ id: literal(1) }) })),
      ),
    ).toEqual([]);
    expect(run("no-empty-where", call("delete", literal("id")))).toEqual([]);
  });

  it("caps literal limits with a configurable maximum", () => {
    const node = call("list", object({ limit: literal(5000) }));
    expect(run("max-limit", node)).toEqual([
      { messageId: "tooLarge", data: { limit: "5000", max: "1000" } },
    ]);
    expect(run("max-limit", node, [{ max: 10_000 }])).toEqual([]);
  });

  it("requires maxAffected on update and delete by filter, with a cap", () => {
    const where = object({ where: object({}) });

    expect(run("require-max-affected", call("delete", where))).toEqual([
      { messageId: "missing", data: { method: "delete" } },
    ]);
    expect(
      run("require-max-affected", call("update", where, object({}))),
    ).toEqual([{ messageId: "missing", data: { method: "update" } }]);

    const bounded = call(
      "update",
      where,
      object({}),
      object({ maxAffected: literal(5000) }),
    );

    expect(run("require-max-affected", bounded)).toEqual([
      { messageId: "tooLarge", data: { value: "5000", max: "1000" } },
    ]);
    expect(run("require-max-affected", bounded, [{ max: 10_000 }])).toEqual([]);
    expect(
      run(
        "require-max-affected",
        call("delete", where, { type: "Identifier", name: "args" }),
      ),
    ).toEqual([]);
    expect(run("require-max-affected", call("delete", literal("id")))).toEqual(
      [],
    );
  });

  it("flags offset without orderBy", () => {
    expect(
      run("require-order-by", call("list", object({ offset: literal(20) }))),
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
          property: { type: "Identifier", name: "list" },
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

  it("flags like and ilike values that aren't escaped", () => {
    const search = { type: "Identifier", name: "search" };

    const escaped = {
      type: "CallExpression",
      callee: { type: "Identifier", name: "escapeLike" },
      arguments: [search],
    };

    const template = (...expressions: unknown[]) => ({
      type: "TemplateLiteral",
      expressions,
    });

    const find = (where: unknown) =>
      run("require-escape-like", call("list", object({ where })));

    expect(find(object({ name: object({ ilike: search }) }))).toEqual([
      { messageId: "unescaped" },
    ]);
    expect(
      find(object({ name: object({ like: member("query") }) })),
    ).toHaveLength(1);
    expect(
      find(object({ name: object({ ilike: template(search) }) })),
    ).toHaveLength(1);
    expect(
      find(
        object({
          OR: {
            type: "ArrayExpression",
            elements: [object({ name: object({ ilike: search }) }), null],
          },
          owner: object({ email: object({ like: search }) }),
        }),
      ),
    ).toHaveLength(2);
    expect(
      find(
        object({
          name: object({
            ilike: {
              type: "BinaryExpression",
              operator: "+",
              left: search,
              right: literal("%"),
            },
          }),
        }),
      ),
    ).toHaveLength(1);

    expect(find(object({ name: object({ ilike: literal("a%") }) }))).toEqual(
      [],
    );
    expect(
      find(object({ name: object({ ilike: template(escaped) }) })),
    ).toEqual([]);
    expect(find(object({ name: object({ ilike: escaped }) }))).toEqual([]);
    expect(find(object({ name: object({ ieq: search }) }))).toEqual([]);
    expect(
      run("require-escape-like", call("list", object({ limit: literal(1) }))),
    ).toEqual([]);
  });

  it("ships a flat recommended config that registers itself", () => {
    expect(defaultPlugin).toBe(plugin);
    expect(plugin.configs.recommended.plugins["better-supabase"]).toBe(plugin);

    for (const id of Object.keys(plugin.configs.recommended.rules)) {
      expect(plugin.rules).toHaveProperty(id.replace("better-supabase/", ""));
    }
  });
});
