import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `post_board.created` and `post_board.updated`. */
export interface PostBoardEventData {
  readonly organizationId: string;
  /** The board. */
  readonly id: string;
  readonly key: string;
  readonly kind: string;
}

/** The `post.*` events. */
export interface PostEventData {
  readonly organizationId: string;
  /** The post. */
  readonly id: string;
  readonly boardId: string;
  readonly authorId: string | null;
  /** Open, under_review, planned, in_progress, done or closed. */
  readonly status: string;
  /** The moderation status: visible, pending, hidden or removed. */
  readonly moderation: string;
  /** The post it was merged into, on `post.merged`. */
  readonly mergedIntoId: string | null;
}

/** The events of the `posts` block: type to data. */
export type PostsEvents = {
  readonly "post_board.created": PostBoardEventData;
  readonly "post_board.updated": PostBoardEventData;
  readonly "post.created": PostEventData;
  readonly "post.updated": PostEventData;
  readonly "post.status_changed": PostEventData;
  readonly "post.moderated": PostEventData;
  readonly "post.merged": PostEventData;
  readonly "post.deleted": PostEventData;
};

/** The `posts` block's event types, for its manifest and `onBlockEvent`. */
export const postsEvents: Events<PostsEvents> = defineEvents({
  "post_board.created": event<PostBoardEventData>(),
  "post_board.updated": event<PostBoardEventData>(),
  "post.created": event<PostEventData>(),
  "post.updated": event<PostEventData>(),
  "post.status_changed": event<PostEventData>(),
  "post.moderated": event<PostEventData>(),
  "post.merged": event<PostEventData>(),
  "post.deleted": event<PostEventData>(),
});
