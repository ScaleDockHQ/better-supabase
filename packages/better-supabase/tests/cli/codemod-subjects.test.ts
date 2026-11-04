import { describe, expect, it } from "vitest";

import { CODEMOD_0_29 } from "../../src/cli/codemod-subjects.ts";

const config = (source: string, json = false) =>
  CODEMOD_0_29.configFile!(source, json);

const text = (source: string, json = false): string => {
  const result = config(source, json);

  if (!result.ok) {
    throw new Error(result.reason);
  }

  return result.text;
};

describe("0.29 codemod: config", () => {
  it("renames records in the top level and in environment blocks", () => {
    const out = text(
      `export default defineConfig({\n  records: { a: {} },\n  $production: { records: { b: {} } },\n  $env: { staging: { records: { c: {} } }, other: 1 },\n});\n`,
    );

    expect(out).not.toContain("records");
    expect(out.match(/subjects/gu)).toHaveLength(3);
  });

  it("moves records entries into an existing subjects object", () => {
    const result = config(
      `export default defineConfig({\n  records: { a: {}, b: {} },\n  subjects: { b: {} },\n});\n`,
    );

    expect(result.ok && result.text).toContain("a: {}");
    expect(result.ok && result.text).not.toContain("records");
    expect(
      result.ok && "review" in result && result.review[0]?.message,
    ).toContain("records.b");
  });

  it("moves records into an empty subjects object", () => {
    const out = text(
      `export default defineConfig({ records: { a: {} }, subjects: {} });\n`,
    );

    expect(out).toContain("a: {}");
    expect(out).not.toContain("records");
  });

  it("removes a records entry that is the last property", () => {
    const out = text(
      `export default defineConfig({\n  subjects: { x: {} },\n  records: { y: {} }\n});\n`,
    );

    expect(out).toContain("y: {}");
    expect(out).not.toContain("records");
  });

  it("asks for a manual move when one side is not an object literal", () => {
    const result = config(
      `export default defineConfig({ records: shared, subjects: { a: {} } });\n`,
    );

    expect(
      result.ok && "review" in result && result.review[0]?.message,
    ).toContain("by hand");
  });

  it("leaves a file without records alone", () => {
    const source = `export default defineConfig({ subjects: {} });\n`;

    expect(text(source)).toBe(source);
  });

  it("refuses a file without a config object that mentions records", () => {
    const result = config(`const x = load(); records: 1\n`);

    expect(result.ok).toBe(false);
    expect(config(`const x = load();\n`).ok).toBe(true);
  });
});

describe("0.29 codemod: JSON config", () => {
  it("refuses invalid JSON", () => {
    expect(config("{", true).ok).toBe(false);
  });

  it("keeps a file that has no records", () => {
    const source = `{"subjects":{}}`;

    expect(text(source, true)).toBe(source);
  });

  it("renames records, also inside environment blocks", () => {
    const out = JSON.parse(
      text(
        JSON.stringify({
          records: { a: 1 },
          $production: { records: { b: 1 } },
          $env: { staging: { records: { c: 1 } } },
        }),
        true,
      ),
    );

    expect(out.subjects).toEqual({ a: 1 });
    expect(out.$production.subjects).toEqual({ b: 1 });
    expect(out.$env.staging.subjects).toEqual({ c: 1 });
  });

  it("merges records into subjects and lets subjects win", () => {
    const result = config(
      JSON.stringify({ records: { a: 1, b: 1 }, subjects: { b: 2 } }),
      true,
    );

    expect(result.ok && JSON.parse(result.text).subjects).toEqual({
      a: 1,
      b: 2,
    });
    expect(result.ok && "review" in result && result.review).toHaveLength(1);
  });

  it("keeps records and asks for review when one side is not an object", () => {
    const result = config(
      JSON.stringify({ records: [1], subjects: { a: 1 } }),
      true,
    );

    expect(result.ok && JSON.parse(result.text).records).toEqual([1]);
    expect(
      result.ok && "review" in result && result.review[0]?.message,
    ).toContain("by hand");
  });

  it("ignores a value that is not an object", () => {
    expect(text("[1]", true)).toBe("[1]");
  });
});

describe("0.29 codemod: SQL tags", () => {
  const sql = CODEMOD_0_29.sqlFile!;

  it("renames the record tag of a table comment", () => {
    const result = sql(`comment on table public.t is 'Notes\n\n@bsb record'; `);

    expect(result.text).toContain("@bsb subject");
    expect(result.text).not.toContain("@bsb record");
  });

  it("keeps the subject tag when a comment has both", () => {
    const result = sql(`comment on table t is 'x\n\n@bsb subject; record';`);

    expect(result.text).not.toContain("record");
    expect(result.review[0]?.message).toContain("already has a `subject`");
  });

  it("leaves other comments alone", () => {
    const source = `comment on table t is 'plain';`;

    expect(sql(source).text).toBe(source);
  });
});
