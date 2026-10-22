import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";
import type { OperationModule } from "./access-model.ts";

import { operationPermission } from "../../core/operations.ts";
import { sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";
import {
  MODULE_PERMISSION_SCOPES,
  moduleOperations,
  modulePermissionKey,
} from "./access-model.ts";

const isOperationModule = (name: string): name is OperationModule =>
  Object.hasOwn(MODULE_PERMISSION_SCOPES, name);

/**
 * The permission key of every operation the layout knows: each installed
 * module's `OPERATIONS` after `blocks.<name>.permissions` renames, with the
 * provider's `authorization.operations` over them.
 */
function operationKeys(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): ReadonlyMap<string, string> {
  const keys = new Map<string, string>();

  for (const module of ctx.installedModules) {
    if (!isOperationModule(module)) {
      continue;
    }

    const of = moduleContext(module, layout, ctx.installedModules);

    if (of.mode === "custom") {
      continue;
    }

    for (const [action, fallback] of Object.entries(moduleOperations(module))) {
      keys.set(
        `${module}.${action}`,
        modulePermissionKey(of, action, fallback),
      );
    }
  }

  const operations = layout.accessProvider?.operations;

  for (const name of Object.keys(operations ?? {})) {
    const key = operationPermission(operations, name, keys.get(name));

    if (key !== undefined) {
      keys.set(name, key);
    }
  }

  return keys;
}

/**
 * `operation_permission(op)`: the key an operation checks, `null` for one
 * nobody declared.
 */
export function operationsSql(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const keys = [...operationKeys(ctx, layout)].toSorted(([a], [b]) =>
    a.localeCompare(b),
  );

  const body =
    keys.length === 0
      ? "null::text"
      : `case op
    ${keys.map(([name, key]) => `when ${sqlString(name)} then ${sqlString(key)}`).join("\n    ")}
  end`;

  return `
-- The permission key an operation (<module>.<action>, or a name in
-- authorization.operations) checks, after renames and the provider's table.
-- Null for an operation nobody declared, which callers refuse.
create or replace function better_supabase.operation_permission(op text)
returns text
language sql
immutable
set search_path = ''
as $$
  select ${body}
$$;`;
}
