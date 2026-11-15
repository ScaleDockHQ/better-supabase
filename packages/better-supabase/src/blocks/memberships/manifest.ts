import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { membershipsSqlOptions } from "./options.ts";

/** The `memberships` block's manifest (ADR 0029). */
export const membershipsBlock: Block<"memberships"> = defineBlock({
  name: "memberships",
  sql: ["memberships"],
  options: { memberships: membershipsSqlOptions },
  category: "tenancy",
  entities: {
    membership: {
      mutability: "read-only",
      offline: {
        scope: "user",
        join: [
          {
            kind: "member-set",
            stream: "roles",
            table: { roleSet: true },
            optional: true,
          },
          {
            kind: "member-organizations",
            stream: "organizations",
            table: {
              block: "organizations",
              columns: ["id", "name"],
              without: ["user_id"],
            },
            select: ["id", "name", "slug", "disabled_at", "deleted_at"],
            optional: true,
          },
        ],
      },
    },
  },
  description:
    "Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.",
  extension: "membershipsExtension",
});
