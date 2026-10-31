import type { BlockSqlLayout } from "./module-types.ts";

import { permissionMatches } from "../auth/delegation.ts";
import { moduleContext } from "./module-context.ts";
import {
  accessModel,
  moduleOperations,
  rolesOf,
} from "./modules/permissions-model.ts";

/** The blocks whose synced rows follow a `read` permission. */
export type ReadRolesModule =
  | "attachments"
  | "observations"
  | "medications"
  | "activities";

/**
 * The roles whose keys grant the instance's `read` permission, when its access
 * runs on the `roles` model; `undefined` on any other model, where roles don't
 * decide reads.
 */
export function blockReadRoles(
  module: ReadRolesModule,
  layout: BlockSqlLayout,
  installed: readonly string[],
  instance: string,
): readonly string[] | undefined {
  const ctx = moduleContext(module, layout, installed, instance);

  if (accessModel(ctx) !== "roles") {
    return undefined;
  }

  const key = ctx.permissionKey("read", moduleOperations(module).read);

  return Object.entries(rolesOf(ctx)).flatMap(([role, keys]) =>
    keys.some((granted) => permissionMatches(granted, key)) ? [role] : [],
  );
}
