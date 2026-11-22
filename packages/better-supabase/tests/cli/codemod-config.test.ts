import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  configCodemod,
  configFiles,
  tenantEntries,
  withoutColumnEntries,
} from "../../src/cli/codemod-config.ts";
import { resolveConfig } from "../../src/config/index.ts";

const entry = (block: string, table: string, column: string) => ({
  block,
  table,
  column,
  why: "test",
});

const CONFIG = `export default defineConfig({
  sql: { tenantColumn: "org_id" },
  blocks: {
    memberships: {
      columns: {
        memberships: {
          updatedAt: null,
          lastUsedAt: null,
          role: "team_role",
        },
      },
    },
    teams: {
      columns: { teams: { tenant: "org_id", name: "title" } },
      // columns: { teams: { updatedAt: null } },
    },
    tags: { columns: { tags: { rank: null } } },
  },
});
`;

describe("withoutColumnEntries", () => {
  it("drops the entry, its comma and its line, and keeps the others", () => {
    expect(
      withoutColumnEntries(CONFIG, [
        entry("memberships", "memberships", "updatedAt"),
        entry("memberships", "memberships", "lastUsedAt"),
      ]).text,
    ).toContain(
      '        memberships: {\n          role: "team_role",\n        },',
    );
  });

  it("drops an inline entry in its block only", () => {
    const out = withoutColumnEntries(CONFIG, [
      entry("teams", "teams", "tenant"),
      entry("tags", "tags", "rank"),
    ]).text;

    expect(out).toContain('columns: { teams: { name: "title" } }');
    expect(out).toContain("tags: { columns: { tags: {} } }");
    expect(out).toContain("updatedAt: null,");
  });

  it("leaves a name in a comment alone", () => {
    const result = withoutColumnEntries(CONFIG, [
      entry("teams", "teams", "updatedAt"),
    ]);

    expect(result.text).toBe(CONFIG);
    expect(result.review).toHaveLength(1);
  });

  it("removes an entry the config reaches through a spread and a shorthand", () => {
    const text = `const columns = { teams: { updatedAt: null, name: "title" } };
const teams = { columns };
export default defineConfig({
  blocks: { teams, tags: { ...{ columns: { tags: { rank: null } } } } },
});
`;

    const result = withoutColumnEntries(text, [
      entry("teams", "teams", "updatedAt"),
      entry("tags", "tags", "rank"),
    ]);

    expect(result.review).toEqual([]);
    expect(result.text).toContain(
      'const columns = { teams: { name: "title" } };',
    );
    expect(result.text).not.toContain("rank");
  });

  it("keeps the comment of the entry before and drops the comment of the removed one", () => {
    const text = `export default defineConfig({
  blocks: {
    teams: {
      columns: {
        teams: {
          // keep: the title
          name: "title",
          // the codemod removes this one
          updatedAt: null, // trailing
        },
      },
    },
  },
});
`;

    const { text: out } = withoutColumnEntries(text, [
      entry("teams", "teams", "updatedAt"),
    ]);

    expect(out).toContain("// keep: the title");
    expect(out).not.toContain("updatedAt");
    expect(out).not.toContain("trailing");
    expect(out).not.toContain("removes this one");
  });

  it("keeps CRLF line endings", () => {
    const text = CONFIG.replaceAll("\n", "\r\n");

    const { text: out } = withoutColumnEntries(text, [
      entry("memberships", "memberships", "updatedAt"),
    ]);

    expect(out).not.toMatch(/[^\r]\n/);
    expect(out).not.toContain("updatedAt: null,\r\n          lastUsedAt");
  });

  it("reports an entry it cannot follow instead of skipping it", () => {
    const text = `import { columns } from "./columns.ts";
export default defineConfig({ blocks: { teams: { columns } } });
`;

    const result = withoutColumnEntries(text, [
      entry("teams", "teams", "updatedAt"),
    ]);

    expect(result.text).toBe(text);
    expect(result.review[0]).toContain("blocks.teams.columns.teams.updatedAt");
    expect(result.review[0]).toContain("remove it by hand");
  });
});

describe("tenantEntries", () => {
  it("finds the entries that repeat sql.tenantColumn", () => {
    expect(
      tenantEntries({
        sql: { tenantColumn: "org_id" },
        blocks: {
          teams: { columns: { teams: { tenant: "org_id" } } },
          tags: { columns: { tags: { tenant: "account_id" } } },
        },
        // SAFETY: only the fields tenantEntries reads are set.
      } as never),
    ).toEqual([
      expect.objectContaining({
        block: "teams",
        table: "teams",
        column: "tenant",
      }),
    ]);
  });

  it("finds none without sql.tenantColumn", () => {
    expect(
      // SAFETY: only the fields tenantEntries reads are set.
      tenantEntries({
        sql: {},
        blocks: { a: { columns: { a: { tenant: "x" } } } },
      } as never),
    ).toEqual([]);
  });
});

describe("configFiles", () => {
  it("plans one edit of the config, or none when nothing changes", () => {
    const config = { path: "/p/better-supabase.config.ts", text: CONFIG };

    expect(
      configFiles([entry("tags", "tags", "rank")], config).files[0],
    ).toMatchObject({ path: config.path, policy: "edit" });
    expect(configFiles([entry("none", "none", "x")], config).files).toEqual([]);
  });
});

describe("configCodemod", () => {
  const config = resolveConfig(
    {
      database: { sql: { tenantColumn: "org_id" } },
      blocks: {
        tags: { columns: { tags: { tenant: "org_id", name: "title" } } },
      },
    },
    "/p",
  );

  const text = `export default {\n  blocks: {\n    tags: { columns: { tags: { tenant: "org_id", name: "title" } } },\n  },\n};\n`;

  it("edits the config file and reports nothing else", async () => {
    const result = await configCodemod().project!({
      config,
      sql: [],
      configFile: "/p/better-supabase.config.ts",
      configText: text,
    });

    expect(result.review).toEqual([]);
    expect(result.files).toEqual([
      expect.objectContaining({
        path: "/p/better-supabase.config.ts",
        contents: expect.stringContaining('tags: { name: "title" }'),
      }),
    ]);
  });

  it("lists the entries to remove when no config file is known", async () => {
    const result = await configCodemod().project!({ config, sql: [] });

    expect(result.files).toEqual([]);
    expect(result.review).toEqual([
      {
        message:
          'blocks.tags.columns.tags.tenant: repeats sql.tenantColumn "org_id"; remove it from the config.',
      },
    ]);
  });

  it("changes nothing for a config without refused entries", async () => {
    const result = await configCodemod().project!({
      config: resolveConfig({ blocks: ["tags"] }, "/p"),
      sql: [],
      configFile: "/p/c.ts",
      configText: text,
    });

    expect(result).toEqual({ files: [], review: [] });
  });
});

describe("config codemod --prune without a rewrite", () => {
  const config = resolveConfig(
    { blocks: { tags: { columns: { tags: {} } } } },
    "/project",
  );

  it("lists the restated entries when there is no config file", async () => {
    const { files, review } = await configCodemod().project!({
      config,
      sql: [],
      prune: true,
    });

    expect(files).toEqual([]);
    expect(review).toContainEqual({
      message: expect.stringMatching(
        /^blocks\.tags\.columns\.tags .+; remove it from the config\.$/u,
      ),
    });
  });

  it("writes nothing when the config text lacks an empty entry", async () => {
    const { files, review } = await configCodemod().project!({
      config,
      sql: [],
      prune: true,
      configFile: "/project/better-supabase.config.ts",
      configText: "export default {};\n",
    });

    expect(files).toEqual([]);
    expect(review).toEqual([]);
  });
});

describe("config codemod --prune with a restated notNull", () => {
  it("names a restated entry it cannot find in the config text", async () => {
    const config = resolveConfig(
      {
        blocks: { announcements: {} },
        functions: { "public.list_announcements": { notNull: true } },
      } as Parameters<typeof resolveConfig>[0],
      "/project",
    );

    const { files, review } = await configCodemod().project!({
      config,
      sql: [],
      prune: true,
      configFile: "/project/better-supabase.config.ts",
      configText: "export default {};\n",
    });

    expect(files).toEqual([]);
    expect(review).toContainEqual({
      message:
        "gen.functions.public.list_announcements.notNull repeats its default, but the codemod could not find it in /project/better-supabase.config.ts; remove it by hand.",
    });
  });
});

describe("config codemod --prune for a config that does not render", () => {
  it("still lists the static entries", async () => {
    const root = mkdtempSync(join(tmpdir(), "bsb-config-broken-"));

    writeFileSync(join(root, "broken.json"), "not json");

    const config = resolveConfig(
      { blocks: { "not-a-block": { columns: { x: {} } } } },
      root,
    );

    const { review } = await configCodemod().project!({
      config: {
        ...config,
        source: { ...config.source, snapshot: "broken.json" },
      },
      sql: [],
      prune: true,
    });

    expect(review).toEqual([
      {
        message:
          "blocks.not-a-block.columns.x is empty; remove it from the config.",
      },
    ]);
  });
});

describe("withoutColumnEntries leaves", () => {
  it("leaves a table the columns object lacks and rejects an unclosed block", () => {
    const result = withoutColumnEntries(CONFIG, [
      entry("teams", "members", "name"),
    ]);

    expect(result.text).toBe(CONFIG);
    expect(result.review).toHaveLength(1);

    const unclosed = "export default { tags: { columns: { tags: { rank: null";

    expect(() =>
      withoutColumnEntries(unclosed, [entry("tags", "tags", "rank")]),
    ).toThrow("Expected");
  });
});
