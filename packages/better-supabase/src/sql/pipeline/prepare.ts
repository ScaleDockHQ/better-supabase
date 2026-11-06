import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout, BlockSql } from "../module-types.ts";

import { applyActorWriteGuards } from "../actor-guard.ts";
import { blockNamesOnAppTables } from "../app-table-names.ts";
import { rangeChecks } from "../emit/check.ts";
import {
  overAppTables,
  overAppViews,
  withoutAppTableEdits,
  withoutCoveredIndexes,
  withoutUnmappedColumns,
  withoutUnmappedTables,
} from "../over-app-tables.ts";
import { withoutAppTablePolicies } from "../policy-cover.ts";
import { renderSeedDefaults, seedFunctionName } from "../seeds.ts";
import { applyTenantScope } from "../tenant-scope.ts";
import { appTableSet } from "./resolve.ts";

/**
 * `sql` with the parameter qualifiers of renamed functions renamed too:
 * PL/pgSQL and SQL functions name a parameter `fn.param`, so
 * `create_organization.name` follows `create_organization` to
 * `create_workspace.name`.
 */
export function renameQualifiers(sql: string, ctx: BlockSqlContext): string {
  let out = sql;

  for (const [from, to] of ctx.functionRenames()) {
    out = out.replaceAll(
      new RegExp(`(?<![\\w."$])${from}\\.(?=[a-z_])`, "g"),
      `${to}.`,
    );
  }

  return out;
}

/**
 * Guards a file's SQL under its header: the marker the CLI recognizes a managed
 * file by stays on the first lines, and the helper functions follow it.
 */
export function guardBelowHeader(
  contents: string,
  layout: BlockSqlLayout,
): string {
  const split = contents.indexOf("\n\n");

  if (split === -1) {
    return applyActorWriteGuards(contents, layout);
  }

  return `${contents.slice(0, split)}\n${applyActorWriteGuards(contents.slice(split + 1), layout)}`;
}

export function moduleSql(
  module: BlockSql,
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  return applyActorWriteGuards(
    applyTenantScope(
      rangeChecks(
        `${module.build(ctx, layout)}${seedDefaultsSql(module, ctx)}`,
      ),
      ctx,
    ),
    layout,
  );
}

/** The module's declared tenant defaults as `seed_<module>_defaults`, if any. */
export function seedDefaultsSql(
  module: BlockSql,
  ctx: BlockSqlContext,
): string {
  const tables = module.seeds?.defaults?.(ctx);

  return tables === undefined || tables.length === 0
    ? ""
    : renderSeedDefaults(
        module.name,
        ctx.fn(seedFunctionName(module.name)),
        ctx.idType,
        tables,
      );
}

/**
 * `sql` over the app's tables: their `create table` becomes the missing
 * columns, and what would change their data rules or access is left out.
 */
export function overApp(
  sql: string,
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const appTables = appTableSet(ctx);
  const appViews = appTableSet(ctx, ctx.appViews);

  return withoutAppTablePolicies(
    withoutCoveredIndexes(
      withoutUnmappedColumns(
        withoutUnmappedTables(
          blockNamesOnAppTables(
            withoutAppTableEdits(
              overAppTables(
                overAppViews(sql, appViews),
                appTables,
                layout.ownColumns,
              ),
              appTables,
            ),
            appTables,
            layout.ownUpdatedAtTriggers,
          ),
          ctx.instance,
        ),
        ctx.instance,
      ),
      appTables,
      layout.ownIndexes,
    ),
    ctx.config.ownTablePolicies === "app" ? appTables : new Set(),
  );
}
