import { describe, expect, it } from "vitest";

import {
  addBlocksToConfig,
  addBlocksToJson,
  addBlocksToWiring,
  cutRange,
  mask,
  properties,
  setBlockInConfig,
  setBlockInJson,
  setPresetInConfig,
  setPathInConfig,
  setPathInJson,
  setPresetInJson,
  tidyInline,
} from "../../../src/cli/sql/config-edit.ts";

const edited = (source: string, names: readonly string[]): string => {
  const result = addBlocksToConfig(source, names);

  if (!result.ok) {
    throw new Error(result.reason);
  }

  return result.text;
};

describe("addBlocksToConfig", () => {
  it("appends keys to an object, one per line, keeping the trailing comma", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  sql: { api: "api" },
  blocks: {
    // The fixture writes the memberships table itself.
    memberships: { mode: "custom", tables: { memberships: "public.memberships" } },
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
    memberships: { mode: "custom", tables: { memberships: "public.memberships" } },
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
  blocks: ['audit', 'queue']
});`;

    expect(edited(source, ["queue", "invitations"]))
      .toBe(`export default defineConfig({
  blocks: ['audit', 'queue', 'invitations']
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
  blocks: ["tags"]
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
  blocks: ["tags"],
});`);
    expect(edited("export default {};", ["tags"])).toBe(
      `export default { blocks: ["tags"] };`,
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
    ).toEqual({ ok: false, reason: "its config object can't be read" });
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
        ["audit", "queue"],
      ),
    ).toBe(`export default defineConfig({
  blocks: [
    "audit",
    "queue",
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
  it("adds to a list and keeps the indent", () => {
    const result = addBlocksToJson(`{\n    "blocks": ["audit"]\n}\n`, ["tags"]);

    expect(result).toEqual({
      ok: true,
      text: `{\n    "blocks": [\n        "audit",\n        "tags"\n    ]\n}\n`,
    });
    expect(
      addBlocksToJson(`{ "blocks": [{ "block": "tags", "name": "labels" }] }`, [
        "labels",
        "tags",
      ]),
    ).toEqual({
      ok: true,
      text: `{\n  "blocks": [\n    {\n      "block": "tags",\n      "name": "labels"\n    },\n    "tags"\n  ]\n}\n`,
    });
    expect(
      addBlocksToJson(`{ "blocks": ["audit"] }`, ["audit", "queue"]),
    ).toEqual({
      ok: true,
      text: `{\n  "blocks": [\n    "audit",\n    "queue"\n  ]\n}\n`,
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
      text: `{\n  "sql": {\n    "dir": "x"\n  },\n  "blocks": [\n    "tags"\n  ]\n}\n`,
    });
  });
});

describe("setPresetInConfig", () => {
  it("adds preset, or replaces the one there, in the file's quotes", () => {
    const single =
      "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  casing: 'snake',\n});\n";

    expect(setPresetInConfig(single, "saas")).toEqual({
      ok: true,
      text: single.replace(
        "  casing: 'snake',\n",
        "  casing: 'snake',\n  preset: 'saas',\n",
      ),
    });
    const double = 'export default defineConfig({ preset: "crm" });\n';
    expect(setPresetInConfig(double, "1abc")).toEqual({
      ok: true,
      text: 'export default defineConfig({ preset: "1abc" });\n',
    });
  });

  it("refuses a config it can't follow", () => {
    expect(setPresetInConfig("export default config;\n", "saas")).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
    expect(
      setPresetInConfig("export default defineConfig({ a: ", "saas").ok,
    ).toBe(false);
  });
});

describe("setPresetInJson", () => {
  it("sets preset and keeps the indent", () => {
    expect(setPresetInJson('{\n    "casing": "camel"\n}\n', "saas")).toEqual({
      ok: true,
      text: '{\n    "casing": "camel",\n    "preset": "saas"\n}\n',
    });
    expect(setPresetInJson("[]", "saas").ok).toBe(false);
    expect(setPresetInJson("{", "saas").ok).toBe(false);
  });
});

describe("addBlocksToWiring", () => {
  const block = {
    key: "comments",
    export: "commentsBlock",
    subpath: "better-supabase/blocks/comments",
  };

  it("adds the import and the entry once", () => {
    const source =
      'import { createBlocks } from "better-supabase/blocks";\n\nexport const blocks = createBlocks({ transport }, { tags: tagsBlock });\n';

    const edit = addBlocksToWiring(source, [block]);
    expect(edit).toEqual({
      ok: true,
      text: 'import { createBlocks } from "better-supabase/blocks";\nimport { commentsBlock } from "better-supabase/blocks/comments";\n\nexport const blocks = createBlocks({ transport }, { tags: tagsBlock, comments: commentsBlock });\n',
    });
    expect(edit.ok && addBlocksToWiring(edit.text, [block])).toEqual({
      ok: true,
      text: edit.ok ? edit.text : "",
    });
  });

  it("adds to the blocks object of defineBlocks(blockConfig, { ... })", () => {
    const edit = addBlocksToWiring(
      "export const blockSet = defineBlocks(blockConfig, { tags: tagsBlock });\n",
      [block],
    );

    expect(edit).toEqual({
      ok: true,
      text: 'import { commentsBlock } from "better-supabase/blocks/comments";\n\nexport const blockSet = defineBlocks(blockConfig, { tags: tagsBlock, comments: commentsBlock });\n',
    });
  });

  it("puts the import first in a file without imports", () => {
    const edit = addBlocksToWiring("createBlocks(options, {});\n", [block]);
    expect(edit).toEqual({
      ok: true,
      text: 'import { commentsBlock } from "better-supabase/blocks/comments";\n\ncreateBlocks(options, { comments: commentsBlock });\n',
    });
  });

  it("refuses wiring it can't follow", () => {
    expect(addBlocksToWiring("export {};\n", [block])).toEqual({
      ok: false,
      reason: "it doesn't call defineBlocks() or createBlocks()",
    });
    expect(
      addBlocksToWiring("createBlocks(options, blocks);\n", [block]),
    ).toEqual({
      ok: false,
      reason: "createBlocks() isn't passed an object literal of blocks",
    });
    expect(addBlocksToWiring("createBlocks(options, { a: ", [block]).ok).toBe(
      false,
    );
  });
});

const ADOPTED = {
  mode: "adopt",
  tables: { teams: "public.teams", members: null },
  columns: { teams: { tenant: "organization_id" } },
};

const setBlock = (source: string): string => {
  const result = setBlockInConfig(source, "teams", ADOPTED);

  if (!result.ok) {
    throw new Error(result.reason);
  }

  return result.text;
};

describe("setBlockInConfig", () => {
  it("does not take a comment or a regular expression for the config", () => {
    const text = setBlock(`// export default { blocks: [] }
const quote = /"/;
export default defineConfig({
  blocks: ["teams"],
});
`);

    expect(text).toContain("// export default { blocks: [] }");
    expect(text).toContain("block:");
  });

  it("writes `name: value` for a shorthand property, never a syntax error", () => {
    const text = setBlock(`export default defineConfig({
  blocks: {
    teams,
  },
});
`);

    expect(text).toContain("teams: {");
    expect(text).not.toMatch(/\{\s*\{/);
  });

  it("refuses a method property instead of dropping its body", () => {
    const result = setBlockInConfig(
      `export default defineConfig({ blocks: { teams() { return {}; } } });\n`,
      "teams",
      ADOPTED,
    );

    expect(result).toEqual({
      ok: false,
      reason: "blocks.teams is a method, not a value",
    });
  });

  it("replaces an entry in a blocks object, or appends one", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: {
    teams: {},
    "api-keys": {},
  },
});
`;

    const replaced = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: {
    teams: {
      mode: "adopt",
      tables: {
        teams: "public.teams",
        members: null,
      },
      columns: {
        teams: {
          tenant: "organization_id",
        },
      },
    },
    "api-keys": {},
  },
});
`;

    expect(setBlock(source)).toBe(replaced);
    expect(setBlock(source.replace("    teams: {},\n", ""))).toBe(
      `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: {
    "api-keys": {},
    teams: {
      mode: "adopt",
      tables: {
        teams: "public.teams",
        members: null,
      },
      columns: {
        teams: {
          tenant: "organization_id",
        },
      },
    },
  },
});
`,
    );
  });

  it("sets an entry in a blocks list, and adds a list when there is none", () => {
    const listed = setBlock(
      "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  blocks: ['tags'],\n});\n",
    );

    expect(listed).toContain(
      "  blocks: ['tags', {\n    block: 'teams',\n    mode: 'adopt',",
    );

    const added = setBlock(
      'export default defineConfig({\n  casing: "camel",\n});\n',
    );

    expect(added).toContain(
      '  casing: "camel",\n  blocks: [{\n    block: "teams",\n    mode: "adopt",',
    );
  });

  it("refuses what it can't read", () => {
    expect(setBlockInConfig("export const x = 1;", "teams", {})).toEqual({
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    });
    expect(
      setBlockInConfig("defineConfig({ blocks: names });", "teams", {}),
    ).toEqual({
      ok: false,
      reason: "its blocks key isn't a literal object or list",
    });
  });
});

describe("setBlockInJson", () => {
  it("sets the entry in the list and refuses the object form", () => {
    const result = setBlockInJson(
      '{\n  "blocks": ["tags"]\n}\n',
      "teams",
      ADOPTED,
    );

    expect(result.ok && JSON.parse(result.text)).toEqual({
      blocks: ["tags", { block: "teams", ...ADOPTED }],
    });
    expect(setBlockInJson('{"blocks":{"teams":{}}}', "teams", {}).ok).toBe(
      false,
    );
  });

  it("keeps the file as it is when the entry holds the same values", () => {
    const source =
      '{\n  "blocks": [\n    {\n      "block": "teams",\n      "mode": "adopt"\n    }\n  ]\n}\n';

    expect(setBlockInJson(source, "teams", { mode: "adopt" })).toEqual({
      ok: true,
      text: source,
    });
  });

  it("refuses what isn't a JSON object with readable blocks", () => {
    expect(setBlockInJson("{", "teams", {}).ok).toBe(false);
    expect(setBlockInJson("[]", "teams", {}).ok).toBe(false);
    expect(setBlockInJson('{"blocks":1}', "teams", {}).ok).toBe(false);
  });
});

describe("setPathInConfig", () => {
  const source =
    "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  blocks: ['tags'],\n  appTables: {\n    links: { columns: { url: { type: 'text' } } },\n  },\n});\n";

  const set = (
    text: string,
    path: readonly [string, ...string[]],
    value: unknown,
  ): string => {
    const result = setPathInConfig(text, path, value);

    if (!result.ok) {
      throw new Error(result.reason);
    }

    return result.text;
  };

  it("adds a key in an object and keeps the others", () => {
    const text = set(source, ["appTables", "notes"], {
      columns: { body: { type: "text", default: "it's" } },
      index: ["body"],
    });

    expect(text).toContain(
      "    links: { columns: { url: { type: 'text' } } },",
    );
    expect(text).toContain('default: "it\'s"');
    expect(text).toContain("index: ['body']");
  });

  it("replaces the value at the end of the path", () => {
    const text = set(source, ["appTables", "links"], { columns: {} });
    expect(text).toContain("    links: {\n      columns: {},\n    },");
  });

  it("creates the objects on the way, and turns a listed name into an entry", () => {
    const text = set(
      source,
      ["blocks", "profiles", "options", "extraColumns"],
      { nickname: "text" },
    );

    expect(text).toContain("'tags'");
    expect(text).toContain("block: 'profiles'");
    expect(text).toContain("nickname: 'text'");
    expect(set(source, ["casing"], "camel")).toContain("casing: 'camel'");
  });
});

describe("setPathInJson", () => {
  it("sets a nested key, and turns a listed name into an entry", () => {
    const result = setPathInJson(
      '{\n  "blocks": ["tags"]\n}\n',
      ["blocks", "profiles", "options", "extraColumns"],
      { nickname: "text" },
    );

    expect(result.ok && JSON.parse(result.text)).toEqual({
      blocks: [
        "tags",
        { block: "profiles", options: { extraColumns: { nickname: "text" } } },
      ],
    });
    expect(setPathInJson("[]", ["casing"], "camel").ok).toBe(false);
  });
});

describe("setPathInJson edges", () => {
  const json =
    '{\n  "blocks": ["tags", { "block": "files", "options": { "a": 1 } }]\n}\n';

  const parsed = (path: readonly [string, ...string[]], value: unknown) => {
    const result = setPathInJson(json, path, value);

    return result.ok ? JSON.parse(result.text) : result.reason;
  };

  it("rejects text that is not JSON", () => {
    expect(setPathInJson("{", ["casing"], "camel")).toEqual({
      ok: false,
      reason: "it isn't valid JSON",
    });
  });

  it("merges into a listed entry and keeps the list order", () => {
    expect(parsed(["blocks", "files", "options", "b"], 2)).toEqual({
      blocks: ["tags", { block: "files", options: { a: 1, b: 2 } }],
    });
    expect(parsed(["blocks", "tags", "options", "x"], true)).toEqual({
      blocks: [
        { block: "tags", options: { x: true } },
        { block: "files", options: { a: 1 } },
      ],
    });
  });

  it("replaces a listed entry with a whole value", () => {
    expect(parsed(["blocks", "files"], "files")).toEqual({
      blocks: ["tags", "files"],
    });
    expect(parsed(["blocks", "files"], { options: {} })).toEqual({
      blocks: ["tags", { block: "files", options: {} }],
    });
  });

  it("creates objects on the way over a scalar", () => {
    const result = setPathInJson('{ "sql": 1 }', ["sql", "dir"], "db");

    expect(result.ok && JSON.parse(result.text)).toEqual({
      sql: { dir: "db" },
    });
  });
});

describe("setPathInConfig edges", () => {
  it("refuses a path through a value that is not an object literal", () => {
    expect(
      setPathInConfig(
        "export default defineConfig({ appTables: shared });\n",
        ["appTables", "notes"],
        {},
      ),
    ).toEqual({
      ok: false,
      reason: "its appTables key isn't a literal object",
    });
  });
});

describe("cutRange", () => {
  const range = (source: string, index: number, multiline: boolean) => {
    const code = mask(source);
    const open = source.indexOf("{");

    return cutRange(
      source,
      code,
      open,
      properties(source, code, open)!,
      index,
      multiline,
    );
  };

  it("cuts an inline property with its comma", () => {
    const source = "{ a: 1, b: 2 }";
    const cut = range(source, 0, false);

    expect(cut.text).toBe("a: 1");
    expect(source.slice(0, cut.start) + source.slice(cut.end)).toBe("{ b: 2 }");
    expect(range(source, 1, false).text).toBe("b: 2");
  });

  it("cuts a whole line with its trailing comment", () => {
    const source = "{\n  a: 1,\n  b: 2, // note\n  c: 3\n}";
    const cut = range(source, 1, true);

    expect(cut.text).toBe("  b: 2, // note");
    expect(source.slice(0, cut.start) + source.slice(cut.end)).toBe(
      "{\n  a: 1,\n  c: 3\n}",
    );
  });

  it("stops at the comma when code follows on the line", () => {
    const source = "{ a: 1, b: 2 }";
    const cut = range(source, 0, true);

    expect(cut.text).toBe(" a: 1,");
    expect(cut.end).toBe(source.indexOf(",") + 1);
  });
});

describe("tidyInline", () => {
  it("empties a blank object and drops a dangling comma", () => {
    expect(tidyInline("x = {  }", 4)).toBe("x = {}");
    expect(tidyInline("x = { a: 1, }", 4)).toBe("x = { a: 1 }");
    expect(tidyInline("x = [1, ]", 4)).toBe("x = [1]");
  });
});

describe("addBlocksToJson with a blocks object", () => {
  it("adds the missing names as empty entries and keeps the others", () => {
    const result = addBlocksToJson(
      '{\n  "blocks": { "tags": { "a": 1 } }\n}\n',
      ["tags", "files"],
    );

    expect(result.ok && JSON.parse(result.text)).toEqual({
      blocks: { tags: { a: 1 }, files: {} },
    });
  });
});
