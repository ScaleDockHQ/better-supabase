import type { BlockOf } from "../define-block.ts";
import type { AttachmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { OFFLINE_RULES } from "../offline-rules.ts";
import { createAttachments } from "./attachments.ts";
import { attachmentsEvents } from "./events.ts";
import { attachmentsSqlOptions } from "./options.ts";
import { attachmentsBinding } from "./record-binding.ts";
import { attachmentInputSchema } from "./schemas.ts";

/** The `attachments` block's manifest (ADR 0029). */
export const attachmentsBlock: BlockOf<
  "attachments",
  typeof createAttachments,
  AttachmentsEvents,
  Record<never, never>,
  "attachments",
  typeof attachmentsBinding
> = defineBlock({
  name: "attachments",
  sql: ["attachments"],
  options: { attachments: attachmentsSqlOptions },
  events: attachmentsEvents,
  schemas: { attachment: { input: attachmentInputSchema } },
  provides: { attachments: (client) => client },
  create: createAttachments,
  record: attachmentsBinding,
  category: "collaboration",
  importTarget: ["attachment"],
  entities: {
    attachment: {
      mutability: "state-machine",
      offline: OFFLINE_RULES.attachments,
      emits: { create: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.",
  recipes: ["attachments-uploader", "subject-timeline", "message-composer"],
});
