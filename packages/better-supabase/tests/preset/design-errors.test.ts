import { describe, expect, it } from "vitest";

import {
  decodeDesign,
  DesignParseError,
  DesignTooLongError,
  namedPreset,
  parseDesign,
  readDesignFile,
  resolvePreset,
  safeDesignFileSource,
  safeParseDesign,
} from "../../src/preset/index.ts";

const crm = resolvePreset(namedPreset("crm"));

const issueOf = (value: unknown): { code: string; path: string } => {
  const result = safeParseDesign(value);

  if (result.ok) {
    throw new Error("expected an issue");
  }

  const [issue] = result.issues;

  return { code: issue?.code ?? "", path: issue?.path ?? "" };
};

describe("safeParseDesign", () => {
  it("returns the design without its empty parts", () => {
    expect(
      safeParseDesign({
        extraColumns: { tags: { color: "text" } },
        positions: {},
      }),
    ).toEqual({
      ok: true,
      design: { extraColumns: { tags: { color: "text" } } },
    });
  });

  it.each([
    ["a non-object", [], "invalid_design", ""],
    ["an unknown key", { tables: {} }, "unknown_key", "/tables"],
    ["a newer format", { version: 99 }, "unsupported_format", "/version"],
    [
      "an unknown block",
      { extraColumns: { nope: { a: "text" } } },
      "unknown_block",
      "/extraColumns/nope",
    ],
    [
      "a bad column name",
      { extraColumns: { tags: { "Bad Name": "text" } } },
      "invalid_name",
      "/extraColumns/tags/Bad Name",
    ],
    [
      "a bad SQL type",
      { extraColumns: { tags: { color: "text; drop table x" } } },
      "invalid_type",
      "/extraColumns/tags/color",
    ],
    [
      "a bad position",
      { positions: { "app.tasks": [1, "x"] } },
      "invalid_position",
      "/positions/app.tasks",
    ],
    [
      "a key with a slash",
      { positions: { "a/b": [1, 2] } },
      "invalid_name",
      "/positions/a~1b",
    ],
  ])("reports %s", (_, value, code, path) => {
    expect(issueOf(value)).toEqual({ code, path });
  });

  it("points into an app table column", () => {
    expect(
      issueOf({
        appTables: { tasks: { columns: { title: { type: "money" } } } },
      }),
    ).toEqual({
      code: "invalid_app_table",
      path: "/appTables/tasks/columns/title/type",
    });
  });

  it("resolves a table name with a dot or a space", () => {
    expect(issueOf({ appTables: { "My Table": {} } }).path).toBe(
      "/appTables/My Table",
    );
  });

  it("never throws, and each issue is plain JSON", () => {
    const result = safeParseDesign({ appTables: "x" });

    expect(result.ok).toBe(false);
    expect(JSON.parse(JSON.stringify(result))).toEqual(result);
  });
});

describe("DesignParseError", () => {
  it("is what parseDesign throws, and still a TypeError", () => {
    expect(() => parseDesign({ tables: {} })).toThrow(DesignParseError);
    expect(() => parseDesign({ tables: {} })).toThrow(TypeError);
  });

  it("carries invalid_code for a damaged design code", async () => {
    await expect(decodeDesign("0!!!")).rejects.toMatchObject({
      code: "invalid_code",
      path: "",
    });
  });

  it("makes DesignTooLongError a too_long issue", () => {
    expect(new DesignTooLongError(9000)).toMatchObject({
      code: "too_long",
      path: "",
    });
  });

  it("points into a design file at the same paths as a design", () => {
    const text = JSON.stringify({
      preset: "crm",
      extraColumns: { nope: { a: "text" } },
    });

    expect(() => readDesignFile(text)).toThrow(
      expect.objectContaining({
        code: "unknown_block",
        path: "/extraColumns/nope",
      }),
    );
  });

  it("reports a design file's bad preset at /preset", () => {
    expect(() => readDesignFile('{"preset":"nope"}')).toThrow(
      expect.objectContaining({ code: "invalid_preset", path: "/preset" }),
    );
  });
});

describe("safeDesignFileSource", () => {
  it("returns the file text", () => {
    const result = safeDesignFileSource(crm, {});

    expect(result.ok && JSON.parse(result.source)).toEqual({
      version: 7,
      preset: "crm",
    });
  });

  it("returns the issue for an invalid design", () => {
    expect(
      safeDesignFileSource(crm, { extraColumns: { nope: { a: "text" } } }),
    ).toEqual({
      ok: false,
      issues: [
        {
          code: "unknown_block",
          path: "/extraColumns/nope",
          message: 'design.extraColumns.nope: "nope" is not a block',
        },
      ],
    });
  });
});
