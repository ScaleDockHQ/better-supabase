import { describe, expect, it } from "vitest";

import {
  addContentMapper,
  addRunExternalCode,
  hasContentMapper,
  schemaStampPath,
} from "../../src/cli/content-mapper.ts";

const ENTRY = { package: "better-supabase", extensions: [".bsb"] };

describe("addContentMapper", () => {
  it("appends the entry and keeps the indent", () => {
    const edit = addContentMapper(
      '{\n    "contentMappers": [{ "package": "other", "extensions": [".x"] }]\n}\n',
    );

    expect(edit.kind).toBe("edited");
    expect(edit.kind === "edited" && edit.contents).toBe(
      `${JSON.stringify(
        { contentMappers: [{ package: "other", extensions: [".x"] }, ENTRY] },
        null,
        4,
      )}\n`,
    );
  });

  it("leaves a tsconfig that lists it, even with comments", () => {
    expect(
      addContentMapper(
        `{\n  // types\n  "contentMappers": [${JSON.stringify(ENTRY)}],\n}\n`,
      ),
    ).toEqual({ kind: "unchanged" });
  });

  it("asks for a manual edit when rewriting would drop comments", () => {
    expect(addContentMapper("{\n  // types\n}\n")).toEqual({
      kind: "manual",
      reason: "it holds comments",
    });
  });
});

describe("addRunExternalCode", () => {
  it("adds the flag to the first tsc of the typecheck script", () => {
    const edit = addRunExternalCode(
      JSON.stringify({ scripts: { typecheck: "tsc -b && tsc -p e2e" } }),
    );

    expect(
      edit.kind === "edited" && JSON.parse(edit.contents).scripts.typecheck,
    ).toBe("tsc --runExternalCode -b && tsc -p e2e");
  });

  it("leaves a script that has it, and reports one it can't edit", () => {
    expect(
      addRunExternalCode(
        JSON.stringify({ scripts: { typecheck: "tsc --runExternalCode" } }),
      ),
    ).toEqual({ kind: "unchanged" });
    expect(
      addRunExternalCode(JSON.stringify({ scripts: { lint: "oxlint" } })),
    ).toEqual({
      kind: "manual",
      reason: "it has no typecheck script that runs tsc",
    });
  });
});

describe("content mapper helpers", () => {
  it("matches the entry by package and extension", () => {
    expect(hasContentMapper({ contentMappers: [ENTRY] })).toBe(true);
    expect(
      hasContentMapper({
        contentMappers: [{ package: "better-supabase", extensions: [".x"] }],
      }),
    ).toBe(false);
    expect(hasContentMapper({})).toBe(false);
  });

  it("names one stamp per output", () => {
    expect(schemaStampPath("/app", "src/a.ts")).toMatch(
      /^\/app\/node_modules\/\.cache\/better-supabase\/schema-[0-9a-f]{16}\.stamp$/,
    );
    expect(schemaStampPath("/app", "src/a.ts")).not.toBe(
      schemaStampPath("/app", "src/b.ts"),
    );
  });
});
