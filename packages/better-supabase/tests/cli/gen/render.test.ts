import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import {
  mapperFilePath,
  render,
  renderTypesModule,
} from "../../../src/cli/gen/render.ts";
import { CACHE_DIR } from "../../../src/cli/introspect/cache.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

const base: BetterSupabaseConfig = {
  blocks: { "updated-at": {} },
  recordTypes: { customer: { table: "customers" } },
};

const configFor = (contentMapper: boolean) =>
  resolveConfig(
    {
      ...base,
      gen: { contentMapper, tableModules: false, blockModules: false },
    },
    "/app",
  );

describe("render", () => {
  it("imports EnrichDatabase only when a table needs it", async () => {
    const snapshot = await loadFixtureSnapshot();

    const empty = {
      ...snapshot,
      generator: {
        ...snapshot.generator,
        tables: [],
        views: [],
        columns: [],
        primaryKeys: [],
        relationships: [],
        functions: [],
      },
      extras: { ...snapshot.extras, tables: [], functions: [] },
    };

    const generated = async (input: typeof snapshot): Promise<string> => {
      const { files } = await render(configFor(false), input);

      return files
        .filter((file) => file.contents.includes("export type Database ="))
        .map((file) => file.contents)
        .join("\n");
    };

    const without = await generated(empty);

    expect(without).toContain("export type Database = SupabaseDatabase;");
    expect(without).not.toContain("EnrichDatabase");
  });

  it("renders the types module only when asked in files mode", async () => {
    const snapshot = await loadFixtureSnapshot();
    const config = configFor(false);

    expect((await render(config, snapshot)).typesModule).toBeUndefined();

    const { files, typesModule } = await render(config, snapshot, {
      typesModule: true,
    });

    expect(files.map((file) => file.path)).toContain(
      config.databaseTypesOutput,
    );
    expect(typesModule).toBeDefined();
  });

  it("writes the runtime half and schema.bsb in mapper mode", async () => {
    const snapshot = await loadFixtureSnapshot();
    const config = configFor(true);
    const { files, typesModule } = await render(config, snapshot);
    const paths = files.map((file) => file.path);

    expect(paths).not.toContain(config.databaseTypesOutput);
    expect(paths).toContain(mapperFilePath(config));
    expect(mapperFilePath(config)).toBe("src/lib/supabase/schema.bsb");

    const main = files.find((file) => file.path === config.output);

    expect(main?.contents).toMatchSnapshot();
    expect(typesModule).toBeDefined();
  });

  it("serves the full module with the database types inlined", async () => {
    const snapshot = await loadFixtureSnapshot();

    const files = await render(configFor(false), snapshot, {
      typesModule: true,
    });

    const { typesModule = "" } = await render(configFor(true), snapshot);

    const written =
      files.files.find((file) => file.path === "src/lib/supabase/generated.ts")
        ?.contents ?? "";

    expect(typesModule).toBe(files.typesModule);
    expect(typesModule).not.toContain("database.types");
    expect(typesModule).not.toMatch(/^export const Constants\b/m);
    expect(typesModule).toContain("declare namespace SupabaseTypes {");
    expect(typesModule).toContain("declare const meta: SchemaMeta;");

    const typeLines = (text: string): string[] =>
      text.split("\n").filter((line) => line.startsWith("export type "));

    expect(typeLines(typesModule)).toEqual(typeLines(written));
  });

  it("caches the served module per config and snapshot", async () => {
    const snapshot = await loadFixtureSnapshot();
    const root = await mkdtemp(join(tmpdir(), "bsb-render-"));

    try {
      const config = resolveConfig(
        { ...base, gen: { contentMapper: true } },
        root,
      );

      const first = await renderTypesModule(config, snapshot, "config");

      expect(first).toBe((await render(config, snapshot)).typesModule);
      expect(await renderTypesModule(config, snapshot, "config")).toBe(first);
      expect(await readdir(join(root, CACHE_DIR))).toEqual(
        expect.arrayContaining([expect.stringMatching(/^types-/)]),
      );
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("render with gen.tableModules", () => {
  const split = resolveConfig({ ...base, gen: { tableModules: true } }, "/app");

  it("writes one module per table and a server schema module", async () => {
    const snapshot = await loadFixtureSnapshot();
    const { files } = await render(split, snapshot);
    const paths = files.map((file) => file.path);
    const meta = files.find((file) => file.path.endsWith("generated.meta.js"));

    expect(paths).toContain("src/lib/supabase/tables/customers.ts");
    expect(paths).toContain("src/lib/supabase/generated-schema.ts");
    expect(meta?.contents).toContain('"tables": {}');

    const table = files.find((file) =>
      file.path.endsWith("tables/customers.ts"),
    );

    expect(table?.contents).toContain(
      "export const customersTable = /*#__PURE__*/ defineTable(",
    );
    expect(table?.contents).toContain('"key":"customers"');
  });

  it("keeps the table metadata and the schema out of the main module", async () => {
    const snapshot = await loadFixtureSnapshot();
    const { files } = await render(split, snapshot);
    const main = files.find((file) => file.path === split.output)?.contents;

    const schema = files.find((file) =>
      file.path.endsWith("generated-schema.ts"),
    )?.contents;

    expect(main).toContain("export const clientSchema");
    expect(main).toContain("lazyTables: true");
    expect(main).not.toContain("export const schema");
    expect(main).not.toContain("generated.meta.js");
    expect(main).not.toContain("./tables/");
    expect(schema).toContain("export const schema");
    expect(schema).toContain("/*#__PURE__*/ defineSchema({ ...meta, tables }");
    expect(schema).toContain('from "./tables/customers.ts"');
  });

  it("makes every hook read through its table module", async () => {
    const snapshot = await loadFixtureSnapshot();

    const { files } = await render(
      resolveConfig(
        { ...base, gen: { tableModules: true, hooks: "react" } },
        "/app",
      ),
      snapshot,
    );

    const hooks = files.find((file) =>
      file.path.endsWith("hooks.ts"),
    )?.contents;

    expect(hooks).toContain(
      'import { customersTable } from "./tables/customers.ts";',
    );
    expect(hooks).toMatch(
      /defineListHook\(\s*"customers",\s*\(db: AppDb\) => db\.customers,\s*customersTable,/,
    );
  });

  it("leaves the layout alone with the option off", async () => {
    const snapshot = await loadFixtureSnapshot();
    const { files } = await render(configFor(false), snapshot);

    expect(files.some((file) => file.path.includes("/tables/"))).toBe(false);
    expect(
      files.some((file) => file.path.endsWith("generated-schema.ts")),
    ).toBe(false);
  });

  it("keeps the single-module output in stdin mode and mapper mode", async () => {
    const snapshot = await loadFixtureSnapshot();

    const inline = await render(split, snapshot, { inlineMeta: true });

    const mapper = await render(
      resolveConfig(
        { ...base, gen: { tableModules: true, contentMapper: true } },
        "/app",
      ),
      snapshot,
    );

    expect(inline.files.some((file) => file.path.includes("/tables/"))).toBe(
      false,
    );
    expect(mapper.files.some((file) => file.path.includes("/tables/"))).toBe(
      false,
    );
  });
});

describe("render with gen.blockModules", () => {
  const blocks: BetterSupabaseConfig = {
    blocks: { "updated-at": {}, comments: {}, tags: {} },
    recordTypes: { customer: { table: "customers" } },
  };

  const renderWith = async (blockModules: boolean) =>
    (
      await render(
        resolveConfig({ ...blocks, gen: { blockModules } }, "/app"),
        await loadFixtureSnapshot(),
      )
    ).files;

  it("writes every slice as an export of blocks/slices.ts", async () => {
    const files = await renderWith(true);
    const slices = files.find((file) => file.path.endsWith("blocks/slices.ts"));

    expect(slices?.contents).toContain("export const commentsConfig = {");
    expect(slices?.contents).toContain("as const satisfies GeneratedBlock;");
  });

  it("composes blockConfig from the slices", async () => {
    const files = await renderWith(true);

    const config = files.find((file) =>
      file.path.endsWith("blocks.config.ts"),
    )?.contents;

    expect(config).toContain('} from "./blocks/slices.ts";');
    expect(config).toContain("comments: commentsConfig,");
    expect(config).not.toContain("schema:");
  });

  it("gives a record the slices of the blocks it binds", async () => {
    const files = await renderWith(true);

    const record = files.find((file) =>
      file.path.endsWith("records/customer.ts"),
    )?.contents;

    expect(record).toBeDefined();
    expect(record).toContain('from "../blocks/slices.ts"');
    expect(record).not.toContain("blockConfig");
    expect(record).toMatch(/config: \{\n\s+comments: commentsConfig,/);
  });

  it("leaves the layout alone with the option off", async () => {
    const files = await renderWith(false);

    expect(files.some((file) => file.path.includes("/blocks/"))).toBe(false);
  });
});
