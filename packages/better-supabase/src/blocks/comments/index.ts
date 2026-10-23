export type {
  CommentsOptimisticAction,
  CommentsWrites,
} from "./record-binding.ts";

export {
  type Comment,
  type CommentAssignment,
  type CommentEdit,
  type Comments,
  type CommentsOptions,
  createComments,
  type ListCommentsOptions,
  mentionsIn,
  type NewComment,
} from "./comments.ts";

export type { MessageEdit } from "../messaging/messaging.ts";

export { conversationTopic } from "../messaging/messaging.ts";

export { fileAnchor, isFileAnchor } from "../messaging/anchors.ts";

export type {
  AnchorRegion,
  FileAnchor,
  FileAnchorAt,
} from "../messaging/anchors.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export type { Author } from "../../core/block-authors.ts";

export { commentsBlock } from "./manifest.ts";

export { commentsOptimistic, commentsBinding } from "./record-binding.ts";

export {
  type CommentDraft,
  type CommentsActions,
  type CommentsController,
  type CommentsControllerOptions,
  type CommentsSnapshot,
  createCommentsController,
} from "./client.ts";

export { commentChangeSchema, commentInputSchema } from "./schemas.ts";

export type { CommentsSqlOptions } from "./options.ts";
