import type { BlockOf } from "../define-block.ts";
import type { SsoEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { ssoEvents } from "./events.ts";
import { ssoSqlOptions } from "./options.ts";
import { createSso } from "./sso.ts";

/** The `sso` block's manifest (ADR 0029). */
export const ssoBlock: BlockOf<"sso", typeof createSso, SsoEvents> =
  defineBlock({
    name: "sso",
    sql: ["sso"],
    options: { sso: ssoSqlOptions },
    events: ssoEvents,
    create: createSso,
    category: "identity",
    entities: {
      organization: { mutability: "state-machine" },
      sso_domain: {
        mutability: "editable",
        emits: { create: true, update: true, delete: true },
      },
      sso_provider: { mutability: "state-machine" },
      scim_user: {
        mutability: "editable",
        emits: { create: true, update: true, delete: true },
      },
      scim_group: {
        mutability: "editable",
        emits: { create: true, update: true, delete: true },
      },
    },
    description:
      "Verified email domains with auto-join and SSO enforcement, SAML providers per organization registered with Supabase Auth, and SCIM 2.0 users and groups that provision memberships and map groups to roles.",
    recipes: ["sso-settings"],
  });
