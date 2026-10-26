import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { TableComment } from "./gen/table-tags.ts";

import { tableTagComments } from "../sql/index.ts";
import { withTableTags } from "./gen/table-tags.ts";
import { readSupabaseToml, schemaPaths, sqlWorkflow } from "./supabase-toml.ts";

/** The `@bsb` table comments in the project's declarative schema files. */
export async function schemaTagComments(
  config: ResolvedConfig,
): Promise<TableComment[]> {
  const toml = await readSupabaseToml(config.root);

  const { files } = await schemaPaths(
    config.root,
    toml,
    sqlWorkflow(config, toml),
  );

  const texts = await Promise.all(
    files.map((path) => readFile(resolve(config.root, path), "utf-8")),
  );

  return texts.flatMap((sql) => tableTagComments(sql));
}

/**
 * `config` with the features the schema files' `@bsb` table comments turn on
 * (ADR 0102), so the SQL modules, `gen` and doctor read the same config. A key
 * the config sets itself wins. `appTables` stays as declared: `encrypted` and
 * `events` tags describe tables whose SQL the files already hold, and `gen`
 * reads them from the snapshot.
 */
export async function withSchemaTags(
  config: ResolvedConfig,
): Promise<ResolvedConfig> {
  const tagged = withTableTags(config, await schemaTagComments(config));

  return tagged === config
    ? config
    : { ...tagged, appTables: config.appTables };
}
