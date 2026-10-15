import type { BlockOf } from "../define-block.ts";
import type { AttachmentsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAttachments } from "./attachments.ts";
import { attachmentsEvents } from "./events.ts";

/** The `attachments` block's manifest (ADR 0029). */
export const attachmentsBlock: BlockOf<
  "attachments",
  typeof createAttachments,
  AttachmentsEvents,
  Record<never, never>,
  "attachments"
> = defineBlock({
  name: "attachments",
  sql: ["attachments"],
  options: {
    attachments: optionKeys([
      "bucket",
      "requireScan",
      "maxSize",
      "allowedMimeTypes",
      "subjects",
      "path",
      "scanBuckets",
    ]),
  },
  events: attachmentsEvents,
  provides: {
    attachments: (client) => client,
  },
  create: createAttachments,
  category: "collaboration",
});
