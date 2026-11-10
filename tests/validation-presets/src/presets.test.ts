import {
  emitBlockConfig,
  emitBlockConfigModule,
  emitBlockReads,
} from "better-supabase/cli";
import { defineConfig, resolveConfig } from "better-supabase/config";
import {
  namedPreset,
  PRESET_NAMES,
  presetBlocksSource,
  resolvePreset,
} from "better-supabase/preset";
import { PRELUDE_MODULE, UNSCOPED_MODULE } from "better-supabase/sql";
import { readFile, writeFile } from "node:fs/promises";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, installAndRollBack, presetFiles, reachable } from "./stack.ts";

const live = await reachable();

const wiringFile = (name: string): URL =>
  new URL(`wiring/${name}.generated.ts`, import.meta.url);

const configModuleFile = (name: string): URL =>
  new URL(`wiring/${name}.blocks.config.ts`, import.meta.url);

const readsFile = (name: string): URL =>
  new URL(`wiring/${name}.blocks.reads.ts`, import.meta.url);

const blockConfigFile = (name: string): URL =>
  new URL(`wiring/${name}.blocks.generated.ts`, import.meta.url);

describe("named presets", () => {
  it.each(PRESET_NAMES)(
    "%s expands to the blocks the resolver lists",
    (name) => {
      const config = defineConfig({ preset: name });
      const resolved = resolvePreset(namedPreset(name));
      const listed = resolved.blocks.map((block) => block.name);

      const instances = Object.keys(namedPreset(name).instances ?? {}).filter(
        (key) => !listed.includes(key),
      );

      expect(Object.keys(config.blocks ?? {})).toEqual([
        ...listed,
        ...instances,
      ]);
    },
  );

  it.each(PRESET_NAMES)(
    "%s renders every block it lists",
    (name) => {
      const rendered = new Set(
        presetFiles(name, { tests: true })
          .map((file) => file.module)
          .filter(
            (module) => module !== PRELUDE_MODULE && module !== UNSCOPED_MODULE,
          ),
      );

      const { instances } = resolveConfig({ preset: name }, "/");
      expect([...rendered].toSorted()).toEqual(
        [
          ...new Set(
            Object.values(instances).map((instance) => instance.block),
          ),
        ].toSorted(),
      );
      // The "everything" preset renders every block; a CI runner passes the 5 second default.
    },
    60_000,
  );

  // The generated `lib/blocks.ts` of each preset and the
  // `blocks.generated.ts` that `gen` writes for it are committed and
  // typechecked with this project. `pnpm --filter
  // @better-supabase/validation-presets gen` rewrites them.
  it.each(PRESET_NAMES)("%s has current, typechecked wiring", async (name) => {
    const source = presetBlocksSource(
      resolvePreset(namedPreset(name)),
      `./${name}.blocks.generated.ts`,
    );

    // The wiring files hold `blockConfig` as one object, with no slice modules.
    const resolved = resolveConfig(
      { preset: name, gen: { blockModules: false } },
      "/",
    );

    const blockConfig = (emitBlockConfig(resolved)?.contents ?? "")
      .replaceAll("./blocks.config.ts", `./${name}.blocks.config.ts`)
      .replaceAll("./blocks.reads.ts", `./${name}.blocks.reads.ts`);

    const reads = emitBlockReads(resolved)?.contents;

    const configModule = emitBlockConfigModule(resolved)?.contents ?? "";

    if (process.env["UPDATE_WIRING"] === "1") {
      await writeFile(wiringFile(name), source);
      await writeFile(blockConfigFile(name), blockConfig);
      await writeFile(configModuleFile(name), configModule);

      if (reads !== undefined) {
        await writeFile(readsFile(name), reads);
      }
    }

    expect(await readFile(wiringFile(name), "utf-8")).toBe(source);
    expect(await readFile(blockConfigFile(name), "utf-8")).toBe(blockConfig);
    expect(await readFile(configModuleFile(name), "utf-8")).toBe(configModule);

    expect(
      reads === undefined
        ? undefined
        : await readFile(readsFile(name), "utf-8"),
    ).toBe(reads);
  });
});

describe.skipIf(!live)("installing a named preset", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it.each(PRESET_NAMES)(
    "%s applies as one migration",
    async (name) => {
      const sql = presetFiles(name)
        .map((file) => file.contents)
        .join("\n\n");

      await installAndRollBack(pool, sql, async (client) => {
        const { rows } = await client.query<{ installed: boolean }>(
          "select to_regnamespace('better_supabase') is not null as installed",
        );

        expect(rows[0]?.installed).toBe(true);
      });
    },
    120_000,
  );
});
