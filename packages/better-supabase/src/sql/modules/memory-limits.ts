import type { BlockSqlContext } from "../context.ts";

import { serviceGrant } from "../shared.ts";

/** The scopes whose memory belongs to the tenant unless it has an owner. */
export const SHARED = "'organization', 'record'";

/** What `options.tenant` and `options.maxItems` turn on. */
export interface MemoryLimits {
  /** `options.tenant: false`: personal memory may have no tenant. */
  readonly tenantless: boolean;
  /** `options.maxItems`: the most live archival facts per owner and tenant. */
  readonly maxItems: number | undefined;
}

export function memoryLimits(ctx: BlockSqlContext): MemoryLimits {
  const maxItems = ctx.option("maxItems");

  if (
    maxItems !== undefined &&
    (typeof maxItems !== "number" ||
      !Number.isInteger(maxItems) ||
      maxItems < 1)
  ) {
    throw new TypeError(
      "blocks.memory.options.maxItems must be a positive whole number",
    );
  }

  return { tenantless: !ctx.flag("tenant", true), maxItems };
}

/** The columns `capSql` and `purgeSql` read. */
export interface MemoryLimitColumns {
  readonly id: string;
  readonly tenant: string;
  readonly owner: string;
  readonly kind: string;
  readonly supersededBy: string;
  readonly updatedAt: string;
  readonly deletedAt: string;
  readonly expiresAt: string;
}

/**
 * The statement in `memory_save` that forgets the oldest archival facts of the
 * namespace's owner and tenant past `maxItems`, keeping the one it just saved.
 * Shared memory without an owner counts as the tenant's own pool.
 */
export function capSql(
  ctx: BlockSqlContext,
  limits: MemoryLimits,
  columns: MemoryLimitColumns,
  order: string,
): string {
  if (limits.maxItems === undefined) {
    return "";
  }

  const memories = ctx.table("memories");
  const m = columns;
  const soft = ctx.has("memories", "deletedAt");
  const live = soft ? ` and y.${m.deletedAt} is null` : "";

  const forget = soft
    ? `update ${memories} x set ${m.deletedAt} = now(), ${m.updatedAt} = now()`
    : `delete from ${memories} x`;

  return `
  ${forget}
  where x.${m.id} in (
    select y.${m.id} from ${memories} y
    where y.${m.tenant} is not distinct from memory_save.tenant and y.${m.owner} is not distinct from v_owner
      and y.${m.kind} = 'archival' and y.${m.supersededBy} is null${live}
    order by y.${m.id} = v_row.${m.id} desc, ${order} desc, y.${m.id} desc
    offset ${String(limits.maxItems)}
  );`;
}

/**
 * `purge_memories`, which removes memories deleted more than retention_days ago
 * and expired ones, in every tenant or in `tenant`.
 */
export function purgeSql(
  ctx: BlockSqlContext,
  columns: MemoryLimitColumns,
): string {
  const memories = ctx.table("memories");
  const fn = ctx.fn("purge_memories");
  const m = columns;
  const id = ctx.idType;

  const expired = ctx.has("memories", "expiresAt")
    ? ` or y.${m.expiresAt} < now()`
    : "";

  return `
-- Removes memories deleted more than retention_days ago${expired ? " and expired ones" : ""}, up to
-- batch rows, in every tenant or only in tenant, and returns how many it
-- removed.
drop function if exists ${fn}(integer, integer);
create or replace function ${fn}(retention_days integer default 30, batch integer default 1000, tenant ${id} default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${memories} x
  where x.${m.id} in (
    select y.${m.id} from ${memories} y
    where (purge_memories.tenant is null or y.${m.tenant} = purge_memories.tenant)
      and (y.${m.deletedAt} < now() - make_interval(days => greatest(purge_memories.retention_days, 0))${expired})
    limit least(greatest(purge_memories.batch, 1), 10000)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn}(integer, integer, ${id})`)}
`;
}

/**
 * Version 4: organization and record memory may have an owner, and with
 * `options.tenant: false` the tenant column takes nulls.
 */
export function upgradeOwners(ctx: BlockSqlContext): string {
  if (!ctx.owns("memories")) {
    return "";
  }

  const memories = ctx.table("memories");
  const scope = ctx.col("memories", "scope");
  const owner = ctx.col("memories", "owner");
  const check = ctx.naming.rename("memories_owner_check");

  const tenant = memoryLimits(ctx).tenantless
    ? `\nalter table ${memories} alter column ${ctx.col("memories", "tenant")} drop not null;`
    : "";

  return `alter table ${memories} drop constraint if exists ${check};
alter table ${memories} add constraint ${check} check (${scope} in (${SHARED}) or ${owner} is not null);${tenant}`;
}
