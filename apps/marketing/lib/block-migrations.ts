import {
  type ModuleFile,
  renderModules,
  resolveModules,
} from "better-supabase/sql";

export interface BlockMigrations {
  /** The modules `sql add` installs, dependencies first. */
  readonly installed: readonly string[];
  readonly files: readonly ModuleFile[];
}

/**
 * The files `npx better-supabase sql add <name>` writes with the default
 * layout. A module that needs options to render (`entitlements` needs a
 * customer column) gets the managed organizations module, which supplies the
 * default.
 */
export function blockMigrations(name: string): BlockMigrations {
  const attempts = [[name], [name, "organizations"]];
  let failure: unknown;
  for (const names of attempts) {
    try {
      return {
        installed: resolveModules(names).map((module) => module.name),
        files: renderModules(names),
      };
    } catch (error) {
      failure = error;
    }
  }
  throw failure;
}
