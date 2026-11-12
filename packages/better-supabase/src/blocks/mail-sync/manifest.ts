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
  MailSyncEvents,
  Record<never, never>,
  "mailer"
> = defineBlock({
  name: "mail-sync",
  sql: ["mail-sync"],
  options: { "mail-sync": mailSyncSqlOptions },
  events: mailSyncEvents,
  schemas: {
    mail_account: { input: mailAccountInputSchema },
    mail_message: { input: mailDraftSchema },
  },
  provides: { mailer: (client) => client },
  create: createMailSync,
  category: "crm",
  entities: {
    mail_thread: { mutability: "append-only", emits: { create: false } },
    mail_account: { mutability: "editable", emits: { update: false } },
    mail_message: { mutability: "state-machine" },
  },
  description:
    "Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email activities, and a record of the mail members send, with opens and clicks per message and per template version.",
  providers: [
    {
      option: "providers",
      type: "MailProvider",
      from: "better-supabase/blocks/mail-sync",
      required: true,
      description: "Reads and sends each member's mailbox.",
      example: "[gmailMail(), outlookMail()]",
    },
  ],
});
