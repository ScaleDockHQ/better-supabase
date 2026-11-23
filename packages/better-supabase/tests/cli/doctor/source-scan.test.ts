import { describe, expect, it } from "vitest";

import {
  bindingNames,
  sourceModel,
  targetKeys,
  unwrap,
} from "../../../src/cli/doctor/source-scan.ts";

const names = (text: string): string[] =>
  sourceModel(text).declarations.flatMap((each) => each.names);

describe("bindingNames", () => {
  it.each([
    ["const x = 1;", ["x"]],
    ["const { a, b: c, ...rest } = o;", ["a", "c", "rest"]],
    ["const [d, , e = 1, ...f] = o;", ["d", "e", "f"]],
  ])("reads %s", (text, expected) => {
    expect(names(text)).toEqual(expected);
  });

  it("reads a parameter property and nothing for other nodes", () => {
    const { program } = sourceModel(
      "class A { constructor(private readonly x: number) {} }",
    );

    const klass = program.body[0]!;

    const ctor =
      klass.type === "ClassDeclaration" ? klass.body.body[0] : undefined;

    const param =
      ctor?.type === "MethodDefinition" ? ctor.value.params[0] : undefined;

    expect(bindingNames(param)).toEqual(["x"]);
    expect(bindingNames(null)).toEqual([]);
    expect(bindingNames(klass)).toEqual([]);
  });
});

describe("sourceModel", () => {
  it("writes callee paths and drops callees that are not a chain of names", () => {
    const model = sourceModel(
      `this.load();\n(db!).customers.get(1);\nobj[key]();\nmake()();\n(() => 1)();\nfoo?.bar();\nsupabase.from("t").select().eq("a", 1);\na.b<string>(x);`,
    );

    expect(model.calls.map((each) => each.path)).toEqual([
      "this.load",
      "db.customers.get",
      undefined,
      "make()",
      "make",
      undefined,
      "foo.bar",
      "supabase.from(...).select().eq",
      "supabase.from(...).select",
      "supabase.from",
      "a.b",
    ]);

    const chain = model.calls.find((each) => each.path === "supabase.from")!;

    expect(model.text[chain.chainClose]).toBe(")");
    expect(chain.chainClose).toBe(model.text.indexOf("1);\na.b") + 1);

    const generic = model.calls.at(-1)!;

    expect(model.text.slice(generic.open, generic.close + 1)).toBe("(x)");
  });

  it("names functions through declarators, assignments, keys and wrappers", () => {
    const model = sourceModel(`
function plain() {}
const arrow = async () => {};
const named = function inner() {};
const cached = cache(async () => {});
let later;
later = () => {};
exports.thing = () => {};
other[key] = () => {};
const [first] = [() => {}];
target = wrap(() => {});
const o = {
  key: () => {},
  "quoted": () => {},
  method() {},
  [computed]: () => {},
  9: () => {},
};
class C {
  field = () => {};
  run() {}
}
call(() => {});
`);

    expect(
      model.functions.map(
        (each) =>
          `${each.name}${each.local ? " local" : ""}${each.wrapped ? " wrapped" : ""}`,
      ),
    ).toEqual([
      "plain local",
      "arrow local",
      "inner local",
      "cached wrapped",
      "cached",
      "later",
      "thing",
      "target wrapped",
      "target",
      "key",
      "quoted",
      "method",
      "field",
      "run",
    ]);
  });

  it("blanks strings and comments, and collects loops, properties and scope ends", () => {
    const model = sourceModel(
      `// note\nfunction f() { const a = "x"; for (const r of rows) {} }\nconst o = { a: 1, b, c() {}, [d]: 2, "e": 3 };\nlet none;`,
    );

    expect(model.code).not.toContain("note");
    expect(model.code).not.toContain('"x"');
    expect(model.code).toHaveLength(model.text.length);
    expect(model.loops).toHaveLength(1);
    expect(model.properties.map((each) => each.key)).toEqual(["a", "e"]);

    const inner = model.declarations.find((each) => each.names[0] === "a")!;

    expect(model.text[inner.scopeEnd - 1]).toBe("}");
    expect(model.declarations.at(-1)!.scopeEnd).toBe(model.text.length);
  });

  it("collects names typed as a service or repository", () => {
    const model = sourceModel(`
let a: CustomersService;
let b: Readonly<OrdersRepository>;
let c: ns.TasksQueries;
let d: Service[];
let e: Readonly<Map<string, NotesService>>;
let f: Readonly<NotesService<string>>;
let g: Promise<NotesService>;
let h: Readonly<A, B>;
let i: string;
let j;
let k: Readonly<typeof x>;
interface Deps { notes: NotesRepo; "quoted": UsersRepos; [key]: AService; other: number }
class Holder { repo: ItemsRepository; plain = 1 }
`);

    expect([...model.typedServices].toSorted()).toEqual([
      "a",
      "b",
      "c",
      "notes",
      "quoted",
      "repo",
    ]);
  });
});

describe("unwrap", () => {
  it("strips await, parentheses, casts and non-null assertions", () => {
    const [declaration] = sourceModel(
      "async function f() { const x = (await (y as Z)!) satisfies W; }",
    ).declarations;

    expect(unwrap(declaration!.init)).toMatchObject({
      type: "Identifier",
      name: "y",
    });
  });
});

describe("targetKeys", () => {
  it("keys calls by the innermost named function, the outer wrapper or the module", () => {
    const functions = [
      { name: "outer", start: 0, end: 100 },
      { name: "inner", start: 10, end: 50 },
      { name: "action", start: 200, end: 300, wrapped: true as const },
      { name: "exported", start: 190, end: 310, wrapped: true as const },
    ];

    const keys = targetKeys("a.ts", functions, [
      { start: 20, callee: "db.get" },
      { start: 5, callee: "db.get" },
      { start: 30, callee: "db.get" },
      { start: 250, callee: "db.get" },
      { start: 400, callee: "db.get" },
    ]);

    expect([...keys.entries()]).toEqual([
      [5, "a.ts#outer:db.get"],
      [20, "a.ts#inner:db.get"],
      [30, "a.ts#inner:db.get#2"],
      [250, "a.ts#exported:db.get"],
      [400, "a.ts#<module>:db.get"],
    ]);
  });
});
