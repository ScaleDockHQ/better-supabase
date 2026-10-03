import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { renderFiles, runGen } from "../../../src/cli/commands/gen.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type BetterSupabaseConfig,
  type Generator,
  resolveConfig,
} from "../../../src/config/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const src = resolve(import.meta.dirname, "../../../src");
const fixtures = resolve(import.meta.dirname, "../../fixtures");
const snapshot = parseSnapshot(fixture);

const READ_SETS = `import { defineSupabase } from ${JSON.stringify(join(src, "core/define.ts"))};
import { defineReadSet } from ${JSON.stringify(join(src, "core/read-set.ts"))};
import { schema } from ${JSON.stringify(join(fixtures, "generated-camel.ts"))};

export const chrome = defineReadSet(defineSupabase(schema), "chrome", { params: { orgId: "uuid" } }, (s, p) => ({
  customers: s.customers.count({ where: { organizationId: p.orgId } }),
}));
`;
const READ_SET_FILE = "supabase/schemas/900_better_supabase_14_read_sets.sql";

describe("gen", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-gen-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const configure = (config: BetterSupabaseConfig) =>
    resolveConfig(
      { casing: "camel", output: "src/db/generated.ts", ...config },
      root,
    );

  it("runs configured generators with root-relative import paths", async () => {
    const seen: string[] = [];
    const tables: Generator = {
      name: "tables",
      generate: (input) => {
        seen.push(
          input.importPath("src/db/tables.ts", "src/db/generated.ts"),
          input.output,
        );
        return [
          {
            path: "src/db/tables.ts",
            contents: `${Object.keys(input.meta.tables).sort().join("\n")}\n`,
          },
        ];
      },
    };
    const config = configure({ generators: [tables] });
    const files = await renderFiles(config, snapshot);
    expect(files.map((file) => file.path)).toEqual([
      "src/db/database.types.ts",
      "src/db/generated.ts",
      "src/db/tables.ts",
    ]);
    expect(seen).toEqual(["./generated.ts", join(root, "src/db/generated.ts")]);
    expect(files[2]!.contents).toContain("customers\n");
  });

  it("writes the read-sets module after the generated one and checks it for drift", async () => {
    await mkdir(join(root, "src"), { recursive: true });
    await writeFile(join(root, "src/read-sets.ts"), READ_SETS);
    const config = configure({ readSets: ["src/read-sets.ts"] });
    const gen = (check: boolean) =>
      runGen({ config, env: {}, check, snapshot });

    const first = await gen(false);
    expect(first.code).toBe(0);
    expect(first.output).toMatch(
      new RegExp(
        `^Generated \\d+ tables:\\n  src/db/database.types.ts\\n  src/db/generated.ts\\n  ${READ_SET_FILE}$`,
      ),
    );
    const sql = await readFile(join(root, READ_SET_FILE), "utf8");
    expect(sql).toContain(
      "create or replace function public.rs_chrome(p jsonb)",
    );

    expect(await gen(true)).toEqual({
      code: 0,
      data: { stale: [], upToDate: true },
      output: "Generated files are up to date (3).",
    });
    expect((await gen(false)).output).toMatch(/^No changes \(\d+ tables\)\.$/);

    await writeFile(
      join(root, READ_SET_FILE),
      sql.replace("rs_chrome", "rs_other"),
    );
    const stale = await gen(true);
    expect(stale).toMatchObject({
      code: 1,
      error: `Generated files are out of date:\n  ${READ_SET_FILE}\nRun \`better-supabase gen\`.`,
    });
    expect(stale.output).toContain(
      "-create or replace function public.rs_other(p jsonb)\n+create or replace function public.rs_chrome(p jsonb)",
    );
  });

  it("reports missing files with --check", async () => {
    const result = await runGen({
      config: configure({}),
      env: {},
      check: true,
      snapshot,
    });
    expect(result.error).toBe(
      "Generated files are out of date:\n  src/db/database.types.ts\n  src/db/generated.ts\nRun `better-supabase gen`.",
    );
  });
});
