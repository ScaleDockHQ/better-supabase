import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { renderFiles, runGen } from "../../../src/cli/commands/gen.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type BetterSupabaseConfig,
  type Generator,
  type GeneratorModel,
  resolveConfig,
} from "../../../src/config/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const src = resolve(import.meta.dirname, "../../../src");
const fixtures = resolve(import.meta.dirname, "../../fixtures");
const snapshot = await parseSnapshot(fixture);

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
      "src/db/generated.meta.js",
      "src/db/generated.meta.d.ts",
      "src/db/tables.ts",
    ]);
    expect(seen).toEqual(["./generated.ts", join(root, "src/db/generated.ts")]);
    expect(files[4]!.contents).toContain("customers\n");
  });

  it("refuses generator files outside the root or on another file's path, naming the generator", async () => {
    const writing = (name: string, path: string): Generator => ({
      name,
      generate: () => [{ path, contents: "" }],
    });
    const failing = async (...generators: Generator[]) =>
      renderFiles(configure({ generators }), snapshot).then(
        () => "rendered",
        (error: unknown) => (error instanceof Error ? error.message : ""),
      );
    expect(await failing(writing("escape", "../outside.ts"))).toBe(
      'generator "escape" wrote ../outside.ts, which is outside the project root',
    );
    expect(await failing(writing("absolute", "/tmp/outside.ts"))).toBe(
      'generator "absolute" wrote /tmp/outside.ts, which is outside the project root',
    );
    expect(await failing(writing("core", "src/db/generated.ts"))).toBe(
      'generator "core" wrote src/db/generated.ts, which better-supabase gen writes',
    );
    expect(
      await failing(writing("a", "src/x.ts"), writing("b", "./src/x.ts")),
    ).toBe('generator "b" wrote ./src/x.ts, which generator "a" also writes');
    expect(
      await failing({
        name: "broken",
        generate: () => {
          throw new Error("no tables");
        },
      }),
    ).toBe('generator "broken" failed: no tables');
  });

  it("imports JSON column types per file, in code point order", async () => {
    const config = configure({
      json: {
        "notes.attachments": { import: "src/types/notes.ts#Attachments" },
        "customers.metadata": { import: "src/types/Customer.ts#Metadata" },
      },
    });
    const [, main] = await renderFiles(config, snapshot);
    const imports = main!.contents
      .split("\n")
      .filter(
        (line) =>
          line.startsWith("import type { Attachments }") ||
          line.startsWith("import type { Metadata }"),
      );
    expect(imports).toEqual([
      'import type { Metadata } from "../types/Customer.ts";',
      'import type { Attachments } from "../types/notes.ts";',
    ]);
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
        `^Generated \\d+ tables:\\n  src/db/database.types.ts\\n  src/db/generated.ts\\n  src/db/generated.meta.js\\n  src/db/generated.meta.d.ts\\n  ${READ_SET_FILE}$`,
      ),
    );
    const sql = await readFile(join(root, READ_SET_FILE), "utf8");
    expect(sql).toContain(
      "create or replace function public.rs_chrome(p jsonb)",
    );

    expect(await gen(true)).toEqual({
      code: 0,
      data: { stale: [], leftovers: [], upToDate: true, warnings: [] },
      output: "Generated files are up to date (5).",
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

  it("gives generators a frozen model with the column types gen wrote", async () => {
    let model: GeneratorModel | undefined;
    const config = configure({
      json: { "customers.metadata": { type: "{ tier: string }" } },
      generators: [
        {
          apiVersion: 1,
          name: "spy",
          generate: (input) => {
            model = input.model;
            return [];
          },
        },
      ],
    });
    await renderFiles(config, snapshot);
    const customers = model?.tables.find((table) => table.name === "customers");
    expect(customers?.key).toBe("customers");
    expect(
      customers?.columns.find((column) => column.db === "metadata"),
    ).toMatchObject({
      app: "metadata",
      tsType: "{ tier: string }",
      json: true,
    });
    expect(
      customers?.columns.find((column) => column.db === "organization_id")?.app,
    ).toBe("organizationId");
    expect(Object.isFrozen(model)).toBe(true);
    expect(Object.isFrozen(customers?.columns[0])).toBe(true);
  });

  it("refuses a generator that targets an unknown API version", () => {
    const future = {
      apiVersion: 2,
      name: "future",
      generate: () => [],
    } as unknown as Generator;
    expect(() => configure({ generators: [future] })).toThrow(
      'generator "future" targets generator API 2',
    );
  });

  it("warns about tables and json entries that match nothing", async () => {
    const result = await runGen({
      config: configure({
        tables: { ghosts: { exclude: true }, customers: { casing: "snake" } },
        json: {
          "customers.name": { type: "string" },
          "ghosts.data": { type: "string" },
          "customers.metadata": { type: "{ tier: string }" },
        },
      }),
      env: {},
      check: false,
      snapshot,
    });
    expect(result.data).toMatchObject({
      warnings: [
        expect.stringContaining('tables["ghosts"]: no table by that name'),
        expect.stringContaining('json["customers.name"]: no json or jsonb'),
        expect.stringContaining('json["ghosts.data"]'),
      ],
    });
    expect(result.output).toContain('\nWarning: tables["ghosts"]');
  });

  it("removes files an earlier gen wrote and this one doesn't, and reports them with --check", async () => {
    const extra: Generator = {
      name: "extra",
      generate: () => [{ path: "src/db/extra.ts", contents: "x\n" }],
    };
    await runGen({
      config: configure({ generators: [extra] }),
      env: {},
      check: false,
      snapshot,
    });
    await writeFile(join(root, "src/db/mine.ts"), "hand written\n");

    const check = await runGen({
      config: configure({}),
      env: {},
      check: true,
      snapshot,
    });
    expect(check.code).toBe(1);
    expect(check.error).toBe(
      "Generated files are out of date:\n  src/db/extra.ts (no longer generated)\nRun `better-supabase gen`.",
    );

    const written = await runGen({
      config: configure({}),
      env: {},
      check: false,
      snapshot,
    });
    expect(written.output).toContain(
      "  src/db/extra.ts (removed, no longer generated)",
    );
    expect(existsSync(join(root, "src/db/extra.ts"))).toBe(false);
    expect(existsSync(join(root, "src/db/mine.ts"))).toBe(true);
    expect(
      (await runGen({ config: configure({}), env: {}, check: true, snapshot }))
        .code,
    ).toBe(0);
  });

  it("reports missing files with --check", async () => {
    const result = await runGen({
      config: configure({}),
      env: {},
      check: true,
      snapshot,
    });
    expect(result.error).toBe(
      "Generated files are out of date:\n  src/db/database.types.ts\n  src/db/generated.ts\n  src/db/generated.meta.js\n  src/db/generated.meta.d.ts\nRun `better-supabase gen`.",
    );
  });
});
