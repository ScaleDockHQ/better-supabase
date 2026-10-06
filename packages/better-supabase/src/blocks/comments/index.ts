export {
  type ActivityDescription,
  type ActivityFacet,
  activityListQuery,
  activitySink,
  type ActivitySinkOptions,
  type ActivitySort,
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
export { rpcTransport, sqlTransport } from "../../core/block-transport.ts";
export type { BlockTransport } from "../../core/block-transport.ts";
