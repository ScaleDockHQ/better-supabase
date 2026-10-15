import { describe, expect, it } from "vitest";

import {
  addBlocksToConfig,
  addBlocksToJson,
} from "../../../src/cli/sql/config-edit.ts";

const edited = (source: string, names: readonly string[]): string => {
  const result = addBlocksToConfig(source, names);
  if (!result.ok) throw new Error(result.reason);
  return result.text;
};

describe("addBlocksToConfig", () => {
  it("appends keys to an object, one per line, keeping the trailing comma", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  sql: { api: "api" },
  blocks: {
    // The fixture writes the memberships table itself.
    tenant: { mode: "custom", tables: { memberships: "public.memberships" } },
    "api-keys": {},
  },
});
`;
    expect(edited(source, ["tags", "saved-views"]))
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  sql: { api: "api" },
  blocks: {
    // The fixture writes the memberships table itself.
    tenant: { mode: "custom", tables: { memberships: "public.memberships" } },
    "api-keys": {},
    tags: {},
    "saved-views": {},
  },
});
`);
  });

  it("skips blocks the object already lists", () => {
    const source = `export default defineConfig({ blocks: { tags: {} } });`;
    expect(edited(source, ["tags", "comments"])).toBe(
      `export default defineConfig({ blocks: { tags: {}, comments: {} } });`,
    );
    expect(edited(source, ["tags"])).toBe(source);
  });

  it("appends names to a list in its quote style", () => {
    const source = `export default defineConfig({
  blocks: ['audit', 'jobs']
});`;
    expect(edited(source, ["jobs", "invitations"]))
      .toBe(`export default defineConfig({
  blocks: ['audit', 'jobs', 'invitations']
});`);
  });

  it("adds blocks to a config without them", () => {
    expect(
      edited(
        `export default defineConfig({
  schemas: ["public"],
  sql: {
    dir: "supabase/schemas"
  }
});`,
        ["tags"],
      ),
    ).toBe(`export default defineConfig({
  schemas: ["public"],
  sql: {
    dir: "supabase/schemas"
  },
  blocks: { tags: {} }
});`);
    expect(
      edited(
        `export default defineConfig({
  schemas: ["public"],
});`,
        ["tags"],
      ),
    ).toBe(`export default defineConfig({
  schemas: ["public"],
  blocks: { tags: {} },
});`);
    expect(edited("export default {};", ["tags"])).toBe(
      "export default { blocks: { tags: {} } };",
    );
  });

  it("fills an empty multi-line object", () => {
    expect(
      edited(
        `export default defineConfig({
  blocks: {
  },
});`,
        ["tags"],
      ),
    ).toBe(`export default defineConfig({
  blocks: {
    tags: {},
  },
});`);
  });

  it("ignores braces and keys inside strings and comments", () => {
    const source = `export default defineConfig({
  // blocks: {}
  name: "blocks: { }",
  blocks: { audit: { options: { exempt: ["public.}*"] } } },
});`;
    expect(edited(source, ["tags"])).toContain(
      `blocks: { audit: { options: { exempt: ["public.}*"] } }, tags: {} },`,
    );
  });

  it("refuses a config it can't follow", () => {
    expect(
      addBlocksToConfig("export default defineConfig(base);", ["tags"]),
    ).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
    expect(
      addBlocksToConfig("export default defineConfig({ blocks: shared });", [
        "tags",
      ]),
    ).toEqual({
      ok: false,
      reason: "its blocks key isn't a literal object or list",
    });
  });
});

describe("addBlocksToConfig with other property shapes", () => {
  it("reads past spreads, methods, computed and shorthand keys", () => {
    const source = `const plugins = {};
module.exports = {
  ...base,
  plugins,
  ["computed"]: 1,
  'quoted': \`a \${"}"} b\`,
  hook(value) { return { value }; },
  blocks: { audit: {} },
}; // trailing`;
    expect(edited(source, ["tags"])).toContain(
      "blocks: { audit: {}, tags: {} },",
    );
  });

  it("refuses an object it can't read", () => {
    expect(
      addBlocksToConfig("export default defineConfig({ 1: 2 });", ["tags"]),
    ).toEqual({
      ok: false,
      reason: "its config object can't be read",
    });
    expect(
      addBlocksToConfig("export default defineConfig({ blocks: { 1: 2 } });", [
        "tags",
      ]),
    ).toEqual({ ok: false, reason: "its blocks object can't be read" });
    expect(
      addBlocksToConfig("export default defineConfig({ blocks: {", ["tags"]),
    ).toEqual({ ok: false, reason: "its config object can't be read" });
    expect(
      addBlocksToConfig('export default defineConfig({ name: "open', ["tags"]),
    ).toEqual({ ok: false, reason: "its config object can't be read" });
    expect(addBlocksToConfig("export default config;", ["tags"])).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
  });

  it("appends to an empty or multi-line list, and skips names it lists", () => {
    expect(
      edited("export default defineConfig({ blocks: [] });", [
        "tags",
        "api-keys",
      ]),
    ).toBe('export default defineConfig({ blocks: ["tags", "api-keys"] });');
    expect(
      edited(
        `export default defineConfig({
  blocks: [
    "audit",
  ],
});`,
        ["audit", "jobs"],
      ),
    ).toBe(`export default defineConfig({
  blocks: [
    "audit",
    "jobs",
  ],
});`);
    const listed = 'export default defineConfig({ blocks: ["tags"] });';
    expect(edited(listed, ["tags"])).toBe(listed);
  });

  it("quotes names that aren't identifiers as keys", () => {
    expect(
      edited("export default defineConfig({ blocks: {} });", ["api-keys"]),
    ).toBe('export default defineConfig({ blocks: { "api-keys": {} } });');
  });
});

describe("addBlocksToJson", () => {
  it("adds to an object or a list and keeps the indent", () => {
    const result = addBlocksToJson(`{\n    "blocks": { "audit": {} }\n}\n`, [
      "tags",
    ]);
    expect(result).toEqual({
      ok: true,
      text: `{\n    "blocks": {\n        "audit": {},\n        "tags": {}\n    }\n}\n`,
    });
    expect(
      addBlocksToJson(`{ "blocks": ["audit"] }`, ["audit", "jobs"]),
    ).toEqual({
      ok: true,
      text: `{\n  "blocks": [\n    "audit",\n    "jobs"\n  ]\n}\n`,
    });
    expect(addBlocksToJson("[]", ["tags"])).toEqual({
      ok: false,
      reason: "it isn't a JSON object",
    });
    expect(addBlocksToJson("{", ["tags"])).toEqual({
      ok: false,
      reason: "it isn't valid JSON",
    });
    expect(addBlocksToJson('{ "blocks": 1 }', ["tags"])).toEqual({
      ok: false,
      reason: "its blocks key isn't an object or a list",
    });
    expect(addBlocksToJson('{ "sql": { "dir": "x" } }', ["tags"])).toEqual({
      ok: true,
      text: `{\n  "sql": {\n    "dir": "x"\n  },\n  "blocks": {\n    "tags": {}\n  }\n}\n`,
    });
  });
});
