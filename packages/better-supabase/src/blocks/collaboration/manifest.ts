import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { attachmentsBlock } from "../attachments/manifest.ts";
import { commentsBlock } from "../comments/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { reactionsBlock } from "../reactions/manifest.ts";
import { tagsBlock } from "../tags/manifest.ts";
import { timelineBlock } from "../timeline/manifest.ts";

/** The blocks `collaboration` is made of, by block name. */
export const collaborationParts: {
  readonly comments: typeof commentsBlock;
  readonly tags: typeof tagsBlock;
  readonly attachments: typeof attachmentsBlock;
  readonly timeline: typeof timelineBlock;
  readonly reactions: typeof reactionsBlock;
} = {
  comments: commentsBlock,
  tags: tagsBlock,
  attachments: attachmentsBlock,
  timeline: timelineBlock,
  reactions: reactionsBlock,
};

export type CollaborationParts = typeof collaborationParts;

/**
 * The `collaboration` composite (ADR 0177): comments, tags, attachments, the
 * activity feed and reactions on any record. It installs its parts and sets
 * their defaults; the parts stay ordinary blocks in the config.
 */
export const collaborationBlock: BlockOf<
  "collaboration",
  (options: BlockContext & CompositeOptions<CollaborationParts>) => undefined
> = defineBlock({
  name: "collaboration",
  composes: collaborationParts,
  category: "collaboration",
});
