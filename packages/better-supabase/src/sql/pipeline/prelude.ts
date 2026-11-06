import type { BlockSqlFile, BlockSqlLayout } from "../module-types.ts";

import { CONFIG_DEFAULTS } from "../../config/defaults.ts";
import { ACTING_MEMBER, actorWriteFunctions } from "../actor-guard.ts";
import { columnTypeFunctions } from "../column-type.ts";
import { MEMO_FUNCTIONS } from "../memo.ts";
import { moduleContext } from "../module-context.ts";
import { EQUIVALENT_TRIGGERS } from "../shared.ts";
import { subjectMergeDispatcher } from "../subject-merge-sql.ts";
import { moduleHeader } from "./assemble.ts";

/**
 * The `module` of the file that holds the helpers every block shares. It is not
 * a block: no `SQL_MODULES` entry and no row in `better_supabase.blocks`.
 */
export const PRELUDE_MODULE = "prelude";

/** The version in the `@bsb-block` line of the prelude file. */
const PRELUDE_VERSION = 1;

const DESCRIPTION =
  "The schema, the blocks table and the helper functions every block calls, each defined once.";

/** The table `moduleRow` writes to. */
const BLOCKS_TABLE = `create table better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;`;

/**
 * `member_organization_ids` as an empty set, for a layout that has tenant scope
 * policies but no memberships block. Policies call it before `or`
 * short-circuits, so it must exist. The layout decides at generation time: when
 * memberships is installed it defines the function, and this file never does.
 */
function membersStub(layout: BlockSqlLayout, installed: readonly string[]) {
  const ctx = moduleContext("memberships", layout, installed);
  const name = ctx.fn("member_organization_ids");

  return {
    name,
    sql: `-- Until memberships installs, the caller is a member of no organization.
create function ${name}(roles text[] default null)
returns setof ${ctx.idType}
language sql
stable
set search_path = ''
as $$ select null::${ctx.idType} where false $$;
revoke execute on function ${name}(text[]) from public;
grant execute on function ${name}(text[]) to anon, authenticated, service_role, supabase_auth_admin;`,
  };
}

/** The prelude's SQL, without its header. */
export function preludeSql(
  layout: BlockSqlLayout,
  installed: readonly string[],
  schemaFiles: readonly BlockSqlFile[],
): string {
  const parts = [
    `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`,
    BLOCKS_TABLE,
    ACTING_MEMBER,
    actorWriteFunctions().trim(),
    columnTypeFunctions(),
    subjectMergeDispatcher(),
    MEMO_FUNCTIONS.trim(),
    EQUIVALENT_TRIGGERS.trim(),
  ];

  if (!installed.includes("memberships")) {
    const stub = membersStub(layout, installed);

    if (schemaFiles.some((file) => file.contents.includes(`${stub.name}(`))) {
      parts.push(stub.sql);
    }
  }

  return parts.join("\n\n");
}

/**
 * The file `renderBlocks` writes first: it sorts before every module, so a
 * workflow that applies files in name order has the helpers when a module calls
 * them. `undefined` when no module renders a schema file.
 */
export function preludeFile(
  layout: BlockSqlLayout,
  installed: readonly string[],
  schemaFiles: readonly BlockSqlFile[],
): BlockSqlFile | undefined {
  if (schemaFiles.length === 0) {
    return undefined;
  }

  const dir = (layout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, "");
  const prefix = layout.prefix ?? CONFIG_DEFAULTS.sql.prefix;

  const header = moduleHeader({
    instance: PRELUDE_MODULE,
    version: PRELUDE_VERSION,
    mode: "managed",
    description: DESCRIPTION,
    block: undefined,
    entities: [],
  });

  return {
    module: PRELUDE_MODULE,
    kind: "schema",
    path: `${dir}/${prefix}_000_${PRELUDE_MODULE}.sql`,
    contents: `${header}\n\n${preludeSql(layout, installed, schemaFiles)}\n`,
  };
}
