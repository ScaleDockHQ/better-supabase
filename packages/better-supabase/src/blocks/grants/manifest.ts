import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { grantsSqlOptions } from "./options.ts";

/** The `grants` block's manifest (ADR 0029). */
export const grantsBlock: Block<"grants"> = defineBlock({
  name: "grants",
  sql: ["grants"],
  options: { grants: grantsSqlOptions },
  category: "identity",
  entities: { grant: { mutability: "read-only" } },
  description:
    "Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.",
});
