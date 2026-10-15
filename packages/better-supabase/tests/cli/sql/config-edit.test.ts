import { describe, expect, it } from "vitest";

import {
  addBlocksToConfig,
  addBlocksToJson,
  addBlocksToWiring,
  setBlockInConfig,
  setBlockInJson,
  setPresetInConfig,
  setPresetInJson,
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
  if (!result.ok) throw new Error(result.reason);
  return result.text;
};

describe("setBlockInConfig", () => {
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

  it("turns a blocks list into an object, and adds blocks when there is none", () => {
    const listed = setBlock(
      "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  blocks: ['tags'],\n});\n",
    );
    expect(listed).toContain(
      "  blocks: {\n    tags: {},\n    teams: {\n      mode: 'adopt',",
    );
    const added = setBlock(
      'export default defineConfig({\n  casing: "camel",\n});\n',
    );
    expect(added).toContain(
      '  casing: "camel",\n  blocks: {\n    teams: {\n      mode: "adopt",',
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
  it("sets the entry, turning a list into an object", () => {
    const result = setBlockInJson(
      '{\n  "blocks": ["tags"]\n}\n',
      "teams",
      ADOPTED,
    );
    expect(result.ok && JSON.parse(result.text)).toEqual({
      blocks: { tags: {}, teams: ADOPTED },
    });
    const object = setBlockInJson('{"blocks":{"teams":{}}}', "teams", {});
    expect(object.ok && JSON.parse(object.text)).toEqual({
      blocks: { teams: {} },
    });
  });

  it("keeps the file as it is when the entry holds the same values", () => {
    const source = '{ "blocks": { "teams": { "mode": "adopt" } } }\n';
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
