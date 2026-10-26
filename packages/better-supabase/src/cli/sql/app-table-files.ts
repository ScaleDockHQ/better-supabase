import { join, resolve, sep } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { FilePlan } from "../core/files.ts";

import { APP_TABLES_MODULE, renderBlocks } from "../../sql/index.ts";
import { CliError } from "../core/errors.ts";
import { declarativeSchemasDir, readSupabaseToml } from "../supabase-toml.ts";
import { layoutFor } from "./providers.ts";
import { splitAppTables } from "./schema-first.ts";

/**
 * The deepest directory that holds both paths. A project in a monorepo keeps
 * its `supabase` folder above its own root, and the plan may not leave `root`.
 */
function commonAncestor(first: string, second: string): string {
  const left = resolve(first).split(sep);
  const right = resolve(second).split(sep);
  const shared: string[] = [];

  for (const [index, part] of left.entries()) {
    if (part !== right[index]) {
      break;
    }

    shared.push(part);
  }

  return shared.join(sep) || sep;
}

/**
 * The plan that writes the tables `config.appTables` renders as files you own
 * under the declarative schemas folder (ADR 0102), with each table's features
 * as `@bsb` tags in its comment. A file that exists stays as it is. The config
 * only carries `appTables` from a Create design or an old config that `migrate
 * schema-first` reads; the public config has no key for it.
 */
export async function appTablePlan(
  config: ResolvedConfig,
  regenerate: string,
): Promise<{ plan: FilePlan; tables: string[]; files: string[] } | undefined> {
  const tables = Object.keys(config.appTables);

  if (tables.length === 0) {
    return undefined;
  }

  const layout = await layoutFor(config, {}, config.blockNames);
  const rendered = renderBlocks(config.blockNames, layout);

  const source = rendered.find(
    (file) => file.module === APP_TABLES_MODULE && file.kind === "schema",
  );

  if (source === undefined) {
    throw new CliError("usage", "The config renders no app tables file.");
  }

  const dir = join(
    config.root,
    declarativeSchemasDir(await readSupabaseToml(config.root)),
  );

  const split = splitAppTables(config, source.contents, tables);

  return {
    tables,
    files: split.map((file) => file.path),
    plan: {
      root: commonAncestor(config.root, dir),
      base: config.root,
      regenerate,
      files: split.map((file) => ({
        path: join(dir, file.path),
        contents: file.contents,
        policy: "create",
      })),
    },
  };
}
