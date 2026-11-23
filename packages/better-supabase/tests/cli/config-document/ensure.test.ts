import { describe, expect, it } from "vitest";

import {
  ConfigDocument,
  rewriteSource,
} from "../../../src/cli/config-document/index.ts";

describe("ConfigDocument.keys", () => {
  it("lists object keys through a spread and list names", () => {
    const document = ConfigDocument.parse(
      `const shared = { drive: {}, tags: {} };
export default {
  blocks: { ...shared, "time-tracking": {}, notes },
  list: ["a", { name: "b" }, { block: "c" }],
};
`,
    );

    expect(document.keys(["blocks"])).toEqual([
      "drive",
      "tags",
      "time-tracking",
      "notes",
    ]);
    expect(document.keys(["list"])).toEqual(["a", "b", "c"]);
    expect(document.keys(["missing"])).toBeUndefined();
  });
});

describe("ConfigDocument.ensure", () => {
  it("creates the objects above the path at the file's indent", () => {
    const document = ConfigDocument.parse(
      `export default {\n  blocks: {\n    drive: {\n      tables: {},\n    },\n  },\n};\n`,
    );

    expect(
      document.ensure(["blocks", "drive", "columns", "nodes", "x"], '"y"'),
    ).toEqual({ status: "done" });
    expect(document.text).toBe(
      `export default {\n  blocks: {\n    drive: {\n      tables: {},\n      columns: {\n        nodes: {\n          x: "y",\n        },\n      },\n    },\n  },\n};\n`,
    );
  });

  it("keeps CRLF line endings", () => {
    const document = ConfigDocument.parse(
      `export default {\r\n  blocks: {\r\n    drive: {\r\n      a: 1,\r\n    },\r\n  },\r\n};\r\n`,
    );

    document.ensure(["blocks", "drive", "columns", "nodes", "x"], '"y"');

    expect(document.text).not.toMatch(/[^\r]\n/);
    expect(document.text).toContain('x: "y"');
  });

  it("reports a block that is not an object literal and leaves the text", () => {
    const text = `export default { blocks: { drive: true } };`;
    const document = ConfigDocument.parse(text);
    const result = document.ensure(["blocks", "drive", "columns", "a"], '"b"');

    expect(result.status).toBe("review");
    expect(document.text).toBe(text);
    expect(document.review).toHaveLength(1);
  });
});

describe("rewriteSource", () => {
  it("lists a file that does not parse instead of skipping it", () => {
    const result = rewriteSource("const = ;\n", () => {
      throw new Error("not called");
    });

    expect(result.text).toBe("const = ;\n");
    expect(result.review[0]?.message).toContain("does not parse");
  });

  it("returns the reports with their line", () => {
    const result = rewriteSource("a;\nb;\n", ({ report }) => {
      report(3, "look here");
    });

    expect(result.review).toEqual([{ line: 2, message: "look here" }]);
  });
});
