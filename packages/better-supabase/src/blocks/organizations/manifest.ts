import type { BlockOf } from "../define-block.ts";
import type { OrganizationsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { organizationsEvents } from "./events.ts";
import { createOrganizations } from "./organizations.ts";

/** The `organizations` block's manifest (ADR 0029). */
export const organizationsBlock: BlockOf<
  "organizations",
  typeof createOrganizations,
  OrganizationsEvents
> = defineBlock({
  name: "organizations",
  sql: ["organizations", "invitations"],
  options: {
    organizations: optionKeys([
      "assignmentGuard",
      "attributes",
      "auditCategory",
      "deleteMode",
      "extraColumns",
      "formerOwnerRole",
      "ownerInvariant",
      "ownerRole",
      "reservedSlugs",
      "slugCitext",
      "slugMaxLength",
      "slugMinLength",
      "slugPattern",
    ]),
    invitations: optionKeys([
      "maxValidFor",
      "platformRoles",
      "prefill",
      "previewColumns",
      "requireConfirmedEmail",
      "tokenBytes",
      "tokenStorage",
      "validFor",
    ]),
  },
  events: organizationsEvents,
  create: createOrganizations,
  category: "foundation",
  recipes: ["org-switcher", "members-table", "invite-dialog"],
});
