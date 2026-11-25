import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { ReadSet } from "../index.ts";
import type { CompiledReadSet } from "../sql/index.ts";

import { isReadSet } from "../index.ts";
import { compileReadSets } from "../sql/index.ts";
import { CliError } from "./core/errors.ts";
import { importFresh } from "./fresh-import.ts";

/** Every read set exported by the modules in `config.readSets`. */
async function getReadSets(config: ResolvedConfig): Promise<ReadSet[]> {
  const sets: ReadSet[] = [];

  for (const entry of config.readSets) {
    const loaded = await importFresh(resolve(config.root, entry));
    const found = Object.values(loaded).filter(isReadSet);

    if (found.length === 0) {
      throw new CliError(
        "invalid_input",
        `${entry} exports no read set (defineReadSet)`,
      );
    }

    for (const set of found) {
      if (!sets.includes(set)) {
        sets.push(set);
      }
    }
  }

  return sets;
}

/**
 * Compiled read sets by config object. One run asks for them from `gen`, the
 * layout and the read-set module, and each import is a fresh copy of the user's
 * modules; a reload makes a new config object, so watch mode reads them again.
 */
const COMPILED = new WeakMap<ResolvedConfig, Promise<CompiledReadSet[]>>();

/** The compiled functions for `config.readSets`; empty when none are configured. */
export function compiledReadSets(
  config: ResolvedConfig,
): Promise<CompiledReadSet[]> {
  if (config.readSets.length === 0) {
    return Promise.resolve([]);
  }

  const held = COMPILED.get(config);

  if (held !== undefined) {
    return held;
  }

  const compiled = getReadSets(config).then((sets) => compileReadSets(sets));
  COMPILED.set(config, compiled);

  // A failed load is not kept, so the next call reports it again.
  compiled.catch(() => COMPILED.delete(config));

  return compiled;
}
