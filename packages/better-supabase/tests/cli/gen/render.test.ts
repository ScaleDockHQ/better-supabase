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
  subjects: { customer: { table: "customers" } },
};

const configFor = (contentMapper: boolean) =>
  resolveConfig({ ...base, gen: { contentMapper } }, "/app");

describe("render", () => {
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
