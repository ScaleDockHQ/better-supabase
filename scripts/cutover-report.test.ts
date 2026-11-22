import { describe, expect, it } from "vitest";

import {
  blockEntrySizes,
  classifyDiffs,
  configSections,
  diffSnapshots,
  parseArgs,
  totalLines,
} from "./cutover-report.ts";

const config = [
  'import { defineConfig } from "better-supabase/config";',
  "",
  "export default defineConfig({",
  "  auth: {",
  "    a: 1,",
  "  },",
  "  blocks: {",
  "    expenses: {",
  "      x: 1,",
  "    },",
  "    leave: {},",
  "  },",
  "});",
  "",
].join("\n");

describe("configSections", () => {
  it("counts the lines of each top-level key and the preamble", () => {
    const counts = configSections(config);
    expect(counts.get("preamble")).toBe(3);
    expect(counts.get("auth")).toBe(3);
    expect(counts.get("blocks")).toBe(7);
    expect(totalLines(counts)).toBe(13);
  });

  it("counts blocks entries", () => {
    expect(blockEntrySizes(config)).toEqual(
      new Map([
        ["expenses", 3],
        ["leave", 1],
      ]),
    );
  });
});

describe("diffSnapshots and classifyDiffs", () => {
  const before = {
    files: new Map([
      ["a.sql", "x\ny\n"],
      ["b.sql", "same\n"],
    ]),
  };

  const after = {
    files: new Map([
      ["a.sql", "x\nalter table tax_codes add unique (id, tenant);\n"],
      ["b.sql", "same\n"],
      ["c.sql", "select 1;\n"],
    ]),
  };

  it("lists changed and added files", () => {
    const diffs = diffSnapshots(before, after);
    expect(diffs.map((diff) => diff.file)).toEqual(["a.sql", "c.sql"]);
    expect(diffs[0]?.removed).toEqual(["y"]);
  });

  it("explains allowlisted lines and reports the rest", () => {
    const { explained, unexplained } = classifyDiffs(
      diffSnapshots(before, after),
    );

    expect(explained["tax_codes"]).toBe(1);
    expect(unexplained.map((item) => item.file)).toEqual(["a.sql", "c.sql"]);
  });
});

describe("parseArgs", () => {
  it("reads the flags", () => {
    const options = parseArgs([
      "--source",
      "/tmp/x",
      "--skip-prune",
      "--strict",
    ]);

    expect(options.source).toBe("/tmp/x");
    expect(options.skipPrune).toBe(true);
    expect(options.strict).toBe(true);
  });

  it("rejects an unknown flag", () => {
    expect(() => parseArgs(["--nope"])).toThrow("Unknown option");
  });
});

describe("blockEntrySizes with a list", () => {
  it("names each entry by its block and adds instances up", () => {
    const list = [
      "export default defineConfig({",
      "  blocks: [",
      '    { block: "seeds", api: false },',
      "    {",
      '      block: "leave",',
      "      x: 1,",
      "    },",
      "    {",
      '      block: "leave",',
      '      name: "b",',
      "    },",
      "  ],",
      "});",
    ].join("\n");

    expect(blockEntrySizes(list)).toEqual(
      new Map([
        ["seeds", 1],
        ["leave", 8],
      ]),
    );
  });
});
