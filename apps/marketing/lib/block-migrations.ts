import type { BlockSqlFile } from "better-supabase/sql";

import { renderBlocks, resolveBlocks } from "better-supabase/sql";

export interface BlockMigrations {
  /** The modules `add` installs, dependencies first. */
  readonly installed: readonly string[];
  readonly files: readonly BlockSqlFile[];
}

/**
 * The files `npx better-supabase add <name>` writes with the default layout. A
 * module that needs options to render (`entitlements` needs a customer column)
 * gets the managed organizations module, which supplies the default.
 */
export function blockMigrations(name: string): BlockMigrations {
  const attempts = [[name], [name, "organizations"]];
  let failure: unknown;

  for (const names of attempts) {
    try {
      return {
        installed: resolveBlocks(names).map((module) => module.name),
        files: renderBlocks(names),
      };
    } catch (error) {
      failure = error;
    }
  }

  throw failure;
}
