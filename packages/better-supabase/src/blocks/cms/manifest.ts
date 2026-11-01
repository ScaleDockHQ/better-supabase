import type { BlockOf } from "../define-block.ts";

import { PUBLIC_MEDIA } from "../../preset/preset-blocks.ts";
import { approvalsBlock } from "../approvals/manifest.ts";
import { attachmentsBlock } from "../attachments/manifest.ts";
import { contentBlock } from "../content/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { versionsBlock } from "../versions/manifest.ts";
import { createCms } from "./cms.ts";

/** The blocks `cms` is made of, by block name. */
export const cmsParts: {
  readonly content: typeof contentBlock;
  readonly versions: typeof versionsBlock;
  readonly approvals: typeof approvalsBlock;
  readonly attachments: typeof attachmentsBlock;
} = {
  content: contentBlock,
  versions: versionsBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
};

export type CmsParts = typeof cmsParts;

/**
 * The `cms` composite (ADR 0177): content entries with versions, approvals and
 * public media. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const cmsBlock: BlockOf<"cms", typeof createCms> = defineBlock({
  name: "cms",
  composes: cmsParts,
  create: createCms,
  defaults: PUBLIC_MEDIA,
  category: "content",
});
