import { describe, expect, it } from "vitest";

import { ConfigDocument } from "../../../src/cli/config-document/index.ts";

const BASIC = `import { defineConfig } from "better-supabase/config";
import { unused } from "./helpers.ts";

export default defineConfig({
  // the tables
  tables: {
    tasks: { schema: "public" },
    notes: {},
  },
  sameTenant: ["a", "b", "c"],
  blocks: [
    "invoices", // billing
    "leave",
  ],
});
`;

describe("ConfigDocument", () => {
  it("finds the config through the defineConfig binding", () => {
    const forms = [
      `import { defineConfig as dc } from "x";\nexport default dc({ a: 1 });`,
      `import { defineConfig } from "x";\nconst config = { a: 1 } as const satisfies Foo;\nexport default defineConfig(config);`,
      `import { defineConfig } from "x";\nconst config = defineConfig({ a: 1 });\nexport default config;`,
      `import { defineConfig } from "x";\nexport default defineConfig(() => ({ a: 1 }));`,
      `import { defineConfig } from "x";\nexport default defineConfig(async () => { return { a: 1 }; });`,
      `export default { a: 1 };`,
    ];

    for (const form of forms) {
      expect(ConfigDocument.parse(form).valueText(["a"])).toBe("1");
    }
  });

  it("is not fooled by a comment or a string that holds the config shape", () => {
    const document = ConfigDocument.parse(
      `// export default {\nconst note = "defineConfig({ a: 0 })";\nexport default { a: 1 };`,
    );

    expect(document.valueText(["a"])).toBe("1");
  });

  it("looks up array indexes and quoted keys", () => {
    const document = ConfigDocument.parse(
      `export default { "a-b": { c: [10, 20, { d: 3 }] } };`,
    );

    expect(document.valueText(["a-b", "c", 1])).toBe("20");
    expect(document.valueText(["a-b", "c", 2, "d"])).toBe("3");
    expect(document.has(["a-b", "c", 3])).toBe(false);
  });

  it("follows a shorthand, an identifier and a spread to the declaration", () => {
    const document = ConfigDocument.parse(
      `const tasks = { schema: "x" };\nconst more = { notes: { a: 1 } };\nexport default { tasks, ...more };`,
    );

    expect(document.valueText(["tasks", "schema"])).toBe('"x"');
    expect(document.valueText(["notes", "a"])).toBe("1");
  });

  it("removes an array element by index", () => {
    const document = ConfigDocument.parse(BASIC);

    expect(document.remove(["sameTenant", 1])).toEqual({ status: "done" });
    expect(document.text).toContain(`sameTenant: ["a", "c"],`);
  });

  it("removes a property with its comment and drops an import it leaves unused", () => {
    const document = ConfigDocument.parse(
      `import { defineConfig } from "x";\nimport { helper, keep } from "./h.ts";\n\nexport default defineConfig({\n  // uses the helper\n  a: helper(),\n  b: keep,\n});\n`,
    );

    document.remove(["a"]);

    expect(document.text).toBe(
      `import { defineConfig } from "x";\nimport { keep } from "./h.ts";\n\nexport default defineConfig({\n  b: keep,\n});\n`,
    );
  });

  it("removes a whole import and a constant that nothing uses afterwards", () => {
    const document = ConfigDocument.parse(
      `import { defineConfig } from "x";\nimport { helper } from "./h.ts";\nconst list = [1];\nexport default defineConfig({\n  a: helper(list),\n  b: 2,\n});\n`,
    );

    document.remove(["a"]);

    expect(document.text).toBe(
      `import { defineConfig } from "x";\nexport default defineConfig({\n  b: 2,\n});\n`,
    );
  });

  it("keeps a declaration the file never used", () => {
    const document = ConfigDocument.parse(BASIC);

    document.remove(["sameTenant"]);

    expect(document.text).toContain(`import { unused }`);
  });

  it("removes the last entry of a one-line object and of a block without a trailing comma", () => {
    const one = ConfigDocument.parse(
      `export default { a: { x: 1, y: 2 }, b: 1 };`,
    );

    one.remove(["a", "y"]);
    expect(one.text).toBe(`export default { a: { x: 1 }, b: 1 };`);

    const many = ConfigDocument.parse(
      `export default {\n  a: 1,\n  b: 2\n};\n`,
    );

    many.remove(["b"]);
    expect(many.text).toBe(`export default {\n  a: 1\n};\n`);
  });

  it("empties an object when its only entry goes", () => {
    const document = ConfigDocument.parse(
      `export default {\n  a: {\n    x: 1,\n  },\n};\n`,
    );

    document.remove(["a", "x"]);

    expect(document.text).toBe(`export default {\n  a: {},\n};\n`);
  });

  it("keeps CRLF and tab layout", () => {
    const document = ConfigDocument.parse(
      "export default {\r\n\ta: 1,\r\n\tb: 2,\r\n};\r\n",
    );

    expect(document.style.eol).toBe("\r\n");
    expect(document.style.indent).toBe("\t");

    document.remove(["a"]);
    document.set(["c"], "3");

    expect(document.text).toBe(
      "export default {\r\n\tb: 2,\r\n\tc: 3,\r\n};\r\n",
    );
    expect(document.text.replaceAll("\r\n", "")).not.toContain("\n");
  });

  it("detects quotes and a trailing comma", () => {
    const document = ConfigDocument.parse(
      `import { defineConfig } from 'x';\nexport default defineConfig({ a: 'b', c: 'd' });`,
    );

    expect(document.style.quote).toBe("'");
    expect(document.style.trailingComma).toBe(false);
  });

  it("sets a value and adds a property", () => {
    const document = ConfigDocument.parse(BASIC);

    document.set(["tables", "tasks", "schema"], '"app"');
    document.set(["tables", "projects"], "{}");

    expect(document.valueText(["tables", "tasks", "schema"])).toBe('"app"');
    expect(document.text).toContain(`    projects: {},`);
  });

  it("writes a shorthand property as a key and value", () => {
    const document = ConfigDocument.parse(
      `const a = 1;\nexport default { a };`,
    );

    document.set(["a"], "2");

    expect(document.text).toContain("a: 2");
  });

  it("sorts keys and keeps each comment with its entry", () => {
    const document = ConfigDocument.parse(
      `export default {\n  tables: {\n    // z note\n    z: 1,\n    a: 2, // a note\n    m: 3,\n  },\n};\n`,
    );

    expect(document.sortKeys(["tables"])).toEqual({ status: "done" });
    expect(document.text).toBe(
      `export default {\n  tables: {\n    a: 2, // a note\n    m: 3,\n    // z note\n    z: 1,\n  },\n};\n`,
    );
  });

  it("asks for a review where it cannot follow the shape, and never changes the text", () => {
    const text = `const k = "a";\nexport default { [k]: 1, ...make(), b: { ...other } };\n`;
    const document = ConfigDocument.parse(text);

    expect(document.sortKeys([])).toMatchObject({ status: "review" });
    expect(document.set(["x", "y"], "1")).toMatchObject({ status: "review" });
    expect(document.review).toHaveLength(2);
    expect(document.text).toBe(text);
  });

  it("reports an absent path as absent", () => {
    expect(ConfigDocument.parse(BASIC).remove(["nope"])).toEqual({
      status: "absent",
    });
  });

  it("throws a usage error that names the file for text that does not parse", () => {
    expect(() => ConfigDocument.parse("export default {", "a.ts")).toThrow(
      /^a\.ts:1:/,
    );
  });
});

describe("ConfigDocument edges", () => {
  it.each([
    [
      `import { defineConfig } from "x";\nmodule.exports = defineConfig({ a: 1 });`,
      "1",
    ],
    [
      `import { defineConfig } from "x";\nconst c = defineConfig({ a: 2 });`,
      "2",
    ],
    [
      `import * as bs from "x";\nexport default bs.defineConfig({ a: 3 });`,
      "3",
    ],
    [`export default defineConfig(function () { return { a: 4 }; });`, "4"],
    [`const a = b;\nconst b = a;\nexport default a;`, undefined],
    [`export default defineConfig(() => { const x = 1; });`, undefined],
    [`export default defineConfig(...args);`, undefined],
    [`export default make({ a: 1 });`, undefined],
    [`export default "x";`, undefined],
    [`const o = { ...o };\nexport default o;`, undefined],
  ])("reads the config of %j", (source, value) => {
    expect(ConfigDocument.parse(source).valueText(["a"])).toBe(value);
  });

  it("reads the declared object inside a range and nothing outside it", () => {
    const source = `import x from "x";\nconst a = 1;\nexport const extra = { b: 2 };\n`;
    const start = source.indexOf("extra");

    const inside = ConfigDocument.parseDeclared(source, "e.ts", {
      start,
      end: source.length,
    });

    expect(inside.valueText(["b"])).toBe("2");
    expect(
      ConfigDocument.parseDeclared(source, "e.ts", {
        start: 0,
        end: 5,
      }).configObject(),
    ).toBeUndefined();
  });

  it("finds the blocks object of a wiring call", () => {
    expect(
      ConfigDocument.parseWiring(
        `defineBlocks(config, { a: 1 });\ncreateBlocks(o, { a: 2 });`,
      ).valueText(["a"]),
    ).toBe("1");
    expect(
      ConfigDocument.parseWiring(`createBlocks(o, make());`).wiredCall(),
    ).toEqual({ name: "createBlocks", blocks: undefined });
    expect(
      ConfigDocument.parseWiring(`createBlocks(o);`).wiredCall()?.blocks,
    ).toBeUndefined();
  });

  it("lists every defineConfig object once, skipping calls without one", () => {
    const document = ConfigDocument.parse(
      `const shared = { a: 1 };\ndefineConfig();\ndefineConfig(...x);\ndefineConfig(shared);\ndefineConfig(shared);\ndefineConfig({ b: 2 });`,
    );

    expect(
      document.defineConfigCalls().map((each) => Object.keys(each)),
    ).toHaveLength(2);
    expect(document.sortKeys([], 1)).toEqual({ status: "done" });
  });

  it("steps through holes, spreads and labels of a list", () => {
    const document = ConfigDocument.parse(
      `const more = [{ block: "c" }];\nexport default { list: ["a", , ...more, { name: "b" }, 7], n: 1 };`,
    );

    expect(document.has(["list", 1])).toBe(false);
    expect(document.valueText(["list", 2])).toBe(`[{ block: "c" }]`);
    expect(document.valueText(["list", "b"])).toBe(`{ name: "b" }`);
    expect(document.has(["list", "c"])).toBe(false);
    expect(document.keys(["list"])).toEqual(["a", "b"]);
    expect(document.keys(["n"])).toBeUndefined();
    expect(document.has(["n", "x"])).toBe(false);
    expect(document.valueRange(["n"])).toEqual({
      start: document.text.lastIndexOf("1"),
      end: document.text.lastIndexOf("1") + 1,
    });
    expect(document.valueRange(["none"])).toBeUndefined();
  });

  it("counts an object spread twice only once", () => {
    const document = ConfigDocument.parse(
      `const base = { x: 1 };\nexport default { ...base, ...base, y: 2 };`,
    );

    expect(document.keys([])).toEqual(["x", "y"]);
  });

  it.each([
    [
      `const more = [1];\nexport default { list: [...more] };`,
      ["list", 0],
      /is a spread/,
    ],
    [`export default { a() { return 1; } };`, ["a"], /method or accessor/],
    [`export default { get a() { return 1; } };`, ["a"], /method or accessor/],
  ])("flags an entry it cannot edit in %j", (source, path, review) => {
    const document = ConfigDocument.parse(source);

    expect(document.set(path, "2")).toMatchObject({
      status: "review",
      review: expect.stringMatching(review),
    });
    expect(document.remove(path)).toMatchObject({ status: "review" });
    expect(document.text).toBe(source);
  });

  it.each([[["a", "b"]], [["o", 3]]])(
    "flags adding %j under a non-object",
    (path) => {
      const document = ConfigDocument.parse(
        `export default { a: [1], o: {} };`,
      );

      expect(document.set(path, "1")).toMatchObject({ status: "review" });
    },
  );

  it("ensures an existing path by setting it, and flags what it cannot create", () => {
    const document = ConfigDocument.parse(
      `export default { a: 1, "b-c": {} };`,
    );

    expect(document.ensure(["a"], "2")).toEqual({ status: "done" });
    expect(document.ensure(["b-c", "list", 0], "1")).toMatchObject({
      status: "review",
    });
    expect(document.ensure(["b-c", "x-y", "z"], "3")).toEqual({
      status: "done",
    });
    expect(document.valueText(["a"])).toBe("2");
    expect(document.valueText(["b-c", "x-y", "z"])).toBe("3");
    expect(document.text).toContain(`"x-y": {`);
    expect(
      ConfigDocument.parse(`export const x = 1;`).ensure(["a", "b"], "1"),
    ).toMatchObject({ review: "config.ts: no config object found." });
  });

  it.each([
    [`export default { l: [] };`, `export default { l: [9] };`],
    [`export default { l: [\n  ] };`, `export default { l: [\n    9,\n  ] };`],
    [`export default { l: [1] };`, `export default { l: [1, 9] };`],
    [
      `export default {\n  l: [\n    1 // one\n  ],\n};`,
      `export default {\n  l: [\n    1, // one\n    9\n  ],\n};`,
    ],
    [
      `export default {\n  l: [\n    1, // one\n  ],\n};`,
      `export default {\n  l: [\n    1, // one\n    9,\n  ],\n};`,
    ],
  ])("appends to %j", (source, expected) => {
    const document = ConfigDocument.parse(source);

    expect(document.append(["l"], "9")).toEqual({ status: "done" });
    expect(document.text).toBe(expected);
  });

  it("flags appending to a value that is not a list", () => {
    expect(
      ConfigDocument.parse(`export default { l: 1 };`).append(["l"], "2"),
    ).toMatchObject({ status: "review" });
  });

  it.each([
    [
      `export default {\n  o: {\n    a: 1 // one\n  },\n};`,
      `export default {\n  o: {\n    a: 1, // one\n    b: 2\n  },\n};`,
    ],
    [`export default { o: {\n} };`, `export default { o: {\n  b: 2,\n} };`],
  ])("adds a property to %j", (source, expected) => {
    const document = ConfigDocument.parse(source);

    document.set(["o", "b"], "2");

    expect(document.text).toBe(expected);
  });

  it("reports sorting an absent path as absent and a non-object as a review", () => {
    const document = ConfigDocument.parse(`export default { a: 1 };`);

    expect(document.sortKeys(["none"])).toEqual({ status: "absent" });
    expect(document.sortKeys(["a"])).toMatchObject({ status: "review" });
    expect(
      ConfigDocument.parse(`export const x = 1;`).sortKeys([]),
    ).toMatchObject({ status: "review" });
  });

  it("reads a trailing comma behind a comment", () => {
    expect(
      ConfigDocument.parse(`export default { a: 1 /* c */, };`).style
        .trailingComma,
    ).toBe(true);
  });

  it("keeps a default import that shares a statement with named ones", () => {
    const document = ConfigDocument.parse(
      `import helper, { keep } from "./h.ts";\nexport default { a: helper(), b: keep };`,
    );

    document.remove(["a"]);

    expect(document.text).toBe(
      `import helper, { keep } from "./h.ts";\nexport default { b: keep };`,
    );
  });

  it("rewrites through a callback only when it changes the text", () => {
    const document = ConfigDocument.parse(`export default { a: 1 };`);

    document.rewrite(() => undefined);
    expect(document.text).toBe(`export default { a: 1 };`);
    document.rewrite(({ edit, text }) =>
      edit.overwrite(text.indexOf("1"), text.indexOf("1") + 1, "2"),
    );
    expect(document.valueText(["a"])).toBe("2");
    expect(() => {
      document.rewrite(({ edit }) => edit.append("{"));
    }).toThrow(/^config\.ts:/);
    expect(document.valueText(["a"])).toBe("2");
  });
});
