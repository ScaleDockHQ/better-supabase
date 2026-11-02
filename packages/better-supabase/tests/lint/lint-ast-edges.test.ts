import { describe, expect, it } from "vitest";

import type { CallExpression, RuleContext } from "../../src/lint/index.ts";

import { plugin } from "../../src/lint/index.ts";

const ident = (name: string) => ({ type: "Identifier", name });
const literal = (value: unknown) => ({ type: "Literal", value });

const member = (name: string, extra: Record<string, unknown> = {}) => ({
  type: "MemberExpression",
  computed: false,
  object: ident("db"),
  property: ident(name),
  ...extra,
});

const property = (key: unknown, value: unknown, computed = false) => ({
  type: "Property",
  computed,
  key,
  value,
});

const object = (...properties: unknown[]) => ({
  type: "ObjectExpression",
  properties,
});

const callOf = (callee: unknown, ...args: unknown[]): CallExpression =>
  // SAFETY: a test AST node; the rules read only the fields built here.
  ({
    type: "CallExpression",
    callee,
    arguments: args,
  }) as unknown as CallExpression;

function run(
  rule: keyof typeof plugin.rules,
  node: CallExpression,
  options: unknown[] = [],
): number {
  let count = 0;
  const context: RuleContext = { options, report: () => (count += 1) };

  plugin.rules[rule].create(context).CallExpression(node);

  return count;
}

describe("lint rules on unusual syntax", () => {
  it("ignores calls whose method name can't be read", () => {
    expect(run("no-unbounded-list", callOf(ident("list")))).toBe(0);
    expect(
      run("no-unbounded-list", callOf(member("list", { computed: true }))),
    ).toBe(0);
    expect(
      run(
        "no-unbounded-list",
        callOf(member("list", { property: literal("list") })),
      ),
    ).toBe(0);
    expect(run("no-unbounded-list", callOf(member("list")))).toBe(1);
  });

  it("reads literal and unreadable object keys", () => {
    const limited = (key: unknown, computed = false) =>
      callOf(member("list"), object(property(key, literal(1), computed)));

    expect(run("no-unbounded-list", limited(literal("limit")))).toBe(0);
    expect(run("no-unbounded-list", limited(literal(5)))).toBe(0);
    expect(run("no-unbounded-list", limited(ident("limit"), true))).toBe(0);
    expect(run("no-unbounded-list", limited({ type: "TemplateLiteral" }))).toBe(
      0,
    );
    expect(
      run(
        "no-unbounded-list",
        callOf(member("list"), object({ type: "SpreadElement" })),
      ),
    ).toBe(0);
  });

  it("ignores limits that are not number literals", () => {
    const limit = (value: unknown) =>
      callOf(member("list"), object(property(ident("limit"), value)));

    expect(run("max-limit", limit(ident("n")))).toBe(0);
    expect(run("max-limit", limit(literal("5000")))).toBe(0);
    expect(run("max-limit", limit(literal(5000)))).toBe(1);
    expect(run("max-limit", callOf(ident("list")))).toBe(0);
    expect(run("max-limit", callOf(member("get")))).toBe(0);
  });

  it("matches tables only through a plain receiver property", () => {
    const on = (receiver: unknown) =>
      callOf({ ...member("list"), object: receiver }, object());

    const strict = [{ strict: true }];

    expect(run("unbounded-read", on(member("users")), strict)).toBe(1);
    expect(run("unbounded-read", on(ident("users")), strict)).toBe(0);
    expect(
      run("unbounded-read", on(member("users", { computed: true })), strict),
    ).toBe(0);
    expect(
      run(
        "unbounded-read",
        on(member("users", { property: literal("users") })),
        strict,
      ),
    ).toBe(0);
    expect(
      run("unbounded-read", on(member("public.Order_Items")), [
        { tables: ["order_items"] },
      ]),
    ).toBe(1);
  });

  it("flags only update and delete options it can read", () => {
    const where = object(property(ident("where"), object()));

    expect(
      run("require-max-affected", callOf(member("update"), where, object())),
    ).toBe(1);
    expect(
      run(
        "require-max-affected",
        callOf(
          member("update"),
          where,
          object(),
          object(property(ident("maxAffected"), ident("n"))),
        ),
      ),
    ).toBe(0);
    expect(run("require-max-affected", callOf(ident("update"), where))).toBe(0);
    expect(run("no-empty-where", callOf(ident("delete"), where))).toBe(0);
    expect(run("no-empty-where", callOf(member("get"), where))).toBe(0);
  });

  it("walks through nested wheres and ignores other value kinds", () => {
    const where = (value: unknown) =>
      callOf(member("list"), object(property(ident("where"), value)));

    expect(run("require-escape-like", where(ident("dynamic")))).toBe(0);
    expect(
      run(
        "require-escape-like",
        where(
          object(
            { type: "SpreadElement" },
            property(
              ident("name"),
              object(property(ident("like"), ident("q"))),
            ),
          ),
        ),
      ),
    ).toBe(1);
    expect(
      run(
        "require-escape-like",
        where(
          object(
            property(
              ident("name"),
              object(
                property(ident("ilike"), {
                  type: "BinaryExpression",
                  operator: "-",
                  left: ident("a"),
                  right: ident("b"),
                }),
              ),
            ),
          ),
        ),
      ),
    ).toBe(0);
    expect(
      run(
        "require-escape-like",
        where(
          object(
            property(
              ident("name"),
              object(
                property(ident("like"), {
                  type: "CallExpression",
                  callee: member("escapeLike", { object: ident("sql") }),
                  arguments: [ident("q")],
                }),
              ),
            ),
          ),
        ),
      ),
    ).toBe(0);
    expect(
      run(
        "require-escape-like",
        where(
          object(
            property(
              ident("name"),
              object(
                property(ident("like"), {
                  type: "CallExpression",
                  callee: { type: "FunctionExpression" },
                  arguments: [],
                }),
              ),
            ),
          ),
        ),
      ),
    ).toBe(0);
  });
});
