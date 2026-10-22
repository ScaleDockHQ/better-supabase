import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { permissionsSqlOptions } from "./options.ts";
import { createPermissions } from "./permissions.ts";

/** The `access` block's manifest (ADR 0029). */
export const permissionsBlock: BlockOf<
  "permissions",
  typeof createPermissions
> = defineBlock({
  name: "permissions",
  sql: ["permissions"],
  options: { permissions: permissionsSqlOptions },
  create: createPermissions,
  category: "identity",
  recipes: ["can"],
});
