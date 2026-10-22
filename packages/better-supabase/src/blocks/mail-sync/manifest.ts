import type { BlockOf } from "../define-block.ts";
import type { MailSyncEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { mailSyncEvents } from "./events.ts";
import { createMailSync } from "./mail-sync.ts";
import { mailSyncSqlOptions } from "./options.ts";
import { mailAccountInputSchema, mailDraftSchema } from "./schemas.ts";

/** The `mail-sync` block's manifest (ADR 0029). */
export const mailSyncBlock: BlockOf<
  "mail-sync",
  typeof createMailSync,
  MailSyncEvents
> = defineBlock({
  name: "mail-sync",
  sql: ["mail-sync"],
  options: { "mail-sync": mailSyncSqlOptions },
  events: mailSyncEvents,
  schemas: {
    mail_account: { input: mailAccountInputSchema },
    mail_message: { input: mailDraftSchema },
  },
  create: createMailSync,
  category: "crm",
});
