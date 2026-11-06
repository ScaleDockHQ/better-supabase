import type { BlockMode } from "../../config/blocks.ts";
import type { BlockSql } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { entitiesMarker } from "../markers.ts";
import { blockSqlVersion } from "../module-types.ts";

/** The table `moduleRow` writes to, created by every schema module's file. */
export const BLOCKS_TABLE = `
create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
`;

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

  return instance === module.name
    ? `insert into better_supabase.blocks (name, version, mode)
values (${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`
    : `alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values (${sqlString(instance)}, ${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();`;
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
