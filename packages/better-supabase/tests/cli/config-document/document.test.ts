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
