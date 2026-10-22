import type { BlockSqlLayout } from "./module-types.ts";

import { moduleContext } from "./module-context.ts";
import { platformRolesProblem } from "./modules/invitations-roles.ts";
import { sharedRolesProblem } from "./modules/memberships.ts";
import { resolveBlocks } from "./registry.ts";

/**
 * Why a roles table that holds both tenant and platform roles (the tenant
 * module's `roleThrough` and the invitations module's `platformRoles.through`
 * under the `provider` model) can't tell them apart: the setting that lacks
 * `where` and why. Empty when the modules don't share a roles table.
 */
export function sharedRolesProblems(
  names: readonly string[],
  layout: BlockSqlLayout,
): { readonly setting: string; readonly message: string }[] {
  const installed = resolveBlocks(names, layout).map((module) => module.name);

  if (
    !installed.includes("memberships") ||
    !installed.includes("invitations")
  ) {
    return [];
  }

  const ctx = moduleContext("invitations", layout, installed);

  return [sharedRolesProblem(ctx.of("memberships")), platformRolesProblem(ctx)]
    .filter((problem): problem is string => problem !== undefined)
    .map((problem) => {
      const at = problem.indexOf(": ");

      return { setting: problem.slice(0, at), message: problem.slice(at + 2) };
    });
}
