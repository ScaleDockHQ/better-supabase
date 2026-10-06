import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { CliIo } from "../../src/cli/io.ts";

import { render } from "../../src/cli/commands/gen.ts";
import { parseSnapshot } from "../../src/cli/commands/snapshot.ts";
import { buildModel } from "../../src/cli/gen/model.ts";
import { fromMetadata } from "../../src/cli/introspect/from-metadata.ts";
import { serializeGenerator } from "../../src/cli/introspect/typegen.ts";
import { run } from "../../src/cli/run.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { snapshotFixture } from "./fixtures/library.ts";

const snapshot = await parseSnapshot(snapshotFixture);
const document = await serializeGenerator(snapshot.generator);

interface Captured {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

describe("gen --metadata", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-gen-stdin-"));
    await writeFile(
      join(root, "better-supabase.config.ts"),
      `export default { casing: "camel", output: "src/db/generated.ts" };\n`,
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const gen = async (
    args: readonly string[],
    stdin: string = document,
  ): Promise<Captured> => {
    const stdout: string[] = [];
    const stderr: string[] = [];
    const io: CliIo = {
      stdout: (text) => {
        stdout.push(text);
      },
      stderr: (text) => {
        stderr.push(text);
      },
      stdin: () => Promise.resolve(stdin),
    };
    const result = await run(["gen", ...args, "--cwd", root], { io });
    return {
      code: result.code,
      stdout: stdout.join(""),
      stderr: stderr.join(""),
    };
  };

  it("prints the defineSchema module with its metadata inlined, and nothing else on stdout", async () => {
    const result = await gen(["--metadata", "-"]);
    expect(result.code).toBe(0);
    expect(result.stdout).toMatchSnapshot();
    expect(result.stdout).toContain("const meta: SchemaMeta = {");
    expect(result.stdout).not.toContain("generated.meta.js");
    expect(result.stdout).toContain(
      'import type { Database as SupabaseDatabase } from "./database.types.ts";',
    );
    expect(result.stderr).toContain(
      "Notice: the schema came from a GeneratorMetadata document",
    );
    expect(existsSync(join(root, "src"))).toBe(false);
  });

  it("reads the document from a file relative to the working directory", async () => {
    await writeFile(join(root, "metadata.json"), document);
    const fromFile = await gen(["--metadata", "metadata.json"], "");
    const fromStdin = await gen(["--metadata", "-"]);
    expect(fromFile.code).toBe(0);
    expect(fromFile.stdout).toBe(fromStdin.stdout);
  });

  it("prints database.types.ts with --emit types, matching gen from the snapshot", async () => {
    const result = await gen(["--metadata", "-", "--emit", "types"]);
    expect(result.code).toBe(0);
    const config = resolveConfig(
      { casing: "camel", output: "src/db/generated.ts" },
      root,
    );
    const { files } = await render(config, snapshot);
    expect(result.stdout).toBe(
      files.find((file) => file.path === config.databaseTypesOutput)!.contents,
    );
  });

  it.each(["zod", "valibot"])(
    "prints the %s generator's file with --emit",
    async (emit) => {
      const result = await gen(["--metadata", "-", "--emit", emit]);
      expect(result.code).toBe(0);
      expect(result.stdout).toContain("export const validators");
    },
  );

  it("prints the JSON Schema document with --emit json-schema", async () => {
    const result = await gen(["--metadata", "-", "--emit", "json-schema"]);
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toHaveProperty("$defs");
  });

  it("exits 65 with the reason on stderr for a document it rejects", async () => {
    const cases = [
      ["", /is empty/],
      ["{ not json", /is not JSON/],
      [JSON.stringify({ schemas: [] }), /has no "version"/],
      [
        JSON.stringify({ ...JSON.parse(document), version: 2 }),
        /version 2, and better-supabase reads version 1/,
      ],
      [JSON.stringify({ version: 1, tables: [] }), /Invalid GeneratorMetadata/],
    ] as const;
    for (const [input, reason] of cases) {
      const result = await gen(["--metadata", "-"], input);
      expect(result.code).toBe(65);
      expect(result.stdout).toBe("");
      expect(result.stderr).toMatch(reason);
    }
    const missing = await gen(["--metadata", "nope.json"]);
    expect(missing.code).toBe(65);
    expect(missing.stderr).toMatch(/Could not read nope\.json/);
  });

  it("refuses flags that don't combine with --metadata", async () => {
    const cases = [
      [["--metadata", "-", "--watch"], /can't be combined with --watch/],
      [["--metadata", "-", "--snapshot", "s.json"], /--snapshot/],
      [["--metadata", "-", "--emit", "sql"], /--emit must be one of/],
      [
        ["--metadata", "-", "--emit", "types", "--out", "x"],
        /Pass one of them/,
      ],
      [["--metadata", "-", "--check"], /needs --out/],
      [["--metadata", "-", "--json"], /--json has nothing to print/],
      [["--emit", "types"], /--emit only applies with --metadata/],
      [["--out", "x"], /--out only applies with --metadata/],
    ] as const;
    for (const [args, reason] of cases as readonly (readonly [
      readonly string[],
      RegExp,
    ])[]) {
      const result = await gen(args);
      expect(result.code).toBe(2);
      // --json reports the error as Problem Details on stdout.
      expect(args.includes("--json") ? result.stdout : result.stderr).toMatch(
        reason,
      );
    }
  });

  it("writes the multi-file layout into --out, leaving the configured paths and the manifest alone", async () => {
    const result = await gen(["--metadata", "-", "--out", "out"]);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("out/generated.ts");
    for (const name of [
      "database.types.ts",
      "generated.ts",
      "generated.meta.js",
      "generated.meta.d.ts",
    ]) {
      expect(existsSync(join(root, "out", name))).toBe(true);
    }
    expect(existsSync(join(root, "src"))).toBe(false);
    expect(
      existsSync(
        join(root, "node_modules/.cache/better-supabase/gen-manifest.json"),
      ),
    ).toBe(false);
    const check = await gen(["--metadata", "-", "--out", "out", "--check"]);
    expect(check.code).toBe(0);
    expect(await readFile(join(root, "out/generated.ts"), "utf8")).toContain(
      'import meta from "./generated.meta.js";',
    );
  });
});

describe("fromMetadata", () => {
  const config = resolveConfig(
    { casing: "camel", output: "src/db/generated.ts" },
    "/project",
  );
  const full = buildModel(snapshot, config);
  const partial = buildModel(fromMetadata(snapshot.generator), config);

  it("marks the snapshot and leaves the extras it can't infer empty", () => {
    const built = fromMetadata(snapshot.generator);
    expect(built.extras.fromMetadata).toBe(true);
    expect(built.extras.buckets).toEqual([]);
    expect(built.extras.realtime).toEqual([]);
    expect(
      built.extras.tables.every(
        (table) => table.policies.length === 0 && table.grants.length === 0,
      ),
    ).toBe(true);
  });

  it("types the same tables, columns and relations as the database snapshot", () => {
    const typed = (model: typeof full) =>
      model.tables.map((table) => ({
        key: table.key,
        columns: table.columns.map((column) => [column.app, column.tsType]),
        relations: table.relations.map((relation) => [
          relation.name,
          relation.meta.kind,
          relation.meta.table,
        ]),
      }));
    expect(typed(partial)).toEqual(typed(full));
  });

  it("keeps single-column unique keys and CHECK unions under the default Postgres names", () => {
    const table = (model: typeof full, key: string) =>
      model.tables.find((entry) => entry.key === key)!;
    expect(table(partial, "organizations").meta.uniqueKeys).toEqual(
      table(full, "organizations").meta.uniqueKeys,
    );
    const status = (model: typeof full) =>
      table(model, "customers").columns.find((column) => column.db === "status")
        ?.values;
    expect(status(partial)).toEqual(["lead", "active", "archived"]);
    expect(status(partial)).toEqual(status(full));
  });

  it("gives views no unique keys, foreign keys or checks of their own", () => {
    const [table] = snapshot.generator.tables;
    const view = {
      id: 999_999,
      schema: table!.schema,
      name: "customer_names",
      comment: null,
      is_updatable: false,
    };
    const viewColumns = snapshot.generator.columns
      .filter((column) => column.table_id === table!.id)
      .map((column) => ({
        ...column,
        id: `999999.${String(column.ordinal_position)}`,
        table_id: view.id,
        table: view.name,
        is_unique: true,
        check: "true",
      }));
    const built = fromMetadata({
      ...snapshot.generator,
      views: [view],
      columns: [...snapshot.generator.columns, ...viewColumns],
    });
    expect(
      built.extras.tables.find((entry) => entry.name === "customer_names"),
    ).toMatchObject({ uniques: [], foreignKeys: [], checks: [] });
  });
});
