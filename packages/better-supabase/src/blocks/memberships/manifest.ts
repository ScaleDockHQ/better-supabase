import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { OFFLINE_RULES } from "../offline-rules.ts";
import { membershipsSqlOptions } from "./options.ts";

/** The `memberships` block's manifest (ADR 0029). */
export const membershipsBlock: Block<"memberships"> = defineBlock({
  name: "memberships",
  sql: ["memberships"],
  options: { memberships: membershipsSqlOptions },
  category: "tenancy",
  entities: {
    membership: { mutability: "read-only", offline: OFFLINE_RULES.memberships },
  },
  description:
    "Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.",
  extension: "membershipsExtension",
});
