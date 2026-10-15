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
    options: {
      sso: ssoSqlOptions,
    },
    events: ssoEvents,
    create: createSso,
    category: "foundation",
  });
