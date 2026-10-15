import type { CommentEventData, Events } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `comments` block: type to data. */
export type CommentsEvents = {
  readonly "comment.created": CommentEventData;
  readonly "comment.mentioned": CommentEventData;
  readonly "comment.deleted": CommentEventData;
};

/** The `comments` block's event types, for its manifest and `onBlockEvent`. */
export const commentsEvents: Events<CommentsEvents> = defineEvents({
  "comment.created": event<CommentEventData>(),
  "comment.mentioned": event<CommentEventData>(),
  "comment.deleted": event<CommentEventData>(),
});
