import type { BlockOf } from "../define-block.ts";
import type { SsoEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { ssoEvents } from "./events.ts";
import { createSso } from "./sso.ts";

/** The `sso` block's manifest (ADR 0029). */
export const ssoBlock: BlockOf<"sso", typeof createSso, SsoEvents> =
  defineBlock({
    name: "sso",
    sql: ["sso"],
    options: {
      sso: optionKeys(["txtPrefix", "defaultRole", "roleOrder", "groupRoles"]),
    },
    events: ssoEvents,
    create: createSso,
    category: "foundation",
  });
