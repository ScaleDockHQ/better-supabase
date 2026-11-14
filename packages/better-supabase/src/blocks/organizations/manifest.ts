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
  sql: ["organizations", "invitations", "seeds"],
  options: {
    organizations: organizationsSqlOptions,
    invitations: invitationsSqlOptions,
  },
  events: organizationsEvents,
  create: createOrganizations,
  category: "tenancy",
  importTarget: ["organization_profile"],
  entities: {
    organization: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    invitation: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  description:
    "create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.",
  recipes: [
    "org-switcher",
    "members-table",
    "invite-dialog",
    "workspace-url-field",
  ],
});
