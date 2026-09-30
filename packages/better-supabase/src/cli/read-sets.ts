import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { isReadSet, type ReadSet } from "../core/read-set.ts";
import { type CompiledReadSet, compileReadSets } from "../sql/read-sets.ts";
import { importModule } from "./config.ts";

/** Every read set exported by the modules in `config.readSets`. */
async function loadReadSets(config: ResolvedConfig): Promise<ReadSet[]> {
  const sets: ReadSet[] = [];
  for (const entry of config.readSets) {
    const loaded = await importModule(resolve(config.root, entry));
    const found = Object.values(loaded).filter(isReadSet);
    if (found.length === 0) {
      throw new Error(`${entry} exports no read set (defineReadSet)`);
    }
    for (const set of found) if (!sets.includes(set)) sets.push(set);
  }
  return sets;
}

/** The compiled functions for `config.readSets`; empty when none are configured. */
export async function compiledReadSets(
  config: ResolvedConfig,
): Promise<CompiledReadSet[]> {
  if (config.readSets.length === 0) return [];
  return compileReadSets(await loadReadSets(config));
}
