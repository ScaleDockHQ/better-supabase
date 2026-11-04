import { describe, expect, it } from "vitest";

import {
  docComment,
  importStatement,
  pureExport,
} from "../../../src/cli/gen/layout.ts";

describe("importStatement", () => {
  it("keeps a short import on one line", () => {
    expect(importStatement(["a", "b"], "pkg")).toEqual([
      'import { a, b } from "pkg";',
    ]);
  });

  it("breaks an import wider than 80 columns, one name per line", () => {
    const names = ["averyveryverylongname", "anotherveryveryverylongname"];

    expect(
      importStatement(names, "some/long/package/path/that/is/wide"),
    ).toEqual([
      "import {",
      "  averyveryverylongname,",
      "  anotherveryveryverylongname,",
      '} from "some/long/package/path/that/is/wide";',
    ]);
  });
});

describe("docComment", () => {
  it("puts a short comment on one line", () => {
    expect(docComment("Short.")).toEqual(["/** Short. */"]);
  });
});

describe("pureExport", () => {
  it("breaks after the equals sign when the callee is too long", () => {
    const name = "a".repeat(40);
    const callee = "b".repeat(40);

    expect(pureExport(name, callee, ["x"])).toEqual([
      `export const ${name} =`,
      `  /*#__PURE__*/ ${callee}(`,
      "    x,",
      "  );",
    ]);
  });
});
