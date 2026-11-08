import { describe, expect, it } from "vitest";

import type { NamingRename } from "../../src/cli/codemod-naming.ts";

import { renameConfigKeys } from "../../src/cli/codemod-config-keys.ts";
import { namingCodemod } from "../../src/cli/codemod-naming.ts";
import { applyCodemod } from "../../src/cli/codemod.ts";
import { movedKeyIssues } from "../../src/cli/config-moved.ts";

const row = (from: string, to: string): NamingRename => ({
  from,
  to,
  kind: "configKey",
  since: "0.54",
});

const rows = [
  row("subjects", "recordTypes"),
  row("gen.output", "gen.file"),
  row("api.specs.outputs.*.output", "api.specs.outputs.*.file"),
  row("organization", "auth.tenant"),
  row("blocks.time-tracking", "blocks.time-entries"),
];

describe("renameConfigKeys", () => {
  it("renames a key at its path and leaves the same name elsewhere", () => {
    const text = `import { defineConfig } from "better-supabase/config";
const local = { subjects: 1, output: "x" };
export default defineConfig({
  // subjects: { in a comment }
  /* output: "in a block comment" */
  subjects: { customer: { table: "customers" } },
  gen: { casing: 'camel', output: "a.ts", "other": \`output: \${1}\` },
  blocks: { tasks: { subjects: {}, output: "kept" } },
  api: { specs: { outputs: [{ format: "openapi", output: "o.json" }, { format: "x", "output": "p.json" }] } },
});
`;

    const { text: next, review } = renameConfigKeys(text, rows);

    expect(review).toEqual([]);
    expect(next).toContain('const local = { subjects: 1, output: "x" };');
    expect(next).toContain("  recordTypes: { customer");
    expect(next).toContain("gen: { casing: 'camel', file: \"a.ts\"");
    expect(next).toContain(
      'blocks: { tasks: { subjects: {}, output: "kept" } }',
    );
    expect(next).toContain('{ format: "openapi", file: "o.json" }');
    expect(next).toContain("// subjects: { in a comment }");
    expect(next).toContain('/* output: "in a block comment" */');
  });

  it("renames a quoted block key", () => {
    const { text } = renameConfigKeys(
      `export default defineConfig({ blocks: { "time-tracking": {}, tasks: { "time-tracking": 1 } } });`,
      rows,
    );

    expect(text).toBe(
      `export default defineConfig({ blocks: { "time-entries": {}, tasks: { "time-tracking": 1 } } });`,
    );
  });

  it("renames the keys of every defineConfig call, nested in other objects", () => {
    const { text } = renameConfigKeys(
      `const recipes = [{ name: "a", config: defineConfig({ subjects: {} }) }, { subjects: 1, config: defineConfig({ gen: { output: "x" } }) }];`,
      rows,
    );

    expect(text).toBe(
      `const recipes = [{ name: "a", config: defineConfig({ recordTypes: {} }) }, { subjects: 1, config: defineConfig({ gen: { file: "x" } }) }];`,
    );
  });

  it("reports a key that moved to another parent and leaves it", () => {
    const { text, review } = renameConfigKeys(
      "export default defineConfig({\n  organization: { column: 'org' },\n});\n",
      rows,
    );

    expect(text).toContain("organization: {");
    expect(review).toEqual([
      {
        line: 2,
        message: "organization moved to auth.tenant; move the key by hand.",
      },
    ]);
  });

  it("leaves a file without defineConfig or without configKey rows alone", () => {
    const plain = "const a = { subjects: 1 };\n";
    expect(renameConfigKeys(plain, rows).text).toBe(plain);

    const config = "export default defineConfig({ subjects: {} });\n";
    expect(renameConfigKeys(config, []).text).toBe(config);
  });

  it("runs as part of the naming codemod", () => {
    const { text } = applyCodemod(
      namingCodemod(rows),
      "export default defineConfig({ gen: { output: 'a.ts' } });\n",
    );

    expect(text).toBe(
      "export default defineConfig({ gen: { file: 'a.ts' } });\n",
    );
  });
});

describe("movedKeyIssues for renamed keys", () => {
  it("names the new key for each old one, in a config and its environment", () => {
    const issues = movedKeyIssues({
      subjects: {},
      organization: {},
      gen: { output: "a.ts", recordTypes: true },
      database: { seed: { output: "s.sql", sample: { output: "x.sql" } } },
      api: {
        specs: { outputs: [{ format: "openapi", output: "o.json" }, {}] },
      },
      $production: { tooling: { env: { output: ".env" } } },
    });

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.stringContaining("subjects: renamed to `recordTypes`"),
        expect.stringContaining("organization: renamed to `auth.tenant`"),
        expect.stringContaining("gen.output: renamed to `gen.file`"),
        expect.stringContaining("gen.recordTypes: renamed to `gen.records`"),
        expect.stringContaining(
          "database.seed.output: renamed to `database.seed.file`",
        ),
        expect.stringContaining("database.seed.sample.output: renamed"),
        expect.stringContaining(
          "api.specs.outputs.0.output: renamed to `file`",
        ),
        expect.stringContaining("$production.tooling.env.output: renamed"),
      ]),
    );
  });

  it("accepts the new keys", () => {
    expect(
      movedKeyIssues({
        recordTypes: {},
        gen: { file: "a.ts", records: true },
        api: { specs: { outputs: [{ format: "openapi", file: "o.json" }] } },
      }),
    ).toEqual([]);
  });
});
