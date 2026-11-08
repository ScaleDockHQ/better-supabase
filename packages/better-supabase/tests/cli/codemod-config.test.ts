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
      ]),
    ).toContain(
      '        memberships: {\n          role: "team_role",\n        },',
    );
  });

  it("drops an inline entry in its block only", () => {
    const out = withoutColumnEntries(CONFIG, [
      entry("teams", "teams", "tenant"),
      entry("tags", "tags", "rank"),
    ]);

    expect(out).toContain('columns: { teams: { name: "title" } }');
    expect(out).toContain("tags: { columns: { tags: {} } }");
    expect(out).toContain("updatedAt: null,");
  });

  it("leaves a name in a comment alone", () => {
    expect(
      withoutColumnEntries(CONFIG, [entry("teams", "teams", "updatedAt")]),
    ).toBe(CONFIG);
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
      configFiles([entry("tags", "tags", "rank")], config)[0],
    ).toMatchObject({ path: config.path, policy: "edit" });
    expect(configFiles([entry("none", "none", "x")], config)).toEqual([]);
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
