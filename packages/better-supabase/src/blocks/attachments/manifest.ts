import type { BlockOf } from "../define-block.ts";
import type { AttachmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
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
  recipes: ["attachments-uploader", "subject-timeline", "message-composer"],
});
