import type { BlockOf } from "../define-block.ts";
import type { OrganizationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { organizationsEvents } from "./events.ts";
import { organizationsSqlOptions, invitationsSqlOptions } from "./options.ts";
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
    organizations: organizationsSqlOptions,
    invitations: invitationsSqlOptions,
  },
  events: organizationsEvents,
  create: createOrganizations,
  category: "tenancy",
  recipes: [
    "org-switcher",
    "members-table",
    "invite-dialog",
    "workspace-url-field",
  ],
});
