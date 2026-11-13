import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { permissionsSqlOptions } from "./options.ts";
import { createPermissions } from "./permissions.ts";

/** The `permissions` block's manifest (ADR 0029). */
export const permissionsBlock: BlockOf<
  "permissions",
  typeof createPermissions
> = defineBlock({
  name: "permissions",
  sql: ["permissions"],
  options: { permissions: permissionsSqlOptions },
  create: createPermissions,
  category: "identity",
  entities: { permission: { mutability: "read-only" } },
  description:
    "can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).",
  recipes: ["can"],
});
