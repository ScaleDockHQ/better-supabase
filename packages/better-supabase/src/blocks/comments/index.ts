export {
  type ActivityDescription,
  type ActivityEntry,
  type ActivityHistoryOptions,
  type ActivityFacet,
  activityListQuery,
  activitySink,
  type ActivitySinkOptions,
  type ActivitySort,
  type ActivitySource,
  type Comment,
  type CommentEdit,
  type Comments,
  type CommentsOptions,
  createComments,
  type ListCommentsOptions,
  mentionsIn,
  type NewComment,
} from "./comments.ts";

export type { CommentSubject } from "../../sql/modules/comments.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export type { Author } from "../../core/block-authors.ts";

export { commentsBlock } from "./manifest.ts";

export { commentsEvents } from "./events.ts";

export type { CommentsEvents } from "./events.ts";

export {
  type CommentDraft,
  type CommentsActions,
  type CommentsController,
  type CommentsControllerOptions,
  type CommentsSnapshot,
  createCommentsController,
} from "./client.ts";

export { commentChangeSchema, commentInputSchema } from "./schemas.ts";
