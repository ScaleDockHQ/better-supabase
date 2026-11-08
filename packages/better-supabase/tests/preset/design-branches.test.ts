import { describe, expect, it } from "vitest";

import {
  designConfig,
  designFileSource,
  designFormat,
  designSchema,
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

const tasks = (extra: Record<string, unknown>) => ({
  appTables: { tasks: { columns: { title: { type: "text" } }, ...extra } },
});

describe("designFormat", () => {
  it("reports the lowest format for each feature", () => {
    expect(designFormat({ seeds: { locale: "nl" } })).toBe(9);
    // SAFETY: the test passes only the instances key, the part designFormat reads.
    expect(designFormat({ preset: { instances: { a: "crm" } } as never })).toBe(
      8,
    );
    expect(designFormat({ preset: "crm" })).toBe(7);
    expect(
      designFormat({
        appTables: {
          tasks: { columns: { title: { type: "text" } }, auditReads: true },
        },
      }),
    ).toBe(6);
    expect(designFormat({})).toBe(0);
  });
});

describe("designSchema", () => {
  it("returns the design for a valid value", () => {
    expect(
      designSchema["~standard"].validate({ seeds: { locale: "nl" } }),
    ).toEqual({ value: { seeds: { locale: "nl" } } });
  });

  it("returns issues whose path lists the pointer keys", () => {
    expect(designSchema["~standard"].validate({ foo: 1 })).toEqual({
      issues: [
        {
          message: expect.stringContaining('unknown key "foo"'),
          path: ["foo"],
        },
      ],
    });

    expect(
      designSchema["~standard"].validate(tasks({ indexes: [5] })),
    ).toMatchObject({
      issues: [{ path: ["appTables", "tasks", "indexes", "0"] }],
    });

    expect(designSchema["~standard"].validate("text")).toMatchObject({
      issues: [{ path: [] }],
    });
  });
});

describe("design issue paths", () => {
  it("points into an array position of an app table", () => {
    expect(issueOf(tasks({ indexes: [5] }))).toEqual({
      code: "invalid_app_table",
      path: "/appTables/tasks/indexes/0",
    });
  });

  it("resolves a table name with a dot and a space", () => {
    expect(
      issueOf({ appTables: { "a.b c": { columns: { x: "nope" } } } }),
    ).toEqual({ code: "invalid_app_table", path: "/appTables/a.b c" });
  });

  it("points at the column that is not an object", () => {
    expect(issueOf(tasks({ columns: { title: 5 } })).path).toBe(
      "/appTables/tasks/columns/title",
    );
  });

  it("rejects an unknown table key and a non-object appTables", () => {
    expect(issueOf(tasks({ checks: [5] }))).toEqual({
      code: "invalid_app_table",
      path: "/appTables/tasks",
    });
    expect(issueOf({ appTables: [] }).path).toBe("/appTables");
  });
});

describe("design versions and non-object parts", () => {
  it("rejects a bad or newer version", () => {
    expect(issueOf({ version: -1 })).toEqual({
      code: "invalid_design",
      path: "/version",
    });
    expect(issueOf({ version: 1.5 }).code).toBe("invalid_design");
    expect(issueOf({ version: "1" }).code).toBe("invalid_design");
    expect(issueOf({ version: 99 })).toEqual({
      code: "unsupported_format",
      path: "/version",
    });
  });

  it("rejects positions that are not objects and the removed extraColumns key", () => {
    expect(issueOf({ positions: 5 }).path).toBe("/positions");
    expect(issueOf({ extraColumns: { tags: { a: "text" } } }).code).toBe(
      "unknown_key",
    );
  });

  it("rejects a preset that is neither a name nor an object", () => {
    expect(issueOf({ preset: 5 })).toEqual({
      code: "invalid_preset",
      path: "/preset",
    });
    expect(issueOf({ preset: { x: 1 } }).code).toBe("invalid_preset");
  });
});

describe("design seeds", () => {
  it("rejects each malformed shape with a pointer", () => {
    expect(issueOf({ seeds: [] }).path).toBe("/seeds");
    expect(issueOf({ seeds: { x: 1 } }).path).toBe("/seeds/x");
    expect(issueOf({ seeds: { locale: "NL" } }).path).toBe("/seeds/locale");
    expect(issueOf({ seeds: { locale: 5 } }).path).toBe("/seeds/locale");
    expect(issueOf({ seeds: { variants: [] } }).path).toBe("/seeds/variants");
    expect(issueOf({ seeds: { variants: { A: "b" } } }).path).toBe(
      "/seeds/variants/A",
    );
    expect(issueOf({ seeds: { variants: { a: 5 } } }).path).toBe(
      "/seeds/variants/a",
    );
  });

  it("drops empty seeds and keeps variants or locale alone", () => {
    expect(parseDesign({ seeds: {} })).toEqual({});
    expect(parseDesign({ seeds: { variants: {} } })).toEqual({});
    expect(parseDesign({ seeds: { variants: { crm: "demo" } } })).toEqual({
      seeds: { variants: { crm: "demo" } },
    });
    expect(parseDesign({ seeds: { locale: "nl-BE" } })).toEqual({
      seeds: { locale: "nl-BE" },
    });
  });

  it("reads and writes the sample size and random seed", () => {
    const seeds = { sample: { size: "l", seed: 42 } } as const;

    expect(parseDesign({ seeds })).toEqual({ seeds });
    expect(designFormat({ seeds })).toBe(9);
    expect(designConfig(crm, { seeds }).seed).toEqual({
      defaults: {},
      sample: { size: "l", seed: 42 },
    });
  });

  it("rejects a malformed sample with a pointer", () => {
    expect(issueOf({ seeds: { sample: 5 } }).path).toBe("/seeds/sample");
    expect(issueOf({ seeds: { sample: { size: "m", x: 1 } } }).path).toBe(
      "/seeds/sample/x",
    );
    expect(issueOf({ seeds: { sample: { size: "xl", seed: 1 } } }).path).toBe(
      "/seeds/sample/size",
    );
    expect(issueOf({ seeds: { sample: { size: "m", seed: 1.5 } } }).path).toBe(
      "/seeds/sample/seed",
    );
    expect(issueOf({ seeds: { sample: { size: "m", seed: -1 } } }).path).toBe(
      "/seeds/sample/seed",
    );
  });

  it("writes seeds into the config", () => {
    expect(designConfig(crm, { seeds: { locale: "nl" } }).seed).toEqual({
      defaults: { locale: "nl" },
    });
    expect(
      designConfig(crm, { seeds: { variants: { crm: "demo" } } }).seed,
    ).toEqual({ defaults: { variants: { crm: "demo" } } });
    expect(designConfig(crm, {}).seed).toBeUndefined();
  });
});

describe("design files", () => {
  it("returns the issue of an unreadable design file source", () => {
    // SAFETY: the test passes an unknown key on purpose.
    expect(safeDesignFileSource(crm, { foo: 1 } as never)).toMatchObject({
      ok: false,
      issues: [{ code: "unknown_key" }],
    });
  });

  it("writes the version of the design and reads it back", () => {
    const source = designFileSource(crm, { seeds: { locale: "nl" } });

    expect(JSON.parse(source)).toMatchObject({ version: 9 });
    expect(readDesignFile(source).design).toEqual({ seeds: { locale: "nl" } });
  });

  it("rejects a file without a preset or with text that is not JSON", () => {
    expect(() => readDesignFile("{}")).toThrow(/preset is missing/);
    expect(() => readDesignFile("{bad")).toThrow(/not JSON/);
    expect(() => readDesignFile('{"design":{}}')).toThrow(/0\.14/);
  });
});
