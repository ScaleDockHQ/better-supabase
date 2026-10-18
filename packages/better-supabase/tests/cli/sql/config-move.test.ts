import { describe, expect, it } from "vitest";

import {
  moveSqlModulesToBlocks,
  moveSqlModulesToBlocksJson,
} from "../../../src/cli/sql/config-move.ts";

const moved = (source: string): string => {
  const edit = moveSqlModulesToBlocks(source);

  if (!edit.ok) {
    throw new Error(edit.reason);
  }

  return edit.text;
};

describe("moveSqlModulesToBlocks", () => {
  it("moves sql.modules to a top-level blocks key, with its comments", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  schema: "public",
  // SQL-wide settings.
  sql: {
    dir: "supabase/schemas",
    // Blocks this app installs.
    modules: {
      tenant: { options: { column: "org_id" } }, // the tenant column
      access: {
        model: "roles",
        // keep "modules" here: it's a string
        functions: { canAssignFor: "x" },
      },
      "updated-at": true,
    }, // end of modules
    prefix: "app",
  },
  realtime: { triggers: [] },
});
`;

    expect(moved(source))
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  schema: "public",
  // SQL-wide settings.
  sql: {
    dir: "supabase/schemas",
    prefix: "app",
  },
  // Blocks this app installs.
  blocks: {
    tenant: { options: { column: "org_id" } }, // the tenant column
    access: {
      model: "roles",
      // keep "modules" here: it's a string
      functions: { canAssignFor: "x" },
    },
    "updated-at": true,
  }, // end of modules
  realtime: { triggers: [] },
});
`);
  });

  it("drops sql when modules was all it held", () => {
    const source = `export default defineConfig({
  sql: {
    modules: ["tenant", "access"],
  },
  schema: "public",
});
`;

    expect(moved(source)).toBe(`export default defineConfig({
  blocks: ["tenant", "access"],
  schema: "public",
});
`);
  });

  it("adds the comma when sql is the last property", () => {
    const source = `export default defineConfig({
  schema: "public",
  sql: {
    modules: ["tenant"],
    dir: "db"
  }
});
`;

    expect(moved(source)).toBe(`export default defineConfig({
  schema: "public",
  sql: {
    dir: "db"
  },
  blocks: ["tenant"],
});
`);
  });

  it("rewrites one-line objects and a shorthand modules", () => {
    expect(
      moved(
        `export default defineConfig({ sql: { dir: "db", modules }, x: 1 });`,
      ),
    ).toBe(
      `export default defineConfig({ sql: { dir: "db" }, blocks: modules, x: 1 });`,
    );
    expect(
      moved(`export default defineConfig({ sql: { "modules": ["tenant"] } });`),
    ).toBe(`export default defineConfig({ "blocks": ["tenant"] });`);
  });

  it("keeps a config without sql.modules, so a second run changes nothing", () => {
    const source = `export default defineConfig({
  sql: {
    modules: ["tenant"],
    dir: "db",
  },
});
`;

    const once = moved(source);

    expect(moved(once)).toBe(once);
    expect(moved(`export default defineConfig({ schema: "public" });`)).toBe(
      `export default defineConfig({ schema: "public" });`,
    );
  });

  it("refuses when blocks is already set or sql isn't a literal", () => {
    expect(
      moveSqlModulesToBlocks(
        `export default defineConfig({ sql: { modules: ["a"] }, blocks: ["b"] });`,
      ),
    ).toMatchObject({ ok: false, reason: expect.stringContaining("merge") });
    expect(
      moveSqlModulesToBlocks(
        `const sql = { modules: ["a"] };\nexport default defineConfig({ sql });`,
      ),
    ).toMatchObject({ ok: false, reason: expect.stringContaining("by hand") });
  });
});

describe("moveSqlModulesToBlocksJson", () => {
  it("moves the key in place and drops an empty sql", () => {
    const edit = moveSqlModulesToBlocksJson(
      `{\n  "schema": "public",\n  "sql": { "modules": ["tenant"] },\n  "x": 1\n}\n`,
    );

    expect(edit).toEqual({
      ok: true,
      text: `{\n  "schema": "public",\n  "blocks": [\n    "tenant"\n  ],\n  "x": 1\n}\n`,
    });
  });

  it("keeps the other sql settings and refuses with blocks set", () => {
    const edit = moveSqlModulesToBlocksJson(
      `{ "sql": { "dir": "db", "modules": { "tenant": true } } }`,
    );

    expect(edit.ok && JSON.parse(edit.text)).toEqual({
      sql: { dir: "db" },
      blocks: { tenant: true },
    });
    expect(
      moveSqlModulesToBlocksJson(`{ "sql": { "modules": [] }, "blocks": [] }`),
    ).toMatchObject({ ok: false });
  });
});
