import type { BlockSqlContext } from "../context.ts";

import { fail } from "../shared.ts";

/**
 * The target tenant of a clone: `overrides.tenantId` when
 * `instantiate_template` sets it, else the source's tenant. Another tenant is
 * only reachable from a row a template owns (or by the service role), so a user
 * cannot copy a row from a tenant they cannot read.
 */
export function cloneTenant(
  ctx: BlockSqlContext,
  spec: {
    readonly fn: string;
    readonly code: string;
    readonly source: string;
    readonly tenant: string;
    readonly owned: string;
    readonly service: string;
    readonly can: string;
    readonly message: string;
  },
): string {
  return `v_tenant := coalesce(nullif(coalesce(${spec.fn}.overrides, '{}'::jsonb) ->> 'tenantId', '')::${ctx.idType}, ${spec.source}.${spec.tenant});
  if v_tenant is distinct from ${spec.source}.${spec.tenant} and not (${spec.service} or ${spec.owned}) then
    ${fail(spec.code, spec.message)}
  end if;
  if not (${spec.service} or ${ctx.scope.can("v_tenant", spec.can)}) then
    ${fail(spec.code, spec.message)}
  end if;`;
}

/**
 * `'name', value` pairs for the header columns of `alias` the table has, in the
 * attribute names `create_*` takes, so a clone copies the whole header and not
 * only its title and currency.
 */
export function headerPairs(
  ctx: BlockSqlContext,
  table: string,
  alias: string,
  column: (logical: string) => string,
  attrs: readonly (readonly [string, string])[],
): string {
  return attrs
    .filter(([logical]) => ctx.has(table, logical))
    .map(([logical, name]) => `'${name}', ${alias}.${column(logical)}`)
    .join(", ");
}

/** The `company` and `contact` attrs, null when the source has no such party. */
export function partyPairs(
  ctx: BlockSqlContext,
  table: string,
  alias: string,
  column: (logical: string) => string,
): string {
  return (["company", "contact"] as const)
    .filter(
      (kind) => ctx.has(table, `${kind}Type`) && ctx.has(table, `${kind}Id`),
    )
    .map(
      (kind) =>
        `'${kind}', case when ${alias}.${column(`${kind}Id`)} is null then null else jsonb_build_object('type', ${alias}.${column(`${kind}Type`)}, 'id', ${alias}.${column(`${kind}Id`)}) end`,
    )
    .join(", ");
}
