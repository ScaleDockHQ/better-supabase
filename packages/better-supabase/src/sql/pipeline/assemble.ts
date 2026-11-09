import type { BlockMode } from "../../config/blocks.ts";
import type { BlockSql } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { FORMER_BLOCK_NAMES } from "../former-block-names.ts";
import { entitiesMarker } from "../markers.ts";
import { blockSqlVersion } from "../module-types.ts";

/**
 * Records the module in `better_supabase.blocks`, which `upgrade` and doctor
 * read. An instance that installs it under another name records its block too.
 */
export function moduleRow(
  module: BlockSql,
  mode: BlockMode,
  instance: string,
): string {
  const version = String(blockSqlVersion(module));
  const former = FORMER_BLOCK_NAMES.get(instance);

  // A block renamed since it was installed keeps one row. Rename the old row
  // when the new name is free, and delete the old row when the new one is
  // already there.
  const rename =
    former === undefined
      ? ""
      : `delete from better_supabase.blocks
  where name = ${sqlString(former)}
    and exists (select 1 from better_supabase.blocks where name = ${sqlString(instance)});
update better_supabase.blocks set name = ${sqlString(instance)}
  where name = ${sqlString(former)}
    and not exists (select 1 from better_supabase.blocks where name = ${sqlString(instance)});
`;

  return (
    rename +
    (instance === module.name
      ? `insert into better_supabase.blocks (name, version, mode)
values (${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`
      : `insert into better_supabase.blocks (name, block, version, mode)
values (${sqlString(instance)}, ${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();`)
  );
}

const TITLE = (instance: string): string =>
  `-- better-supabase module: ${instance}`;

const MANAGED: readonly string[] = [
  "-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.",
  "-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.",
];

/** What the header of a module's schema (or test target) file needs. */
export interface ModuleHeaderInput {
  readonly instance: string;
  readonly version: number;
  readonly mode: BlockMode;
  readonly description: string;
  /** The block, when the instance installs it under another name. */
  readonly block: string | undefined;
  readonly entities: readonly {
    readonly key: string;
    readonly singular: string;
    readonly plural: string;
  }[];
}

/** The comment header of a module file: marker, entity renames, notice. */
export function moduleHeader(input: ModuleHeaderInput): string {
  const entities = entitiesMarker(input.instance, input.entities);

  return [
    TITLE(input.instance),
    `-- @bsb-block ${input.instance}@${String(input.version)} ${input.mode}${input.block === undefined ? "" : ` ${input.block}`}`,
    ...(entities === undefined ? [] : [entities]),
    `-- ${input.description}`,
    ...MANAGED,
  ].join("\n");
}

/** The comment header of a module's data file. */
export function dataFileHeader(instance: string): string {
  return [
    TITLE(instance),
    `-- @bsb-block-data ${instance}`,
    "-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`",
    "-- after the schema migration to put them in a migration.",
    ...MANAGED,
  ].join("\n");
}

/** The comment header of a module's pgTAP file. */
export function testFileHeader(instance: string): string {
  return [TITLE(instance), `-- @bsb-block-test ${instance}`, ...MANAGED].join(
    "\n",
  );
}
