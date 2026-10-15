import { describe, expect, it } from "vitest";

import {
  addModulesToConfig,
  addModulesToJson,
} from "../../../src/cli/sql/config-edit.ts";

const edited = (source: string, names: readonly string[]): string => {
  const result = addModulesToConfig(source, names);
  if (!result.ok) throw new Error(result.reason);
  return result.text;
};

describe("addModulesToConfig", () => {
  it("appends keys to an object, one per line, keeping the trailing comma", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  sql: {
    api: "api",
    modules: {
      // The fixture writes the memberships table itself.
      tenant: { mode: "custom", tables: { memberships: "public.memberships" } },
      "api-keys": {},
    },
  },
});
`;
    expect(edited(source, ["tags", "saved-views"]))
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  sql: {
    api: "api",
    modules: {
      // The fixture writes the memberships table itself.
      tenant: { mode: "custom", tables: { memberships: "public.memberships" } },
      "api-keys": {},
      tags: {},
      "saved-views": {},
    },
  },
});
`);
  });

  it("skips modules the object already lists", () => {
    const source = `export default defineConfig({ sql: { modules: { tags: {} } } });`;
    expect(edited(source, ["tags", "comments"])).toBe(
      `export default defineConfig({ sql: { modules: { tags: {}, comments: {} } } });`,
    );
    expect(edited(source, ["tags"])).toBe(source);
  });

  it("appends names to a list in its quote style", () => {
    const source = `export default defineConfig({
  sql: {
    modules: ['audit', 'jobs']
  }
});`;
    expect(edited(source, ["jobs", "invitations"]))
      .toBe(`export default defineConfig({
  sql: {
    modules: ['audit', 'jobs', 'invitations']
  }
});`);
  });

  it("adds modules to a sql object without them, and sql to a config without it", () => {
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
    dir: "supabase/schemas",
    modules: { tags: {} }
  }
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
  sql: { modules: { tags: {} } },
});`);
    expect(edited("export default {};", ["tags"])).toBe(
      "export default { sql: { modules: { tags: {} } } };",
    );
  });

  it("fills an empty multi-line object", () => {
    expect(
      edited(
        `export default defineConfig({
  sql: {
    modules: {
    },
  },
});`,
        ["tags"],
      ),
    ).toBe(`export default defineConfig({
  sql: {
    modules: {
      tags: {},
    },
  },
});`);
  });

  it("ignores braces and keys inside strings and comments", () => {
    const source = `export default defineConfig({
  // sql: { modules: {} }
  name: "sql: { modules }",
  sql: { modules: { audit: { options: { exempt: ["public.}*"] } } } },
});`;
    expect(edited(source, ["tags"])).toContain(
      `sql: { modules: { audit: { options: { exempt: ["public.}*"] } }, tags: {} } },`,
    );
  });

  it("refuses a config it can't follow", () => {
    expect(
      addModulesToConfig("export default defineConfig(base);", ["tags"]),
    ).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
    expect(
      addModulesToConfig(
        "export default defineConfig({ sql: { modules: shared } });",
        ["tags"],
      ),
    ).toEqual({
      ok: false,
      reason: "its sql.modules isn't a literal object or list",
    });
    expect(
      addModulesToConfig("export default defineConfig({ sql: base });", [
        "tags",
      ]),
    ).toEqual({ ok: false, reason: "its sql key isn't an object literal" });
  });
});

describe("addModulesToConfig with other property shapes", () => {
  it("reads past spreads, methods, computed and shorthand keys", () => {
    const source = `const plugins = {};
module.exports = {
  ...base,
  plugins,
  ["computed"]: 1,
  'quoted': \`a \${"}"} b\`,
  hook(value) { return { value }; },
  sql: { modules: { audit: {} } },
}; // trailing`;
    expect(edited(source, ["tags"])).toContain(
      "sql: { modules: { audit: {}, tags: {} } },",
    );
  });

  it("refuses an object it can't read", () => {
    expect(
      addModulesToConfig("export default defineConfig({ 1: 2 });", ["tags"]),
    ).toEqual({
      ok: false,
      reason: "its config object can't be read",
    });
    expect(
      addModulesToConfig("export default defineConfig({ sql: { 1: 2 } });", [
        "tags",
      ]),
    ).toEqual({ ok: false, reason: "its sql object can't be read" });
    expect(
      addModulesToConfig(
        "export default defineConfig({ sql: { modules: { 1: 2 } } });",
        ["tags"],
      ),
    ).toEqual({ ok: false, reason: "its sql.modules object can't be read" });
    expect(
      addModulesToConfig("export default defineConfig({ sql: { modules: {", [
        "tags",
      ]),
    ).toEqual({ ok: false, reason: "its config object can't be read" });
    expect(
      addModulesToConfig('export default defineConfig({ name: "open', ["tags"]),
    ).toEqual({ ok: false, reason: "its config object can't be read" });
    expect(addModulesToConfig("export default config;", ["tags"])).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
  });

  it("appends to an empty or multi-line list, and skips names it lists", () => {
    expect(
      edited("export default defineConfig({ sql: { modules: [] } });", [
        "tags",
        "api-keys",
      ]),
    ).toBe(
      'export default defineConfig({ sql: { modules: ["tags", "api-keys"] } });',
    );
    expect(
      edited(
        `export default defineConfig({
  sql: {
    modules: [
      "audit",
    ],
  },
});`,
        ["audit", "jobs"],
      ),
    ).toBe(`export default defineConfig({
  sql: {
    modules: [
      "audit",
      "jobs",
    ],
  },
});`);
    const listed =
      'export default defineConfig({ sql: { modules: ["tags"] } });';
    expect(edited(listed, ["tags"])).toBe(listed);
  });

  it("quotes names that aren't identifiers as keys", () => {
    expect(
      edited("export default defineConfig({ sql: { modules: {} } });", [
        "api-keys",
      ]),
    ).toBe(
      'export default defineConfig({ sql: { modules: { "api-keys": {} } } });',
    );
  });
});

describe("addModulesToJson", () => {
  it("adds to an object or a list and keeps the indent", () => {
    const result = addModulesToJson(
      `{\n    "sql": { "modules": { "audit": {} } }\n}\n`,
      ["tags"],
    );
    expect(result).toEqual({
      ok: true,
      text: `{\n    "sql": {\n        "modules": {\n            "audit": {},\n            "tags": {}\n        }\n    }\n}\n`,
    });
    expect(
      addModulesToJson(`{ "sql": { "modules": ["audit"] } }`, [
        "audit",
        "jobs",
      ]),
    ).toEqual({
      ok: true,
      text: `{\n  "sql": {\n    "modules": [\n      "audit",\n      "jobs"\n    ]\n  }\n}\n`,
    });
    expect(addModulesToJson("[]", ["tags"])).toEqual({
      ok: false,
      reason: "it isn't a JSON object",
    });
    expect(addModulesToJson("{", ["tags"])).toEqual({
      ok: false,
      reason: "it isn't valid JSON",
    });
    expect(addModulesToJson('{ "sql": 1 }', ["tags"])).toEqual({
      ok: false,
      reason: "its sql key isn't an object",
    });
    expect(addModulesToJson('{ "sql": { "modules": 1 } }', ["tags"])).toEqual({
      ok: false,
      reason: "its sql.modules isn't an object or a list",
    });
    expect(addModulesToJson("{}", ["tags"])).toEqual({
      ok: true,
      text: `{\n  "sql": {\n    "modules": {\n      "tags": {}\n    }\n  }\n}\n`,
    });
  });
});
